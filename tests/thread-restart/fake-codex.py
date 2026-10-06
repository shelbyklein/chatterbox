#!/usr/bin/python3
import json,os,sys,time
root=os.environ['CHATTERBOX_DATA_DIR']
def out(v): print(json.dumps(v),flush=True)
for line in sys.stdin:
    r=json.loads(line); method=r.get('method'); p=r.get('params') or {}
    with open(root+'/codex-requests.jsonl','a') as f:
        f.write(json.dumps({'method':method,'threadId':p.get('threadId'),'turnId':p.get('turnId')})+'\n')
    if 'id' not in r:continue
    if method=='thread/resume' and p['threadId']=='fail':
        out({'id':r['id'],'error':{'code':-32000,'message':'Original thread unavailable'}}); continue
    if method=='thread/resume':
        time.sleep(.12)
        result={'thread':{'id':p['threadId']}}
    elif method=='turn/interrupt':
        if p['threadId']!='never-stops':
            out({'method':'turn/completed','params':{'threadId':p['threadId'],'turn':{'id':p['turnId'],'status':'interrupted'}}})
        result={}
    elif method=='thread/read':
        status='unknown' if p['threadId']=='unknown-state' else ('active' if p['threadId']=='missing-active' else 'idle')
        turns=[{'id':'recovered-turn','status':'inProgress'}] if status=='active' else []
        result={'thread':{'id':p['threadId'],'status':{'type':status},'turns':turns}}
    elif method=='model/list':result={'data':[]}
    elif method=='test/slow':time.sleep(.3);result={}
    else:result={}
    out({'id':r['id'],'result':result})
