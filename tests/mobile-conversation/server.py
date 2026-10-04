import http.server,json,os,time,uuid,subprocess
from pathlib import Path
ROOT=Path(os.environ['CHATTERBOX_TEST_OUTPUT']); logs=[]; revision=1; delay_next=False; structured=False
IDS=['11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333']
def summary(i):return {'id':IDS[i],'title':['Codex fixture','Claude project'][i],'backend':['codex','claude'][i],'isRunning':False,'isWaitingOnYou':False,'updatedAt':'2026-10-02T00:00:00Z','isDot':i==0 and os.environ.get('GOLEM_TEST_PRODUCT')=='golem'}
def detail(i):
 def item(n,kind,text,**extra):return dict(id=str(uuid.uuid5(uuid.NAMESPACE_URL,f'{i}:{n}')),kind=kind,text=text,isStreaming=False,isCommentary=False,isPending=False,attachments=[],isQueued=False,**extra)
 items=[item(1,'user','What changed on mobile?'),item(2,'tool','Reading the mobile layout',toolState='done'),item(3,'assistant','The mobile layout is ready. Each paragraph has its own bubble.\n\nCodex uses green and Claude uses orange, so you can tell which agent you are talking to.\n\n**Next:** try it on your phone and iPad. Your existing chats and attachments stay available.')]
 if i==0 and structured:
  items[-1]['text']='- Review the page\n- Check the contrast\n\n```swift\nlet greeting = "Hello"\n\nprint(greeting)\n```\n\n| Name | State |\n|---|---|\n| Preview | Ready |'
 if i==1:items=[item(1,'user','Can you review this layout?'),item(3,'assistant','I reviewed the layout. The controls fit on the phone and the reading column stays centered on iPad.')]
 options={'backend':['codex','claude'][i],'model':'default','effort':'','mode':'default','claudeModels':[{'id':'default','name':'Default','detail':'Recommended','efforts':[]}],'codexModels':[{'id':'default','name':'Default','detail':'Recommended','efforts':[]}],'modes':[{'id':'default','title':'Default','detail':'Ask before changes','systemImage':'lock','isUnrestricted':False}],'presets':[]}
 return {'revision':revision,'summary':summary(i),'settings':['Codex · GPT-6.1-Sol','Claude · Opus'][i],'items':items,'earlierCount':0,'options':options,'contextFraction':0.32,'contextTokens':32000,'contextWindow':100000}
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
  logs.append({'method':'POST','path':self.path})
  if self.path=='/v1/golem/read':return self.reply({'ok':True})
  self.send_error(400,'No chat writes allowed')
 def do_GET(self):
  global delay_next,structured,revision
  if self.path=='/test/log':return self.reply(logs)
  if self.path=='/test/structured':structured=True;revision+=1;return self.reply({'ok':True})
  if self.path=='/test/light':
   subprocess.run(['xcrun','simctl','ui',(ROOT/'simulator').read_text(),'appearance','light'],check=True)
   return self.reply({'ok':True})
  delayed=delay_next and self.path.startswith('/v1/chats/'+IDS[0])
  if delayed:delay_next=False
  logs.append({'method':'GET','path':self.path,'time':time.time(),'delayed':delayed}); (ROOT/'requests.json').write_text(json.dumps(logs))
  if delayed:time.sleep(8)
  if self.path=='/v1/chats':return self.reply({'revision':revision,'groups':[{'id':'dot' if summary(0)['isDot'] else 'chats','kind':'dot' if summary(0)['isDot'] else 'chats','title':'Chats','chats':[summary(0)]},{'id':'projects','kind':'projects','title':'Projects','chats':[summary(1)]}]})
  if self.path=='/v1/addresses':return self.reply({'addresses':['127.0.0.1']})
  if self.path=='/v1/avatar':return self.reply({'files':[]})
  for i,ident in enumerate(IDS):
   if self.path.startswith('/v1/chats/'+ident):return self.reply({'unchanged':True,'revision':revision} if f'?since={revision}' in self.path else detail(i))
  self.send_error(404)
http.server.ThreadingHTTPServer(('127.0.0.1',19646),Handler).serve_forever()
