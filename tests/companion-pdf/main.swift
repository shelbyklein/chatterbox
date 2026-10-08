import ImageIO
import AppKit
import Foundation
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
@MainActor func run() async throws {
 let root=ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!
 precondition(root.hasPrefix("/tmp/chatterbox-pdf-mac."))
 UserDefaults.standard.setVolatileDomain(["dotCheckIns":false,"dotWatchWaiting":false,"dotSummarizeFinished":false,"dotEmailWatch":false,"companionEnabled":false,"notifyNeeds":false,"notifyFinished":false,"keepMacAwake":false],forName:UserDefaults.argumentDomain)
 let model=AppModel();let chat=model.newChat(backend:.claude)
 let url=URL(fileURLWithPath:root).appendingPathComponent("Review proof.pdf")
 var box=CGRect(x:0,y:0,width:612,height:792)
 let context=CGContext(url as CFURL,mediaBox:&box,nil)!
 for _ in 0..<3 {context.beginPDFPage(nil);context.setFillColor(NSColor.blue.cgColor);context.fill(box);context.endPDFPage()};context.closePDF()
 // A large file exercises multiple bounded chunks rather than a single whole-file response.
 let handle=try FileHandle(forWritingTo:url);try handle.seekToEnd();try handle.write(contentsOf:Data(repeating:32,count:8*1024*1024));try handle.close()
 let text="Review [Review PDF](<\(url.path)>)."
 let item=DisplayItem(kind:.assistant,text:text)
 chat.appendItem(item)
 let mapped=CompanionMapper.item(item,folder:root)
 let original=try Data(contentsOf:url)
 precondition(mapped.attachments.count==1 && mapped.attachments[0].byteCount==Int64(original.count))
 let id=mapped.attachments[0].id
 precondition(mapped.text.contains("chatterbox-document://\(id.uuidString)"))
 precondition(item.text==text)
 let relative=CompanionMapper.item(DisplayItem(kind:.assistant,text:"[Review PDF](Review%20proof.pdf)"),folder:root)
 precondition(relative.text.contains("chatterbox-document://"))
 try await Task.sleep(for:.milliseconds(500))
 let token=try String(contentsOf:CompanionServer.agentTokenFile,encoding:.utf8)
 func request(_ path:String,authenticated:Bool=true) async throws -> (Data,Int) {
  var r=URLRequest(url:URL(string:"http://127.0.0.1:19648"+path)!)
  if authenticated {r.setValue(token,forHTTPHeaderField:Companion.tokenHeader)}
  let (data,response)=try await URLSession.shared.data(for:r);return (data,(response as! HTTPURLResponse).statusCode)
 }
 let path="/v1/chats/\(chat.id.uuidString)/files/\(id.uuidString)"
 let unauthorized=try await request(path,authenticated:false);precondition(unauthorized.1==401)
 let unknown=try await request("/v1/chats/\(chat.id.uuidString)/files/\(UUID().uuidString)");precondition(unknown.1==404)
 async let transfer = request(path)
 let list = try await request("/v1/chats"); precondition(list.1 == 200)
 let download = try await transfer;precondition(download.1==200 && download.0 == original)
 let attachment=Attachment(name:"Review proof.pdf",path:url.path,mediaType:"application/pdf",kind:.pdf)
 chat.appendItem(DisplayItem(kind:.user,text:"Attached proof",attachments:[attachment]))
 let attached=try await request("/v1/chats/\(chat.id.uuidString)/files/\(attachment.id.uuidString)")
 precondition(attached.1==200 && attached.0==original)
 let imageURL=URL(fileURLWithPath:root).appendingPathComponent("existing-image.png")
 let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:640,pixelsHigh:480,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 let graphics=NSGraphicsContext(bitmapImageRep:bitmap)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
 NSColor.blue.setFill();NSRect(x:0,y:0,width:640,height:480).fill()
 NSGraphicsContext.restoreGraphicsState()
 let pixels=bitmap.representation(using:.png,properties:[:])!
 try pixels.write(to:imageURL)
 let image=Attachment(name:"existing-image.png",path:imageURL.path,mediaType:"image/png",kind:.image)
 chat.appendItem(DisplayItem(kind:.user,text:"Attached image",attachments:[image]))
 let existingImage=try await request("/v1/chats/\(chat.id.uuidString)/files/\(image.id.uuidString)")
 precondition(existingImage.1==200 && existingImage.0==pixels)
 let thumbnail=CompanionMapper.summary(chat).thumbnail!
 precondition(thumbnail.id==ChatSession.mediaID(imageURL.path))
 let thumbPath="/v1/chats/\(chat.id.uuidString)/thumbnail/\(thumbnail.id.uuidString)"
 let thumb=try await request(thumbPath)
 precondition(thumb.1==200)
 let thumbSource=CGImageSourceCreateWithData(thumb.0 as CFData,nil)!
 let thumbImage=CGImageSourceCreateImageAtIndex(thumbSource,0,nil)!
 precondition(thumbImage.width == 320 && thumbImage.height == 240)
 let thumbUnauthorized=try await request(thumbPath,authenticated:false);precondition(thumbUnauthorized.1==401)
 let other=model.newChat(backend:.claude)
 let cross=try await request("/v1/chats/\(other.id.uuidString)/files/\(id.uuidString)");precondition(cross.1==404)
 let crossThumb=try await request("/v1/chats/\(other.id.uuidString)/thumbnail/\(thumbnail.id.uuidString)");precondition(crossThumb.1==404)
 try FileManager.default.removeItem(at:url)
 let missing=try await request(path);precondition(missing.1==404)
 print("PASS: portable relative/absolute links, unchanged transcript, authenticated byte-identical 8 MiB transfer, cross-chat/unknown/missing rejection, attachment and image transfer compatibility")
}
Task { @MainActor in
 do {try await run();exit(0)}catch{print("FAIL: \(error)");exit(1)}
}
app.run()
