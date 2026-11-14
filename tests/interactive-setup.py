#!/usr/bin/env python3
"""Drive the normal Docker Console setup with a disposable credential."""
import os
import sys
from uuid import uuid4

import pexpect

command = os.environ.get("CONTAINER_ENGINE", "docker")
container = sys.argv[1]
fake_key = os.environ.get("VELLUM_AIO_TEST_KEY") or "fixture-" + uuid4().hex
child = pexpect.spawn(command, ["exec", "-it", container, "vellum-aio", "setup"],
                      encoding="utf-8", timeout=180)
child.expect_exact("Assistant name")
child.sendline("Local Test")
child.expect_exact("Use a custom OpenAI-compatible endpoint?")
if len(sys.argv) > 2 and sys.argv[2] == "default":
    child.sendline("n")
    child.expect_exact("Enter a number")
    child.sendline("4")
    child.expect_exact("Model ID")
    child.sendline("openai/gpt-5-mini")
else:
    child.sendline("y")
    child.expect_exact("OpenAI-compatible base URL")
    child.sendline("http://127.0.0.1:18999/v1")
    child.expect_exact("Model ID")
    child.sendline("aio-fixture-model")
child.expect_exact("Provider API key (hidden")
child.sendline(fake_key)
if child.expect_exact([pexpect.EOF, "Retry key"]) != 0:
    child.sendline("")
    child.expect(pexpect.EOF)
output = child.before
child.close()
if fake_key in output:
    raise SystemExit("Setup echoed the test credential")
print(output.strip())
sys.exit(child.exitstatus if child.exitstatus is not None else 1)
