#!/usr/bin/env python3
"""Isolated daemon wire tests. No provider accounts or real app data."""
import json, os, socket, subprocess, tempfile, time, uuid
from pathlib import Path
root = Path(tempfile.mkdtemp(prefix='golem-rpc.', dir='/tmp'))
env = dict(os.environ, CHATTERBOX_DATA_DIR=str(root/'data'), CHATTERBOX_HOST_DIR=str(root/'host'),
           CHATTERBOX_AGENT_PORT='0', CHATTERBOX_COMPANION_PORT='0',
           CHATTERBOX_TEST_DISABLE_COMPUTER='1', FAKE_PROVIDER=str(Path('tests/golem-integration/fake-provider.py').resolve()))
class Peer:
    def __init__(self, role, trusted=False):
        self.s = socket.socket(socket.AF_UNIX); self.s.settimeout(8)
        self.s.connect(str(root/'data/daemon.sock')); self.f = self.s.makefile('rwb')
        reply=self.call('hello', {'role':role})
        if role in ('ui','golem-ui'): assert ('error' not in reply) == trusted, reply
    def call(self, op, body=None, key=None, version=1):
        key=key or str(uuid.uuid4())
        self.f.write((json.dumps(dict(version=version,id=key,operation=op,body=body or {}))+'\n').encode()); self.f.flush()
        while True:
            r=json.loads(self.f.readline())
            if r.get('id')==key: return r
    def close(self): self.f.close(); self.s.close()
def start(trust):
    if trust: env['CHATTERBOX_TEST_TRUST_UI']='1'
    else: env.pop('CHATTERBOX_TEST_TRUST_UI',None)
    log=open(root/('trusted.log' if trust else 'untrusted.log'),'wb')
    p=subprocess.Popen(['build/runtime/chatterboxd'],env=env,stdout=log,stderr=log)
    for _ in range(200):
        if p.poll() is not None: raise AssertionError((root/'untrusted.log').read_text())
        if (root/'data/daemon.sock').exists(): return p
        time.sleep(.05)
    raise AssertionError('daemon did not start')
def stop(p):
    p.terminate(); p.wait(timeout=10)
p=start(False)
try:
    ui=Peer('ui'); assert ui.call('list').get('error')=='handshake_required'; ui.close()
    denied=Peer('golem-ui'); assert denied.call('list').get('error')=='handshake_required'; denied.close()
    agent=Peer('agent')
    assert agent.call('health',version=2).get('error')=='unsupported_version'
    for op in ['approve','answer','integration','delete','settings']:
        assert agent.call(op).get('error')=='permission_denied', op
    agent.close()
finally: stop(p)
# Model an event history pruned while this UI was disconnected. This is a real
# expired cursor (not merely a future cursor) against the persisted replay log.
statefile=root/'data/runtime-state.json'
state=json.loads(statefile.read_text())
state['sequence']=5000
state['events']=[dict(sequence=4999,revision=0,kind='chat.changed',date='2026-10-04T12:00:00Z'),
                 dict(sequence=5000,revision=0,kind='chat.changed',date='2026-10-04T12:00:01Z')]
statefile.write_text(json.dumps(state))
p=start(True)
try:
    ui=Peer('ui',True)
    expired=ui.call('subscribe',{'after':1})['result']
    assert expired['resync'] and expired['sequence']==5000,expired
    chat=ui.call('ensureAssistant')['result']
    assert isinstance(chat,str)
    key=str(uuid.uuid4()); body={'chatID':chat,'title':'Fixture Golem'}
    a=ui.call('rename',body,key); b=ui.call('rename',body,key); assert a==b
    assert 'error' in ui.call('rename',dict(body,title='Other'),key)
    ui.call('setDraft',{'chatID':chat,'text':'persistent draft'})
    replay=ui.call('subscribe',{'after':0})['result']; assert replay['events']
    sequence=replay['sequence']
    assert ui.call('subscribe',{'after':sequence})['result']['events']==[]
    assert ui.call('subscribe',{'after':sequence+100})['result']['resync']
    ordinary_record=ui.call('get',{'chatID':chat})['result']['record']
    ordinary_record=dict(ordinary_record,id=str(uuid.uuid4()),isDot=False,items=[])
    ordinary=ui.call('create',{'record':ordinary_record})['result']
    golem_ui=Peer('golem-ui',True)
    assert 'result' in golem_ui.call('get',{'chatID':ordinary})
    for op in ('send','setDraft','stop','approve','answer','rename'):
        assert golem_ui.call(op,{'chatID':ordinary,'text':'denied','title':'denied'}).get('error')=='permission_denied',op
    forged=dict(ordinary_record,isDot=True)
    assert golem_ui.call('metadata',{'record':forged}).get('error')=='permission_denied'
    assert 'result' in golem_ui.call('list')
    assert 'result' in golem_ui.call('rename',{'chatID':chat,'title':'Golem interface'})
    assert golem_ui.call('integration',{'enabled':False}).get('error')=='permission_denied'
    assert golem_ui.call('preferences',{'codexPath':'/invalid'}).get('error')=='permission_denied'
    assert golem_ui.call('companion',{'newCode':True}).get('error')=='permission_denied'
    assert golem_ui.call('companionStatus')['result']['pairingCode']==''
    golem=Peer('golem')
    ui.call('integration',{'enabled':False})
    assert golem.call('list').get('error')=='integration_disabled'
    assert golem_ui.call('rename',body).get('error')=='integration_disabled'
    assert 'result' in golem.call('health')
    ui.call('integration',{'enabled':True}); assert 'result' in golem.call('list')
    assert 'result' in golem_ui.call('list')
    golem_ui.close(); golem.close(); ui.close()
finally: stop(p)
p=start(True)
try:
    ui=Peer('ui',True)
    assert ui.call('draft',{'chatID':chat})['result']['text']=='persistent draft'
    assert ui.call('rename',body,key)==a
    assert len(ui.call('list')['result'])==2
    ui.close()
finally: stop(p)
print('PASS signed-UI capability boundary, protocol version, receipt retry, event replay/resync, plugin revocation, restart persistence')
print('RPC artifacts:',root)
