import AppKit
import CryptoKit
import ScreenCaptureKit
import SwiftUI
import Vision
@testable import ChatterboxTestEngine
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-push."))
    UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,
        "dotEmailWatch":false,"companionEnabled":true,"keepMacAwake":false,"mobilePushConfigured":false,
        "themeBackground":"black", GolemMiniWindow.visibleKey:false, GolemMiniWindow.collapsedKey:true], forName:UserDefaults.argumentDomain)
    let key = P256.Signing.PrivateKey()
    let credentials = PushCredentials(keyID:"ABCDEFGHIJ",teamID:"9F3MKVW9C5",pem:key.pemRepresentation)
    let jwt = try APNsJWT.make(credentials,now:Date(timeIntervalSince1970:1234))
    let pieces = jwt.split(separator:".").map(String.init)
    func decode(_ s:String)->Data { let v=s.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/"); return Data(base64Encoded:v+String(repeating:"=",count:(4-v.count%4)%4))! }
    let sig = try P256.Signing.ECDSASignature(rawRepresentation:decode(pieces[2]))
    precondition(key.publicKey.isValidSignature(sig,for:Data((pieces[0]+"."+pieces[1]).utf8)))
    let claims = try JSONSerialization.jsonObject(with:decode(pieces[1])) as! [String:Any]
    precondition(claims["iat"] as? Int == 1234 && claims["iss"] as? String == "9F3MKVW9C5")
    print("PASS ES256 JWT signature and claims")
    let chatID=UUID()
    let event=MobilePush.Event(title:"Private email",body:"Private contents",chat:chatID,kind:"email")
    let redacted = try JSONSerialization.jsonObject(with:MobilePush.payload(event,previews:false,sound:false)) as! [String:Any]
    let redactedData=try JSONSerialization.data(withJSONObject:redacted)
    precondition(!String(decoding:redactedData,as:UTF8.self).contains("Private"))
    precondition(redacted["chat"] as? String == chatID.uuidString)
    let aps=redacted["aps"] as! [String:Any];precondition(aps["sound"]==nil)
    let request=APNsProvider.request(token:String(repeating:"a",count:64),environment:"sandbox",jwt:jwt,payload:Data(),collapse:"test")
    precondition(request.url!.host=="api.sandbox.push.apple.com" && request.value(forHTTPHeaderField:"apns-topic")==APNsProvider.topic)
    print("PASS payload privacy, deep-link chat ID and APNs request headers")
    let folder=root.appendingPathComponent("Dot/Avatar");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for name in ["head.png","idle.mov","thinking.mov"] {
        let original=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Chatterbox/Dot/Avatar/"+name)
        if FileManager.default.fileExists(atPath:original.path) {try FileManager.default.copyItem(at:original,to:folder.appendingPathComponent(name))}
    }
    let model=AppModel()
    CompanionServer.shared.setEnabled(true)
    try await Task.sleep(for:.milliseconds(400))
    func call(_ path:String,method:String="POST",body:Data?=nil,token:String?=nil) async throws -> (Data,Int) {
        var r=URLRequest(url:URL(string:"http://127.0.0.1:19650"+path)!);r.httpMethod=method;r.httpBody=body
        if let token {r.setValue(token,forHTTPHeaderField:Companion.tokenHeader)}
        let (data,response)=try await URLSession.shared.data(for:r);return(data,(response as! HTTPURLResponse).statusCode)
    }
    let registration=Companion.PushRegistration(token:String(repeating:"b",count:64),environment:"sandbox",enabled:true)
    let encoded=try JSONEncoder().encode(registration)
    let unauth=try await call("/v1/push",body:encoded);precondition(unauth.1==401)
    let paired=try await call("/v1/pair",body:JSONEncoder().encode(Companion.PairRequest(code:CompanionServer.shared.pairingCode,deviceName:"Push test")))
    let pair=try Companion.decoder.decode(Companion.PairResponse.self,from:paired.0)
    let invalid=try await call("/v1/push",body:Data("{\"token\":\"bad\",\"environment\":\"production\",\"enabled\":true}".utf8),token:pair.token);precondition(invalid.1==400)
    let accepted=try await call("/v1/push",body:encoded,token:pair.token);precondition(accepted.1==200)
    precondition(CompanionServer.shared.devices.first!.push==registration)
    var disabled=registration;disabled.enabled=false
    let off=try await call("/v1/push",body:JSONEncoder().encode(disabled),token:pair.token);precondition(off.1==200 && CompanionServer.shared.devices.first!.push?.enabled==false)
    let oldData=try JSONSerialization.data(withJSONObject:["id":UUID().uuidString,"name":"Old phone","tokenHash":"hash","pairedAt":0])
    let oldDevice=try JSONDecoder().decode(CompanionServer.Device.self,from:oldData)
    precondition(oldDevice.push==nil)
    let deleted=try await call("/v1/push",method:"DELETE",token:pair.token);precondition(deleted.1==200 && CompanionServer.shared.devices.first!.push==nil)
    CompanionServer.shared.forget(CompanionServer.shared.devices.first!)
    let revoked=try await call("/v1/push",body:encoded,token:pair.token);precondition(revoked.1==401)
    print("PASS pairing-auth registration, invalid-token rejection, disable, deletion, revocation and old-device decoding")
    CompanionServer.shared.setEnabled(false)
    let dot=model.ensureDot()
    dot.appendItem(DisplayItem(kind:.notice,text:"Email for you · Joan Carter: Press inquiry. Suggested: review the request."))
    let image=NSImage(contentsOfFile:"Chatterbox/Assets.xcassets/Gmail.imageset/gmail.png")!;image.setName("Gmail")
    let panel=NSPanel(contentRect:NSRect(x:20,y:20,width:640,height:700),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.appearance=NSAppearance(named:.darkAqua)
    func capture(_ window:NSWindow,_ name:String) async throws {
        try await Task.sleep(for:.seconds(2))
        let target=try await SCShareableContent.currentProcess.windows.first{$0.windowID==CGWindowID(window.windowNumber)}!
        let config=SCStreamConfiguration();config.width=Int(window.frame.width);config.height=Int(window.frame.height);config.ignoreShadowsSingleWindow=true
        let cg=try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:target),configuration:config)
        try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
    }
    panel.contentView=NSHostingView(rootView:Form{MobilePushSettings()}.formStyle(.grouped));panel.orderFrontRegardless()
    try await capture(panel,"setup")
    panel.contentView=NSHostingView(rootView:DotConversation(session:dot).environment(model).padding(24).frame(width:640,height:160))
    try await capture(panel,"gmail")
    panel.orderOut(nil)
    let mini=GolemMiniWindow(model:model);mini.show()
    mini.panel!.backgroundColor = .windowBackgroundColor
    mini.panel!.isOpaque = true
    try await capture(mini.panel!,"shadow");mini.hide()
    print("PASS rendered Mac push setup, Gmail card and Golem shadow (review screenshots)")
}
Task {do {try await run();exit(0)}catch{print("FAIL \(error)");exit(1)}}
app.run()
