"""A stand-in for GitHub, for installer/test_install.sh.

Serves a directory tree, plus one thing python -m http.server cannot do: paths
under /private/ are 404 without an Authorization header, which is exactly how a
private repository behaves. That is what proves the installer actually sends the
token it was given rather than merely accepting one.
"""
import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler


class Handler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        # /private/<rest> maps to the same file as /<rest>
        if path.startswith("/private/"):
            path = path[len("/private"):]
        return super().translate_path(path)

    def do_GET(self):
        if self.path.startswith("/private/") and not self.headers.get("Authorization"):
            self.send_error(404, "Not Found")
            return
        super().do_GET()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port, root = int(sys.argv[1]), sys.argv[2]
    os.chdir(root)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
