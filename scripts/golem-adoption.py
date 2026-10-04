#!/usr/bin/env python3
"""Offline adoption/restore tool. The operator must quiesce all existing writers first.
No background process installation, launching, or provider requests occur here.
"""
import argparse, fcntl, hashlib, json, plistlib, shutil
from pathlib import Path
RUNTIME_KEYS={'defaultBackend','defaultModel','defaultEffort','defaultPersonality','claudePath','codexPath','codexFolder','codexDefaultModel','codexDefaultEffort','claudeDefaultMode','codexDefaultMode','remoteControlClaudeChats','easyCLIProxyEnabled','companionEnabled','companionDevices','pins','openWebsitePinsInApp','plugin.nextSteps.enabled','plugin.nextSteps.minAnswerChars','plugin.nextSteps.suggestCommands','mobilePushEnabled','mobilePushConfigured','mobilePushPreviews','mobilePushSound','dotDefaultBackend','dotDefaultModel','dotApplyDefault','dotSeenItem'}
GOLEM_KEYS={'dotCheckIns','dotCheckInTimes','dotWatchWaiting','dotSummarizeFinished','dotEmailWatch','dotEmailModel','dotEmailLastAttempt','dotEmailLastSweep','dotEmailReported','dotCheckInsDone','dotDefaultBackend','dotDefaultModel','dotApplyDefault','dotSeenItem','golemMiniVisible','golemMiniExpandedFrame','golemMiniAvatarFrame','golemMiniSize','dotCollapsed','golemPanelTab','golemActivityExpanded'}
def inventory(path):
    return {str(p.relative_to(path)):hashlib.sha256(p.read_bytes()).hexdigest() for p in path.rglob('*') if p.is_file() and p.name!='runtime.lock'}
def lock(root):
    root.mkdir(parents=True,exist_ok=True)
    stream=open(root/'runtime.lock','a+b');fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB);return stream
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['adopt','restore']);p.add_argument('--data',type=Path,required=True);p.add_argument('--assistant',type=Path,required=True)
    p.add_argument('--host',type=Path,required=True);p.add_argument('--memory',type=Path,required=True);p.add_argument('--preferences',type=Path,required=True)
    p.add_argument('--backup',type=Path,required=True);p.add_argument('--quiesced',action='store_true',required=True)
    args=p.parse_args();locks=[lock(args.data),lock(args.assistant/'Service')]
    roots={'data':args.data,'assistant':args.assistant,'host':args.host,'memory':args.memory}
    if args.action=='adopt':
        import_file=args.data/'golem-import.json'
        if import_file.exists():
            record=json.loads(import_file.read_text());assert record['schema']==1
            print('Already adopted; import retained.');return
        assert not args.backup.exists(),'Use a new backup destination; existing backups are never overwritten.'
        args.backup.mkdir(parents=True,mode=0o700)
        manifest={}
        for name,root in roots.items():
            if root.exists():shutil.copytree(root,args.backup/name,ignore=shutil.ignore_patterns('*.sock','runtime.lock'));manifest[name]=inventory(args.backup/name)
        shutil.copyfile(args.preferences,args.backup/'preferences.plist')
        (args.backup/'manifest.json').write_text(json.dumps(manifest,indent=2))
        prefs=plistlib.loads(args.preferences.read_bytes())
        (args.data/'runtime-preferences.plist').write_bytes(plistlib.dumps({k:v for k,v in prefs.items() if k in RUNTIME_KEYS}))
        (args.assistant/'service-preferences.plist').write_bytes(plistlib.dumps({k:v for k,v in prefs.items() if k in GOLEM_KEYS}))
        (args.data/'runtime-owner.json').write_text(json.dumps({'schema':1,'owner':'chatterboxd'}))
        import_file.write_text(json.dumps({'schema':1,'backup':str(args.backup),'conversations':len(list((args.data/'Conversations').glob('*.json'))),'sourceHashes':manifest}))
        print('Adopted offline store; original preferences retained. Services remain stopped.')
    else:
        manifest=json.loads((args.backup/'manifest.json').read_text())
        for name,expected in manifest.items():assert inventory(args.backup/name)==expected,'Backup verification failed: '+name
        recovery=args.backup/'post-adoption-recovery'
        assert not recovery.exists(),'Recovery export already exists; inspect it before another restore.'
        recovery.mkdir(mode=0o700)
        for name,root in roots.items():
            if root.exists():shutil.copytree(root,recovery/name,ignore=shutil.ignore_patterns('*.sock','runtime.lock'))
            if (args.backup/name).exists():
                # Preserve locked inode while replacing files beneath it.
                for child in root.iterdir():
                    if child.name=='runtime.lock' or (name=='assistant' and child.name=='Service'):continue
                    if child.is_dir():shutil.rmtree(child)
                    else:child.unlink()
                shutil.copytree(args.backup/name,root,dirs_exist_ok=True)
        assert all(inventory(root)==manifest[name] for name,root in roots.items() if name in manifest)
        print('Backup restored and verified; post-adoption files retained in recovery export. Services remain stopped.')
    for stream in locks:stream.close()
if __name__=='__main__':main()
