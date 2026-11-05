import os,http.server,json,uuid
ID='11111111-1111-1111-1111-111111111111'
chat={'id':ID,'title':'History fixture','backend':'codex','isRunning':False,'isWaitingOnYou':False,'updatedAt':'2026-10-02T00:00:00Z'}
item={'id':'22222222-2222-2222-2222-222222222222','kind':'assistant','text':'History loaded without sending a message. This is the initial-load regression test.','isStreaming':False,'isCommentary':False,'isPending':False,'attachments':[],'isQueued':False}
detail={'revision':0,'summary':chat,'settings':'Codex · GPT-6.1-Sol','items':[item],'earlierCount':0}
class Handler(http.server.BaseHTTPRequestHandler):
 def reply(self,x):
  data=json.dumps(x).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 def do_POST(self):
  n=int(self.headers.get('Content-Length',0));self.rfile.read(n)
  if self.path=='/v1/pair':self.reply({'token':'isolated-regression-token','macName':'Regression Mac','addresses':['127.0.0.1']})
  else:self.send_error(400,'Test does not accept chat mutations')
 def do_GET(self):
  if self.path=='/v1/chats':self.reply({'revision':0,'groups':[{'id':'chats','kind':'chats','title':'Chats','chats':[chat]}]})
  elif self.path.startswith('/v1/chats/'+ID):self.reply({'unchanged':True,'revision':0} if '?since=0' in self.path else detail)
  elif self.path=='/v1/addresses':self.reply({'addresses':['127.0.0.1']})
  else:self.send_error(404)
# The port: CHATTERBOX_TEST_PORT, or 0 for a free one (start_test_server, test-hygiene.sh);
# the one it got goes to CHATTERBOX_TEST_PORT_FILE once it's listening.
server=http.server.ThreadingHTTPServer(('127.0.0.1',int(os.environ.get('CHATTERBOX_TEST_PORT','19645'))),Handler)
PORT=server.server_address[1]
if os.environ.get('CHATTERBOX_TEST_PORT_FILE'):
 open(os.environ['CHATTERBOX_TEST_PORT_FILE']+'.tmp','w').write(str(PORT));os.rename(os.environ['CHATTERBOX_TEST_PORT_FILE']+'.tmp',os.environ['CHATTERBOX_TEST_PORT_FILE'])
print('listening on 127.0.0.1:%d'%PORT,flush=True)
server.serve_forever()
