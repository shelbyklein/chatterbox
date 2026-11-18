"""Isolated authenticated companion fixture; never contacts the real Mac service."""
import http.server
import json
import os
import struct
import threading
import time
import uuid
import zlib
from pathlib import Path

CHAT = '33333333-3333-3333-3333-333333333333'
IMAGE = '22222222-2222-2222-2222-222222222222'
OLDER = '11111111-1111-1111-1111-111111111111'
ROOT = Path(os.environ['CHATTERBOX_TEST_OUTPUT'])
mode = 'transient'
revision = 1
counts = {}
recovered = False
gate = threading.Event()
advance = threading.Event()

def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))

# A real, opaque blue/teal PNG, with stable 2:1 dimensions matching the placeholder.
rows = b''.join(b'\0' + bytes((25, 135, 190) if y < 80 else (35, 175, 155)) * 320 for y in range(160))
PNG = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', 320, 160, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')
# Same real picture, uncompressed so partial transfers have measurable byte counts.
PROGRESS_PNG = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', 320, 160, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows, level=0)) + chunk(b'IEND', b'')

streamed = 0

def summary():
    return dict(id=CHAT, title='Image retries', project='Image retries', backend='claude',
                isRunning=mode == 'streaming', isWaitingOnYou=False, updatedAt='2026-10-21T00:00:00Z')

def item(key, text, image=None):
    files = [] if image is None else [dict(id=image, name='Retry proof.png', mediaType='image/png',
                                         isImage=True, revision=str(revision))]
    return dict(id=str(uuid.uuid5(uuid.NAMESPACE_URL, key)), kind='image' if image else 'assistant',
                text=text, isStreaming=False, isCommentary=False, isPending=False, attachments=files, isQueued=False)

def detail():
    global streamed
    items = [item('older', 'An older image stays offscreen.', OLDER)]
    items += [item(str(n), f'Earlier reply {n}. ' + 'Read older messages here. ' * 18) for n in range(15)]
    if mode == 'streaming':
        # As on the Duo: the image belongs to a finished reply (a render it names), and the
        # next reply streams below it, so the transcript changes on every refresh.
        latest = item('latest', 'Visible image retry proof.', IMAGE)
        latest['kind'] = 'assistant'
        streamed += 1
        items += [latest, dict(id=str(uuid.uuid5(uuid.NAMESPACE_URL, 'streaming')), kind='assistant',
                               text='Uploading V17 to the Duo print queue. ' * streamed, isStreaming=True,
                               isCommentary=False, isPending=False, attachments=[], isQueued=False)]
        return dict(revision=revision + streamed, summary=summary(), settings='Claude', items=items, earlierCount=0)
    items += [item('latest', 'Visible image retry proof.', IMAGE)]
    return dict(revision=revision, summary=summary(), settings='Claude', items=items, earlierCount=0)

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, value, status=200):
        self.binary(json.dumps(value).encode(), 'application/json', status)

    def binary(self, data, content_type, status=200):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        global mode, revision, counts, recovered, gate, advance
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
        if self.path == '/v1/pair':
            return self.reply(dict(token='fixture', macName='Image Regression Mac', addresses=['127.0.0.1']))
        if self.path == '/test/reset':
            gate.set()
            advance.set()
            gate = threading.Event()
            advance = threading.Event()
            mode = body.get('mode', 'transient')
            global streamed
            streamed = 0
            revision += 1
            counts = {}
            recovered = False
            return self.reply({})
        if self.path == '/test/recover':
            recovered = True
            return self.reply({})
        if self.path == '/test/release':
            gate.set()
            return self.reply({})
        if self.path == '/test/advance':
            advance.set()
            return self.reply({})
        self.send_error(404)

    def do_GET(self):
        if self.path == '/test/counts':
            return self.reply(counts)
        if '/files/' in self.path:
            file = self.path.split('/files/')[1].split('?')[0].lower()
            counts[file] = counts.get(file, 0) + 1
            attempt = counts[file]
            (ROOT / 'requests.json').write_text(json.dumps(counts))
            if file == IMAGE:
                if mode in ('progress', 'unknown-length'):
                    final, halfway = gate, advance
                    self.send_response(200)
                    self.send_header('Content-Type', 'image/png')
                    if mode == 'progress':
                        self.send_header('Content-Length', str(len(PROGRESS_PNG)))
                    self.end_headers()
                    quarter = len(PROGRESS_PNG) // 4
                    try:
                        self.wfile.write(PROGRESS_PNG[:quarter]); self.wfile.flush()
                        halfway.wait(timeout=45)
                        self.wfile.write(PROGRESS_PNG[quarter:quarter * 2]); self.wfile.flush()
                        final.wait(timeout=45)
                        self.wfile.write(PROGRESS_PNG[quarter * 2:])
                    except (BrokenPipeError, ConnectionResetError):
                        pass
                    return
                if mode == 'slow' and attempt == 1:
                    gate.wait(timeout=20)
                elif not recovered and (mode in ('permanent', 'manual') or attempt == 1):
                    return self.reply(dict(error='Fixture transient failure'), 503)
            return self.binary(PNG, 'image/png')
        if self.path == '/v1/chats':
            return self.reply(dict(revision=revision, groups=[dict(id='projects', kind='projects', title='Projects', chats=[summary()])]))
        if self.path == '/v1/addresses':
            return self.reply(dict(addresses=['127.0.0.1']))
        if self.path.startswith('/v1/chats/' + CHAT):
            if mode == 'streaming':
                return self.reply(detail())
            return self.reply(dict(unchanged=True, revision=revision) if f'?since={revision}' in self.path else detail())
        self.send_error(404)

# The port: CHATTERBOX_TEST_PORT, or 0 for a free one (start_test_server, test-hygiene.sh);
# the one it got goes to CHATTERBOX_TEST_PORT_FILE once it's listening.
server=http.server.ThreadingHTTPServer(('127.0.0.1',int(os.environ.get('CHATTERBOX_TEST_PORT','47410'))),Handler)
PORT=server.server_address[1]
if os.environ.get('CHATTERBOX_TEST_PORT_FILE'):
 open(os.environ['CHATTERBOX_TEST_PORT_FILE']+'.tmp','w').write(str(PORT));os.rename(os.environ['CHATTERBOX_TEST_PORT_FILE']+'.tmp',os.environ['CHATTERBOX_TEST_PORT_FILE'])
print('listening on 127.0.0.1:%d'%PORT,flush=True)
server.serve_forever()
