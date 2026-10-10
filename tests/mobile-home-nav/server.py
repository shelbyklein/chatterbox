import http.server,json,os,uuid,zlib,struct,datetime
# Isolated fixture: Golem, six projects (one a worktree, one waiting on you) and a Studio.
PORT=int(os.environ.get('CHATTERBOX_TEST_PORT','47411'))
def cid(n):return str(uuid.uuid5(uuid.NAMESPACE_URL,'home:'+n))
DOT=cid('golem')
PROJECTS=[('Chatterbox','Shipped the Next Steps plugin and the new message box.',None,False),
 ('optimization','Speed up switching between long chats.','optimization',False),
 ('SDHQ','Read SSL mode, cache rules and zone settings.',None,True),
 ('PlayCase Magnets','Finished the product photos for the store.',None,False),
 ('Galley','Phase 3 is ready for review: the typography engine.',None,False),
 ('Tracker Trapper','Checked the menu-bar progress after the update.',None,False)]
# Working now, for the Activity box (with Tracker Trapper's reply as new).
RUNNING=['Galley','Coach Archie']
REMOVED=set()
ACTIVITY=[]
READS=0
STARTED=datetime.datetime.now(datetime.timezone.utc).isoformat()
FAIL=False
MUTATIONS=[]
RENAMES={}
def completed(name):
 return {'id':str(uuid.uuid4()),'chatID':cid(name),'title':name,'backend':'claude','endedAt':datetime.datetime.now(datetime.timezone.utc).isoformat()}
def reset():
 global RUNNING,REMOVED,ACTIVITY,READS,STARTED,FAIL,MUTATIONS,RENAMES
 RUNNING=['Galley','Coach Archie'];REMOVED=set();ACTIVITY=[];READS=0
 STARTED=datetime.datetime.now(datetime.timezone.utc).isoformat();FAIL=False;MUTATIONS=[];RENAMES={}

def summary(name,line,branch=None,waiting=False,dot=False):
 s={'id':DOT if dot else cid(name),'title':name,'project':None if dot else name,'subtitle':line,'backend':'codex' if dot else 'claude','isRunning':False,'isWaitingOnYou':waiting,'updatedAt':'2026-10-03T00:00:00Z','isDot':dot}
 if name in ['Coach Archie','Chatterbox']:
  s['thumbnail']={'id':cid('thumbnail'),'name':'proof.png','mediaType':'image/png','isImage':True,'revision':'1'}
  if name=='Coach Archie':s['project']=None
 if name in ['No image','Crystal concept','Loose chat']:s['project']=None
 if name in RENAMES:s['title']=RENAMES[name]
 if branch:s['worktreeBranch']=branch
 if name in RUNNING:s['isRunning']=True;s['turnStartedAt']=STARTED
 return s
def chats():
 global READS,ACTIVITY
 READS+=1
 if READS==2:ACTIVITY.append(completed('Tracker Trapper'))
 groups=[{'id':'dot','kind':'dot','title':'Golem','chats':[summary('Golem','Ready',dot=True)]},
  {'id':'projects','kind':'projects','title':'Projects','chats':[summary(*p) for p in PROJECTS]},
  {'id':'studio-1','kind':'studio','title':'USA Archery','chats':[summary('Coach Archie','Full USA flags on both sleeves.'),summary('No image','Text-only session.')],'studioID':cid('studio')},
  {'id':'chats','kind':'chats','title':'Chats','chats':[summary('Loose chat','An ordinary chat.')]},
  {'id':'studio-2','kind':'studio','title':'Geekify','chats':[summary('Crystal concept','Purple faceted crystal.')],'studioID':cid('studio2')}]
 for g in groups:g['chats']=[c for c in g['chats'] if c['id'].lower() not in REMOVED]
 return {'revision':1,'groups':groups,'activity':ACTIVITY}

def detail(id):
 s=next(c for g in chats()['groups'] for c in g['chats'] if c['id'].lower()==id.lower())
 items=[{'id':cid(id+'u'),'kind':'user','text':'Hello','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False},
        {'id':cid(id+'a'),'kind':'assistant','text':'Hi! This is '+s['title']+'.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False}]
 if s.get('isDot'):items.append({'id':cid('email'),'kind':'notice','text':'Email for you \u00b7 Shelby Klein, \u201cFW: One pager for NASP Coaches\u201d (shelbykleindesign@gmail.com): Callie forwarded copy changes for the NASP one pager. Suggested: Apply the updated 80% discount copy.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False})
 return {'revision':1,'summary':s,'settings':'Claude · Opus','items':items,'earlierCount':0}
def thumbnail():
 def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
 w,h=240,160
 rows=b''.join(b'\0'+b''.join(bytes((40+x//3,70+y//2,140)) for x in range(w)) for y in range(h))
 return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def reply(self,x,status=200):
  b=json.dumps(x).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(b)));self.end_headers()
  try:self.wfile.write(b)
  except BrokenPipeError:pass
 def do_POST(self):
  global FAIL,STARTED
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))) or '{}')
  if self.path=='/test/reset':reset();return self.reply({'ok':True})
  if self.path=='/test/fail':FAIL=body['value'];return self.reply({'ok':True})
  if self.path=='/test/complete':
   name=body['name']
   if name in RUNNING:RUNNING.remove(name)
   ACTIVITY.append(completed(name));return self.reply({'ok':True})
  if self.path=='/test/start':
   if body['name'] not in RUNNING:RUNNING.append(body['name'])
   STARTED=datetime.datetime.now(datetime.timezone.utc).isoformat();return self.reply({'ok':True})
  if self.path.startswith('/v1/chats/') and self.path.endswith('/rename'):
   if FAIL:return self.reply({'error':'Fixture rename failed. Try again.'},503)
   id=self.path.split('/')[3].lower()
   names=[p[0] for p in PROJECTS]+['Coach Archie','No image','Crystal concept','Loose chat']
   name=next(n for n in names if cid(n)==id)
   RENAMES[name]=body['title'];MUTATIONS.append('rename');return self.reply(detail(id))
  if self.path.startswith('/v1/chats/') and self.path.endswith('/archive'):
   if FAIL:return self.reply({'error':'Fixture archive failed. Try again.'},503)
   id=self.path.split('/')[3].lower();result=detail(id);result['isArchived']=True
   REMOVED.add(id);MUTATIONS.append('archive');return self.reply(result)
  if self.path=='/v1/pair':return self.reply({'token':'fixture','macName':'Regression Mac','addresses':['127.0.0.1']})
  self.send_error(404)
 def do_DELETE(self):
  if self.path.startswith('/v1/chats/'):
   if FAIL:return self.reply({'error':'Fixture delete failed. Try again.'},503)
   REMOVED.add(self.path.split('/')[3].lower());MUTATIONS.append('delete');return self.reply({'ok':True})
  self.send_error(404)
 def do_GET(self):
  if self.path=='/test/mutations':return self.reply(MUTATIONS)
  if '/thumbnail/' in self.path:
   b=thumbnail();self.send_response(200);self.send_header('Content-Type','image/png');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b);return
  if self.path=='/v1/chats':return self.reply(chats())
  if self.path=='/v1/addresses':return self.reply({'addresses':['127.0.0.1']})
  if self.path=='/v1/avatar':return self.reply({'files':[]})
  if self.path.startswith('/v1/chats/'):
   id=self.path.split('/')[3].split('?')[0]
   return self.reply({'unchanged':True,'revision':1} if '?since=1' in self.path else detail(id))
  self.send_error(404)
http.server.ThreadingHTTPServer(('127.0.0.1',PORT),Handler).serve_forever()
