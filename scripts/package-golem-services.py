#!/usr/bin/env python3
"""Prepare reviewable per-user LaunchAgent plists; never load/install them."""
import argparse, plistlib
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--bundle-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--data',type=Path,required=True);p.add_argument('--assistant',type=Path,required=True);p.add_argument('--host',type=Path,required=True);p.add_argument('--label-prefix',default='com.shelbyklein');a=p.parse_args()
for key in ('bundle_root','output','data','assistant','host'):
    setattr(a,key,getattr(a,key).expanduser().resolve())
a.output.mkdir(parents=True,exist_ok=True)
for product,executable in [('Chatterbox','chatterboxd'),('Golem','golemd')]:
    label=a.label_prefix+'.'+executable
    environment={'CHATTERBOX_DATA_DIR':str(a.data),'CHATTERBOX_HOST_DIR':str(a.host),'CHATTERBOX_ASSISTANT_DIR':str(a.assistant),
        'CHATTERBOX_HOST_BINARY':str(a.bundle_root/'Chatterbox.app/Contents/MacOS/ChatterboxHost'),
        'CHATTERBOX_MCP_BINARY':str(a.bundle_root/'Chatterbox.app/Contents/MacOS/chatterbox-mcp')}
    # Retain ~/Chatterbox/Dot identity in production. Data override makes isolated tests
    # put it under their temporary root; no relocation is performed by this tool.
    plist={'Label':label,'ProgramArguments':[str(a.bundle_root/(product+'.app')/'Contents/MacOS'/executable)],
        'EnvironmentVariables':environment,'RunAtLoad':True,'KeepAlive':{'SuccessfulExit':False},'ThrottleInterval':30,
        'ProcessType':'Background','StandardOutPath':str(a.data/(executable+'.log')),'StandardErrorPath':str(a.data/(executable+'.log'))}
    (a.output/(label+'.plist')).write_bytes(plistlib.dumps(plist))
print('Prepared LaunchAgent plists only; no services were installed or loaded.')
