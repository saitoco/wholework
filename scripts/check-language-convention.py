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

False positives are excluded for four legitimate CJK usages, per CLAUDE.md's
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
  (iv)  Single-quoted string literals carrying an output message (e.g. a
        bash `printf '...'` / `echo '...'` Japanese literal) — the content
        of single-quoted strings is stripped before the CJK check, subject
        to the asymmetry guard below.

Unlike double quotes, an apostrophe also appears mid-word in English prose
(contractions such as `don't`, possessives such as `user's`). A naive
symmetric pattern would pair up two unrelated apostrophes and swallow
everything between them — including real CJK violations — as a false
negative. `SINGLE_QUOTED_PATTERN` guards against this by requiring that
neither the opening nor the closing quote is adjacent to a word character:
an apostrophe preceded by a letter/digit/underscore (as in a contraction or
possessive) can never open or close a stripped span.

Any CJK character remaining in plain prose after these four exclusions is
treated as a language convention violation.

Uses Python standard library only.
"""

import re
import sys

CJK_PATTERN = re.compile(r"[぀-ゟ゠-ヿ一-鿿]")
# Captures the opening backtick run and requires a closing run of the same length
# (Markdown code span rule), so a double-backtick span containing a nested single
# backtick (e.g. ``the `foo` value``) is recognized as one span instead of the
# unmatched first backtick greedily consuming the rest of the document.
INLINE_CODE_PATTERN = re.compile(r'(`+)(?:(?!\1).)+?\1', re.DOTALL)
DOUBLE_QUOTED_PATTERN = re.compile(r'"[^"]*"')
SINGLE_QUOTED_PATTERN = re.compile(r"(?<!\w)'[^']*'(?!\w)")
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
        stripped = SINGLE_QUOTED_PATTERN.sub("", stripped)

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
