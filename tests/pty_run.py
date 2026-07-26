#!/usr/bin/env python3
"""Run a command inside a real pseudo-terminal, feeding scripted input.

Some ell behaviour (record mode, interactive prompts) only exercises its real
code path over a tty, which a pipe cannot emulate. This helper gives a command
a genuine PTY so shell tests can drive it. It is intentionally generic and not
record-specific.

Usage:
    pty_run.py [--timeout SECONDS] [--send-eof] \\
               [--input LINE] [--delay SECONDS] -- CMD [ARG...]

Options:
    --input LINE     A line to type into the PTY (the trailing newline is
                     added). May be given multiple times, sent in order.
    --send-eof       Send Ctrl-D (EOF) after the inputs.
    --delay SECONDS  Pause before/after sending inputs (default 1.0), to let
                     the child reach its prompt.
    --timeout SECONDS Overall bound (default 15); on expiry the child is
                     killed and exit status 124 is reported (like `timeout`).

The child's stdout/stderr (as seen on the PTY) is streamed to this process's
stdout. The final line printed is always:
    CHILD_EXIT=<n>
where <n> is the child's exit status, or 124 on timeout, or -1 if it could not
be determined. Tests should parse that line.
"""

import argparse
import os
import pty
import select
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--delay", type=float, default=1.0)
    parser.add_argument("--input", action="append", default=[])
    parser.add_argument("--send-eof", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    cmd = args.command
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        sys.stderr.write("pty_run.py: no command given\n")
        return 2

    pid, fd = pty.fork()
    if pid == 0:
        # Child: become the command inside the PTY.
        os.execvp(cmd[0], cmd)
        os._exit(127)  # execvp only returns on failure

    # Parent: let the child reach its prompt, send the scripted input, then EOF.
    time.sleep(args.delay)
    for line in args.input:
        os.write(fd, (line + "\n").encode())
        time.sleep(args.delay)
    if args.send_eof:
        os.write(fd, b"\x04")  # Ctrl-D

    deadline = time.time() + args.timeout
    timed_out = False
    while True:
        if time.time() >= deadline:
            timed_out = True
            break
        try:
            r, _, _ = select.select([fd], [], [], 0.5)
        except OSError:
            break
        if not r:
            continue
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()

    if timed_out:
        try:
            import signal

            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except OSError:
            pass
        print("CHILD_EXIT=124")
        return 0

    try:
        _, status = os.waitpid(pid, 0)
        code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1
    except OSError:
        code = -1
    print("CHILD_EXIT=%d" % code)
    return 0


if __name__ == "__main__":
    sys.exit(main())
