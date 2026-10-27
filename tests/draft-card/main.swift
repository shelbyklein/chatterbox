@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// A ```draft block in a reply: rendered as a card, with the email's subject apart and the
// text copied clean. Evidence: draft-card.png.
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-draft-card."))
 let reply="""
 Here's a draft to Lauren.

 ```draft
 Subject: USA Archery website: feedback and next steps

 Hey Lauren,

 Could you walk us through the following?

 - **Site audit:** Was an audit done?
 - **Sitemap:** Where will today's menu items live?

 Thanks,
 Shelby
 ```

 Before you send: the doc still mixes stages.
 """
 let card=DraftCard(draft:"Subject: USA Archery website: feedback and next steps\n\nHey Lauren,\n\n- **Site audit:** Was an audit done?\n  - *nested* point\n\nThanks,\nShelby")
 precondition(card.parts.subject=="USA Archery website: feedback and next steps","the subject is apart")
 precondition(card.parts.body.hasPrefix("Hey Lauren,"),"the body starts after the subject")
 let plain=DraftCard.plain(card.parts.body)
 precondition(plain=="Hey Lauren,\n\n• Site audit: Was an audit done?\n    • nested point\n\nThanks,\nShelby","plain copy drops Markdown marks: \(plain)")
 let rich=DraftCard.rich(card.parts.body)!
 let back=NSAttributedString(rtf:rich,documentAttributes:nil)!
 precondition(back.string==plain,"the formatted copy has the same text")
 var bold=false
 back.enumerateAttribute(.font,in:NSRange(location:0,length:back.length)) { v,_,_ in if let f=v as? NSFont, NSFontManager.shared.traits(of:f).contains(.boldFontMask) || (f.fontDescriptor.object(forKey:.traits) as? [NSFontDescriptor.TraitKey:Any])?[.weight] as? CGFloat ?? 0 > 0 { bold=true } }
 precondition(bold,"the formatted copy keeps bold")
 let mail=DraftCard.mailURL(subject:"Hi & bye",body:"Line one\nLine two")!.absoluteString
 precondition(mail.hasPrefix("mailto:?subject=Hi") && mail.contains("body=Line%20one%0ALine%20two"),"a mail link with subject and body: \(mail)")
 precondition(DraftCard(draft:"Just a text message").parts.subject==nil,"no subject: a plain draft")
 print("PASS subject apart, plain and formatted copies, mail link")
 let panel=NSPanel(contentRect:NSRect(x:40,y:80,width:640,height:520),styleMask:[.titled],backing:.buffered,defer:false)
 panel.appearance=NSAppearance(named:.darkAqua)
 panel.contentView=NSHostingView(rootView:MarkdownText(text:reply).padding(20).frame(width:640,alignment:.topLeading).background(Color(white:0.1)).environment(\.colorScheme,.dark))
 panel.orderFrontRegardless()
 try await Task.sleep(for:.milliseconds(700))
 let view=panel.contentView!;view.layoutSubtreeIfNeeded()
 let rendered=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
 view.cacheDisplay(in:view.bounds,to:rendered)
 try rendered.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:root).appendingPathComponent("draft-card.png"))
 panel.close()
 print("PASS rendered. Evidence: \(root)/draft-card.png")
}
Task { @MainActor in do {try await run();exit(0)}catch{print(error);exit(1)} }
app.run()
