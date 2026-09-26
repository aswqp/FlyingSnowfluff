#!/usr/bin/env python3

import subprocess
import sys
import time

helper = sys.argv[1]
started = time.perf_counter_ns()
result = subprocess.run(
    [helper, "--event", "sessionEnd"],
    input=b'{"session_id":"offline-test"}',
    check=False,
    timeout=0.3,
)
elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000

assert result.returncode == 0, result.returncode
assert elapsed_ms < 300, elapsed_ms
assert subprocess.run(
    [helper, "--event", "preToolUse"], input=b"not-json", check=False, timeout=0.3
).returncode == 0
assert subprocess.run(
    [helper, "--event", "unknown-event"], input=b"{}", check=False, timeout=0.3
).returncode == 0

oversized = subprocess.run(
    [helper, "--event", "preToolUse"],
    input=b'{' + (b'"x":1,' * 20_000) + b'"done":true}',
    check=False,
    timeout=0.3,
)
assert oversized.returncode == 0

held_open = subprocess.Popen(
    [helper, "--event", "userPromptSubmit"],
    stdin=subprocess.PIPE,
)
try:
    assert held_open.wait(timeout=0.3) == 0
finally:
    if held_open.poll() is None:
        held_open.kill()
        held_open.wait()

print(f"PASS: helper fail-open ({elapsed_ms:.1f}ms)")
