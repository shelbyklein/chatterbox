import http.server,json,os,uuid
from pathlib import Path
# Isolated fixture: one long project chat whose reply "streams" when the test calls /test/advance.
PORT=int(os.environ.get('CHATTERBOX_TEST_PORT','47410'))
CHAT='33333333-3333-3333-3333-333333333333'
revision=1; extra=[]; streamed=0
def item(key,kind,text,streaming=False):
 return dict(id=str(uuid.uuid5(uuid.NAMESPACE_URL,'scroll:'+key)),kind=kind,text=text,isStreaming=streaming,isCommentary=False,isPending=False,attachments=[],isQueued=False)
def summary():return {'id':CHAT,'title':'Long chat','project':'Long chat','backend':'claude','isRunning':streamed>0,'isWaitingOnYou':False,'updatedAt':'2026-10-02T00:00:00Z','isDot':False}
def items():
 out=[]
 for n in range(1,31):
  out.append(item(f'u{n}','user',f'Question {n:02d}'))
  out.append(item(f'a{n}','assistant',f'Answer {n:02d}. '+'This is a reply with enough words to wrap across a few lines on a phone. '*3))
 if streamed:out.append(item('stream','assistant','Streaming reply. '+'More text arrives. '*streamed*4,True))
 return out+extra
def detail():
 options={'backend':'claude','model':'default','effort':'','mode':'default','claudeModels':[{'id':'default','name':'Default','detail':'Recommended','efforts':[]}],'codexModels':[],'modes':[{'id':'default','title':'Default','detail':'Ask before changes','systemImage':'lock','isUnrestricted':False}],'presets':[]}
 return {'revision':revision,'summary':summary(),'settings':'Claude · Opus','items':items(),'earlierCount':0,'options':options}
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def reply(self,x,status=200):
  b=json.dumps(x).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(b)));self.send_header('Cache-Control','no-store');self.end_headers()
  try:self.wfile.write(b)
  except BrokenPipeError:pass
 def do_POST(self):
  global revision,streamed
  self.rfile.read(int(self.headers.get('Content-Length',0)))
  if self.path=='/v1/pair':return self.reply({'token':'fixture','macName':'Regression Mac','addresses':['127.0.0.1']})
  if self.path=='/test/advance':streamed+=1;revision+=1;return self.reply({'revision':revision})
  if self.path=='/v1/chats/'+CHAT+'/messages':
   extra.append(item(f'sent{len(extra)}','user','Sent from the test '+str(len(extra))));revision+=1
   return self.reply(detail())
  self.send_error(404)
 def do_GET(self):
  if self.path=='/v1/chats':return self.reply({'revision':revision,'groups':[{'id':'projects','kind':'projects','title':'Projects','chats':[summary()]}]})
  if self.path=='/v1/addresses':return self.reply({'addresses':['127.0.0.1']})
  if self.path=='/v1/avatar':return self.reply({'files':[]})
  if self.path.startswith('/v1/chats/'+CHAT):return self.reply({'unchanged':True,'revision':revision} if f'?since={revision}' in self.path else detail())
  self.send_error(404)
http.server.ThreadingHTTPServer(('127.0.0.1',PORT),Handler).serve_forever()
