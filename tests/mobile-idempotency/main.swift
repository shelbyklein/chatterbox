import AppKit
import Foundation
@testable import ChatterboxTestEngine

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

@MainActor func run() async throws {
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":true,"keepMacAwake":false], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    let server = CompanionServer.shared
    server.model = model
    server.start()
    for _ in 0..<100 where !server.isRunning { try await Task.sleep(for:.milliseconds(30)) }
    precondition(server.isRunning, "Isolated server failed to start")
    let port = CompanionServer.port
    func make(_ host: String, _ path: String, _ method: String, _ body: Data = Data(), _ token: String? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string:"http://\(host):\(port)\(path)")!)
        r.httpMethod = method; r.httpBody = method == "GET" ? nil : body
        r.timeoutInterval = 3; r.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { r.setValue(token,forHTTPHeaderField:Companion.tokenHeader) }
        return r
    }
    let pairing = try Companion.encoder.encode(Companion.PairRequest(code:server.pairingCode,deviceName:"Idempotency fixture"))
    let pair = try await URLSession.shared.data(for:make("127.0.0.1","/v1/pair","POST",pairing))
    precondition((pair.1 as! HTTPURLResponse).statusCode == 200)
    let token = try Companion.decoder.decode(Companion.PairResponse.self,from:pair.0).token
    func validate(_ data: Data, _ response: URLResponse) throws {
        let http = response as! HTTPURLResponse
        if http.statusCode != 200 { throw CompanionRetry.Failure(message:String(data:data,encoding:.utf8) ?? "error") }
    }
    var posts: [(String,String?)] = []
    var discarded: Data?
    func lostReply(_ path: String, body: Data, afterFirst: () -> Void = {}) async throws -> Companion.ChatDetail {
        var first = true
        let result = try await CompanionRetry.load(hosts:["127.0.0.1","localhost"],method:"POST",request:{host,probe in
            make(host,probe ? "/v1/addresses" : path,probe ? "GET" : "POST",body,token)
        },validate:validate,send:{ request in
            let result = try await URLSession.shared.data(for:request)
            if request.httpMethod == "POST" {
                posts.append((request.url!.host!,request.value(forHTTPHeaderField:CompanionRetry.operationHeader)))
                if first {
                    first = false; discarded = result.0; afterFirst()
                    throw URLError(.networkConnectionLost) // Mac applied it; caller loses the entire reply.
                }
                precondition(result.0 == discarded, "Retry didn't return original response bytes")
            }
            return result
        })
        precondition(result.host == "localhost")
        let two = posts.suffix(2)
        precondition(two.count == 2 && two.first!.1 != nil && two.first!.1 == two.last!.1)
        return try Companion.decoder.decode(Companion.ChatDetail.self,from:result.data)
    }
    let regular = model.newChat(backend:.codex)
    regular.isRunning = true // Queue only: no paid model or agent process.
    let golem = model.ensureDot()
    golem.setBackend(.codex); golem.isRunning = true
    // Pairings are product-scoped after extraction; the Chatterbox token only
    // exercises ordinary mutations here. Separate Golem RPC fixtures cover it.
    for chat in [regular] {
        let body = try Companion.encoder.encode(Companion.SendRequest(text:"Intentional identical text"))
        let before = chat.items.filter{$0.kind == .user}.count
        _ = try await lostReply("/v1/chats/\(chat.id)/messages",body:body)
        precondition(chat.items.filter{$0.kind == .user}.count == before+1)
        let firstID = posts.last!.1
        _ = try await lostReply("/v1/chats/\(chat.id)/messages",body:body)
        precondition(chat.items.filter{$0.kind == .user}.count == before+2 && posts.last!.1 != firstID,
                     "Intentional repeated message was deduped by text")
    }
    let count = model.sessions.count
    let created = try await lostReply("/v1/chats",body:Data("{\"backend\":\"codex\"}".utf8),afterFirst:{
        // Make a newly created chat nonempty so a second accidental create cannot be
        // hidden by the app's normal empty-chat reuse.
        model.sessions.first(where:{$0.items.isEmpty && !$0.isDot && !$0.isRunning})?.appendItem(.init(kind:.assistant,text:"Fixture changed after lost create reply"))
    })
    precondition(model.sessions.count == count+1 && model.sessions.contains{$0.id == created.summary.id})
    regular.isRunning = false
    let forksBefore = model.sessions.count
    let fork = try await lostReply("/v1/chats/\(regular.id)/fork",body:Data("{}".utf8))
    precondition(model.sessions.count == forksBefore+1 && fork.summary.id != regular.id)
    print("PASS actual authenticated HTTP routes: dropped message replies for ordinary, creates and forks; one effect, same original response; intentional same text gets distinct IDs")

    // Ledger faults, without a real chat mutation.
    let clock = Date(timeIntervalSince1970:1000)
    let ledger = CompanionMutationLedger(maxEntries:2,maxBytes:20)
    let device = UUID(), operation = UUID()
    func req(_ ledger:CompanionMutationLedger, _ op:UUID = operation, _ text:String = "hello", time:Date = clock) -> HTTPRequest {
        var h = ledger.headers(now:time).reduce(into:[String:String]()){$0[$1.key.lowercased()]=$1.value}
        h[CompanionRetry.operationHeader.lowercased()] = op.uuidString
        return .init(method:"POST",path:"/v1/chats/test/messages",query:[:],headers:h,body:Data(text.utf8))
    }
    var effects = 0
    func effect() -> HTTPResponse { effects += 1; return .init(status:200,contentType:"text/plain",body:Data("ok".utf8)) }
    let request = req(ledger)
    precondition(ledger.respond(device:device,request:request,now:clock,execute:effect).status == 200)
    precondition(ledger.respond(device:device,request:request,now:clock,execute:effect).status == 200 && effects == 1)
    precondition(ledger.respond(device:device,request:req(ledger,operation,"different"),now:clock,execute:effect).status == 409 && effects == 1)
    precondition(ledger.respond(device:UUID(),request:request,now:clock,execute:effect).status == 200 && effects == 2)
    precondition(ledger.respond(device:device,request:req(ledger,UUID()),now:clock,execute:effect).status == 503 && effects == 2)
    let expired = Date(timeIntervalSince1970:1600)
    precondition(ledger.respond(device:device,request:request,now:expired,execute:effect).status == 409 && effects == 2)
    let restarted = CompanionMutationLedger()
    precondition(restarted.respond(device:device,request:request,now:clock,execute:effect).status == 409 && effects == 2)
    let small = CompanionMutationLedger(maxBytes:1)
    let largeRequest = req(small)
    precondition(small.respond(device:device,request:largeRequest,now:clock,execute:effect).status == 200)
    let largeCount = effects
    precondition(small.respond(device:device,request:largeRequest,now:clock,execute:effect).status == 409 && effects == largeCount)
    let nowRequest = req(ledger,UUID(),time:expired)
    precondition(ledger.respond(device:device,request:nowRequest,now:expired,execute:effect).status == 200)
    precondition(ledger.respond(device:device,request:request,now:expired,execute:effect).status == 409)
    print("PASS device isolation, payload conflict, bounds, expiry/eviction, incarnation restart, oversize tombstone")

    for scenario in ["legacy","restart","exhausted","http-error"] {
        var attempts = 0; var probes = 0
        let epoch = UUID().uuidString
        do {
            _ = try await CompanionRetry.load(hosts:["first","second"],method:"POST",request:{host,probe in
                make(host,probe ? "/v1/addresses":"/v1/chats","POST") // Fixture distinguishes path.
            },validate:validate,send:{request in
                let probe = request.url!.path == "/v1/addresses"
                var headers = [String:String]()
                if probe {
                    probes += 1
                    if scenario != "legacy" {
                        headers = [CompanionRetry.versionHeader:"1",CompanionRetry.incarnationHeader:scenario == "restart" && probes == 2 ? UUID().uuidString:epoch,CompanionRetry.issuedHeader:"1000"]
                    }
                    return (Data("{}".utf8),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:headers)!)
                }
                attempts += 1
                if scenario == "http-error" {
                    return (Data("rejected".utf8),HTTPURLResponse(url:request.url!,statusCode:400,httpVersion:nil,headerFields:nil)!)
                }
                throw URLError(.networkConnectionLost)
            })
            preconditionFailure("Uncertain request returned success")
        } catch {
            precondition(scenario == "http-error" ? error.localizedDescription == "rejected" : error.localizedDescription.contains("check the chat"))
        }
        precondition(attempts == (scenario == "exhausted" ? 2:1))
    }
    print("PASS legacy single attempt, changed incarnation fallback refusal, exhausted retries uncertainty, definitive HTTP failure not retried")
    do {
        let _: Companion.ChatDetail = try CompanionRetry.decode(Companion.ChatDetail.self,data:Data(),method:"POST")
        preconditionFailure("Unreadable mutation reply accepted")
    } catch { precondition(error.localizedDescription.contains("check the chat")) }
    print("PASS unreadable successful mutation reply reports uncertainty")
    // Authorization is checked before cached responses can be retrieved.
    let unauthorized = try await URLSession.shared.data(for:make("127.0.0.1","/v1/chats/\(regular.id)/fork","POST",Data("{}".utf8),"revoked-token"))
    precondition((unauthorized.1 as! HTTPURLResponse).statusCode == 401)
    print("PASS unauthenticated mutation rejected before replay")
    server.stop()
}
Task { do { try await run(); exit(0) } catch { print("FAIL",error); exit(1) } }
app.run()
