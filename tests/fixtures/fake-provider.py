#!/usr/bin/env python3
"""Deterministic stdio provider fixture. No accounts or network; request logs stay in the test data directory."""
import json,sys,uuid,os,time,threading
if 'exec' in sys.argv:
 from pathlib import Path
 output=sys.argv[sys.argv.index('-o')+1]
 Path(output).write_text(json.dumps({'emails':[{'account':'fixture@example.invalid','from':'Fixture Sender','subject':'Fixture appointment','why':'A fixture needs a decision.','action':'Review the appointment.','link':'','id':'fixture-mail-1'}]}))
 sys.exit(0)
codex='app-server' in sys.argv
if os.environ.get('FAKE_PROVIDER_LAUNCHES'):
 # Where and how each launch happened, for the PC worker test.
 # Its priority and a child shell's (inherited), and the build caps in its environment, for the pressure checks.
 import subprocess
 child=subprocess.run(['/bin/sh','-c','ps -o nice= -p $$'],capture_output=True,text=True).stdout.strip()
 build={k:os.environ.get(k) for k in ('CMAKE_BUILD_PARALLEL_LEVEL','MAKEFLAGS','CARGO_BUILD_JOBS')}
 with open(os.environ['FAKE_PROVIDER_LAUNCHES'],'a') as f:f.write(json.dumps({'pid':os.getpid(),'cwd':os.getcwd(),'argv':sys.argv[1:],'chat':os.environ.get('CHATTERBOX_CHAT_ID'),'base':os.environ.get('ANTHROPIC_BASE_URL'),
  'nice':os.nice(0),'childNice':child,'build':build})+'\n')
thread='fixture-thread';turn='fixture-turn';pending=None;fail_unsubscribe=False

lock=threading.Lock()
def emit(obj):
 with lock:print(json.dumps(obj),flush=True)
def background(stall):
 # A message ending "background" (Claude): the turn starts a background command and ends saying
 # so; when the command finishes, Claude Code picks back up by itself with a new turn and the
 # real answer. "background-stall": the command finishes but nothing picks back up.
 task='bg-'+str(uuid.uuid4())[:8]
 emit({'type':'system','subtype':'task_started','task_id':task,'task_type':'local_bash','is_backgrounded':True,'description':'Run the suite'})
 emit({'type':'assistant','uuid':str(uuid.uuid4()),'message':{'id':str(uuid.uuid4()),'content':[{'type':'text','text':"Suite running. I'll be notified when the suite finishes."}]}})
 emit({'type':'result','subtype':'success','is_error':False,'result':"I'll be notified when the suite finishes."})
 def finish():
  emit({'type':'system','subtype':'task_updated','task_id':task,'patch':{'status':'completed'}})
  emit({'type':'system','subtype':'task_notification','task_id':task,'status':'completed'})
  if stall:return
  emit({'type':'stream_event','event':{'type':'message_start','message':{}}})
  emit({'type':'assistant','uuid':str(uuid.uuid4()),'message':{'id':str(uuid.uuid4()),'content':[{'type':'text','text':'Suite passed: all 42 tests green.'}]}})
  emit({'type':'result','subtype':'success','is_error':False,'result':'Suite passed: all 42 tests green.'})
 threading.Timer(float(os.environ.get('FAKE_PROVIDER_BACKGROUND_SECONDS','1.5')),finish).start()
def race(mode):
 # As Claude Code does when a background command finishes while the turn's last answer is being
 # written (seen 2026-11-05): the task ends (task_updated, task_notification) before the result,
 # so nothing is running when the turn ends, but Claude Code then starts a turn of its own to hand
 # the agent the notification ("background-race"). "background-race-stall": that turn never comes.
 # "background-delivered": the notification reaches the agent within the turn (echoed as a
 # message), and the turn's answer is the result.
 task='bg-'+str(uuid.uuid4())[:8];run='run-'+task
 emit({'type':'system','subtype':'background_tasks_changed','tasks':[{'task_id':task,'run_id':run,'task_type':'local_bash','description':'Rerun the tests'}]})
 emit({'type':'system','subtype':'task_started','task_id':task,'run_id':run,'task_type':'local_bash','is_backgrounded':True,'description':'Rerun the tests'})
 emit({'type':'stream_event','event':{'type':'message_start','message':{}}})
 emit({'type':'system','subtype':'task_updated','task_id':task,'run_id':run,'patch':{'status':'completed'}})
 emit({'type':'system','subtype':'task_notification','task_id':task,'run_id':run,'status':'completed','summary':'Background command "Rerun the tests" completed (exit code 0)'})
 emit({'type':'system','subtype':'background_tasks_changed','tasks':[]})
 notification='<task-notification>\n<task-id>%s</task-id>\n<status>completed</status>\n</task-notification>'%task
 if mode=='delivered':
  emit({'type':'user','isReplay':True,'origin':{'kind':'task-notification'},'message':{'role':'user','content':notification}})
  text='Tests rerun: all 42 pass, and the Dev install is done.'
 elif mode=='stall':text='Started the test rerun.'
 else:text="Tests are rerunning in the background, with the Chatterbox Dev install queued behind them. I'll pick up when they finish."
 emit({'type':'assistant','uuid':str(uuid.uuid4()),'message':{'id':str(uuid.uuid4()),'content':[{'type':'text','text':text}]}})
 emit({'type':'result','subtype':'success','is_error':False,'result':text,'queued_turn_count':0})
 if mode!='race':return
 def wake():
  emit({'type':'system','subtype':'init','session_id':'fixture-session','slash_commands':[]})
  emit({'type':'stream_event','event':{'type':'message_start','message':{}}})
  emit({'type':'assistant','uuid':str(uuid.uuid4()),'message':{'id':str(uuid.uuid4()),'content':[{'type':'text','text':'Rerun done: all 42 tests pass, Dev installed.'}]}})
  emit({'type':'result','subtype':'success','is_error':False,'result':'Rerun done.','origin':{'kind':'task-notification','runId':run},'queued_turn_count':0})
 threading.Timer(float(os.environ.get('FAKE_PROVIDER_WAKE_SECONDS','0.05')),wake).start()
def say(text):
 emit({'type':'assistant','uuid':str(uuid.uuid4()),'message':{'id':str(uuid.uuid4()),'content':[{'type':'text','text':text}]}})
 emit({'type':'result','subtype':'success','is_error':False,'result':text})
def note(name,value):
 # What the agent was given, for tests that check instructions and messages.
 with open(os.path.join(os.environ.get('CHATTERBOX_DATA_DIR','/tmp'),name),'a') as f:f.write(json.dumps(value)+'\n')
def mcp_call():
 # A message ending "mcp" uses a tool from an "indesign" MCP server first.
 if codex:emit({'method':'item/started','params':{'threadId':thread,'item':{'id':str(uuid.uuid4()),'type':'mcpToolCall','server':'indesign','tool':'set_text'}}})
 else:emit({'type':'assistant','uuid':str(uuid.uuid4()),'message':{'id':str(uuid.uuid4()),'content':[{'type':'tool_use','id':'tu-'+str(uuid.uuid4()),'name':'mcp__indesign__set_text','input':{}}]}})
def result():
 if codex:
  emit({'method':'item/started','params':{'threadId':thread,'item':{'id':str(uuid.uuid4()),'type':'agentMessage','text':'Fixture reply.'}}})
  emit({'method':'turn/completed','params':{'threadId':thread,'turn':{'id':turn,'status':'completed'}}})
 else:
  emit({'type':'assistant','uuid':str(uuid.uuid4()),'message':{'id':str(uuid.uuid4()),'content':[{'type':'text','text':'Fixture reply.'}]}})
  emit({'type':'result','subtype':'success','is_error':False,'result':'Fixture reply.'})
if not codex:
 if '--append-system-prompt' in sys.argv:note('claude-system.jsonl',sys.argv[sys.argv.index('--append-system-prompt')+1])
 emit({'type':'system','subtype':'init','session_id':'fixture-session','slash_commands':[]})
for line in sys.stdin:
 try:m=json.loads(line)
 except ValueError:continue
 if codex:
  op=m.get('method');rid=m.get('id');p=m.get('params') or {}
  log=os.path.join(os.environ['CHATTERBOX_DATA_DIR'],'codex-requests.jsonl')
  with open(log,'a') as f:f.write(json.dumps({'method':op,'threadId':p.get('threadId')})+'\n')
  if p.get('threadId'):thread=p['threadId']
  if op in ('thread/start','thread/resume','thread/fork'):
   note('codex-system.jsonl',{'method':op,'instructions':((p.get('config') or {}).get('developer_instructions') or p.get('developerInstructions') or '')})
   if op in ('thread/start','thread/fork'):thread='fixture-'+str(uuid.uuid4())
   emit({'id':rid,'result':{'thread':{'id':thread}}})
  elif op=='thread/unsubscribe':
   time.sleep(0.15)
   if fail_unsubscribe:
    emit({'id':rid,'error':{'code':-32000,'message':'Fixture unsubscribe failure'}});fail_unsubscribe=False
   else:emit({'id':rid,'result':{'status':'unsubscribed'}})
  elif op=='fixture/failUnsubscribe':fail_unsubscribe=True;emit({'id':rid,'result':{}})
  elif op=='thread/read':time.sleep(0.15);emit({'id':rid,'result':{}})
  elif op=='fixture/closeThread':
   emit({'id':rid,'result':{}})
   emit({'method':'thread/status/changed','params':{'threadId':thread,'status':{'type':'notLoaded'}}})
   emit({'method':'thread/closed','params':{'threadId':thread}})
  elif op=='model/list':emit({'id':rid,'result':{'data':[],'nextCursor':None}})
  elif op=='turn/start':
   turn='turn-'+str(uuid.uuid4());emit({'id':rid,'result':{'turn':{'id':turn}}})
   text=' '.join(x.get('text','') for x in p.get('input',[]))
   note('codex-input.jsonl',text)
   note('codex-turns.jsonl',{'model':p.get('model'),'effort':p.get('effort'),'cwd':p.get('cwd')})
   if text.endswith('mcp'):mcp_call()
   if text.endswith('question'):
    pending=True;emit({'id':'fixture-question','method':'item/tool/requestUserInput','params':{'threadId':thread,'questions':[{'id':'q','header':'Choice','question':'Pick one','options':[{'label':'A','description':'A'}]}]}})
   elif text.endswith('approval'):
    pending=True;emit({'id':'fixture-approval','method':'item/commandExecution/requestApproval','params':{'threadId':thread,'command':'true','reason':'Fixture approval'}})
   elif text.endswith('hold'):pending=True
   else:result()
  elif op=='turn/interrupt':emit({'id':rid,'result':{}});emit({'method':'turn/completed','params':{'threadId':thread,'turn':{'id':turn,'status':'interrupted'}}});pending=None
  elif op=='turn/steer':emit({'id':rid,'result':{'turnId':turn}});result();pending=None
  elif op:emit({'id':rid,'result':{}}) if rid is not None else None
  elif rid is not None and pending:result();pending=None
 else:
  if m.get('type')=='user':
   text=' '.join(x.get('text','') for x in m['message']['content'])
   emit(dict(m, isReplay=True))
   note('claude-input.jsonl',text)
   if text.endswith('mcp'):mcp_call()
   if text.endswith('question'):
    pending=True;emit({'type':'control_request','request_id':'fixture-q','request':{'subtype':'can_use_tool','tool_name':'AskUserQuestion','input':{'questions':[{'header':'Choice','question':'Pick one','options':[{'label':'A','description':'A'}],'multiSelect':False}]}}})
   elif text.endswith('approval'):
    pending=True;emit({'type':'control_request','request_id':'fixture-a','request':{'subtype':'can_use_tool','tool_name':'Bash','input':{'command':'true'}}})
   elif text.endswith('hold'):pending=True
   elif text.endswith('background'):background(False)
   elif text.endswith('background-stall'):background(True)
   elif text.endswith('background-race'):race('race')
   elif text.endswith('background-race-stall'):race('stall')
   elif text.endswith('background-delivered'):race('delivered')
   elif text.endswith('say-interim'):say("Rerunning now; the Dev install follows if the three tests pass. I'll continue when the notification arrives.")
   elif text.endswith('say-result'):say('All 42 tests pass and Chatterbox Dev is installed. Committed and pushed; I\'ll continue when you say ship.')
   else:result();pending=None
  elif m.get('type')=='control_response' and pending:result();pending=None
  elif m.get('type')=='control_request':
   emit({'type':'control_response','response':{'subtype':'success','request_id':m['request_id'],'response':{}}})
   if m['request'].get('subtype')=='interrupt':emit({'type':'result','subtype':'success','is_error':False});pending=None
