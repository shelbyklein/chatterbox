import http.server,json,os,time,uuid
from pathlib import Path
ROOT=Path(os.environ['CHATTERBOX_TEST_OUTPUT']); logs=[]; revision=1; delay_next=False
IDS=['11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333']
def summary(i):return {'id':IDS[i],'title':['Regression Golem','Regression Project'][i],'backend':'codex','isRunning':False,'isWaitingOnYou':False,'updatedAt':'2026-10-02T00:00:00Z','isDot':i==0}
def detail(i):
 items=[{'id':str(uuid.uuid5(uuid.NAMESPACE_URL,f'{i}:{n}')),'kind':'assistant','text':f'Previous message {n}. This transcript has enough rows to exercise the initial scroll layout.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False} for n in range(299)]
 items.append({'id':'44444444-4444-4444-4444-444444444444','kind':'assistant','text':f'History ready {i} version {revision}. No message was sent.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False})
 return {'revision':revision,'summary':summary(i),'settings':'Codex · GPT-6.1-Sol','items':items,'earlierCount':42}
class Handler(http.server.BaseHTTPRequestHandler):
 def reply(self,x):
  b=json.dumps(x).encode(); self.send_response(200); self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(b)));self.send_header('Cache-Control','no-store');self.end_headers()
  try:self.wfile.write(b)
  except BrokenPipeError:pass
 def do_POST(self):
  global revision,delay_next
  self.rfile.read(int(self.headers.get('Content-Length',0)))
  if self.path=='/v1/pair':return self.reply({'token':'fixture-only','macName':'Regression Mac','addresses':['127.0.0.1']})
  if self.path=='/test/delay':delay_next=True;return self.reply({'armed':True})
  if self.path=='/test/advance':revision+=1; return self.reply({'revision':revision})
  logs.append({'method':'POST','path':self.path});self.send_error(400,'No chat writes allowed')
 def do_GET(self):
  global delay_next
  if self.path=='/test/log':return self.reply(logs)
  delayed=delay_next and self.path.startswith('/v1/chats/'+IDS[0])
  if delayed:delay_next=False
  logs.append({'method':'GET','path':self.path,'time':time.time(),'delayed':delayed}); (ROOT/'requests.json').write_text(json.dumps(logs))
  if delayed:time.sleep(8)
  if self.path=='/v1/chats':return self.reply({'revision':revision,'groups':[{'id':'dot','kind':'dot','title':'Assistant','chats':[summary(0)]},{'id':'projects','kind':'projects','title':'Projects','chats':[summary(1)]}]})
  if self.path=='/v1/addresses':return self.reply({'addresses':['127.0.0.1']})
  if self.path=='/v1/avatar':return self.reply({'files':[]})
  for i,ident in enumerate(IDS):
   if self.path.startswith('/v1/chats/'+ident):return self.reply({'unchanged':True,'revision':revision} if f'?since={revision}' in self.path else detail(i))
  self.send_error(404)
http.server.ThreadingHTTPServer(('127.0.0.1',19645),Handler).serve_forever()
