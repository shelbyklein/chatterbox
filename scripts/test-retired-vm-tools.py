import json,os,subprocess
binary='build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/MacOS/chatterbox-mcp'
for legacy in (False,True):
 env=os.environ.copy()
 env.pop('CHATTERBOX_MCP_TOOLS',None)
 if legacy:env['CHATTERBOX_MCP_TOOLS']='computer'
 p=subprocess.run([binary],input=json.dumps({'jsonrpc':'2.0','id':1,'method':'tools/list','params':{}})+'\n',text=True,capture_output=True,env=env,timeout=10)
 replies=[json.loads(l) for l in p.stdout.splitlines()]
 reply=next(x for x in replies if x.get('id')==1)
 names=[x['name'] for x in reply['result']['tools']]
 assert not any('computer' in n or n in ('hand_off_download','list_previews') for n in names),names
 assert (not names) if legacy else ('send_message' in names and 'suggest_answer' in names)
 request={'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'start_computer','arguments':{}}}
 result=subprocess.run([binary],input=json.dumps(request)+'\n',text=True,capture_output=True,env=env,timeout=10)
 assert json.loads(result.stdout)['result']['isError'] is True
 print('Legacy isolated' if legacy else 'Assistant tools',names)
