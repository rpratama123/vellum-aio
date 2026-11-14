#!/usr/bin/env python3
"""Open the ChatGPT authorization flow from the browser's own machine."""

import argparse
import http.server
import shlex
import subprocess
import sys
import time
import urllib.parse
import webbrowser


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ssh", metavar="USER@HOST", help="host running the container")
    parser.add_argument("--engine", choices=("docker", "podman"), default="docker")
    parser.add_argument("--container", default="vellum-aio")
    parser.add_argument("--new-account", action="store_true")
    args = parser.parse_args()

    def run(*arguments, data=None):
        command = [args.engine, "exec", "-i", "--", args.container,
                   "vellum-aio", "chatgpt", *arguments]
        if args.ssh:
            command = ["ssh", "-T", "--", args.ssh, shlex.join(command)]
        return subprocess.run(command, input=data, text=True, check=True,
                              stdout=subprocess.PIPE, timeout=75).stdout.strip()

    class Callback(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            # A request path contains a short-lived authorization code.
            pass

        def do_GET(self):
            parsed = urllib.parse.urlsplit(self.path)
            if (parsed.netloc or parsed.scheme or parsed.path != "/auth/callback"
                    or urllib.parse.parse_qs(parsed.query).get("state") != [state]):
                self.send_error(404)
                return
            self.server.callback = redirect + "?" + parsed.query
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(b"Callback received. Check your terminal for the sign-in result.")

    with http.server.HTTPServer(("127.0.0.1", 0), Callback) as server:
        server.timeout = 1
        server.callback = None
        port = server.server_port
        redirect = f"http://127.0.0.1:{port}/auth/callback"
        options = ["--new-account"] if args.new_account else []
        url = run("begin", str(port), *options)
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme, parsed.netloc, parsed.path) != (
            "https", "auth.openai.com", "/api/accounts/authorize"
        ):
            raise ValueError("The container returned an unexpected authorization URL.")
        query = urllib.parse.parse_qs(parsed.query)
        if query.get("redirect_uri") != [redirect] or len(query.get("state", [])) != 1:
            raise ValueError("The container returned an invalid callback configuration.")
        state = query["state"][0]
        print(f"Open this URL to continue with ChatGPT:\n{url}", flush=True)
        try:
            webbrowser.open(url)
        except webbrowser.Error:
            pass
        deadline = time.monotonic() + 590
        while server.callback is None and time.monotonic() < deadline:
            server.handle_request()
        if server.callback is None:
            raise TimeoutError("ChatGPT sign-in timed out. Run the command again.")
        print(run("finish", data=server.callback))


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError:
        sys.exit("The ChatGPT command failed in the Vellum AIO container.")
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
