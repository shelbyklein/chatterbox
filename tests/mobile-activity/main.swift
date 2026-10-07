@testable import ChatterboxTestEngine
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() throws {
 let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-mobile-activity."))
 UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyReplies":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 let model=AppModel()
 var r=ConversationRecord(model:"opus",effort:"medium",personality:.pragmatic);r.title="Timeline fixture"
 let s=model.insertSession(r)
 let before=Date();s.isRunning=true;s.isRunning=false;s.isRunning=false
 precondition(s.record.turnCompletions?.count==1)
 let first=s.record.turnCompletions![0]
 precondition(first.endedAt>=before && first.endedAt<=Date() && first.chatID==s.id)
 s.isRunning=true;s.isRunning=false
 precondition(s.record.turnCompletions?.count==2 && s.record.turnCompletions![1].id != first.id)
 let saved=try JSONEncoder().encode(s.record), restored=try JSONDecoder().decode(ConversationRecord.self,from:saved)
 precondition(restored.turnCompletions==s.record.turnCompletions)
 var old=try JSONSerialization.jsonObject(with:saved) as! [String:Any];old.removeValue(forKey:"turnCompletions")
 let legacy=try JSONDecoder().decode(ConversationRecord.self,from:JSONSerialization.data(withJSONObject:old));precondition(legacy.turnCompletions==nil)
 let payload=CompanionMapper.chatList(model,product:"chatterbox")
 precondition(payload.activity?.count==2 && payload.activity![0].endedAt>=payload.activity![1].endedAt)
 precondition(CompanionMapper.chatList(model,product:"golem").activity==nil)
 let encoded=try Companion.encoder.encode(payload),decoded=try Companion.decoder.decode(Companion.ChatList.self,from:encoded)
 precondition(decoded.activity?.map(\.id)==payload.activity?.map(\.id))
 precondition(abs(decoded.activity![0].endedAt.timeIntervalSince(payload.activity![0].endedAt))<1)
 for _ in 0..<501 {s.isRunning=true;s.isRunning=false}
 precondition(s.record.turnCompletions?.count==500 && CompanionMapper.chatList(model,product:"chatterbox").activity?.count==500)
 print("PASS exact ends, duplicate prevention, persistence, legacy records, ordered export, Golem isolation, wire codec, bounded retention")
}
Task { @MainActor in do {try run();exit(0)} catch {print(error);exit(1)} };app.run()
