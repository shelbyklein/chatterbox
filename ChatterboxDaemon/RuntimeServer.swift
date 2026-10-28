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
            if let chat=event.chatID.flatMap(self.runtime.session) {
                if ["approval.waiting","question.waiting"].contains(event.kind){
                    MobilePush.shared.post(title:chat.title,body:chat.items.last(where:{$0.approvalState == .pending})?.text ?? "This session needs you",chat:chat.id,kind:"needs",identity:"event-\(event.sequence)")
                }else if event.kind=="turn.finished" {
                    MobilePush.shared.post(title:chat.title,body:chat.items.last(where:{$0.kind == .assistant && $0.phase == .final})?.text ?? "Reply finished",chat:chat.id,kind:"replies",identity:"event-\(event.sequence)")
                }
            }
        }
    }
    func stop(){source?.cancel();source=nil;if listenFD>=0{Darwin.close(listenFD);listenFD = -1};for p in peers.values{p.stop()};peers.removeAll();unlink(socketURL.path);try? runtime.flush();runtime.waitForSaves()}
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
                guard ["agent","ui"].contains(role) else {throw RuntimeFailure("permission_denied")}
                guard role != "ui" || (peer.isTrustedUI && RuntimePeerIdentity.permitsUIRole(role,fd:peer.fd,root:root)) else {throw RuntimeFailure("permission_denied")}
                roles[peer.id]=role
                peer.send(RuntimeReply(id:r.id,result:["version":1,"priorityList":true,"navigationSummaries":true,"role":.string(role),"sequence":.number(Double(runtime.state.sequence))]));return
            }
            guard let role=roles[peer.id] else {throw RuntimeFailure("handshake_required")}
            if ["approve","answer","studios","metadata","delete","settings","remoteControl","restartTools","restartThread","shell","stopShell","companion","connector","preferences"].contains(r.operation), role != "ui" {
                throw RuntimeFailure("permission_denied")
            }
            if r.operation == "preferences", r.body["proxyClaudeChats"] != nil || r.body["proxyCodexChats"] != nil {
                await EasyCLIProxy.shared.refresh()
            }
            let result:JSON
            switch r.operation {
            case "health":result=["version":1,"sequence":.number(Double(runtime.state.sequence))]
            case "codexModels":
                guard role == "ui" else { throw RuntimeFailure("permission_denied") }
                try await CodexAppServer.shared.refreshModels()
                result = .array(CodexAppServer.shared.models.map { model in
                    ["model": .string(model.model), "displayName": .string(model.displayName),
                     "defaultEffort": .string(model.defaultEffort),
                     "efforts": .array(model.efforts.map(JSON.string)),
                     "hidden": .bool(model.hidden), "isDefault": .bool(model.isDefault)]
                })
            case "getStudios":result=try .value(runtime.studios)
            case "getPins":result=try .value(PinStore.shared.pins)
            case "getPreferences":
                guard role=="ui" else{throw RuntimeFailure("permission_denied")}
                var values:[String:JSON]=[:]
                for key in RuntimePreferences.keys.subtracting(["companionDevices","pins"]){
                    guard let value=AppPreferences.defaults.object(forKey:key) else{continue}
                    if let string=value as? String{values[key] = .string(string)}
                    else if let number=value as? NSNumber{values[key]=CFGetTypeID(number)==CFBooleanGetTypeID() ? .bool(number.boolValue):.number(number.doubleValue)}
                    else if let list=value as? [String]{values[key] = .array(list.map(JSON.string))}
                }
                result = .object(values)
            case "pushStatus", "testPush":
                guard role == "ui" else { throw RuntimeFailure("permission_denied") }
                let push = MobilePush.shared
                if r.operation == "pushStatus" {
                    result = ["configured": .bool(push.configured), "enabled": .bool(push.enabled),
                              "optedIn": .bool(AppPreferences.defaults.object(forKey: "mobilePushEnabled") as? Bool ?? true),
                              "status": .string(push.deliveryStatus)]
                } else {
                    guard let deviceID = r.body["deviceID"]?.string.flatMap(UUID.init(uuidString:)),
                          CompanionServer.shared.devices.contains(where: { $0.id == deviceID }) else { throw RuntimeFailure("permission_denied") }
                    let fingerprint = SHA256.hash(data: try r.body.encoded()).map { String(format: "%02x", $0) }.joined()
                    result = try await runtime.executeAsync(id: r.id, operation: r.operation, fingerprint: fingerprint) {
                        let status = try await push.testDelivery(deviceID, identity: r.id)
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
            case "pcErrand":
                // "Do that on the PC": like a sidequest, but on Shelby-PC and the same agent.
                // Here, not with the receipts: copying files to the PC takes a while.
                let task=(r.body["task"]?.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
                guard !task.isEmpty else{throw RuntimeFailure("invalid_sidequest")}
                let parent=try chat(r.body)
                guard role=="ui" || (role=="agent" && parent.isRunning && !parent.isSidequest) else{throw RuntimeFailure("permission_denied")}
                let files=(r.body["files"]?.array ?? []).compactMap(\.string)
                let backend=r.body["agent"]?.string.flatMap(Backend.init(rawValue:))
                result = .string(try await DaemonContext(runtime).newPCErrand(of:parent,task:task,files:files,backend:backend).id.uuidString)
            case "refreshSecrets", "authorizeSecret":
                // Only Chatterbox's signed Settings window can inspect availability or
                // request a native prompt. Agents cannot use this as a key broker.
                guard role == "ui" else { throw RuntimeFailure("permission_denied") }
                let vault = SecretVault.shared
                try vault.reload()
                var authorized: Bool?
                if r.operation == "authorizeSecret" {
                    guard let id = r.body["secretID"]?.string.flatMap(UUID.init(uuidString:)),
                          vault.entries.contains(where: { $0.id == id }) else { throw RuntimeFailure("secret_not_found") }
                    authorized = await vault.authorize(id)
                }
                // No key material, and no persisted command receipt. Claude compares the
                // environment fingerprint before its next message; active turns continue.
                var status: [String: JSON] = ["availability": .object(Dictionary(vault.entries.map {
                    ($0.id.uuidString, JSON.bool(vault.hasValue($0)))
                }, uniquingKeysWith: { _, last in last }))]
                if let authorized { status["authorized"] = .bool(authorized) }
                result = .object(status)
            case "authorizePush":
                // Push notifications are signed here, so this process needs its own Keychain
                // access to the APNs key: the key's ACL lists programs by signing identity,
                // and the app's "Always Allow" doesn't cover chatterboxd. This read may show
                // the system Keychain prompt, so it runs off the main thread (other chats keep
                // being answered while it's open). Only Chatterbox's signed window may ask; the
                // reply carries the outcome, never key material. Reading changes nothing, so
                // there's no command receipt.
                guard role=="ui" else{throw RuntimeFailure("permission_denied")}
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
                guard role=="ui" else{throw RuntimeFailure("permission_denied")}
                let server=CompanionServer.shared
                result=["enabled":.bool(server.isEnabled),"running":.bool(server.isRunning),"problem":server.problem.map(JSON.string) ?? .null,"pairingCode":.string(server.pairingCode),"devices":try .value(server.devices)]
            case "subscribe":
                let cursor=r.body["after"]?.int ?? 0;let replay=runtime.events(after:cursor)
                subscribed.insert(peer.id)
                result=["resync":.bool(replay.resync),"sequence":.number(Double(runtime.state.sequence)),"events":try .value(replay.events)]
            case "list":result=try .value(runtime.snapshots(workingOnly:r.body["workingOnly"]?.bool == true, summaryOnly:r.body["summaryOnly"]?.bool == true))
            case "get":
                let s=try chat(r.body)
                if r.body["summaryOnly"]?.bool == true { result = try .value(runtime.navigationSnapshot(s)); break }
                var record=s.record
                if r.body["limit"] != nil { record.claudeHost = nil; record.codexHost = nil }
                var end = s.items.count
                if let before = r.body["before"]?.string {
                    guard let id = UUID(uuidString: before), let index = s.items.firstIndex(where: { $0.id == id }) else { throw RuntimeFailure("history_cursor_not_found") }
                    end = index
                }
                let start = r.body["limit"]?.int.map { max(0, end - max(40,min(500,$0))) } ?? 0
                record.items = Array(s.items[start..<end])
                result=try .value(RuntimeChatState(record:record,running:s.isRunning,revision:runtime.state.revisions[s.id.uuidString] ?? 0,draft:RuntimeDraft(text:s.draft,attachments:s.draftAttachments),totalCount:s.items.count,pendingItems:s.pendingRequests,summary:runtime.navigationSnapshot(s).summary,historyStart:start))
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
                let s=try chat(r.body)
                runtime.updateDraft(s,text:r.body["text"]?.string ?? "",attachments:try r.body["attachments"]?.decode([Attachment].self) ?? [])
                result = .null
            default:
                let fingerprint=SHA256.hash(data:try r.body.encoded()).map{String(format:"%02x",$0)}.joined()
                result=try runtime.execute(id:r.id,operation:r.operation,fingerprint:fingerprint) {try mutate(r,role:role)}
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
            return .string(try runtime.insert(record).id.uuidString)
        case "connector":
            if let id=r.body["request"]?.string.flatMap(UUID.init(uuidString:)),let allow=r.body["allow"]?.bool{ConnectorServer.shared.decide(id,allow:allow)}
        case "companion":
            let server=CompanionServer.shared
            if let enabled=r.body["enabled"]?.bool{server.setEnabled(enabled)}
            if r.body["newCode"]?.bool==true{server.newPairingCode()}
            if let id=r.body["forget"]?.string.flatMap(UUID.init(uuidString:)),let device=server.devices.first(where:{$0.id==id}){server.forget(device)}
        case "preferences":
            let previousClaude = EasyCLIProxy.shared.claudeOn
            try RuntimePreferences.update(r.body.object ?? [:])
            if previousClaude != EasyCLIProxy.shared.claudeOn {
                for session in runtime.sessions where session.record.backend == .claude {
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
        case "archive":try chat(r.body).setArchived(r.body["archived"]?.bool ?? true)
        case "rename":try chat(r.body).setTitle(r.body["title"]?.string ?? "")
        case "setBrief":
            guard role=="ui" else{throw RuntimeFailure("permission_denied")}
            try chat(r.body).setBrief(r.body["brief"]?.string ?? "")
        case "delete":guard role=="ui" else{throw RuntimeFailure("permission_denied")};let s=try chat(r.body);try runtime.remove(s.id)
        case "sidequest":
            let task=(r.body["task"]?.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            guard !task.isEmpty else{throw RuntimeFailure("invalid_sidequest")}
            let parent=try chat(r.body)
            // An agent may start one only from a chat that's mid-reply (its own).
            guard role=="ui" || (role=="agent" && parent.isRunning && !parent.isSidequest) else{throw RuntimeFailure("permission_denied")}
            return .string(try DaemonContext(runtime).newSidequest(of:parent,task:task).id.uuidString)
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
            if let x=body["runOn"]{s.setRunOn(x.string)}
            if let x=body["openModel"]{s.setOpenModel(x.string)}
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
