@testable import ChatterboxTestEngine
import AppKit
// Claude's connector, end to end: discovery, registration, the Mac's Allow, PKCE, the token,
// and the tools (through the phone API). No network beyond this Mac's loopback.
let app=NSApplication.shared;app.setActivationPolicy(.accessory)
func check(_ ok:Bool,_ what:String) {if !ok {print("FAIL: \(what)");exit(1)};print("PASS: \(what)")}
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-connector."))
 UserDefaults.standard.setVolatileDomain(["companionEnabled":true,"mobilePushEnabled":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 let model=AppModel();CompanionServer.shared.model=model
 var record=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
 record.title="Website feedback";record.items=[DisplayItem(kind:.user,text:"Draft the email"),DisplayItem(kind:.assistant,text:"Here's the draft.",phase:.final)]
 let session=model.insertSession(record)
 let connector=ConnectorServer.shared
 var asked:[(UUID,String)]=[]
 connector.onRequest={asked.append(($0,$1))}
 func get(_ path:String,_ query:[String:String]=[:],headers:[String:String]=[:]) async -> HTTPResponse {await connector.respond(to:HTTPRequest(method:"GET",path:path,query:query,headers:headers,body:Data()))}
 func post(_ path:String,_ body:Data,headers:[String:String]=[:]) async -> HTTPResponse {await connector.respond(to:HTTPRequest(method:"POST",path:path,query:[:],headers:headers,body:body))}
 func json(_ r:HTTPResponse) -> JSON {(try? JSONDecoder().decode(JSON.self,from:r.body)) ?? .null}

 // Discovery: an unsigned call says where to sign in.
 let bare=await post("/mcp",Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8))
 check(bare.status==401 && bare.headers["WWW-Authenticate"]?.contains("resource_metadata=") == true,"unsigned MCP call gets 401 with resource metadata")
 let resource=json(await get("/.well-known/oauth-protected-resource"))
 check(resource["authorization_servers"]?.array?.first?.string=="https://connector.test","protected resource names its sign-in server")
 let server=json(await get("/.well-known/oauth-authorization-server"))
 check(server["code_challenge_methods_supported"]?.array?.first?.string=="S256" && server["registration_endpoint"] != nil,"sign-in server: PKCE S256 and registration")

 // Registration: only Claude's own redirect hosts.
 let bad=await post("/register",Data(#"{"client_name":"Elsewhere","redirect_uris":["https://evil.example/cb"]}"#.utf8))
 check(bad.status==400,"a redirect outside Claude is refused")
 let redirect="http://claude.test/api/mcp/auth_callback"
 let reg=json(await post("/register",Data(#"{"client_name":"Claude","redirect_uris":["\#(redirect)"]}"#.utf8)))
 let client=reg["client_id"]?.string ?? ""
 check(!client.isEmpty,"Claude registers")

 // Sign-in: waits for the Mac; Don't Allow sends Claude away.
 let verifier="verifier-0123456789-abcdefghijklmnopqrstuvwxyz-ABCDEFG"
 let auth=["response_type":"code","client_id":client,"redirect_uri":redirect,"code_challenge":ConnectorServer.challenge(verifier),"code_challenge_method":"S256","state":"xyz"]
 var page=await get("/authorize",auth)
 check(page.status==200 && asked.count==1 && asked[0].1=="Claude","sign-in asks the Mac to Allow")
 check(json(await get("/authorize/status",["request":asked[0].0.uuidString]))["state"]?.string=="waiting","the page waits for the Mac")
 connector.decide(asked[0].0,allow:false)
 let denied=json(await get("/authorize/status",["request":asked[0].0.uuidString]))
 check(denied["redirect"]?.string?.contains("error=access_denied") == true && denied["redirect"]?.string?.contains("state=xyz") == true,"Don't Allow returns access_denied")
 var noPKCE=auth;noPKCE["code_challenge_method"]="plain"
 page=await get("/authorize",noPKCE);check(page.status==400 && asked.count==1,"plain PKCE is refused without asking")
 page=await get("/authorize",auth)
 connector.decide(asked[1].0,allow:true)
 let approved=json(await get("/authorize/status",["request":asked[1].0.uuidString]))
 let back=URLComponents(string:approved["redirect"]?.string ?? "")
 let code=back?.queryItems?.first{$0.name=="code"}?.value ?? ""
 check(approved["state"]?.string=="approved" && !code.isEmpty && back?.queryItems?.first{$0.name=="state"}?.value=="xyz","Allow returns a code and the state")

 // Token: the wrong verifier fails (and spends the code); the right one, on a fresh code, works.
 func form(_ items:[String:String]) -> Data {var c=URLComponents();c.queryItems=items.map{URLQueryItem(name:$0.key,value:$0.value)};return Data((c.percentEncodedQuery ?? "").utf8)}
 let wrong=await post("/token",form(["grant_type":"authorization_code","code":code,"redirect_uri":redirect,"client_id":client,"code_verifier":"nope"]))
 check(wrong.status==400,"a wrong PKCE verifier is refused")
 _=await get("/authorize",auth);connector.decide(asked[2].0,allow:true)
 let code2=URLComponents(string:json(await get("/authorize/status",["request":asked[2].0.uuidString]))["redirect"]?.string ?? "")?.queryItems?.first{$0.name=="code"}?.value ?? ""
 let tokenReply=json(await post("/token",form(["grant_type":"authorization_code","code":code2,"redirect_uri":redirect,"client_id":client,"code_verifier":verifier])))
 let token=tokenReply["access_token"]?.string ?? ""
 check(!token.isEmpty && CompanionServer.shared.devices.contains{$0.name=="Claude"},"a token, listed with the paired devices")
 let reused=await post("/token",form(["grant_type":"authorization_code","code":code2,"redirect_uri":redirect,"client_id":client,"code_verifier":verifier]))
 check(reused.status==400,"a code works once")

 // MCP with the token.
 let auth2=["authorization":"Bearer \(token)"]
 func rpc(_ method:String,_ params:String="{}") async -> JSON {json(await post("/mcp",Data(#"{"jsonrpc":"2.0","id":7,"method":"\#(method)","params":\#(params)}"#.utf8),headers:auth2))}
 let hello=await rpc("initialize",#"{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}"#)
 check(hello["result"]?["serverInfo"]?["name"]?.string=="chatterbox","initialize")
 let tools=(await rpc("tools/list"))["result"]?["tools"]?.array?.compactMap{$0["name"]?.string} ?? []
 check(Set(tools)==["list_sessions","read_session","send_message","start_session","answer","stop_reply"],"six tools: \(tools)")
 let listed=(await rpc("tools/call",#"{"name":"list_sessions","arguments":{}}"#))["result"]?["content"]?.array?.first?["text"]?.string ?? ""
 check(listed.contains("Website feedback") && listed.contains(session.id.uuidString),"list_sessions shows the session")
 let read=(await rpc("tools/call",#"{"name":"read_session","arguments":{"session_id":"\#(session.id.uuidString)"}}"#))["result"]?["content"]?.array?.first?["text"]?.string ?? ""
 check(read.contains("Shelby: Draft the email") && read.contains("Here's the draft."),"read_session shows the messages")
 let missing=(await rpc("tools/call",#"{"name":"read_session","arguments":{"session_id":"\#(UUID().uuidString)"}}"#))["result"]
 check(missing?["isError"]?.bool==true,"an unknown session is an error, not a crash")
 // Revoked like a phone: the token stops working.
 if let device=CompanionServer.shared.device(forToken:token) {CompanionServer.shared.forget(device)}
 check((await post("/mcp",Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8),headers:auth2)).status==401,"a removed connector is signed out")

 // The real listener: loopback only.
 connector.start();try await Task.sleep(for:.milliseconds(300))
 let (data,_)=try await URLSession.shared.data(from:URL(string:"http://127.0.0.1:\(ConnectorServer.port)/.well-known/oauth-authorization-server")!)
 check(String(decoding:data,as:UTF8.self).contains("authorization_endpoint"),"listens on loopback")
}
Task {do {try await run();exit(0)}catch{print("FAIL:",error);exit(1)}}
app.run()
