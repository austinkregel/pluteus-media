#!/usr/bin/env python3
"""Reject shell commands that filter or truncate their own output.

Reads a PreToolUse hook payload on stdin. Emits a deny decision when the
command invokes an output-filtering tool in command position. `tee` is
permitted: it preserves the full stream and writes a file that can be read
more than once.

Detection uses shlex tokenization so a banned word inside a quoted string or
a filename does not trigger. Malformed input is allowed through rather than
blocking the session on a parse failure.
"""
import json
import shlex
import sys

BLOCKED = {
    "grep", "egrep", "fgrep", "rg", "ag", "ack",
    "head", "tail", "sed", "awk", "cut", "uniq", "sort",
    "tr", "column", "less", "more", "fold", "nl",
}

# A token is in command position at the start, or immediately after one of
# these shell operators.
OPERATORS = {"|", "||", "&&", ";", "&", "(", ")", "{", "}", "|&", "\n"}


def offenders(command: str) -> list[str]:
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return []

    found, expect_command = [], True
    for token in tokens:
        if token in OPERATORS:
            expect_command = True
            continue
        if expect_command:
            name = token.rsplit("/", 1)[-1]
            if name in {"sudo", "command", "env", "time", "nice", "xargs"}:
                continue
            if name in BLOCKED and name not in found:
                found.append(name)
        expect_command = False
    return found


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return

    command = payload.get("tool_input", {}).get("command", "")
    found = offenders(command)
    if not found:
        return

    reason = (
        f"Blocked: {', '.join(found)}. These discard or buffer output before "
        "you see it.\n\n"
        "Instead:\n"
        "  - Run the command and read all of its output, or\n"
        "  - Capture it: <command> | tee /tmp/out.txt   then Read /tmp/out.txt\n"
        "    (tee is allowed, and the file can be re-read without re-running)\n"
        "  - To search files, use the Grep and Glob tools, not shell grep.\n"
        "  - To read part of a file, use Read with offset and limit."
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))


if __name__ == "__main__":
    main()
