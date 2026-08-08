#!/usr/bin/env python3
"""
Language convention check script

Detects CJK (Japanese) characters accidentally transcribed into English-only
documents (skills/**/*.md, modules/*.md, scripts/*) from a unified diff.

Reads a unified diff (`git diff` format) from stdin and checks added
(`+`-prefixed) lines for violations. Context lines (unchanged, space-prefixed)
are also scanned for fence markers — but not for violations — so fence state
stays correct when a diff edits content inside an already-existing fenced
block without touching the fence delimiters themselves. The caller is
expected to pass a diff already scoped to the target paths (e.g.
`git diff -- skills/ modules/ scripts/`); this script does not filter by path
itself.

False positives are excluded for three legitimate CJK usages, per CLAUDE.md's
"Skill output (terminal): Japanese" convention:
  (i)   Fenced code blocks containing terminal output templates (e.g. the
        `Print advisory` template block in skills/verify/SKILL.md) — added
        lines whose enclosing fence (tracked across both added and unchanged
        context lines) is open are skipped entirely.
  (ii)  Inline code spans (`...`) containing Japanese keywords used as data
        values rather than prose (e.g. the domain classification table's
        `デザイン` entries in skills/audit/SKILL.md) — the content of inline
        code spans is stripped before the CJK check.
  (iii) Double-quoted string literals carrying an output message (e.g. after
        `Print:` / `Notify user:`) — the content of double-quoted strings is
        stripped before the CJK check.

Any CJK character remaining in plain prose after these three exclusions is
treated as a language convention violation.

Uses Python standard library only.
"""

import re
import sys

CJK_PATTERN = re.compile(r"[぀-ゟ゠-ヿ一-鿿]")
INLINE_CODE_PATTERN = re.compile(r"`[^`]*`")
DOUBLE_QUOTED_PATTERN = re.compile(r'"[^"]*"')
FENCE_PATTERN = re.compile(r"^\s*```")


def find_violations(diff_text):
    violations = []
    current_file = None
    fence_count = 0

    for line in diff_text.splitlines():
        if line.startswith("+++ "):
            path = line[len("+++ "):].strip()
            current_file = path[2:] if path.startswith("b/") else path
            fence_count = 0
            continue

        if line.startswith("---"):
            continue

        if line.startswith("-"):
            continue

        if line.startswith("+"):
            content = line[1:]
            is_added = True
        elif line.startswith(" "):
            content = line[1:]
            is_added = False
        else:
            continue

        if FENCE_PATTERN.match(content):
            fence_count += 1
            continue

        if not is_added:
            continue

        if fence_count % 2 == 1:
            continue

        stripped = INLINE_CODE_PATTERN.sub("", content)
        stripped = DOUBLE_QUOTED_PATTERN.sub("", stripped)

        if CJK_PATTERN.search(stripped):
            violations.append(f"{current_file}:{content}")

    return violations


def main():
    diff_text = sys.stdin.read()
    violations = find_violations(diff_text)

    if violations:
        for violation in violations:
            print(violation)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
