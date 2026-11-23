"""Loopback-only appcast fixture for the real Sparkle integration test."""
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import threading

url_file, counts_file = map(Path, sys.argv[1:])
counts = {'appcast': 0, 'archive': 0}
lock = threading.Lock()
counts_file.write_text(json.dumps(counts))

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        kind = 'appcast' if self.path == '/appcast.xml' else 'archive'
        with lock:
            counts[kind] += 1
            counts_file.write_text(json.dumps(counts))
        if kind != 'appcast':
            self.send_error(404)
            return
        signature = base64.b64encode(bytes(64)).decode()
        content = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<title>Test updates</title><item><title>Focuselle 0.4.1</title>
<sparkle:version>5</sparkle:version><sparkle:shortVersionString>0.4.1</sparkle:shortVersionString>
<enclosure url="http://127.0.0.1:{self.server.server_port}/Focuselle.zip" length="1234" type="application/octet-stream" sparkle:edSignature="{signature}"/>
</item></channel></rss>'''.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/rss+xml')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)
    def log_message(self, *args):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
url_file.write_text(f'http://127.0.0.1:{server.server_port}/appcast.xml')
server.serve_forever()
