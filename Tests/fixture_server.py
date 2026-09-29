"""Local test media server with HTTP byte ranges, required for MKV seeking."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent / 'Fixtures'


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def send_head(self):
        path = Path(self.translate_path(self.path))
        if not path.is_file():
            self.send_error(404)
            return None
        source = path.open('rb')
        size = path.stat().st_size
        start, end = 0, size - 1
        requested = self.headers.get('Range')
        if requested:
            match = re.fullmatch(r'bytes=(\d*)-(\d*)', requested)
            if match and any(match.groups()):
                first, last = match.groups()
                start = int(first) if first else max(0, size - int(last))
                end = min(size - 1, int(last)) if first and last else size - 1
            else:
                start = size
            if start > end or start >= size:
                source.close()
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{size}')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return None
        self.send_response(206 if requested else 200)
        self.send_header('Content-Type', self.guess_type(str(path)))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(end - start + 1))
        if requested:
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers()
        source.seek(start)
        self.remaining = end - start + 1
        return source

    def copyfile(self, source, outputfile):
        while self.remaining:
            data = source.read(min(self.remaining, 65536))
            if not data:
                break
            try:
                outputfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                break
            self.remaining -= len(data)


if __name__ == '__main__':
    if '--self-test' in sys.argv:
        import threading
        import urllib.request
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_port}/languages.mkv'
        expected = (ROOT / 'languages.mkv').read_bytes()
        for value, data in [('bytes=10-99', expected[10:100]), ('bytes=-32', expected[-32:]), ('bytes=100-', expected[100:])]:
            with urllib.request.urlopen(urllib.request.Request(url, headers={'Range': value})) as response:
                assert response.status == 206 and response.read() == data
        server.shutdown()
        print('Fixture HTTP byte-range tests passed')
    else:
        ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
