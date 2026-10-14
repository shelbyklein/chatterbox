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
 // Images for the chat at the phone's size: a large render comes resized (JPEG without
 // transparency), the original without ?max, and an image already small comes as it is.
 func pixelSize(_ data:Data)->(Int,Int) { let i=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData,nil)!,0,nil)!; return (i.width,i.height) }
 let render=URL(fileURLWithPath:root).appendingPathComponent("hero-render.jpg")
 let big=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:3000,pixelsHigh:2000,bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 try big.representation(using:.jpeg,properties:[.compressionFactor:0.9])!.write(to:render)
 let reply=DisplayItem(kind:.assistant,text:"Here it is: [render](<\(render.path)>)",phase:.final)
 chat.appendItem(reply)
 let mappedReply=CompanionMapper.item(reply,folder:root)
 guard let renderFile=mappedReply.attachments.first(where:{$0.isImage && $0.name=="hero-render.jpg"}) else { print("FAIL: the render travels with the reply: \(mappedReply.attachments.map(\.name)) refs \(PathLinks.referencedFiles(in:reply.text,folder:root)) text \(reply.text)");exit(1) }
 precondition(renderFile.revision != nil,"a pointed-to image carries a revision")
 let renderPath="/v1/chats/\(chat.id.uuidString)/files/\(renderFile.id.uuidString)"
 let sized=try await request(renderPath+"?max=1200");precondition(sized.1==200)
 precondition(pixelSize(sized.0)==(1200,800),"resized to 1200 on its longer side: \(pixelSize(sized.0))")
 let full=try await request(renderPath);let renderBytes=try Data(contentsOf:render);precondition(full.1==200 && full.0==renderBytes,"the original without ?max")
 precondition(sized.0.count < full.0.count,"the chat-size copy is smaller")
 let small=try await request("/v1/chats/\(chat.id.uuidString)/files/\(image.id.uuidString)?max=1200")
 precondition(small.1==200 && small.0==pixels,"an image already small comes as it is")
 print("PASS: chat-size images (\(sized.0.count / 1024) KB instead of \(full.0.count / 1024) KB), originals, and small images as they are")
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
