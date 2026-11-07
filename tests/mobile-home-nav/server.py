import http.server,json,os,uuid,zlib,struct,datetime,time
# Isolated fixture: six projects (one a worktree, one waiting on you), Studios, and the Desk.
PORT=int(os.environ.get('CHATTERBOX_TEST_PORT','47411'))
NEWCHAT=[];CREATED=[]
def cid(n):return str(uuid.uuid5(uuid.NAMESPACE_URL,'home:'+n))
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
PROMOTIONS={}
LIST_DELAY=0
# The UX panel tour (testUXPanelTour): fuller transcripts for Galley and SDHQ, off unless asked for.
RICH=False
# Its connection-error step: every /v1 reply held past the app's 6-second timeout.
OFFLINE=False
def completed(name):
 return {'id':str(uuid.uuid4()),'chatID':cid(name),'title':name,'backend':'claude','endedAt':datetime.datetime.now(datetime.timezone.utc).isoformat()}
# The Desk (plans/front-desk.md): an approval and questions waiting, two requests to place (one
# with a proposed Studio, one with none), and what's running. Calls are recorded for asserts.
# The approval is a project's session: named by its project, with its own title under it.
PLACES=[{'kind':'studio','id':cid('studio'),'name':'USA Archery','detail':'Banners, flyers and social posts for USA Archery.'},
 {'kind':'studio','id':cid('studio2'),'name':'Geekify','detail':'3D-printed figures and crystal stands.'},
 {'kind':'project','id':cid('Chatterbox'),'name':'Chatterbox','detail':'The Mac and iPhone app for Claude and Codex sessions.'},
 {'kind':'project','id':cid('PlayCase Magnets'),'name':'PlayCase Magnets','detail':'Magnet products and their store photos.'},
 {'kind':'loose','id':None,'name':'A session of its own','detail':'Not in a Studio or project.'}]
DESK_SOURCE_PULL=None
DESK_WAITING=[];DESK_INCOMING=[];DESK_CALLS=[];DESK_REVISION=1;DESK_SILENCED=[];DESK_READY=[];DESK_DONE=[]
DESK_HOLD_ENABLED=False;DESK_HELD=[];DESK_HELD_RECORDS={}
# Tasks and work threads (plans/work-threads.md), off unless a test asks (/test/tasks): tasks linked
# to the working, ready and done threads; the Chatterbox project's session as a front thread with
# two work threads (one working, one ready). Starts and task changes are recorded in DESK_CALLS.
TASKS=False;DESK_LINKED=[]
WORK=[('work-columns','Desk board columns','working'),('work-tabs','Phone tabs','ready')]
# Chatterbox's work threads in the session list too, right after it (/test/work-listed): the two
# above and three more, newest first by hour; Desk board columns (working) is the oldest, Highlights
# sync waits on you.
WORK_LISTED=False
LISTED=[('work-tabs',5),('work-docs',4),('work-icons',3),('work-sync',2),('work-columns',1)]
LISTED_ONLY={'work-docs':('Release notes','ready'),'work-icons':('App icons','ready'),'work-sync':('Highlights sync','ready')}
def listed_summary(key,hour):
 if key in LISTED_ONLY:
  title,state=LISTED_ONLY[key]
  s={'id':cid(key),'title':title,'project':None,'subtitle':'Done: '+title.lower()+'.','backend':'claude','isRunning':False,
     'isWaitingOnYou':key=='work-sync','sidechatOf':cid('Chatterbox'),'workOf':cid('Chatterbox')}
 else:s=work_summary(key)
 s['updatedAt']='2026-11-04T%02d:00:00Z'%hour
 return s
def stamp(minutes=0):
 return (datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=minutes)).strftime('%Y-%m-%dT%H:%M:%SZ')
def place_named(name):
 return next((p for p in PLACES if p['name'].lower()==(name or '').lower()),None)
def desk_reset(empty=False):
 global DESK_SOURCE_PULL,DESK_WAITING,DESK_INCOMING,DESK_CALLS,DESK_REVISION,DESK_SILENCED,DESK_READY,DESK_DONE,DESK_HOLD_ENABLED,DESK_HELD,DESK_HELD_RECORDS
 DESK_SOURCE_PULL=None
 DESK_HOLD_ENABLED=False;DESK_HELD=[];DESK_HELD_RECORDS={}
 DESK_CALLS=[];DESK_REVISION+=1;DESK_SILENCED=[]
 # The board (plans/desk-board.md): two sessions ready to mark complete, one done this week.
 DESK_READY=[] if empty else [
  {'id':cid('PlayCase Magnets'),'title':'PlayCase Magnets','place':'PlayCase Magnets','text':'Finished the product photos for the store.','finishedAt':stamp(40)},
  {'id':cid('Chatterbox'),'title':'Chatterbox','subtitle':'Next Steps plugin','place':'Chatterbox','text':'Shipped the Next Steps plugin and the new message box.','finishedAt':stamp(180)}]
 DESK_DONE=[] if empty else [
  {'id':cid('Crystal concept'),'title':'Crystal concept','place':'Geekify','completedAt':stamp(90)}]
 DESK_WAITING=[] if empty else [
  {'id':cid('desk-approval'),'chatID':cid('SDHQ'),'title':'SDHQ','subtitle':'Cache rules','place':'SDHQ','kind':'approval','text':'Run wrangler deploy to publish the new cache rules?','detail':'wrangler deploy --env production'},
  {'id':cid('desk-questions'),'chatID':cid('Tracker Trapper'),'title':'Tracker Trapper','place':'Tracker Trapper','kind':'questions','text':'Which progress style for the menu bar: a ring or a bar?',
   'questions':[{'id':'style','header':'Style','question':'Which progress style?','options':[{'label':'Ring','detail':''},{'label':'Bar','detail':''}],'multiSelect':False,'isSecret':False}]}]
 DESK_INCOMING=[] if empty else [
  {'id':cid('desk-banner'),'text':'Make a banner for the fall archery camp','source':'claude','createdAt':stamp(12),
   'proposed':{k:v for k,v in PLACES[0].items() if k!='detail'},'note':'Camp graphics belong to USA Archery.'},
  {'id':cid('desk-printer'),'text':'Find out why the print queue stalls overnight','source':'you','createdAt':stamp(3),'proposed':None}]
def desk():
 working=[{'id':cid(n),'title':n,'place':'USA Archery' if n=='Coach Archie' else n,'since':stamp(6),
  'activity':'Editing Sources/Typography/Engine.swift' if n=='Galley' else 'Thinking\u2026'} for n in RUNNING]
 d={'revision':DESK_REVISION,'needsYou':DESK_WAITING,'incoming':DESK_INCOMING,'working':working,'silenced':DESK_SILENCED,'ready':DESK_READY,'done':DESK_DONE}
 if DESK_SOURCE_PULL is not None:d["sourcePull"]=DESK_SOURCE_PULL
 if DESK_HOLD_ENABLED:d["onHold"]=DESK_HELD
 if not TASKS:return d
 def tagged(items,key):
  out=[]
  for item in items:
   task=next((t for t in DESK_LINKED if t['chatID'].lower()==item[key].lower()),None)
   out.append(item|({'task':task['id'],'taskText':task['text']} if task else {}))
  return out
 return d|{'needsYou':tagged(DESK_WAITING,'chatID'),'working':tagged(working,'id'),'ready':tagged(DESK_READY,'id'),'done':tagged(DESK_DONE,'id'),'linked':DESK_LINKED}
def tasks_reset(on=False):
 global TASKS,DESK_LINKED
 TASKS=on
 DESK_LINKED=[{'id':cid('task-'+n),'text':t,'chatID':cid(n)} for n,t in [('Galley','Finish the typography engine'),('Coach Archie','Coach jacket mockups'),
  ('PlayCase Magnets','Store photos for the magnets'),('Chatterbox','Ship the Next Steps plugin')]]+[{'id':cid('task-Crystal concept'),'text':'Crystal stand concept','chatID':cid('Crystal concept'),'completedAt':stamp(90)}]
def work_summary(key):
 n,title,state=next(w for w in WORK if w[0]==key)
 return {'id':cid(n),'title':title,'project':None,'subtitle':'Working on it' if state=='working' else 'Done: the columns render.','backend':'claude',
  'isRunning':state=='working','isWaitingOnYou':False,'updatedAt':'2026-11-04T00:00:00Z','sidechatOf':cid('Chatterbox'),'workOf':cid('Chatterbox')}
# Start There's step: sessions already in USA Archery like the banner request (Coach Archie, a
# clear match, working; No image, possible). Other places and requests have none.
def desk_threads(id,place):
 if id.lower()!=cid('desk-banner') or (place or '').lower()!=cid('studio'):return []
 return [{'id':cid('Coach Archie'),'title':'Coach Archie','detail':'Full USA flags on both sleeves.','settings':'Claude · Opus 5.5 · High','updatedAt':stamp(30),'isRunning':'Coach Archie' in RUNNING,'match':'clear'},
  {'id':cid('No image'),'title':'No image','detail':'Text-only session.','settings':'Codex · GPT-6.1-Sol','updatedAt':stamp(600),'isRunning':False,'match':'possible'}]
# Link a thread's list (all=1): every thread in USA Archery; Coach Archie already carries a task.
def desk_all_threads(id,place):
 if (place or '').lower()!=cid('studio'):return []
 threads=desk_threads(cid('desk-banner'),cid('studio'))
 for t in threads:
  task=next((x['text'] for x in DESK_LINKED if x['chatID'].lower()==t['id'].lower() and not x.get('completedAt')),None)
  if task:t['task']=task
 return threads
def started_chat(place):
 # The session a start opens: a fixture chat in that place.
 if not place or place.get('kind')=='loose':return 'Loose chat'
 if place.get('id','').lower()==cid('studio'):return 'Coach Archie'
 if place.get('id','').lower()==cid('studio2'):return 'Crystal concept'
 return next((n for n,*_ in PROJECTS if cid(n)==place.get('id','').lower()),'Loose chat')
desk_reset()
# Automations (MobileAutomations.swift): a daily routine (seven automations on the Mac), a weekly
# one, and one switched off. Edits and runs are recorded for asserts; a run opens 'Morning run'.
AUTOMATIONS=[];AUTOMATION_CALLS=[];AUTOMATION_RAN=False;AUTOMATION_REPORT_PREPARED=False
def automations_reset():
 global AUTOMATIONS,AUTOMATION_CALLS,AUTOMATION_RAN,AUTOMATION_REPORT_PREPARED
 AUTOMATION_CALLS=[];AUTOMATION_RAN=False;AUTOMATION_REPORT_PREPARED=False
 tomorrow=(datetime.datetime.now()+datetime.timedelta(days=1)).replace(hour=8,minute=30,second=0,microsecond=0).astimezone(datetime.timezone.utc)
 AUTOMATIONS=[
  {'id':cid('auto-morning-1'),'ids':[cid('auto-morning-%d'%d) for d in range(1,8)],'title':'Morning priorities',
   'instructions':'Read ClickUp and Outlook, then list today\'s priorities.','project':'General','projectFolder':'','reportSessionID':cid('Morning priorities session'),'reportSessionTitle':'Morning priorities',
   'agent':'codex','model':'GPT-5.5','effort':'High','days':[1,2,3,4,5,6,7],'hour':8,'minute':30,'enabled':True,
   'lastRunAt':stamp(120),'lastThreadID':cid('Tracker Trapper'),'lastResult':'Three priorities today: the camp banner, the SDHQ cache rules and the Galley review.',
   'isRunning':False,'nextRunAt':tomorrow.strftime('%Y-%m-%dT%H:%M:%SZ')},
  {'id':cid('auto-wordpress'),'ids':[cid('auto-wordpress')],'title':'WordPress updates','instructions':'Keep the site up to date, safely.',
   'project':'SDHQ','projectFolder':'/Users/fixture/SDHQ','agent':'claude','days':[2],'hour':9,'minute':0,'enabled':True,
   'nextRunAt':(tomorrow+datetime.timedelta(days=3)).strftime('%Y-%m-%dT%H:%M:%SZ')},
  {'id':cid('auto-links'),'ids':[cid('auto-links'),cid('auto-links-4'),cid('auto-links-6')],'title':'Broken links','instructions':'Crawl the store for broken links.',
   'project':'PlayCase Magnets','projectFolder':'/Users/fixture/PlayCase Magnets','agent':'claude','days':[2,4,6],'hour':16,'minute':0,'enabled':False}]
def automation(id):
 return next((a for a in AUTOMATIONS if id.lower() in [i.lower() for i in a['ids']]),None)
automations_reset()
SENT={}
RATE_LIMIT=None;RATE_RETRIES=[];RATE_RETRIED=None
PRESSURE=None
def pressure(level):
 if level=='ok':return {'level':'ok','updatedAt':'2099-01-01T00:00:00Z','updated':4070908800,'summary':'load 6.0 on 16 cores','memory':'normal','swapUsedGB':1.0,'swapGrowthGB':0,'load1':6,'load5':6,'load15':6,'cores':16,'thermal':'nominal','holding':[],'waiting':0}
 return {'level':level,'since':'2099-01-01T00:00:00Z','updatedAt':'2099-01-01T00:00:00Z','updated':4070908800,
  'summary':'load 52 on 16 cores (over 3\u00d7) for 1 min; swap grew 1.4 GB in 5 min' if level=='overloaded' else 'load 30 on 16 cores (over 1.5\u00d7) for 2 min',
  'reasons':[],'memory':'warning','swapUsedGB':6.2,'swapGrowthGB':1.4 if level=='overloaded' else 0.1,'compressedGB':27.0,'load1':52 if level=='overloaded' else 30,'load5':40,'load15':31,
  'cores':16,'thermal':'nominal','waiting':2,
  'holding':['New builds wait (running ones carry on, at lower priority)','Simulators no build or test is using are shut down',"Work threads don't start their next turn; new ones wait to start",'2 work threads waiting'] if level=='overloaded'
   else ['Builds run one at a time; agents\' builds get a quarter of the cores, at lower priority','New work threads wait to start until the Mac is OK','2 work threads waiting']}

def reset():
 global RATE_LIMIT,RATE_RETRIES,RATE_RETRIED
 RATE_LIMIT=None;RATE_RETRIES=[];RATE_RETRIED=None
 global RICH,OFFLINE,SIDECHAT,ABOUT,PRESSURE,WORK_LISTED
 PRESSURE=None
 RICH=False;OFFLINE=False;SIDECHAT=False;ABOUT=False;WORK_LISTED=False
 desk_reset();tasks_reset()
 automations_reset()
 global PINNED
 PINNED[:]=['Loose chat','SDHQ']
 SENT.clear()
 global RUNNING,REMOVED,ACTIVITY,READS,STARTED,FAIL,MUTATIONS,RENAMES,PROMOTIONS,BRIEFS,LIST_DELAY
 RUNNING=['Galley','Coach Archie'];REMOVED=set();ACTIVITY=[];READS=0
 STARTED=datetime.datetime.now(datetime.timezone.utc).isoformat();FAIL=False;MUTATIONS=[];RENAMES={};PROMOTIONS={};BRIEFS={};LIST_DELAY=0

def summary(name,line,branch=None,waiting=False):
 s={'id':cid(name),'title':name,'project':name,'subtitle':line,'backend':'claude','isRunning':False,'isWaitingOnYou':waiting,'updatedAt':'2026-10-03T00:00:00Z'}
 if name in ['Coach Archie','Chatterbox']:
  s['thumbnail']={'id':cid('thumbnail'),'name':'proof.png','mediaType':'image/png','isImage':True,'revision':'1'}
  if name=='Coach Archie':s['project']=None
 if name in ['No image','Crystal concept','Loose chat']:s['project']=None
 if name in RENAMES:s['title']=RENAMES[name]
 if BRIEFS.get(name):s['brief']=BRIEFS[name]
 s['canPromote']=name=='Loose chat' and name not in PROMOTIONS
 if name in PROMOTIONS and PROMOTIONS[name]['kind']=='project':s['project']='Promoted project'
 if branch:s['worktreeBranch']=branch
 if name in RUNNING:s['isRunning']=True;s['turnStartedAt']=STARTED
 # Pinned on the Mac, in this order.
 if name in PINNED:s['pinnedRank']=PINNED.index(name)
 return s
PINNED=['Loose chat','SDHQ']
SIDECHAT=False;ABOUT=False
def chats():
 global READS,ACTIVITY
 READS+=1
 if READS==2:ACTIVITY.append(completed('Tracker Trapper'))
 quest=summary('Sidequest · Render ribbons','Generating image 2 of 4');quest.update({'project':None,'backend':'codex','isRunning':True,'sidechatOf':cid('SDHQ'),'sidequestOf':cid('SDHQ'),'sidequestTask':'Render four ribbon options','sidequestReturned':False})
 groups=[{'id':'projects','kind':'projects','title':'Projects','chats':[summary(*p) for p in PROJECTS]+[quest]},
  {'id':'studio-1','kind':'studio','title':'USA Archery','chats':[summary('Coach Archie','Full USA flags on both sleeves.'),summary('No image','Text-only session.')],'studioID':cid('studio')},
  {'id':'chats','kind':'chats','title':'Chats','chats':[summary('Loose chat','An ordinary chat.')]},
  {'id':'studio-2','kind':'studio','title':'Geekify','chats':[summary('Crystal concept','Purple faceted crystal.')],'studioID':cid('studio2')}]
 for name,p in PROMOTIONS.items():
  source=next(c for g in groups for c in g['chats'] if c['id']==cid(name))
  for g in groups:g['chats']=[c for c in g['chats'] if c['id']!=cid(name)]
  if p['kind']=='project':groups[0]['chats'].append(source)
  elif p.get('studioID'):
   next(g for g in groups if g.get('studioID','').lower()==p['studioID'].lower())['chats'].append(source)
  else:groups.append({'id':'new-studio','kind':'studio','title':p['name'],'studioID':cid('new-studio'),'chats':[source]})
 if SIDECHAT:
  side=summary('Release checklist','Checking the 2.1 release list');side.update({'project':None,'sidechatOf':cid('Chatterbox')})
  groups[0]['chats'].append(side)
 if AUTOMATION_REPORT_PREPARED or AUTOMATION_RAN:
  report=summary('Morning priorities session','Daily planning reports');report.update({'project':None,'backend':'codex'})
  groups.append({'id':'general-automation-report','kind':'chats','title':'Chats','chats':[report]})
 # An automation's run reports to its independent general session.
 if AUTOMATION_RAN:
  run=summary('Morning run','Reading ClickUp and Outlook');run.update({'project':None,'backend':'codex','isRunning':True,'turnStartedAt':STARTED,'sidechatOf':cid('Morning priorities session'),'sidequestOf':cid('Morning priorities session'),'sidequestTask':'Automation run: Morning priorities','sidequestReturned':False})
  groups[0]['chats'].append(run)
 if WORK_LISTED:
  at=next(i for i,c in enumerate(groups[0]['chats']) if c['id']==cid('Chatterbox'))+1
  groups[0]['chats'][at:at]=[listed_summary(k,h) for k,h in LISTED]
 for g in groups:g['chats']=[c for c in g['chats'] if c['id'].lower() not in REMOVED]
 out={'revision':1,'groups':groups,'activity':ACTIVITY}
 # The Mac's pressure (the Activity header's dot), when a test sets one.
 if PRESSURE:out['pressure']=PRESSURE
 return out

def detail(id):
 work=next((w for w in WORK if cid(w[0])==id.lower()),None)
 if work:
  s=work_summary(work[0])
  items=[{'id':cid(id+'u'),'kind':'user','text':'Brief: build the board columns from desk-board.md.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False},
         {'id':cid(id+'a'),'kind':'assistant','text':'Hi! This is '+s['title']+'.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False}]
  return {'revision':1,'summary':s,'settings':'Claude · Opus','items':items,'earlierCount':0,'workOfTitle':'Chatterbox'}
 s=next(c for g in chats()['groups'] for c in g['chats'] if c['id'].lower()==id.lower())
 items=[{'id':cid(id+'u'),'kind':'user','text':'Banner ideas for the USA Archery fall camp' if s['title']=='Loose chat' else 'Hello','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False},
        {'id':cid(id+'a'),'kind':'assistant','text':'Hi! This is '+s['title']+'.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False}]
 # A reply with an email draft, shown as a card with its own Copy.
 if s['title']=='Loose chat':items.append({'id':cid('draft-reply'),'kind':'assistant','text':"Here's a draft to Lauren.\n\n```draft\nSubject: Website feedback\n\nHey Lauren,\n\n- **Sitemap:** Where will today's menu items live?\n\nThanks,\nShelby\n```\n\nBefore you send: check the doc.",'isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False})
 # A reply ending on action buttons (```actions), then whatever was sent since.
 if s['title']=='Loose chat':
  items.append({'id':cid('actions-reply'),'kind':'assistant','text':"Installed to Chatterbox Dev. Try it there; when it's right:\n\n```actions\nShip to the real app | ship\nStart the next part | start the next part\n```",'isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False})
 for n,text in enumerate(SENT.get(id.lower(),[])):
  items.append({'id':cid(id+'sent%d'%n),'kind':'user','text':text,'isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False})
 # A reply with a PDF proof and a photo, to comment on.
 if s['title']=='PlayCase Magnets':items.append({'id':cid('proof-reply'),'kind':'assistant','text':'The proof and a product photo are ready.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[
  {'id':cid('magnet-proof'),'name':'Magnet proof.pdf','mediaType':'application/pdf','isImage':False,'revision':'fixture-1','byteCount':len(PROOF)},
  {'id':cid('magnet-photo'),'name':'magnet-photo.png','mediaType':'image/png','isImage':True,'revision':'1'}],'isQueued':False})
 # A reply with a 3D model (an STL) to preview.
 if s['title']=='Crystal concept':items.append({'id':cid('model-reply'),'kind':'assistant','text':'The crystal stand is ready.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[{'id':cid('model-file'),'name':'stand.stl','mediaType':'application/octet-stream','isImage':False}],'isQueued':False})
 if RICH and s['title'] in RICH_ITEMS:
  def item(n,kind,text,extra=None):return dict(dict(id=cid(s['title']+'-rich-%d'%n),kind=kind,text=text,isStreaming=False,isCommentary=False,isPending=False,attachments=[],isQueued=False),**(extra or {}))
  items=[item(n,*x) for n,x in enumerate(RICH_ITEMS[s['title']])]
 presets=[{'id':cid('preset-'+t),'title':t,'backend':b,'isActive':t=='Opus','provider':b,'summary':m} for t,b,m in [('Sol','codex','Codex · GPT-6.1-Sol · Low'),('Opus','claude','Claude · Opus 5.5 · Medium'),('Fable','claude','Claude · Fable 5.1'),('Maestro','codex','Codex · GPT-6-Luna')]]
 options={'backend':'claude','model':'opus','effort':'medium','mode':'bypassPermissions','claudeModels':[{'id':'opus','name':'Opus 5.5','detail':'Best for everyday, complex tasks','efforts':['low','medium','high','xhigh','max'],'defaultEffort':'medium'},{'id':'fable','name':'Fable 5.1','detail':'Most capable for your hardest and longest-running tasks','efforts':['low','medium','high','xhigh','max'],'defaultEffort':'medium'},{'id':'sonnet','name':'Sonnet 5','detail':'Efficient for routine tasks','efforts':['low','medium','high'],'defaultEffort':'medium'},{'id':'haiku','name':'Haiku 5','detail':'Fastest for quick answers','efforts':[],'defaultEffort':None}],'codexModels':[{'id':'gpt-6.1-sol','name':'GPT-6.1-Sol','detail':'','efforts':['low','medium','high'],'defaultEffort':'medium'}],'modes':[{'id':'auto','title':'Auto','detail':'Claude handles permission decisions','systemImage':'wand.and.stars','isUnrestricted':False},{'id':'default','title':'Manual','detail':'Always ask before making changes','systemImage':'hand.raised','isUnrestricted':False},{'id':'acceptEdits','title':'Accept edits','detail':'Automatically accept all file edits','systemImage':'pencil','isUnrestricted':False},{'id':'plan','title':'Plan','detail':'Create a plan before making changes','systemImage':'list.bullet.clipboard','isUnrestricted':False},{'id':'bypassPermissions','title':'Bypass permissions','detail':'Accepts all permissions','systemImage':'exclamationmark.shield','isUnrestricted':True}],'presets':[],'openModels':[{'id':'qwen3.5:9b','name':'qwen3.5:9b','detail':'On Shelby-PC','efforts':[]}]}
 d={'revision':1,'summary':s,'settings':'Claude · Opus','items':items,'earlierCount':0,'options':options}
 # ABOUT: the same thread's About data, without the work threads in the list (whose running rows
 # spin the wide list's Activity table: a known layout loop, MobileActivityRows).
 if (TASKS or ABOUT) and s['title']=='Chatterbox':
  d['work']=[{'id':cid(n),'title':t,'state':st,'task':cid('task-'+n),'backend':'claude','updatedAt':stamp(5)} for n,t,st in WORK]
  # About this thread: where it works, its tools, how full its context is, and what it made
  # (a picture, a PDF, a published page and a draft).
  d.update(folder='/Users/fixture/Projects/Chatterbox',branch='thread-sidebar',contextFraction=0.42,
           tools=[{'name':'graft','kind':'server','isOn':True},{'name':'mirroir','kind':'server','isOn':True},{'name':'cinema4d','kind':'server','isOn':False},{'name':'Gmail','kind':'connector','isOn':False}])
  d['items'].append({'id':cid('about-outputs'),'kind':'assistant','text':"The board is live: https://snippets.shelbyklein.com/chatterbox/desk-board.html\n\n```draft\nSubject: Desk board\n\nHi team, the board is ready.\n```",'isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[
   {'id':cid('magnet-proof'),'name':'Board spec.pdf','mediaType':'application/pdf','isImage':False,'revision':'fixture-1','byteCount':len(PROOF)},
   {'id':cid('magnet-photo'),'name':'desk-board.png','mediaType':'image/png','isImage':True,'revision':'1'}],'isQueued':False})
 if RATE_LIMIT and id.lower()==cid('Chatterbox'):
  source=RATE_LIMIT.get('backend','claude');target='codex' if source=='claude' else 'claude'
  d['summary']=dict(s,backend=RATE_RETRIED or source,isRunning=RATE_LIMIT.get('running',False),isWaitingOnYou=False)
  d['settings']=('Codex · GPT-6.1-Sol' if d['summary']['backend']=='codex' else 'Claude · Opus 5.5')
  d['options']=dict(options,backend=d['summary']['backend'],model='gpt-6.1-sol' if d['summary']['backend']=='codex' else 'opus')
  original=dict(items[0],text='Should we roll Arcade into Button Test?')
  failure=dict(items[1],kind='notice',text=('Claude Code reported a problem: ' if source=='claude' else 'Codex hit an error: ')+('Authentication failed (401)' if RATE_LIMIT.get('ordinary') else 'API Error: Request rejected (429). This request would exceed your account rate limit. Please try again later.'))
  d['items']=[original,failure]
  if RATE_RETRIED:
   d['revision']=2
   d['items']+=[dict(original,id=cid('rate-retried')),dict(items[1],id=cid('rate-retry-answer'),text='Retry received by '+RATE_RETRIED+'.')]
  elif not RATE_LIMIT.get('ordinary') and not RATE_LIMIT.get('running'):
   d['rateLimitRetry']={'requestID':original['id'],'backend':target}
  assert len({item['id'] for item in d['items']})==len(d['items'])
 return d
RICH_ITEMS={
 'Galley':[
  ('user','Phase 3: finish the typography engine. Hyphenation, kerning pairs and the line breaker, then run the tests.'),
  ('thought','The line breaker still fills greedily. Knuth-Plass needs the hyphenation points first, so do those, then kerning, then the breaker.'),
  ('tool','Read Sources/Typography/LineBreaker.swift',{'toolState':'done'}),
  ('tool','Read Sources/Typography/Hyphenator.swift',{'toolState':'done'}),
  ('tool','Edited Sources/Typography/LineBreaker.swift',{'toolState':'done'}),
  ('plan','',{'planSteps':[{'step':'Hyphenation patterns','status':'completed'},{'step':'Kerning pairs from the font','status':'completed'},{'step':'Knuth-Plass line breaking','status':'completed'},{'step':'Widow and orphan control','status':'pending'}]}),
  ('tool','Ran swift test --filter TypographyTests',{'toolState':'failed'}),
  ('assistant','One test failed: a soft hyphen at the end of a line was kept. Fixing that now.',{'isCommentary':True}),
  ('tool','Ran swift test --filter TypographyTests',{'toolState':'done'}),
  ('assistant',"## Phase 3: typography engine\n\nThe line breaker now uses **Knuth-Plass** with hyphenation points, so paragraphs set evenly instead of filling line by line.\n\n- Hyphenation: Liang patterns for English, cached per word\n- Kerning: pairs read from the font's `GPOS` table\n- Line breaking: total fit, with a penalty for two hyphens in a row\n\n```swift\nlet breaker = LineBreaker(width: 420, tolerance: 2.0)\nlet lines = breaker.lines(for: paragraph, hyphenator: .english)\n```\n\n| Sample | Before | After |\n|---|---|---|\n| Body copy | 31 rivers | 4 rivers |\n| Narrow column | 12 overfull | 0 overfull |\n\n**Next:** widow and orphan control. Check the specimen PDF before I start it.",{'workedSeconds':754})],
 'SDHQ':[
  ('user','Tighten the cache rules for the shop pages and publish them.'),
  ('tool','Read wrangler.toml',{'toolState':'done'}),
  ('tool','Ran curl -sI https://sdhq.example/shop',{'toolState':'done'}),
  ('assistant','The shop pages were cached for 4 hours, so price changes showed late. The new rules cache product pages for 10 minutes and bypass the cache for the cart and checkout.',{'workedSeconds':96}),
  ('approval','Run wrangler deploy to publish the new cache rules?',{'isPending':True,'detail':'wrangler deploy --env production','approval':{'isPlan':False,'state':'pending'}})]}
def stl():
 # A binary STL pyramid on a square base.
 import struct
 a,b,c,d,top=(-1,-1,0),(1,-1,0),(1,1,0),(-1,1,0),(0,0,1.6)
 faces=[(a,c,b),(a,d,c),(a,b,top),(b,c,top),(c,d,top),(d,a,top)]
 out=bytearray(80)+struct.pack('<I',len(faces))
 for f in faces: out+=struct.pack('<3f',0,0,0)+b''.join(struct.pack('<3f',*v) for v in f)+b'\0\0'
 return bytes(out)
def thumbnail():
 def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
 w,h=240,160
 rows=b''.join(b'\0'+b''.join(bytes((40+x//3,70+y//2,140)) for x in range(w)) for y in range(h))
 return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')
def proof(pages=3):
 # A small letter-size PDF, written by hand (no PDF library needed): a title band and two panels per page.
 objects=[]
 def add(body):objects.append(body);return len(objects)
 font=add(b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>')
 parent=add(b'')
 kids=[]
 for n in range(1,pages+1):
  stream=(b'0.96 0.55 0.18 rg 0 672 612 120 re f\n0.16 0.36 0.62 rg 54 220 300 400 re f\n0.86 0.86 0.86 rg 378 220 180 400 re f\n'
          b'BT /F1 40 Tf 0 0 0 rg 54 712 Td (Magnet proof) Tj ET\n'
          b'BT /F1 22 Tf 0 0 0 rg 54 150 Td (Page %d of %d) Tj ET\n'%(n,pages))
  content=add(b'<< /Length %d >>\nstream\n'%len(stream)+stream+b'\nendstream')
  kids.append(add(b'<< /Type /Page /Parent %d 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 %d 0 R >> >> /Contents %d 0 R >>'%(parent,font,content)))
 objects[parent-1]=b'<< /Type /Pages /Kids [%s] /Count %d >>'%(b' '.join(b'%d 0 R'%k for k in kids),pages)
 catalog=add(b'<< /Type /Catalog /Pages %d 0 R >>'%parent)
 out=bytearray(b'%PDF-1.4\n');offsets=[]
 for i,body in enumerate(objects,1):offsets.append(len(out));out+=b'%d 0 obj\n'%i+body+b'\nendobj\n'
 xref=len(out)
 out+=b'xref\n0 %d\n'%(len(objects)+1)+b'0000000000 65535 f \n'+b''.join(b'%010d 00000 n \n'%o for o in offsets)
 out+=b'trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n'%(len(objects)+1,catalog,xref)
 return bytes(out)
PROOF=proof()
def photo():
 # A 640x480 "product photo": a warm gradient with a round magnet in the middle.
 def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
 w,h=640,480
 def px(x,y):
  if (x-320)**2+(y-240)**2<120**2:return bytes((40,90,170))
  return bytes((230-y//6,170-y//8,120+x//10))
 rows=b''.join(b'\0'+b''.join(px(x,y) for x in range(w)) for y in range(h))
 return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')
PHOTO=photo()
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def reply(self,x,status=200):
  b=json.dumps(x).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(b)));self.end_headers()
  try:self.wfile.write(b)
  except BrokenPipeError:pass
 def do_POST(self):
  global FAIL,STARTED,LIST_DELAY,DESK_WAITING,DESK_INCOMING,DESK_REVISION,DESK_SILENCED,DESK_READY,DESK_DONE,AUTOMATION_RAN,AUTOMATION_REPORT_PREPARED,RICH,OFFLINE,WORK_LISTED
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))) or '{}')
  global RATE_LIMIT,RATE_RETRIED
  if self.path=='/test/rate-limit':RATE_LIMIT=body;return self.reply({'ok':True})
  if self.path.startswith('/v1/chats/') and self.path.endswith('/retry-rate-limit'):
   id=self.path.split('/')[3];offer=detail(id).get('rateLimitRetry')
   if not offer or body.get('requestID','').lower()!=offer['requestID'].lower() or body.get('backend')!=offer['backend']:return self.reply({'error':'This request is no longer waiting for a retry.'},409)
   RATE_RETRIES.append(body)
   if RATE_LIMIT.get('fail'):return self.reply({'error':'Could not reach the Mac. Try again.'},503)
   RATE_RETRIED=body['backend']
   return self.reply(detail(id))
  if self.path=='/test/reset':reset();return self.reply({'ok':True})
  global PRESSURE
  if self.path.startswith('/test/pressure/'):PRESSURE=pressure(self.path.rsplit('/',1)[1]);return self.reply({'ok':True})
  if self.path.startswith('/v1/automations/'):
   parts=self.path.split('/');routine=automation(parts[3])
   if not routine:return self.reply({'error':'That automation is gone.'},404)
   if len(parts)==5 and parts[4]=='session':
    AUTOMATION_REPORT_PREPARED=True;AUTOMATION_CALLS.append({'action':'prepare','id':parts[3].lower()})
    return self.reply({'threadID':routine['reportSessionID']})
   if len(parts)==5 and parts[4]=='run':
    AUTOMATION_CALLS.append({'action':'run','id':parts[3].lower()})
    AUTOMATION_RAN=True;routine.update({'lastRunAt':stamp(),'lastThreadID':cid('Morning run'),'isRunning':True,'lastResult':None})
    return self.reply(detail(cid('Morning run')))
   AUTOMATION_CALLS.append({'action':'edit','id':parts[3].lower(),'body':body})
   for key in ('title','instructions','days','hour','minute','enabled','agent'):
    if key in body:routine[key]=body[key]
   if 'agent' in body:routine.pop('model',None);routine.pop('effort',None)
   if 'enabled' in body and not body['enabled']:routine.pop('nextRunAt',None)
   return self.reply(routine)
  if self.path=='/test/work-listed':
   WORK_LISTED=True;return self.reply({'ok':True})
  if self.path=='/test/rich':RICH=bool(body.get('value',True));return self.reply({'ok':True})
  # A Sidechat of the Chatterbox project's session: About's Runs here.
  if self.path=='/test/sidechat':
   global SIDECHAT
   SIDECHAT=True;return self.reply({'ok':True})
  if self.path=='/test/about':
   global ABOUT
   ABOUT=True;return self.reply({'ok':True})
  if self.path=='/test/offline':
   OFFLINE=True;return self.reply({'ok':True})
  if OFFLINE and self.path.startswith('/v1/'):time.sleep(8)
  if self.path=='/test/appearance':
   # The tour's light-mode captures, on the run's own simulator (the script writes its id).
   import subprocess
   sim=open(os.path.join(os.environ['CHATTERBOX_TEST_OUTPUT'],'simulator')).read().strip()
   subprocess.run(['xcrun','simctl','ui',sim,'appearance',body.get('value','dark')],check=True)
   return self.reply({'ok':True})
  if self.path=='/test/desk-empty':desk_reset(empty=True);return self.reply({'ok':True})
  if self.path=='/test/tasks':tasks_reset(True);DESK_REVISION+=1;return self.reply({'ok':True})
  global DESK_LINKED,DESK_HOLD_ENABLED,DESK_HELD,DESK_HELD_RECORDS
  if self.path=='/test/desk-hold':
   tasks_reset(True);DESK_HOLD_ENABLED=True;DESK_HELD=[];DESK_HELD_RECORDS={};DESK_REVISION+=1
   DESK_LINKED.append({'id':cid('task-Tracker Trapper'),'text':'Choose the progress style','chatID':cid('Tracker Trapper')})
   return self.reply({'ok':True})
  if self.path.startswith('/v1/desk/') and self.path.endswith(('/hold','/resume')):
   if not DESK_HOLD_ENABLED:return self.reply({'error':'unsupported'},404)
   if FAIL:return self.reply({'error':'Fixture hold failed. Try again.'},409)
   id=self.path.split('/')[3].lower();action=self.path.rsplit('/',1)[1]
   DESK_CALLS.append({'action':action,'id':id})
   if action=='hold':
    if id in DESK_HELD_RECORDS:return self.reply(desk())
    task=next((t for t in DESK_LINKED if t['id'].lower()==id),None)
    found=None
    for lane,items,key in [('incoming',DESK_INCOMING,'id'),('ready',DESK_READY,'id'),('needsYou',DESK_WAITING,'chatID')]:
     match=next((r for r in items if r[key].lower()==(task['chatID'].lower() if task else id)),None)
     if match:found=(lane,match);items.remove(match);break
    if found is None:return self.reply({'error':'Wait for the reply to finish.'},409)
    lane,item=found;DESK_HELD_RECORDS[id]=(lane,item)
    DESK_HELD.append({'id':id,'text':task['text'] if task else item['text'],'heldAt':stamp(),
                      'place':item.get('place') or (item.get('proposed') or {}).get('name'),
                      'chatID':task['chatID'] if task else None,'note':item.get('note')})
   else:
    saved=DESK_HELD_RECORDS.pop(id,None)
    if saved is None:return self.reply({'error':'Task gone'},404)
    lane,item=saved
    {'incoming':DESK_INCOMING,'ready':DESK_READY,'needsYou':DESK_WAITING}[lane].append(item)
    DESK_HELD=[h for h in DESK_HELD if h['id'].lower()!=id]
   DESK_REVISION+=1
   return self.reply(desk())
  if self.path=='/test/desk-source-result':
   global DESK_SOURCE_PULL
   partial=bool(body.get('partial',False))
   DESK_SOURCE_PULL={'routineID':cid('source-routine'),'lastRequestedAt':stamp(10),'threadID':cid('Chatterbox'),'isRunning':False,'needsYou':partial,
    'result':{'finishedAt':stamp(0),'added':[cid('desk-imported')],'updated':[cid('desk-banner')],'unavailable':['Outlook archive unavailable'] if partial else []}}
   if partial:DESK_SOURCE_PULL['problem']='Check incomplete · Outlook archive unavailable'
   if not any(i['id']==cid('desk-imported') for i in DESK_INCOMING):
    DESK_INCOMING.append({'id':cid('desk-imported'),'text':'Prepare the spring camp poster','source':'codex','createdAt':stamp(0),'proposed':{k:v for k,v in PLACES[0].items() if k!='detail'}})
   DESK_REVISION+=1
   return self.reply({'ok':True})
  if self.path=='/v1/desk/check-sources':
   if DESK_SOURCE_PULL is None:
    DESK_CALLS.append({'action':'checkSources'})
    DESK_SOURCE_PULL={'routineID':cid('source-routine'),'lastRequestedAt':stamp(0),'threadID':cid('Chatterbox'),'isRunning':True,'needsYou':False}
    DESK_REVISION+=1
   return self.reply(desk())
  if self.path=='/v1/desk/task':
   # Make this a task: linked at once, named for its thread.
   DESK_CALLS.append({'action':'makeTask','body':body})
   chat=body.get('chatID','')
   title=next((w['title'] for w in DESK_WAITING if w['chatID'].lower()==chat.lower()),'A thread')
   DESK_LINKED.append({'id':str(uuid.uuid4()),'text':body.get('text') or title,'chatID':chat});DESK_REVISION+=1
   return self.reply(desk())
  if self.path.startswith('/v1/desk/') and self.path.endswith(('/link','/unlink')):
   id=self.path.split('/')[3].lower();action=self.path.rsplit('/',1)[1]
   DESK_CALLS.append({'action':action,'id':id,'body':body})
   if action=='unlink':
    DESK_LINKED=[t for t in DESK_LINKED if t['id'].lower()!=id];DESK_REVISION+=1;return self.reply(desk())
   chat=body.get('chatID','')
   if any(t['chatID'].lower()==chat.lower() and not t.get('completedAt') for t in DESK_LINKED) and not body.get('replace'):
    return self.reply({'error':'That thread already carries a task: \u201cCoach jacket mockups\u201d. Link it anyway to send that one back to To do.'},409)
   request=next((r for r in DESK_INCOMING if r['id'].lower()==id),None)
   DESK_LINKED=[t for t in DESK_LINKED if t['chatID'].lower()!=chat.lower()]+[{'id':id,'text':request['text'] if request else 'Task','chatID':chat}]
   DESK_INCOMING=[r for r in DESK_INCOMING if r['id'].lower()!=id];DESK_REVISION+=1
   return self.reply(desk())
  if self.path.startswith('/v1/chats/') and self.path.endswith('/work'):
   DESK_CALLS.append({'action':'work','chat':self.path.split('/')[3].lower(),'body':body})
   return self.reply(detail(cid('work-tabs')))
  if self.path=='/v1/desk':
   DESK_CALLS.append({'action':'add','body':body})
   text=body.get('text','')
   proposed=place_named(body.get('place')) or (PLACES[0] if 'banner' in text.lower() else PLACES[3] if 'magnet' in text.lower() else None)
   DESK_INCOMING.append({'id':str(uuid.uuid4()),'text':text,'source':body.get('source') or 'you','createdAt':stamp(),'proposed':proposed,'note':body.get('note')})
   DESK_REVISION+=1;return self.reply(desk())
  if self.path=='/v1/desk/silence':
   # Off the Desk, still waiting in its session.
   DESK_CALLS.append({'action':'silence','body':body})
   match=lambda w:w['id'].lower()==body.get('id','').lower() and w['chatID'].lower()==body.get('chatID','').lower()
   DESK_SILENCED+=[w for w in DESK_WAITING if match(w)];DESK_WAITING=[w for w in DESK_WAITING if not match(w)];DESK_REVISION+=1
   # A ready session (its id is the session's): off the board, not archived.
   DESK_READY=[r for r in DESK_READY if not (r['id'].lower()==body.get('chatID','').lower()==body.get('id','').lower() and r['text']==body.get('text'))]
   return self.reply(desk())
  if self.path=='/v1/desk/unsilence':
   # Undo, or the silenced list: back in Needs you, in its place.
   DESK_CALLS.append({'action':'unsilence','body':body})
   match=lambda w:w['id'].lower()==body.get('id','').lower() and w['chatID'].lower()==body.get('chatID','').lower()
   back=[w for w in DESK_SILENCED if match(w)];DESK_SILENCED=[w for w in DESK_SILENCED if not match(w)]
   DESK_WAITING=sorted(DESK_WAITING+back,key=lambda w:0 if w['kind']=='approval' else 1);DESK_REVISION+=1
   return self.reply(desk())
  if self.path in ('/v1/desk/complete','/v1/desk/reopen'):
   # Mark complete: from Ready to Done (archived). Reopen: out of Done, ready again.
   action=self.path.rsplit('/',1)[1];chat=body.get('chatID','').lower()
   DESK_CALLS.append({'action':action,'body':body})
   if action=='complete':
    item=next((r for r in DESK_READY if r['id'].lower()==chat),None)
    if not item:return self.reply({'error':'That session is gone.'},404)
    DESK_READY=[r for r in DESK_READY if r['id'].lower()!=chat]
    DESK_DONE=[{k:v for k,v in item.items() if k not in ('text','finishedAt')}|{'completedAt':stamp()}]+DESK_DONE
   else:
    item=next((d for d in DESK_DONE if d['id'].lower()==chat),None)
    if not item:return self.reply({'error':'That session is gone.'},404)
    DESK_DONE=[d for d in DESK_DONE if d['id'].lower()!=chat]
    DESK_READY=[{k:v for k,v in item.items() if k!='completedAt'}|{'text':'Reopened.','finishedAt':stamp()}]+DESK_READY
   DESK_REVISION+=1;return self.reply(desk())
  if self.path.startswith('/v1/desk/') and self.path.endswith(('/start','/ignore')):
   id=self.path.split('/')[3].lower();action=self.path.rsplit('/',1)[1]
   request=next((r for r in DESK_INCOMING if r['id'].lower()==id),None)
   if not request:return self.reply({'error':'That request is no longer on the Desk.'},404)
   DESK_CALLS.append({'action':action,'id':id,'body':body})
   DESK_INCOMING=[r for r in DESK_INCOMING if r['id'].lower()!=id];DESK_REVISION+=1
   if action=='ignore':return self.reply(desk())
   # Continuing answers with that session; otherwise the one started in the place.
   if body.get('continueChat'):return self.reply(detail(body['continueChat']))
   return self.reply(detail(cid(started_chat(body.get('place') or request['proposed']))))
  if self.path.startswith('/v1/chats/') and '/approvals/' in self.path:
   parts=self.path.split('/');chat,item=parts[3].lower(),parts[5].lower()
   DESK_CALLS.append({'action':'decide','chat':chat,'item':item,'decision':body.get('decision')})
   DESK_WAITING=[w for w in DESK_WAITING if w['id'].lower()!=item];DESK_REVISION+=1
   return self.reply(detail(chat))
  if self.path=='/test/list-delay':
   LIST_DELAY=body.get('seconds',0);return self.reply({'ok':True})
  if self.path=='/test/fail':FAIL=body['value'];return self.reply({'ok':True})
  if self.path=='/test/complete':
   name=body['name']
   if name in RUNNING:RUNNING.remove(name)
   ACTIVITY.append(completed(name));return self.reply({'ok':True})
  if self.path=='/test/start':
   if body['name'] not in RUNNING:RUNNING.append(body['name'])
   STARTED=datetime.datetime.now(datetime.timezone.utc).isoformat();return self.reply({'ok':True})
  if self.path.startswith('/v1/chats/') and self.path.endswith('/promote'):
   if FAIL:return self.reply({'error':'Fixture promotion failed. Try again.'},409)
   PROMOTIONS['Loose chat']=body;MUTATIONS.append('promote');return self.reply(detail(cid('Loose chat')))
  if self.path.startswith('/v1/chats/') and self.path.endswith('/brief'):
   id=self.path.split('/')[3].lower()
   name=next(c['title'] for g in chats()['groups'] for c in g['chats'] if c['id'].lower()==id)
   BRIEFS[name]=body['brief'];MUTATIONS.append('brief');return self.reply(detail(id))
  if self.path.startswith('/v1/chats/') and self.path.endswith('/pin'):
   id=self.path.split('/')[3].lower()
   names=[p[0] for p in PROJECTS]+['Coach Archie','No image','Crystal concept','Loose chat']
   name=next(n for n in names if cid(n)==id)
   pinned=body.get('pinned')
   if pinned and name not in PINNED:PINNED.append(name)
   if not pinned and name in PINNED:PINNED.remove(name)
   MUTATIONS.append('pin');return self.reply(detail(id))
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
  if self.path.startswith('/v1/chats/') and self.path.endswith('/messages'):
   id=self.path.split('/')[3].lower();SENT.setdefault(id,[]).append(body.get('text',''))
   return self.reply(detail(id))
  if self.path=='/v1/chats':
   CREATED.append(body);return self.reply(detail(cid('SDHQ')))
  self.send_error(404)
 def do_DELETE(self):
  if self.path.startswith('/v1/chats/'):
   if FAIL:return self.reply({'error':'Fixture delete failed. Try again.'},503)
   REMOVED.add(self.path.split('/')[3].lower());MUTATIONS.append('delete');return self.reply({'ok':True})
  self.send_error(404)
 def do_GET(self):
  if self.path=='/test/rate-retries':return self.reply(RATE_RETRIES)
  if OFFLINE and self.path.startswith('/v1/'):time.sleep(8)
  if self.path=='/test/mutations':return self.reply(MUTATIONS)
  if self.path=='/test/desk-calls':return self.reply(DESK_CALLS)
  if self.path=='/test/automation-calls':return self.reply(AUTOMATION_CALLS)
  if self.path=='/v1/automations':return self.reply(AUTOMATIONS)
  if self.path=='/v1/desk':return self.reply(desk())
  if self.path=='/v1/desk/places':return self.reply(PLACES)
  if self.path.startswith('/v1/desk/') and self.path.split('?')[0].endswith('/threads'):
   import urllib.parse
   id=self.path.split('/')[3].lower();place=dict(urllib.parse.parse_qsl(urllib.parse.urlparse(self.path).query)).get('place')
   query=dict(urllib.parse.parse_qsl(urllib.parse.urlparse(self.path).query))
   DESK_CALLS.append({'action':'threads','id':id,'place':place}|({'all':True} if query.get('all')=='1' else {}))
   return self.reply(desk_all_threads(id,place) if query.get('all')=='1' else desk_threads(id,place))
  if self.path=='/test/promotions':return self.reply(PROMOTIONS)
  if self.path=='/test/briefs':return self.reply(BRIEFS)
  if self.path=='/test/renames':return self.reply(RENAMES)
  if self.path.startswith('/v1/usage'):
   return self.reply({'claude':[{'label':'5-hour','fraction':0.42,'resetsAt':'2099-01-01T00:00:00Z'},{'label':'7-day','fraction':0.81,'resetsAt':'2099-01-03T00:00:00Z'}],
                      'codex':[{'label':'5-hour','fraction':0.12,'resetsAt':'2099-01-01T00:00:00Z'}],
                      'proxyAccounts':[{'provider':'claude','name':'shelby@example.com','status':'Available','windows':[{'label':'Weekly','fraction':0.65}]}],
                      'proxyChecked':'2026-10-16T12:00:00Z'})
  if self.path.startswith('/v1/project-folders'):
   from urllib.parse import urlparse,parse_qs
   path=parse_qs(urlparse(self.path).query).get('path',['/Users/fixture'])[0]
   return self.reply({'path':path,'parent':'/Users/fixture' if path!='/Users/fixture' else '/Users','folders':[{'path':'/Users/fixture/Projects','name':'Projects'}] if path=='/Users/fixture' else []})
  if self.path.endswith('/organization'):
   return self.reply({'currentFolder':'/Users/fixture','studios':[{'id':cid('studio'),'name':'USA Archery','folder':'/Users/fixture/Studios/USA Archery'},{'id':cid('studio2'),'name':'Geekify','folder':'/Users/fixture/Studios/Geekify'}]})
  if '/files/'+cid('model-file') in self.path.lower():
   b=stl();self.send_response(200);self.send_header('Content-Type','application/octet-stream');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b);return
  for fid,body,kind in [(cid('magnet-proof'),PROOF,'application/pdf'),(cid('magnet-photo'),PHOTO,'image/png')]:
   if '/files/'+fid in self.path.lower():
    self.send_response(200);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body);return
  if '/thumbnail/' in self.path:
   b=thumbnail();self.send_response(200);self.send_header('Content-Type','image/png');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b);return
  if self.path=='/v1/chats':
   time.sleep(LIST_DELAY);return self.reply(chats())
  if self.path=='/test/created':return self.reply(CREATED)
  if self.path=='/test/sent':return self.reply(SENT)
  if self.path=='/test/new-chat-options':return self.reply(NEWCHAT)
  if self.path=='/test/promotions':return self.reply(PROMOTIONS)
  if self.path.startswith('/v1/new-chat-options'):
   import urllib.parse
   q=dict(urllib.parse.parse_qsl(urllib.parse.urlparse(self.path).query))
   NEWCHAT.append(q)
   o=detail(cid('SDHQ'))['options']
   # chat=<id>: as that session would run with the picks. Coach Archie runs Opus at High; No image, Codex's GPT-6.1-Sol.
   chat=(q.get('chat') or '').lower()
   if chat==cid('Coach Archie'):o['effort']='high'
   own=chat==cid('No image') and not q.get('backend')
   if q.get('backend')=='codex' or own:o.update({'backend':'codex','model':'','mode':'fullAccess','modes':[{'id':'readOnly','title':'Read only','detail':'Can look at files but not change them','systemImage':'eye','isUnrestricted':False},{'id':'ask','title':'Ask for approval','detail':'Always ask to edit external files and use the internet','systemImage':'hand.raised','isUnrestricted':False},{'id':'fullAccess','title':'Full access','detail':'Unrestricted access to the internet and any file on your computer','systemImage':'exclamationmark.shield','isUnrestricted':True}],'codexModels':[{'id':'','name':'Codex default','detail':'','efforts':['low','medium','high'],'defaultEffort':'medium'},{'id':'gpt-6.1-sol','name':'GPT-6.1-Sol','detail':'','efforts':['low','medium','high'],'defaultEffort':'medium'}]})
   if own:o['model']='gpt-6.1-sol'
   if q.get('model'):o['model']=q['model']
   if q.get('effort'):o['effort']=q['effort']
   if q.get('openModel'):o['openModel']=q['openModel']
   return self.reply(o)
  if self.path=='/v1/addresses':return self.reply({'addresses':['127.0.0.1']})
  if self.path=='/v1/displays':return self.reply([{'x':0,'y':0,'width':900,'height':584.5},{'x':900,'y':0,'width':756,'height':491}])
  if self.path.startswith('/v1/chats/'):
   id=self.path.split('/')[3].split('?')[0]
   return self.reply({'unchanged':True,'revision':1} if '?since=1' in self.path else detail(id))
  self.send_error(404)
# The port: CHATTERBOX_TEST_PORT, or 0 for a free one (start_test_server, test-hygiene.sh);
# the one it got goes to CHATTERBOX_TEST_PORT_FILE once it's listening.
server=http.server.ThreadingHTTPServer(('127.0.0.1',PORT),Handler)
PORT=server.server_address[1]
if os.environ.get('CHATTERBOX_TEST_PORT_FILE'):
 open(os.environ['CHATTERBOX_TEST_PORT_FILE']+'.tmp','w').write(str(PORT));os.rename(os.environ['CHATTERBOX_TEST_PORT_FILE']+'.tmp',os.environ['CHATTERBOX_TEST_PORT_FILE'])
print('listening on 127.0.0.1:%d'%PORT,flush=True)
server.serve_forever()
