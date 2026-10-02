import http.server,json,os,time,uuid,io
from pathlib import Path
from reportlab.pdfgen import canvas
ROOT=Path(os.environ['CHATTERBOX_TEST_OUTPUT']); logs=[]; offline=False; mode="normal"
CHAT='11111111-1111-1111-1111-111111111111'; FILE='22222222-2222-2222-2222-222222222222'
buf=io.BytesIO(); c=canvas.Canvas(buf,pagesize=(612,792))
for n in range(1,4):
 c.setFillColorRGB(.08,.20,.26);c.rect(0,0,612,792,fill=1,stroke=0)
 c.setFillColorRGB(1,1,1); c.setFont('Helvetica-Bold',32); c.drawString(48,680,'Mobile PDF Review'); c.setFont('Helvetica',18);c.drawString(48,620,f'Page {n} of 3');c.drawString(48,570,'Zoom, review, save and share.'); c.showPage()
c.save();PDF=buf.getvalue()
summary={'id':CHAT,'title':'Golem','backend':'codex','isRunning':False,'isWaitingOnYou':False,'updatedAt':'2026-10-02T00:00:00Z','isDot':True}
file={'id':FILE,'name':'Review proof.pdf','mediaType':'application/pdf','isImage':False,'revision':'fixture-1','byteCount':len(PDF)}
class Handler(http.server.BaseHTTPRequestHandler):
 def reply(self,x):
  b=json.dumps(x).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
 def do_POST(self):
  self.rfile.read(int(self.headers.get('Content-Length',0)))
  if self.path=='/v1/pair':return self.reply({'token':'fixture-only','macName':'PDF Regression Mac','addresses':['127.0.0.1']})
  self.send_error(400)
 def do_GET(self):
  global offline,mode
  if self.path=='/test/offline':offline=True;return self.reply({'ok':True})
  if self.path=='/test/log':return self.reply(logs)
  if self.path.startswith('/test/mode/'):
   mode=self.path.rsplit('/',1)[-1];return self.reply({'ok':True})
  logs.append(self.path);(ROOT/'requests.json').write_text(json.dumps(logs))
  if '/files/' in self.path:
   if offline:return self.send_error(503)
   body=(PDF+ b' '* (8*1024*1024)) if mode=='slow' else (b'not a PDF' if mode=='bad' else PDF)
   self.send_response(200);self.send_header('Content-Type','application/pdf');self.send_header('Content-Length',str(len(body)));self.end_headers()
   try:
    for start in range(0,len(body),65536):
     self.wfile.write(body[start:start+65536]);self.wfile.flush()
     if mode=='slow':time.sleep(.1)
   except (BrokenPipeError,ConnectionResetError):pass
   return
  if self.path=='/v1/chats':return self.reply({'revision':1,'groups':[{'id':'dot','kind':'dot','title':'Assistant','chats':[summary]}]})
  if self.path=='/v1/addresses':return self.reply({'addresses':['127.0.0.1']})
  if self.path=='/v1/avatar':return self.reply({'files':[]})
  if self.path.startswith('/v1/chats/'+CHAT+'?since=1'):return self.reply({'unchanged':True,'revision':1})
  if self.path.startswith('/v1/chats/'+CHAT):return self.reply({'revision':1,'summary':summary,'settings':'Codex','items':[{'id':'44444444-4444-4444-4444-444444444444','kind':'assistant','text':f'Your proof is ready. [Review PDF](chatterbox-document://{FILE})','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[file],'isQueued':False}],'earlierCount':0})
  self.send_error(404)
http.server.ThreadingHTTPServer(('127.0.0.1',19647),Handler).serve_forever()
