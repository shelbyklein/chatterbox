import Foundation
import CoreGraphics
struct MobileError: Error {let message:String}
@main struct Test {
 static func main() throws {
  let chat=UUID();let id=UUID();var file=Companion.File(id:id,name:"Proof.pdf",mediaType:"application/pdf",isImage:false,revision:"1",byteCount:nil)
  let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf")
  defer{try? FileManager.default.removeItem(at:temp)}
  var box=CGRect(x:0,y:0,width:100,height:100);let ctx=CGContext(temp as CFURL,mediaBox:&box,nil)!;ctx.beginPDFPage(nil);ctx.endPDFPage();ctx.closePDF()
  let entry=try MobilePDFCache.save(temp,file:file,chat:chat)
  defer{try? MobilePDFCache.remove(entry)}
  precondition(MobilePDFCache.cached(file,chat:chat) != nil)
  file.revision="2";_ = try MobilePDFCache.save(temp,file:file,chat:chat)
  precondition(MobilePDFCache.cached(file,chat:chat)?.file.revision=="2")
  try Data("not a pdf".utf8).write(to:temp)
  do {_ = try MobilePDFCache.save(temp,file:file,chat:chat);fatalError("corrupt PDF accepted")}catch{}
  precondition(MobilePDFCache.cached(file,chat:chat)?.file.revision=="2")
  print("PASS: saved cache, valid replacement, corrupt refresh preserves previous PDF")
 }
}
