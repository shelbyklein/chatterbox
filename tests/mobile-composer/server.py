import http.server,json,os,threading,time,uuid
from pathlib import Path
ROOT=Path(os.environ['CHATTERBOX_TEST_OUTPUT'])
IDS=['11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333']
logs=[]; messages=[[],[]]; hold=False; fail=False; release=threading.Event(); lock=threading.Lock(); running=False
def summary(i):return {'id':IDS[i],'title':['Regression Golem','Regression Project'][i],'backend':'codex','isRunning':running,'isWaitingOnYou':False,'updatedAt':'2026-10-02T00:00:00Z','isDot':i==0}
def detail(i):
 return {'revision':len(messages[i])+1,'summary':summary(i),'settings':'Codex','earlierCount':0,'items':[{'id':'44444444-4444-4444-4444-444444444444','kind':'assistant','text':'Ready for send regression.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False}]+messages[i]}
class Handler(http.server.BaseHTTPRequestHandler):
 def reply(self,x,status=200):
  b=json.dumps(x).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(b)));self.send_header('Cache-Control','no-store');self.end_headers()
  try:self.wfile.write(b)
  except BrokenPipeError:pass
 def do_POST(self):
  global hold,fail,running
  if self.path.startswith('/v1/') and self.path!='/v1/pair' and self.headers.get('X-Chatterbox-Token')!='fixture':return self.reply({'error':'Unauthorized'},401)
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))) or b'{}')
  if self.path=='/v1/pair':return self.reply({'token':'fixture','macName':'Regression Mac','addresses':['127.0.0.1']})
  if self.path=='/test/reset':logs.clear();messages[0].clear();messages[1].clear();hold=False;fail=False;running=False;return self.reply({})
  if self.path=='/test/running':running=True;return self.reply({})
  for i,ident in enumerate(IDS):
   if self.path in ['/v1/chats/'+ident+'/stop','/v1/chats/'+ident+'/restart']:
    logs.append({'action':self.path.rsplit('/',1)[-1]});running=False;return self.reply(detail(i))
  if self.path=='/test/hold':release.clear();hold=True;return self.reply({})
  if self.path=='/test/release':release.set();return self.reply({})
  if self.path=='/test/fail':fail=True;return self.reply({})
  for i,ident in enumerate(IDS):
   if self.path=='/v1/chats/'+ident+'/messages':
    with lock:
     delayed=hold;hold=False;failed=fail;fail=False
     logs.append({'method':'POST','chat':ident,'text':body['text'],'delayed':delayed,'failed':failed})
     (ROOT/'requests.json').write_text(json.dumps(logs))
     if not failed:messages[i].append({'id':str(uuid.uuid4()),'kind':'user','text':body['text'],'isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False})
    if delayed:release.wait(4.5)
    return self.reply({'error':'Fixture rejected send'} if failed else detail(i),500 if failed else 200)
  self.send_error(404)
 def do_GET(self):
  if self.path.startswith('/v1/') and self.headers.get('X-Chatterbox-Token')!='fixture':return self.reply({'error':'Unauthorized'},401)
  if self.path=='/test/log':return self.reply({'requests':logs,'counts':[len(x) for x in messages]})
  if self.path=='/v1/chats':return self.reply({'revision':1,'groups':[{'id':'dot','kind':'dot','title':'Assistant','chats':[summary(0)]},{'id':'projects','kind':'projects','title':'Projects','chats':[summary(1)]}], 'activity':[{'id':'55555555-5555-5555-5555-555555555555','chatID':IDS[1],'title':'Regression Project','backend':'codex','endedAt':'2026-10-06T14:00:00Z'},{'id':'66666666-6666-6666-6666-666666666666','chatID':IDS[1],'title':'Regression Project','backend':'claude','endedAt':'2026-10-06T13:00:00Z'}]})
  if self.path=='/v1/addresses':return self.reply({'addresses':['127.0.0.1']})
  if self.path=='/v1/avatar':return self.reply({'files':[]})
  for i,ident in enumerate(IDS):
   if self.path.startswith('/v1/chats/'+ident):return self.reply(detail(i))
  self.send_error(404)
http.server.ThreadingHTTPServer(('127.0.0.1',19645),Handler).serve_forever()
