#!/usr/bin/env python3
"""Serves the controlled-field fixture on 127.0.0.1 and keeps the page's latest report in a file.

Usage:  serve.py <port> <report path>
"""
import http.server
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPORT = pathlib.Path(sys.argv[2])


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(HERE), **kwargs)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        REPORT.write_bytes(body)
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


port = int(sys.argv[1])
http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
