#!/usr/bin/python3
import json,os,sys
root=os.environ['CHATTERBOX_DATA_DIR']
session=sys.argv[sys.argv.index('--resume')+1] if '--resume' in sys.argv else 'new-fixture-session'
if session=='claude-missing':
    print('No conversation found for session',file=sys.stderr,flush=True)
    sys.exit(1)
with open(root+'/claude-launches.jsonl','a') as f:f.write(json.dumps({'session':session,'resume':'--resume' in sys.argv})+'\n')
print(json.dumps({'type':'system','subtype':'init','session_id':session,'model':'fixture','tools':[],'slash_commands':[]}),flush=True)
for line in sys.stdin:
    r=json.loads(line)
    with open(root+'/claude-input.jsonl','a') as f:f.write(json.dumps({'type':r.get('type')})+'\n')
    if r.get('type')=='control_request':
        print(json.dumps({'type':'control_response','response':{'subtype':'success','request_id':r['request_id'],'response':{}}}),flush=True)
