#!/usr/bin/env python3
"""Static file server for tests/smoke.sh that logs request headers.

Usage: http-server.py PORT DIR HEADER_LOG [TLS_PORT CERT KEY]
Each GET appends "path<TAB>name: value<TAB>..." (header names lowercased) to HEADER_LOG.
With TLS_PORT the same files are also served over HTTPS (self-signed CERT/KEY).
"""
import functools
import http.server
import ssl
import sys
import threading

port, directory, log = int(sys.argv[1]), sys.argv[2], sys.argv[3]


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        with open(log, "a") as f:
            hdrs = "\t".join(f"{k.lower()}: {v}" for k, v in self.headers.items())
            f.write(f"{self.path}\t{hdrs}\n")
        super().do_GET()

    def log_message(self, *args):
        pass


handler = functools.partial(Handler, directory=directory)

if len(sys.argv) > 6:
    tls = http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[4])), handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(sys.argv[5], sys.argv[6])
    tls.socket = ctx.wrap_socket(tls.socket, server_side=True)
    threading.Thread(target=tls.serve_forever, daemon=True).start()

http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
