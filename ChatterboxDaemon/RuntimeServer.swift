import Foundation
import Darwin
import CryptoKit
import CoreFoundation

@MainActor final class RuntimeServer {
    let runtime:ConversationRuntime
    let root:URL
    private let socketURL:URL
    private var listenFD:Int32 = -1
    private var source:DispatchSourceRead?
    private var peers:[UUID:RuntimePeer]=[:]
    private var roles:[UUID:String]=[:]
    private var subscribed:Set<UUID>=[]
    init(runtime:ConversationRuntime,root:URL=RuntimePaths.data){self.runtime=runtime;self.root=root;socketURL=root.appendingPathComponent("daemon.sock")}
    func start() throws {
        guard let fd=UnixSocket.listen(at:socketURL) else {throw RuntimeFailure("Cannot listen on daemon socket")}
        listenFD=fd
        _ = fcntl(fd,F_SETFL,O_NONBLOCK)
        let source=DispatchSource.makeReadSource(fileDescriptor:fd,queue:.main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated {self?.accept()} }
        self.source=source;source.resume()
        runtime.onEvent={ [weak self] event in
            guard let self else{return}
            for id in self.subscribed {self.peers[id]?.send(RuntimeReply(event:event))}
            if let chat=event.chatID.flatMap(self.runtime.session),!chat.isDot {
                if ["approval.waiting","question.waiting"].contains(event.kind){
                    MobilePush.shared.post(title:chat.title,body:chat.items.last(where:{$0.approvalState == .pending})?.text ?? "This chat needs you",chat:chat.id,kind:"needs",identity:"event-\(event.sequence)")
                }else if event.kind=="turn.finished" {
                    MobilePush.shared.post(title:chat.title,body:chat.items.last(where:{$0.kind == .assistant && $0.phase == .final})?.text ?? "Reply finished",chat:chat.id,kind:"replies",identity:"event-\(event.sequence)")
                }
            }
        }
    }
    func stop(){source?.cancel();source=nil;if listenFD>=0{Darwin.close(listenFD);listenFD = -1};for p in peers.values{p.stop()};peers.removeAll();unlink(socketURL.path);try? runtime.flush()}
    private func accept(){
        while true {
            let fd=Darwin.accept(listenFD,nil,nil);if fd<0{return}
            // macOS inherits O_NONBLOCK from the listener; dedicated reader threads block.
            _ = fcntl(fd,F_SETFL,fcntl(fd,F_GETFL) & ~O_NONBLOCK)
            var uid:uid_t=0;var gid:gid_t=0
            guard getpeereid(fd,&uid,&gid)==0,uid==getuid(),peers.count<64 else {Darwin.close(fd);continue}
            var noSignal:Int32=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout<Int32>.size))
            var timeout=timeval(tv_sec:5,tv_usec:0);setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
            let peer=RuntimePeer(fd:fd,trustedUI:RuntimePeerIdentity.trustedUI(fd,root:root));peers[peer.id]=peer
            Thread { [weak self,peer] in
                var buffer=Data(),chunk=[UInt8](repeating:0,count:65536)
                while true {
                    let n=Darwin.read(fd,&chunk,chunk.count)
                    if n<0,errno==EINTR{continue};if n<=0{break}
                    buffer.append(contentsOf:chunk.prefix(n))
                    if buffer.count>2*1024*1024{break}
                    while let newline=buffer.firstIndex(of:10){
                        let line=buffer.subdata(in:buffer.startIndex..<newline);buffer.removeSubrange(buffer.startIndex...newline)
                        guard let request=try? JSONDecoder().decode(RuntimeRequest.self,from:line) else {peer.send(RuntimeReply(error:"Malformed request"));continue}
                        Task { @MainActor [weak self] in await self?.handle(request,peer:peer) }
                    }
                }
                peer.stop()
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.peers[peer.id]=nil;self?.roles[peer.id]=nil;self?.subscribed.remove(peer.id) } }
            }.start()
        }
    }
    private func handle(_ r:RuntimeRequest,peer:RuntimePeer) async {
        do {
            guard r.version==1 else {throw RuntimeFailure("unsupported_version")}
            if r.operation=="hello" {
                let role=r.body["role"]?.string ?? "agent"
                guard ["agent","golem","ui","golem-ui"].contains(role) else {throw RuntimeFailure("permission_denied")}
                guard !["ui","golem-ui"].contains(role) || (peer.isTrustedUI && RuntimePeerIdentity.permitsUIRole(role,fd:peer.fd,root:root)) else {throw RuntimeFailure("permission_denied")}
                roles[peer.id]=role
                peer.send(RuntimeReply(id:r.id,result:["version":1,"role":.string(role),"sequence":.number(Double(runtime.state.sequence)),"integrationEnabled":.bool(runtime.state.integrationEnabled)]));return
            }
            guard let role=roles[peer.id] else {throw RuntimeFailure("handshake_required")}
            if role=="golem-ui" {
                let allowed:Set<String>=["health","subscribe","list","get","getStudios","getPins","draft","setDraft","ensureAssistant","send","sendNow","sendQueuedNow","stop","answer","approve","rename","metadata","settings","remoteControl","restartTools","restartThread","getPreferences","preferences","companionStatus","companion","authorizePush","pushStatus","testPush","setGolemPushEnabled","codexModels"]
                guard allowed.contains(r.operation) else{throw RuntimeFailure("permission_denied")}
                if let raw=r.body["record"],let record=try? raw.decode(ConversationRecord.self),(record.isDot != true || runtime.session(record.id)?.isDot != true){throw RuntimeFailure("permission_denied")}
                if r.operation=="preferences",!Set((r.body.object ?? [:]).keys).isSubset(of:["dotDefaultBackend","dotDefaultModel","dotApplyDefault","dotSeenItem"]){throw RuntimeFailure("permission_denied")}
                if r.operation=="companion" {
                    if r.body["newCode"]?.bool==true{throw RuntimeFailure("permission_denied")}
                    if let id=r.body["forget"]?.string.flatMap(UUID.init(uuidString:)),CompanionServer.shared.devices.first(where:{$0.id==id})?.product != "golem"{throw RuntimeFailure("permission_denied")}
                }
                if !["get","draft"].contains(r.operation),let id=r.body["chatID"]?.string.flatMap(UUID.init(uuidString:)),runtime.session(id)?.isDot != true{throw RuntimeFailure("permission_denied")}
            }
            if ["approve","answer","integration","studios","metadata","delete","settings","remoteControl","restartTools","restartThread","shell","stopShell","companion","preferences"].contains(r.operation), !["ui","golem-ui"].contains(role) {
                throw RuntimeFailure("permission_denied")
            }
            if ["golem","agent","golem-ui"].contains(role),!runtime.state.integrationEnabled,!["health","subscribe"].contains(r.operation) {throw RuntimeFailure("integration_disabled")}
            if r.operation == "preferences", r.body["proxyClaudeChats"] != nil || r.body["proxyCodexChats"] != nil {
                await EasyCLIProxy.shared.refresh()
            }
            let result:JSON
            switch r.operation {
            case "health":result=["version":1,"sequence":.number(Double(runtime.state.sequence)),"integrationEnabled":.bool(runtime.state.integrationEnabled)]
            case "codexModels":
                guard ["ui", "golem-ui"].contains(role) else { throw RuntimeFailure("permission_denied") }
                try await CodexAppServer.shared.refreshModels()
                result = .array(CodexAppServer.shared.models.map { model in
                    ["model": .string(model.model), "displayName": .string(model.displayName),
                     "defaultEffort": .string(model.defaultEffort),
                     "efforts": .array(model.efforts.map(JSON.string)),
                     "hidden": .bool(model.hidden), "isDefault": .bool(model.isDefault)]
                })
            case "getStudios":result=try .value(runtime.studios)
            case "getPins":result=try .value(PinStore.shared.pins)
            case "assistantNotes":result=try .value(runtime.state.assistantNotes ?? [])
            case "getPreferences":
                guard ["ui","golem-ui"].contains(role) else{throw RuntimeFailure("permission_denied")}
                var values:[String:JSON]=[:]
                for key in RuntimePreferences.keys.subtracting(["companionDevices","pins"]){
                    guard let value=AppPreferences.defaults.object(forKey:key) else{continue}
                    if let string=value as? String{values[key] = .string(string)}
                    else if let number=value as? NSNumber{values[key]=CFGetTypeID(number)==CFBooleanGetTypeID() ? .bool(number.boolValue):.number(number.doubleValue)}
                }
                result = .object(values)
            case "setGolemPushEnabled":
                guard ["ui", "golem-ui"].contains(role), let enabled = r.body["enabled"]?.bool else { throw RuntimeFailure("permission_denied") }
                try RuntimePreferences.update(["golemPushEnabled": .bool(enabled)])
                result = ["enabled": .bool(MobilePush.shared.enabled(forProduct: "golem"))]
            case "pushStatus", "testPush":
                guard ["ui", "golem-ui"].contains(role) else { throw RuntimeFailure("permission_denied") }
                let product = r.body["product"]?.string ?? (role == "golem-ui" ? "golem" : "chatterbox")
                guard ["golem", "chatterbox"].contains(product), role != "golem-ui" || product == "golem" else { throw RuntimeFailure("permission_denied") }
                let push = MobilePush.shared
                if r.operation == "pushStatus" {
                    result = ["configured": .bool(push.configured), "enabled": .bool(push.enabled(forProduct: product)),
                              "optedIn": .bool(product == "golem" ? (AppPreferences.defaults.object(forKey: "golemPushEnabled") as? Bool ?? (AppPreferences.defaults.object(forKey: "mobilePushEnabled") as? Bool ?? true)) : (AppPreferences.defaults.object(forKey: "mobilePushEnabled") as? Bool ?? true)),
                              "status": .string(push.deliveryStatus(product: product))]
                } else {
                    guard let deviceID = r.body["deviceID"]?.string.flatMap(UUID.init(uuidString:)),
                          CompanionServer.shared.devices.contains(where: { $0.id == deviceID && ($0.product ?? "chatterbox") == product }) else { throw RuntimeFailure("permission_denied") }
                    let fingerprint = SHA256.hash(data: try r.body.encoded()).map { String(format: "%02x", $0) }.joined()
                    result = try await runtime.executeAsync(id: r.id, operation: r.operation, fingerprint: fingerprint) {
                        let status = try await push.testDelivery(deviceID, product: product, identity: r.id)
                        return ["accepted": true, "status": .string(status)]
                    }
                }
            case "runAutomation":
                // "Run Now" on a project's automation; only Chatterbox's own window may ask.
                guard role=="ui" else{throw RuntimeFailure("permission_denied")}
                guard let id=r.body["id"]?.string.flatMap(UUID.init(uuidString:)),
                      let automation=ProjectAutomations.load().first(where:{$0.id==id}) else{throw RuntimeFailure("That automation is gone.")}
                guard let runner=AutomationRunner.shared else{throw RuntimeFailure("Automations aren't running yet.")}
                result=["threadID":.string(try runner.run(automation,manual:true).uuidString)]
            case "authorizePush":
                // Push notifications are signed here, so this process needs its own Keychain
                // access to the APNs key: the key's ACL lists programs by signing identity,
                // and the app's "Always Allow" doesn't cover chatterboxd. This read may show
                // the system Keychain prompt, so it runs off the main thread (other chats keep
                // being answered while it's open). Only a signed product window may ask; the
                // reply carries the outcome, never key material. Reading changes nothing, so
                // there's no command receipt.
                guard ["ui","golem-ui"].contains(role) else{throw RuntimeFailure("permission_denied")}
                let outcome=await Task.detached(priority:.userInitiated) { () -> (authorized:Bool,status:String) in
                    do {
                        _ = try PushCredentials.read(allowInteraction:true)
                        return (true,"Keychain access verified for the background service. If the system asked, Always Allow keeps future pushes automatic.")
                    } catch {
                        return (false,error.localizedDescription)
                    }
                }.value
                result=["authorized":.bool(outcome.authorized),"status":.string(outcome.status)]
            case "companionStatus":
                guard ["ui","golem-ui"].contains(role) else{throw RuntimeFailure("permission_denied")}
                let server=CompanionServer.shared
                result=["enabled":.bool(server.isEnabled),"running":.bool(server.isRunning),"problem":server.problem.map(JSON.string) ?? .null,"pairingCode":.string(role=="golem-ui" ? "":server.pairingCode),"golemPairingCode":.string(server.golemPairingCode),"devices":try .value(server.devices.filter{role != "golem-ui" || $0.product=="golem"})]
            case "subscribe":
                let cursor=r.body["after"]?.int ?? 0;let replay=runtime.events(after:cursor)
                subscribed.insert(peer.id)
                result=["resync":.bool(replay.resync),"sequence":.number(Double(runtime.state.sequence)),"events":try .value(replay.events)]
            case "list":result=try .value(runtime.snapshots())
            case "get":
                let s=try chat(r.body)
                var record=s.record
                if let limit=r.body["limit"]?.int {record.items=Array(record.items.suffix(max(40,min(500,limit))))}
                result=try .value(RuntimeChatState(record:record,running:s.isRunning,revision:runtime.state.revisions[s.id.uuidString] ?? 0,draft:RuntimeDraft(text:s.draft,attachments:s.draftAttachments),totalCount:s.items.count))
            case "restartThread":
                let s = try chat(r.body)
                let fingerprint = SHA256.hash(data: try r.body.encoded()).map { String(format: "%02x", $0) }.joined()
                result = try await runtime.executeAsync(id: r.id, operation: r.operation, fingerprint: fingerprint) {
                    await s.restartThread()
                    return ["status": s.threadRestartStatus.map(JSON.string) ?? .null]
                }
            case "draft":
                let s=try chat(r.body);result=try .value(RuntimeDraft(text:s.draft,attachments:s.draftAttachments))
            case "setDraft":
                // The newest draft simply replaces the last, so it needs no command receipt and no
                // conversation rewrite; its save is coalesced. Each keystroke used to rewrite the
                // runtime state three times and the whole chat file, backing up every request.
                guard role != "golem-ui" || (try? chat(r.body))?.isDot == true else { throw RuntimeFailure("permission_denied") }
                let s=try chat(r.body)
                runtime.updateDraft(s,text:r.body["text"]?.string ?? "",attachments:try r.body["attachments"]?.decode([Attachment].self) ?? [])
                result = .null
            default:
                let fingerprint=SHA256.hash(data:try r.body.encoded()).map{String(format:"%02x",$0)}.joined()
                result=try runtime.execute(id:r.id,operation:r.operation,fingerprint:fingerprint) {try mutate(r,role:role=="golem-ui" ? "ui":role)}
            }
            peer.send(RuntimeReply(id:r.id,result:result))
        }catch {peer.send(RuntimeReply(id:r.id,error:error.localizedDescription))}
    }
    private func chat(_ body:JSON) throws -> ChatSession {
        guard let id=body["chatID"]?.string.flatMap(UUID.init(uuidString:)),let s=runtime.session(id) else {throw RuntimeFailure("chat_not_found")};return s
    }
    private func mutate(_ r:RuntimeRequest,role:String) throws -> JSON {
        switch r.operation {
        case "create":
            guard let raw=r.body["record"] else{throw RuntimeFailure("invalid_record")}
            let record=try raw.decode(ConversationRecord.self)
            guard role=="ui" || record.isDot != true else {throw RuntimeFailure("permission_denied")}
            return .string(try runtime.insert(record).id.uuidString)
        case "integration":
            guard role=="ui",let enabled=r.body["enabled"]?.bool else{throw RuntimeFailure("permission_denied")}
            try runtime.setIntegrationEnabled(enabled)
        case "companion":
            let server=CompanionServer.shared
            if let enabled=r.body["enabled"]?.bool{server.setEnabled(enabled)}
            if r.body["newCode"]?.bool==true{server.newPairingCode()}
            if let id=r.body["forget"]?.string.flatMap(UUID.init(uuidString:)),let device=server.devices.first(where:{$0.id==id}){server.forget(device)}
        case "preferences":
            let previousClaude = EasyCLIProxy.shared.claudeOn
            try RuntimePreferences.update(r.body.object ?? [:])
            if previousClaude != EasyCLIProxy.shared.claudeOn {
                for session in runtime.sessions where !session.isDot && session.record.backend == .claude {
                    session.restartClaudeForNewTools()
                }
            }
            runtime.publishConfiguration()
        case "pins":
            guard role=="ui",let raw=r.body["pins"] else{throw RuntimeFailure("permission_denied")}
            let pins=try raw.decode([Pin].self)
            PinStore.shared.applyRuntimePins(pins)
            AppPreferences.defaults.set(try JSONEncoder().encode(pins),forKey:"pins");try RuntimePreferences.persistCurrent()
            runtime.publishConfiguration()
        case "studios":
            guard role=="ui",let raw=r.body["studios"] else{throw RuntimeFailure("permission_denied")}
            try runtime.updateStudios(raw.decode([Studio].self))
        case "metadata":
            guard role=="ui",let raw=r.body["record"] else{throw RuntimeFailure("permission_denied")}
            let incoming=try raw.decode(ConversationRecord.self)
            guard let s=runtime.session(incoming.id) else{throw RuntimeFailure("chat_not_found")}
            let oldFolder=s.record.boundFolder
            s.setTitle(incoming.title);s.setBackend(incoming.backend)
            s.setModel(incoming.model);s.setEffort(incoming.effort);s.setPersonality(incoming.personality)
            s.record.projectNickname=incoming.projectNickname;s.record.tags=incoming.tags
            s.record.projectFolder=incoming.projectFolder;s.record.studioID=incoming.studioID;s.record.studioFolder=incoming.studioFolder
            s.record.sidechatOf=incoming.sidechatOf;s.record.sidechatFolder=incoming.sidechatFolder;s.record.sidechatProjectFolder=incoming.sidechatProjectFolder
            s.record.studioWorkingFolder=incoming.studioWorkingFolder;s.record.convertedProjectFolder=incoming.convertedProjectFolder
            s.record.worktreeOf=incoming.worktreeOf;s.record.worktreeBranch=incoming.worktreeBranch
            s.record.githubRepo=incoming.githubRepo;s.record.gitRemote=incoming.gitRemote
            s.record.claudeMode=incoming.claudeMode;s.record.claudeFastMode=incoming.claudeFastMode
            if let remote=incoming.remoteControl,remote != s.record.remoteControl{s.setRemoteControl(remote)}
            s.record.currentIssue=incoming.currentIssue
            if let c=incoming.codex {
                s.setCodexModel(c.model);s.setCodexEffort(c.effort)
                s.setCodexFolder(c.folder);s.record.codex?.mode=c.mode;s.record.codex?.fastMode=c.fastMode;s.record.codex?.route=c.route
            }
            if oldFolder != s.record.boundFolder{s.claudeWorkingFolderChanged()}
            s.onChange?(s)
        case "ensureAssistant":return .string(try runtime.ensureAssistant().id.uuidString)
        case "sendAutomatic":
            guard role=="golem" else {throw RuntimeFailure("permission_denied")}
            let s=try runtime.ensureAssistant()
            let text=r.body["text"]?.string ?? "",label=r.body["label"]?.string ?? "Check-in"
            s.send(text)
            if let i=s.record.items.lastIndex(where:{$0.kind == .user}) {s.record.items[i].automatic=true;s.record.items[i].detail=label}
            s.automaticTurn=true;s.onChange?(s)
        case "ackAssistantNotes":
            guard role=="golem" else{throw RuntimeFailure("permission_denied")}
            let ids=Set(try r.body["ids"]?.decode([String].self) ?? [])
            try runtime.ackAssistantNotes(ids)
        case "notify":
            guard role=="golem" else{throw RuntimeFailure("permission_denied")}
            if let id=r.body["itemID"]?.string.flatMap(UUID.init(uuidString:)),let assistant=runtime.assistant,
               let index=assistant.items.firstIndex(where:{$0.id==id}),
               let seen=AppPreferences.defaults.string(forKey:"dotSeenItem").flatMap(UUID.init(uuidString:)),
               let seenIndex=assistant.items.firstIndex(where:{$0.id==seen}),index<=seenIndex{return ["suppressed":true]}
            MobilePush.shared.post(title:r.body["title"]?.string ?? "Golem",body:r.body["text"]?.string ?? "",chat:runtime.assistant?.id,kind:"golem",identity:r.id)
        case "send", "sendNow":
            let s=try chat(r.body);let text=r.body["text"]?.string ?? ""
            let files=try r.body["attachments"]?.decode([Attachment].self) ?? []
            if r.operation=="sendNow" {s.sendNow(text,attachments:files)}else{s.send(text,attachments:files)}
        case "stop":try chat(r.body).interrupt()
        case "sendQueuedNow":
            guard let id=r.body["itemID"]?.string.flatMap(UUID.init(uuidString:)) else{throw RuntimeFailure("item_not_found")}
            try chat(r.body).sendQueuedNow(id)
        case "answer", "approve":
            guard role=="ui" else{throw RuntimeFailure("permission_denied")}
            let s=try chat(r.body)
            guard let id=r.body["itemID"]?.string.flatMap(UUID.init(uuidString:)) else{throw RuntimeFailure("item_not_found")}
            if r.operation=="answer" {
                // Skip sends no answers (missing or null): the agent carries on without them.
                let raw=r.body["answers"]
                s.answerQuestions(id,answers:raw == nil || raw == .null ? nil : try raw!.decode([String:[String]].self))
            }
            else {guard let decision=r.body["decision"]?.string.flatMap(DisplayItem.ApprovalState.init(rawValue:)),[.approved,.approvedForSession,.denied].contains(decision) else{throw RuntimeFailure("invalid_decision")};s.resolveApproval(id,decision)}
        case "suggest":
            let s=try chat(r.body)
            guard let id=r.body["itemID"]?.string.flatMap(UUID.init(uuidString:)),let answers=r.body["answers"] else {throw RuntimeFailure("invalid_suggestion")}
            try s.suggestAnswers(id,answers:answers.decode([String:[String]].self),reason:r.body["reason"]?.string ?? "",by:r.body["by"]?.string ?? "Golem")
        case "archive":try chat(r.body).setArchived(r.body["archived"]?.bool ?? true)
        case "rename":try chat(r.body).setTitle(r.body["title"]?.string ?? "")
        case "delete":guard role=="ui" else{throw RuntimeFailure("permission_denied")};let s=try chat(r.body);try runtime.remove(s.id)
        case "sidequest":
            let task=(r.body["task"]?.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            guard role=="ui",!task.isEmpty else{throw RuntimeFailure("invalid_sidequest")}
            return .string(try DaemonContext(runtime).newSidequest(of:try chat(r.body),task:task).id.uuidString)
        case "returnSidequest":
            let s=try chat(r.body)
            guard let parent=s.record.sidequestOf.flatMap(runtime.session) else{throw RuntimeFailure("chat_not_found")}
            s.returnSidequest(to:parent)
        case "fork":
            guard role=="ui",let fork=DaemonContext(runtime).fork(try chat(r.body)) else{throw RuntimeFailure("cannot_fork")}
            return .string(fork.id.uuidString)
        case "settings":
            guard role=="ui" else{throw RuntimeFailure("permission_denied")}
            let s=try chat(r.body),body=r.body
            if let x=body["backend"]?.string.flatMap(Backend.init(rawValue:)){s.setBackend(x)}
            if let x=body["model"]?.string{s.setModel(x)}
            if let x=body["effort"]?.string{s.setEffort(x)}
            if let x=body["codexModel"]{s.setCodexModel(x.string)}
            if let x=body["codexEffort"]{s.setCodexEffort(x.string)}
            if let x=body["codexFolder"]?.string{s.setCodexFolder(x)}
            if let x=body["fastMode"]?.bool{s.setFastMode(x)}
            if let x=body["mode"]?.string{s.setMode(x)}
            if let x=body["personality"]?.string.flatMap(Personality.init(rawValue:)){s.setPersonality(x)}
        case "remoteControl":try chat(r.body).setRemoteControl(r.body["enabled"]?.bool ?? false)
        case "restartTools":try chat(r.body).restartClaudeForNewTools()
        case "shell":try chat(r.body).runShell(r.body["command"]?.string ?? "")
        case "stopShell":try chat(r.body).stopShellJobs()
        default:throw RuntimeFailure("unsupported_operation")
        }
        return ["ok":true]
    }
}
