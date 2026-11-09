import http.server,json,os,time,uuid,io
from pathlib import Path
ROOT=Path(os.environ['CHATTERBOX_TEST_OUTPUT']); logs=[]; offline=False; mode="normal"
CHAT='11111111-1111-1111-1111-111111111111'; FILE='22222222-2222-2222-2222-222222222222'
def tiny_pdf(pages):
 """A minimal PDF (no third-party library): one page per list of content-stream lines, Helvetica."""
 objs=['<< /Type /Catalog /Pages 2 0 R >>',None,'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>','<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>']
 kids=[]
 for content in pages:
  stream='\n'.join(content).encode('latin-1')
  objs.append(f'<< /Length {len(stream)} >>\nstream\n'.encode('latin-1')+stream+b'\nendstream')
  objs.append(f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents {len(objs)} 0 R >>')
  kids.append(f'{len(objs)} 0 R')
 objs[1]=f'<< /Type /Pages /Kids [{" ".join(kids)}] /Count {len(kids)} >>'
 out=bytearray(b'%PDF-1.4\n'); offsets=[]
 for i,o in enumerate(objs,1):
  offsets.append(len(out)); body=o if isinstance(o,bytes) else o.encode('latin-1')
  out+=f'{i} 0 obj\n'.encode()+body+b'\nendobj\n'
 xref=len(out)
 out+=f'xref\n0 {len(objs)+1}\n0000000000 65535 f \n'.encode()+b''.join(f'{o:010d} 00000 n \n'.encode() for o in offsets)
 out+=f'trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
 return bytes(out)
PDF=tiny_pdf([['0.08 0.20 0.26 rg 0 0 612 792 re f','1 1 1 rg',
               'BT /F2 32 Tf 48 680 Td (Mobile PDF Review) Tj ET',
               f'BT /F1 18 Tf 48 620 Td (Page {n} of 3) Tj ET',
               'BT /F1 18 Tf 48 570 Td (Zoom, review, save and share.) Tj ET'] for n in range(1,4)])
summary={'id':CHAT,'title':'PDF review','backend':'codex','isRunning':False,'isWaitingOnYou':False,'updatedAt':'2026-10-02T00:00:00Z'}
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
  if self.path=='/v1/chats':return self.reply({'revision':1,'groups':[{'id':'chats','kind':'chats','title':'Chats','chats':[summary]}]})
  if self.path=='/v1/addresses':return self.reply({'addresses':['127.0.0.1']})
  if self.path.startswith('/v1/chats/'+CHAT+'?since=1'):return self.reply({'unchanged':True,'revision':1})
  if self.path.startswith('/v1/chats/'+CHAT):return self.reply({'revision':1,'summary':summary,'settings':'Codex','items':[{'id':'44444444-4444-4444-4444-444444444444','kind':'assistant','text':f'Your proof is ready. [Review PDF](chatterbox-document://{FILE})','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[file],'isQueued':False}],'earlierCount':0})
  self.send_error(404)
# The port: CHATTERBOX_TEST_PORT, or 0 for a free one (start_test_server, test-hygiene.sh);
# the one it got goes to CHATTERBOX_TEST_PORT_FILE once it's listening.
server=http.server.ThreadingHTTPServer(('127.0.0.1',int(os.environ.get('CHATTERBOX_TEST_PORT','19647'))),Handler)
PORT=server.server_address[1]
if os.environ.get('CHATTERBOX_TEST_PORT_FILE'):
 open(os.environ['CHATTERBOX_TEST_PORT_FILE']+'.tmp','w').write(str(PORT));os.rename(os.environ['CHATTERBOX_TEST_PORT_FILE']+'.tmp',os.environ['CHATTERBOX_TEST_PORT_FILE'])
print('listening on 127.0.0.1:%d'%PORT,flush=True)
server.serve_forever()
