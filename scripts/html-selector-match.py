#!/usr/bin/env python3
"""
HTML CSS selector match counter.

Reads HTML from stdin, matches a CSS selector against an element tree built
from the HTML, and prints the number of matching elements. Standard library
only, no third-party dependencies.

Supported selector grammar:
- Compound selectors: tag / #id / .class / [attr] / [attr='value']
- Combinators: descendant (half-width space), child (`>`), adjacent sibling
  (`+`), general sibling (`~`)

Known constraint: HTML5 implied end tag rules (e.g. an unclosed `<p>` being
auto-closed by a following `<p>`) are not interpreted. Nesting is determined
solely by explicit end tags, so `div > p` against `<div><p>a<p>b</div>`
returns 1 rather than the browser-conformant 2.
"""

import re
import sys
from html.parser import HTMLParser

TAG_RE = re.compile(r'[a-zA-Z][\w-]*')
ID_RE = re.compile(r'#([\w-]+)')
CLASS_RE = re.compile(r'\.([\w-]+)')
ATTR_RE = re.compile(r'''\[([\w-]+)(?:=(?:'([^']*)'|"([^"]*)"))?\]''')

COMBINATOR_RE = re.compile(r'\s*([>+~])\s*|(\s+)')

# html.parser never calls handle_endtag for these, so they must not be
# pushed onto the open-element stack (pushing would leave the stack
# permanently unbalanced and corrupt all subsequent hierarchy judgments).
VOID_ELEMENTS = frozenset({
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
    'link', 'meta', 'param', 'source', 'track', 'wbr',
})


def parse_compound(text):
    """Parse a single compound CSS selector into its components.

    Raises ValueError on unsupported/invalid syntax.
    """
    if not text:
        raise ValueError("empty compound selector")

    pos = 0
    tag = None
    id_ = None
    classes = []
    attrs = []

    m = TAG_RE.match(text, pos)
    if m:
        tag = m.group(0)
        pos = m.end()

    while pos < len(text):
        m = ID_RE.match(text, pos)
        if m:
            id_ = m.group(1)
            pos = m.end()
            continue
        m = CLASS_RE.match(text, pos)
        if m:
            classes.append(m.group(1))
            pos = m.end()
            continue
        m = ATTR_RE.match(text, pos)
        if m:
            name = m.group(1)
            value = m.group(2) if m.group(2) is not None else m.group(3)
            attrs.append((name, value))
            pos = m.end()
            continue
        raise ValueError(
            "invalid selector syntax at position {}: {!r}".format(pos, text[pos:])
        )

    return {"tag": tag, "id": id_, "classes": classes, "attrs": attrs}


def split_selector(selector):
    """Split a selector into an ordered [(combinator, compound_text), ...] list.

    The first entry's combinator is always None. Brackets ('[' ']') and
    quoted attribute values are tracked so that whitespace or `>`/`+`/`~`
    characters inside them are never treated as combinators.

    Raises ValueError on: empty selector, leading combinator, trailing
    combinator, consecutive combinators, unbalanced brackets, unterminated
    quotes.
    """
    if selector is None or selector.strip() == "":
        raise ValueError("empty selector")

    selector = selector.strip()
    mask = list(selector)
    depth = 0
    quote = None
    for i, ch in enumerate(selector):
        if quote is not None:
            if ch == quote:
                quote = None
            mask[i] = 'x'
            continue
        if ch in ("'", '"'):
            quote = ch
            mask[i] = 'x'
            continue
        if ch == '[':
            depth += 1
            mask[i] = 'x'
            continue
        if ch == ']':
            if depth == 0:
                raise ValueError("unbalanced brackets")
            depth -= 1
            mask[i] = 'x'
            continue
        if depth > 0:
            mask[i] = 'x'
            continue
        # outside brackets/quotes: keep original char for combinator detection

    if quote is not None:
        raise ValueError("unterminated quote")
    if depth != 0:
        raise ValueError("unbalanced brackets")

    masked = ''.join(mask)

    segments = []
    combinators = []
    last_end = 0
    for m in COMBINATOR_RE.finditer(masked):
        start, end = m.span()
        segments.append(selector[last_end:start])
        combinators.append(m.group(1) if m.group(1) else ' ')
        last_end = end
    segments.append(selector[last_end:])

    for idx, seg in enumerate(segments):
        if seg.strip() == "":
            if idx == 0:
                raise ValueError("selector cannot start with a combinator")
            if idx == len(segments) - 1:
                raise ValueError("selector cannot end with a combinator")
            raise ValueError("selector cannot contain consecutive combinators")

    result = [(None, segments[0])]
    for combinator, seg in zip(combinators, segments[1:]):
        result.append((combinator, seg))
    return result


def parse_selector(selector):
    """Parse a full (possibly combinator-chained) CSS selector.

    Returns [(combinator, compound_dict), ...] with the first combinator
    always None. Raises ValueError on invalid syntax.
    """
    return [(combinator, parse_compound(text)) for combinator, text in split_selector(selector)]


class Node:
    __slots__ = ('tag', 'attr_dict', 'class_set', 'id_value', 'parent', 'children', 'sibling_index')

    def __init__(self, tag, attr_dict, class_set, id_value, parent):
        self.tag = tag
        self.attr_dict = attr_dict
        self.class_set = class_set
        self.id_value = id_value
        self.parent = parent
        self.children = []
        self.sibling_index = 0


class TreeBuilder(HTMLParser):
    def __init__(self):
        super().__init__()
        self.root = Node('#document', {}, set(), None, None)
        self.stack = [self.root]
        self.nodes = []

    def _build_node(self, tag, attrs):
        parent = self.stack[-1]
        attr_dict = {}
        class_set = set()
        id_value = None
        for name, value in attrs:
            attr_dict[name] = value
            if name == "class" and value:
                class_set = set(value.split())
            elif name == "id":
                id_value = value

        node = Node(tag.lower(), attr_dict, class_set, id_value, parent)
        node.sibling_index = len(parent.children)
        parent.children.append(node)
        self.nodes.append(node)
        return node

    def handle_starttag(self, tag, attrs):
        node = self._build_node(tag, attrs)
        if tag.lower() not in VOID_ELEMENTS:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self._build_node(tag, attrs)

    def handle_endtag(self, tag):
        tag_lower = tag.lower()
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag_lower:
                del self.stack[i:]
                return
        # orphan end tag with no matching open element: ignore and continue


def matches_compound(node, compound):
    if compound["tag"] is not None and node.tag != compound["tag"].lower():
        return False
    if compound["id"] is not None and node.id_value != compound["id"]:
        return False
    if compound["classes"] and not set(compound["classes"]).issubset(node.class_set):
        return False
    for name, value in compound["attrs"]:
        if name not in node.attr_dict:
            return False
        if value is not None and node.attr_dict[name] != value:
            return False
    return True


def matches_chain(node, chain, memo=None):
    """Match `node` against the last compound of `chain`, then resolve the
    remaining (combinator, compound) pairs against node's ancestors/siblings.

    `memo` caches (node, remaining-chain-length) -> bool across the whole run.
    The descendant and general sibling branches re-explore the entire ancestor
    / preceding-sibling axis at every chain step, so without caching a
    k-compound chain costs O(n * d^(k-1)); an ordinary 2000-row table with a
    3-compound `~` chain already took ~90s. The verdict depends only on the
    node and how much of the chain is left to resolve, never on the path taken
    to reach it, so caching is result-preserving and brings the cost back to
    O(n * d * k).
    """
    if memo is None:
        memo = {}
    key = (id(node), len(chain))
    cached = memo.get(key)
    if cached is not None:
        return cached

    result = False
    if matches_compound(node, chain[-1][1]):
        if len(chain) == 1:
            result = True
        else:
            combinator = chain[-1][0]
            rest = chain[:-1]

            if combinator == '>':
                parent = node.parent
                result = (
                    parent is not None
                    and parent.tag != '#document'
                    and matches_chain(parent, rest, memo)
                )

            elif combinator == ' ':
                ancestor = node.parent
                while ancestor is not None and ancestor.tag != '#document':
                    if matches_chain(ancestor, rest, memo):
                        result = True
                        break
                    ancestor = ancestor.parent

            elif combinator == '+':
                if node.sibling_index > 0:
                    prev = node.parent.children[node.sibling_index - 1]
                    result = matches_chain(prev, rest, memo)

            elif combinator == '~':
                siblings = node.parent.children
                for i in range(node.sibling_index - 1, -1, -1):
                    if matches_chain(siblings[i], rest, memo):
                        result = True
                        break

            else:
                raise ValueError("unknown combinator: {!r}".format(combinator))

    memo[key] = result
    return result


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

    builder = TreeBuilder()
    try:
        builder.feed(html_input)
        builder.close()
    except Exception as e:
        print("html parse error: {}".format(e), file=sys.stderr)
        sys.exit(2)

    memo = {}
    count = sum(1 for node in builder.nodes if matches_chain(node, parsed, memo))

    print(count)
    sys.exit(0)


if __name__ == "__main__":
    main()
