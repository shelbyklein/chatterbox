#!/usr/bin/python3
"""No-turn smoke test against the installed CLI, isolated from user auth/config/history."""
import json,os,pathlib,queue,subprocess,tempfile,threading,time
with tempfile.TemporaryDirectory(prefix='chatterbox-restart-cli.') as folder:
    env=dict(os.environ,CODEX_HOME=folder)
    cli=subprocess.Popen(['codex','app-server'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,env=env,cwd=folder)
    messages=queue.Queue()
    def read():
        for line in cli.stdout:messages.put(line)
        messages.put(None)
    threading.Thread(target=read,daemon=True).start()
    def request(method,params):
        request.id+=1; ident=request.id
        cli.stdin.write(json.dumps({'id':ident,'method':method,'params':params})+'\n');cli.stdin.flush()
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            try:line=messages.get(timeout=deadline-time.monotonic())
            except queue.Empty:break
            if not line:raise RuntimeError('CLI exited')
            r=json.loads(line)
            if r.get('id')!=ident:continue
            if 'error' in r:raise RuntimeError(r['error'].get('message','RPC failed'))
            return r['result']
        raise RuntimeError(method+' timed out')
    request.id=0
    try:
        request('initialize',{'clientInfo':{'name':'chatterbox-restart-regression','title':'Restart regression','version':'1'},'capabilities':{'experimentalApi':True}})
        cli.stdin.write(json.dumps({'method':'initialized'})+'\n');cli.stdin.flush()
        params={'cwd':folder,'model':'gpt-6.1-sol','approvalPolicy':'never','sandbox':'read-only','developerInstructions':'Isolated regression fixture. No task is being requested.'}
        a=request('thread/start',params)['thread']['id']
        # Persist a fixture history item locally; inject_items never starts generation.
        request('thread/inject_items',{'threadId':a,'items':[{'type':'message','role':'user','content':[{'type':'input_text','text':'Regression history fixture. No action requested.'}]}]})
        b=request('thread/start',params)['thread']['id']
        restarted=request('thread/resume',dict(params,threadId=a,excludeTurns=True))['thread']['id']
        loaded=request('thread/loaded/list',{})['data']
        assert restarted==a and a in loaded and b in loaded
        assert any('Regression history fixture. No action requested.' in p.read_text() for p in pathlib.Path(folder).rglob('rollout-*.jsonl'))
        print('PASS installed Codex CLI: explicit resume returns original persisted thread ID; second thread stays loaded; fixture history injected locally; zero generation turns; isolated config/auth/history')
    finally:
        cli.terminate()
        try:cli.wait(timeout=5)
        except subprocess.TimeoutExpired:cli.kill();cli.wait()
