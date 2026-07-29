#!/usr/bin/env python3
"""
HTML CSS selector match counter.

Reads HTML from stdin, matches a single compound CSS selector (tag / #id /
.class / [attr] / [attr='value']) against start tags, and prints the number
of matching elements. Standard library only, no third-party dependencies.
"""

import re
import sys
from html.parser import HTMLParser

TAG_RE = re.compile(r'[a-zA-Z][\w-]*')
ID_RE = re.compile(r'#([\w-]+)')
CLASS_RE = re.compile(r'\.([\w-]+)')
ATTR_RE = re.compile(r'''\[([\w-]+)(?:=(?:'([^']*)'|"([^"]*)"))?\]''')


def parse_selector(selector):
    """Parse a compound CSS selector into its components.

    Raises ValueError on unsupported/invalid syntax.
    """
    if not selector:
        raise ValueError("empty selector")

    pos = 0
    tag = None
    id_ = None
    classes = []
    attrs = []

    m = TAG_RE.match(selector, pos)
    if m:
        tag = m.group(0)
        pos = m.end()

    while pos < len(selector):
        m = ID_RE.match(selector, pos)
        if m:
            id_ = m.group(1)
            pos = m.end()
            continue
        m = CLASS_RE.match(selector, pos)
        if m:
            classes.append(m.group(1))
            pos = m.end()
            continue
        m = ATTR_RE.match(selector, pos)
        if m:
            name = m.group(1)
            value = m.group(2) if m.group(2) is not None else m.group(3)
            attrs.append((name, value))
            pos = m.end()
            continue
        raise ValueError(
            "invalid selector syntax at position {}: {!r}".format(pos, selector[pos:])
        )

    return {"tag": tag, "id": id_, "classes": classes, "attrs": attrs}


class SelectorMatcher(HTMLParser):
    def __init__(self, parsed_selector):
        super().__init__()
        self.parsed = parsed_selector
        self.count = 0

    def handle_starttag(self, tag, attrs):
        attr_dict = {}
        class_set = set()
        id_value = None
        for name, value in attrs:
            attr_dict[name] = value
            if name == "class" and value:
                class_set = set(value.split())
            elif name == "id":
                id_value = value

        sel = self.parsed
        if sel["tag"] is not None and tag.lower() != sel["tag"].lower():
            return
        if sel["id"] is not None and id_value != sel["id"]:
            return
        if sel["classes"] and not set(sel["classes"]).issubset(class_set):
            return
        for name, value in sel["attrs"]:
            if name not in attr_dict:
                return
            if value is not None and attr_dict[name] != value:
                return

        self.count += 1


def main():
    if len(sys.argv) != 2:
        print("Usage: html-selector-match.py <css-selector>", file=sys.stderr)
        sys.exit(2)

    try:
        parsed = parse_selector(sys.argv[1])
    except ValueError as e:
        print("selector parse error: {}".format(e), file=sys.stderr)
        sys.exit(2)

    html_input = sys.stdin.read()
    if not html_input:
        print(0)
        sys.exit(0)

    matcher = SelectorMatcher(parsed)
    try:
        matcher.feed(html_input)
        matcher.close()
    except Exception as e:
        print("html parse error: {}".format(e), file=sys.stderr)
        sys.exit(2)

    print(matcher.count)
    sys.exit(0)


if __name__ == "__main__":
    main()
