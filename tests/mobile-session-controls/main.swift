@testable import ChatterboxTestEngine
import AppKit
let app=NSApplication.shared;app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-mobile-restart."))
 UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotEmailWatch":false,"companionEnabled":false,"mobilePushEnabled":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 let model=AppModel(),server=CompanionServer.shared;server.model=model
 UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotEmailWatch":false,"companionEnabled":true,"mobilePushEnabled":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 AppPreferences.defaults.set(true,forKey:"companionEnabled")
 func req(_ path:String,headers:[String:String]=[:],body:Data=Data("{}".utf8))->HTTPRequest {HTTPRequest(method:"POST",path:path,query:[:],headers:headers,body:body)}
 let paired=server.respond(to:req("/v1/pair",body:try Companion.encoder.encode(Companion.PairRequest(code:server.pairingCode,deviceName:"Isolated restart fixture"))),local:false)
 if paired.status != 200 {print("Pairing failure",paired.status,String(data:paired.body,encoding:.utf8) ?? "");fflush(stdout)}
 precondition(paired.status==200)
 let token=try Companion.decoder.decode(Companion.PairResponse.self,from:paired.body).token
 var record=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic)
 record.items=[DisplayItem(kind:.assistant,text:"History kept")]
 let session=model.insertSession(record);session.draft="Unsent draft"
 let path="/v1/chats/\(session.id.uuidString)/restart"
 var headers=[Companion.tokenHeader.lowercased():token]
 let unauthorized=await server.respondAsync(to:req(path),local:false);precondition(unauthorized.status==401)
 let local=await server.respondAsync(to:req(path,headers:headers),local:true);precondition(local.status==403)
 let wrongProduct=await server.respondAsync(to:req(path,headers:headers.merging(["x-chatterbox-product":"golem"]){_,b in b}),local:false);precondition(wrongProduct.status==403)
 let missing=await server.respondAsync(to:req("/v1/chats/\(UUID())/restart",headers:headers),local:false);precondition(missing.status==404)
 let probe=server.respond(to:HTTPRequest(method:"GET",path:"/v1/addresses",query:[:],headers:headers,body:Data()),local:false)
 for (k,v) in probe.headers {headers[k.lowercased()]=v}
 headers[CompanionRetry.operationHeader.lowercased()]=UUID().uuidString
 let request=req(path,headers:headers)
 let restarted=await server.respondAsync(to:request,local:false)
 precondition(restarted.status==200,"Restart failed")
 let saved=try Companion.decoder.decode(Companion.ChatDetail.self,from:restarted.body)
 precondition(saved.summary.id==session.id && session.items.map(\.text)==record.items.map(\.text) && session.draft=="Unsent draft")
 session.threadRestartStatus="Sentinel: retry must not restart again"
 let retry=await server.respondAsync(to:request,local:false)
 precondition(retry.status==200 && retry.body==restarted.body && session.threadRestartStatus!.hasPrefix("Sentinel"))
 let ledger=CompanionMutationLedger();var calls=0
 var envelope=[String:String]();for(k,v)in ledger.headers(){envelope[k.lowercased()]=v};envelope[CompanionRetry.operationHeader.lowercased()]=UUID().uuidString
 let pending=req(path,headers:envelope),device=UUID()
 let first=Task { @MainActor in await ledger.respondAsync(device:device,request:pending){ calls+=1;try? await Task.sleep(for:.milliseconds(100));return .json(["ok":true]) } }
 try await Task.sleep(for:.milliseconds(30))
 let concurrent=await ledger.respondAsync(device:device,request:pending){calls+=1;return .json(["ok":true])}
 precondition(concurrent.status==409 && calls==1)
 let final=await first.value;let replay=await ledger.respondAsync(device:device,request:pending){calls+=1;return .json(["ok":true])}
 precondition(final.status==200 && replay.body==final.body && calls==1)
 // Deletion is paired Chatterbox-only, preserves project files, and replays safely.
 let folder=URL(fileURLWithPath:root).appendingPathComponent("project")
 try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
 let source=folder.appendingPathComponent("keep.txt");try Data("source stays".utf8).write(to:source)
 var deletable=record;deletable.id=UUID();deletable.projectFolder=folder.path
 let target=model.insertSession(deletable)
 target.isRunning=true
 precondition(CompanionMapper.summary(target).turnStartedAt != nil)
 target.isRunning=false
 precondition(CompanionMapper.summary(target).turnStartedAt == nil)
 func deletion(_ headers:[String:String]) -> HTTPRequest {
  HTTPRequest(method:"DELETE",path:"/v1/chats/\(target.id)",query:[:],headers:headers,body:Data())
 }
 precondition(server.respond(to:deletion([:]),local:false).status==401)
 precondition(server.respond(to:deletion([Companion.tokenHeader.lowercased():token,"x-chatterbox-product":"golem"]),local:false).status==403)
 let agentToken=try String(contentsOf:CompanionServer.agentTokenFile,encoding:.utf8)
 precondition(server.respond(to:deletion([Companion.tokenHeader.lowercased():agentToken]),local:true).status==403)
 precondition(model.sessions.contains{$0.id==target.id})
 headers[CompanionRetry.operationHeader.lowercased()]=UUID().uuidString
 let removal=deletion(headers),removed=server.respond(to:removal,local:false)
 precondition(removed.status==200 && !model.sessions.contains{$0.id==target.id})
 precondition(FileManager.default.fileExists(atPath:source.path))
 let removedRetry=server.respond(to:removal,local:false)
 precondition(removedRetry.status==200 && removedRetry.body==removed.body)
 print("PASS: paired delete, unauthorized/agent/product rejection, turn identity, retained project files and idempotent retry")
 print("PASS: paired restart, agent/product rejection, unknown chat, history/draft preservation, cached replay and concurrent retry executes once")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)}};app.run()
