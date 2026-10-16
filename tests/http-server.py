#!/usr/bin/env python3
"""Static file server for tests/smoke.sh that logs request headers.

Usage: http-server.py PORT DIR HEADER_LOG
Each GET appends "path<TAB>name: value<TAB>..." (header names lowercased) to HEADER_LOG.
"""
import functools
import http.server
import sys

port, directory, log = int(sys.argv[1]), sys.argv[2], sys.argv[3]


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        with open(log, "a") as f:
            hdrs = "\t".join(f"{k.lower()}: {v}" for k, v in self.headers.items())
            f.write(f"{self.path}\t{hdrs}\n")
        super().do_GET()

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(
    ("127.0.0.1", port), functools.partial(Handler, directory=directory)
).serve_forever()
