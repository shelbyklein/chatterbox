import Foundation
import Darwin
func check(_ ok: @autoclosure () throws -> Bool, _ text: String) throws {
    guard try ok() else { throw RuntimeFailure(text) }; print("PASS: \(text)")
}
@MainActor func run() async throws {
    let root = RuntimePaths.data
    precondition(root.path.hasPrefix("/tmp/golem-promotion."))
    AppPreferences.defaults.setVolatileDomain(["companionEnabled": true,"mobilePushEnabled": false,"codexFolder":root.path], forName: UserDefaults.argumentDomain)
    let runtime = try ConversationRuntime(root:root), model = DaemonContext(runtime), server = CompanionServer.shared
    server.model = model
    func request(_ path:String,_ method:String="POST",_ body:Data=Data("{}".utf8),_ headers:[String:String]=[:]) -> HTTPRequest {
        HTTPRequest(method:method,path:path,query:[:],headers:headers,body:body)
    }
    let paired = server.respond(to:request("/v1/pair","POST",try Companion.encoder.encode(Companion.PairRequest(code:server.pairingCode,deviceName:"Promotion fixture"))),local:false)
    try check(paired.status == 200,"paired fixture")
    let token = try Companion.decoder.decode(Companion.PairResponse.self,from:paired.body).token
    let headers = [Companion.tokenHeader.lowercased():token]
    func make() throws -> ChatSession {
        var record = ConversationRecord(model:"opus",effort:"medium",personality:.friendly)
        record.items=[DisplayItem(kind:.user,text:"Original prompt"),DisplayItem(kind:.assistant,text:"Original reply")]
        record.tags=["Keep"]
        let chat = try runtime.insert(record)
        runtime.updateDraft(chat,text:"Unsent draft",attachments:[])
        return chat
    }
    func post(_ chat:ChatSession,_ body:Companion.PromotionRequest,_ extra:[String:String]=[:]) throws -> HTTPResponse {
        server.respond(to:request("/v1/chats/\(chat.id)/promote","POST",try Companion.encoder.encode(body),headers.merging(extra){_,b in b}),local:false)
    }
    func saved(_ chat:ChatSession) throws -> ConversationRecord {
        try Companion.decoder.decode(ConversationRecord.self,from:Data(contentsOf:root.appendingPathComponent("Conversations/\(chat.id).json")))
    }
    let chat=try make(), original=chat.record
    let payload=Companion.PromotionRequest(kind:.studio,name:"Design Lab")
    let path="/v1/chats/\(chat.id)/promote", body=try Companion.encoder.encode(payload)
    try check(server.respond(to:request(path,"POST",body),local:false).status==401,"unpaired promotion rejected")
    try check(server.respond(to:request(path,"POST",body,headers),local:true).status != 200,"agent promotion rejected")
    try check(post(chat,payload,["x-chatterbox-product":"golem"]).status==403,"wrong product rejected")
    chat.isRunning=true
    try check(post(chat,payload).status==409 && runtime.studios.isEmpty,"running chat refused before creating a folder")
    chat.isRunning=false
    let probe=server.respond(to:request("/v1/addresses","GET",Data(),headers),local:false)
    var envelope=[String:String]();for(k,v) in probe.headers { envelope[k.lowercased()]=v }
    envelope[CompanionRetry.operationHeader.lowercased()]=UUID().uuidString
    let promoted=try post(chat,payload,envelope)
    try check(promoted.status==200,"new Studio promotion succeeds")
    let retry=try post(chat,payload,envelope)
    try check(retry.body==promoted.body && runtime.studios.count==1,"retry replays without duplicate Studio")
    try check(chat.id==original.id && chat.items==original.items && chat.draft=="Unsent draft" && chat.record.tags==original.tags && chat.record.claudeMode==original.claudeMode,"history identity draft tags and permissions preserved")
    try check(saved(chat).studioID==runtime.studios[0].id,"Studio membership is durable before response")
    try check(FileManager.default.fileExists(atPath:runtime.studios[0].designFile),"new Studio contains design guide")
    let current=try make(), originalFolder=current.workingFolder
    try check(post(current,.init(kind:.studio,studioID:runtime.studios[0].id)).status==200 && current.workingFolder==originalFolder,"existing Studio keeps current folder by default")
    let shared=try make()
    try check(post(shared,.init(kind:.studio,studioID:runtime.studios[0].id,keepFolder:false)).status==200 && shared.workingFolder==runtime.studios[0].folder,"existing Studio can use shared folder")
    let stale=try make()
    try check(post(stale,.init(kind:.studio,studioID:UUID())).status==409 && stale.record.studioID==nil,"stale Studio keeps source chat")
    let folder=root.appendingPathComponent("Existing")
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let file=folder.appendingPathComponent("keep.txt");try Data("source stays".utf8).write(to:file)
    let project=try make()
    try check(post(project,.init(kind:.project,folder:folder.path)).status==200,"existing Project folder succeeds")
    try check(saved(project).projectFolder==folder.path && project.draft=="Unsent draft","Project binding and draft persist")
    let collision=try make()
    try check(post(collision,.init(kind:.project,folder:folder.path)).status==409 && collision.record.projectFolder==nil,"owned Project folder rejected without replacing either chat")
    let newProject=try make()
    try check(post(newProject,.init(kind:.project,folder:root.path,newFolderName:"New Project")).status==200,"new Project subfolder succeeds")
    try check(saved(newProject).projectFolder==root.appendingPathComponent("New Project").path,"new Project path saved")
    try check(post(collision,.init(kind:.project,folder:root.path,newFolderName:"../escape")).status==409,"folder name traversal rejected")
    try check(post(collision,.init(kind:.project,folder:file.path)).status==409,"file is not accepted as a project folder")
    let unknown=try make();unknown.record.sidechatOf=chat.id
    try check(post(unknown,payload).status==409,"Sidechat promotion rejected")
    try check(String(contentsOf:file)=="source stays","existing project files untouched")
    let browse=HTTPRequest(method:"GET",path:"/v1/project-folders",query:["path":root.path],headers:headers,body:Data())
    let folders=await server.respondAsync(to:browse,local:false)
    try check(folders.status==200,"paired folder browser succeeds")
    let listing=try Companion.decoder.decode(Companion.ProjectFolders.self,from:folders.body)
    try check(listing.folders.contains{$0.name=="Existing"} && !listing.folders.contains{$0.name=="keep.txt"},"browser contains only directories")
    let noToken=HTTPRequest(method:"GET",path:browse.path,query:browse.query,headers:[:],body:Data())
    let unauthorized=await server.respondAsync(to:noToken,local:false)
    try check(unauthorized.status==401,"unpaired folder browsing rejected")
    let localBrowse=await server.respondAsync(to:browse,local:true)
    try check(localBrowse.status==403,"agent folder browsing rejected")
    // A storage failure rolls back the record and the newly-created empty folder.
    let failure=try make(), conversation=root.appendingPathComponent("Conversations/\(failure.id).json")
    try FileManager.default.removeItem(at:conversation)
    try FileManager.default.createDirectory(at:conversation,withIntermediateDirectories:false)
    let failed=try post(failure,.init(kind:.project,folder:root.path,newFolderName:"Failed Project"))
    try check(failed.status==409 && failure.record.projectFolder==nil && failure.items.count==2 && failure.draft=="Unsent draft","save failure restores chat in memory")
    try check(!FileManager.default.fileExists(atPath:root.appendingPathComponent("Failed Project").path),"failed promotion removes only its new empty folder")
    try FileManager.default.removeItem(at:conversation);try runtime.flush()
    try check(saved(failure).projectFolder==nil,"restored chat saves after storage recovers")
}
Task { @MainActor in do {try await run();exit(0)}catch{print("FAIL:",error);exit(1)} }
RunLoop.main.run()
