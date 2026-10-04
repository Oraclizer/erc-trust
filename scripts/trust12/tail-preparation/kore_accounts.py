#!/usr/bin/env python3
"""Read the executing account and the concrete account code of a KEVM configuration in KORE text form.

A KEVM accounts cell is a KORE pattern built from `_AccountCellMap_`, `AccountCellMapItem` and
`<account>` applications. This module parses the whole pattern with a small iterative KORE parser
(no external tools, no regular expression over the pattern structure), finds every `<account>`
application, and reads its `<acctID>` and `<code>` children. A code cell is concrete only when it
is exactly `inj{SortBytes{}, SortAccountCode{}}(\\dv{SortBytes{}}("..."))`; every other form is
reported as symbolic. A frame identifier file (the `<id>` cell of the executing frame) is a single
`\\dv{SortInt{}}("...")` pattern.

The reader fails closed: an unknown token, an unknown string escape, a code point above 255 in a
byte string, a repeated account identifier or a map key that names another account raises
`KoreError`.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Union

ACCOUNT = "Lbl'-LT-'account'-GT-'"
ACCOUNT_ID = "Lbl'-LT-'acctID'-GT-'"
CODE = "Lbl'-LT-'code'-GT-'"
MAP_ITEM = "LblAccountCellMapItem"
MAP_ROOTS = {"Lbl'Unds'AccountCellMap'Unds'", MAP_ITEM, "Lbl'Stop'AccountCellMap"}
DOMAIN_VALUE = "\\dv"
INJECTION = "inj"
CODE_INJECTION_SORTS = ("SortBytes{}", "SortAccountCode{}")

_TOKEN = re.compile(r'"(?:[^"\\]|\\.)*"|\\?@?[A-Za-z][A-Za-z0-9\'\-]*|[{}(),:]|\s+|.', re.S)
_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "f": "\f", '"': '"', "\\": "\\"}


class KoreError(ValueError):
    """The text is not a pattern this reader accepts."""


@dataclass(frozen=True)
class Str:
    value: str


@dataclass(frozen=True)
class Var:
    name: str
    sort: str


@dataclass(frozen=True)
class App:
    name: str
    sorts: tuple[str, ...]
    args: tuple["Node", ...]


Node = Union[Str, Var, App]


def decode_string(literal: str) -> str:
    """Decode the body of a KORE string literal (without the quotes)."""
    out, index = [], 0
    while index < len(literal):
        char = literal[index]
        if char != "\\":
            out.append(char)
            index += 1
            continue
        if index + 1 >= len(literal):
            raise KoreError("dangling escape in a string literal")
        kind = literal[index + 1]
        if kind in _ESCAPES:
            out.append(_ESCAPES[kind])
            index += 2
            continue
        width = {"x": 2, "u": 4, "U": 8}.get(kind)
        digits = literal[index + 2:index + 2 + width] if width else ""
        if width is None or len(digits) != width or not all(c in "0123456789abcdefABCDEF" for c in digits):
            raise KoreError(f"unknown string escape \\{kind}")
        out.append(chr(int(digits, 16)))
        index += 2 + width
    return "".join(out)


def string_bytes(value: str) -> bytes:
    """A KORE byte string: every code point is one byte."""
    if any(ord(char) > 0xFF for char in value):
        raise KoreError("byte string contains a code point above 255")
    return value.encode("latin-1")


def _tokens(text: str) -> list[tuple[str, str]]:
    tokens = []
    for match in _TOKEN.finditer(text):
        value = match.group(0)
        first = value[0]
        if first.isspace():
            continue
        if first == '"':
            tokens.append(("str", value))
        elif first in "{}(),:":
            tokens.append(("sym", value))
        elif first.isalpha() or first in "\\@":
            if len(value) == 1 and first in "\\@":
                raise KoreError(f"unexpected character {first!r}")
            tokens.append(("id", value))
        else:
            raise KoreError(f"unexpected character {first!r}")
    return tokens


def _sort(tokens: list[tuple[str, str]], index: int) -> tuple[str, int]:
    kind, value = tokens[index]
    if kind != "id":
        raise KoreError("sort expected")
    index += 1
    if index < len(tokens) and tokens[index] == ("sym", "{"):
        inner, index = _sorts(tokens, index)
        return f"{value}{{{', '.join(inner)}}}", index
    return value, index


def _sorts(tokens: list[tuple[str, str]], index: int) -> tuple[tuple[str, ...], int]:
    if tokens[index] != ("sym", "{"):
        raise KoreError("sort parameters expected")
    index += 1
    found: list[str] = []
    if tokens[index] == ("sym", "}"):
        return (), index + 1
    while True:
        sort, index = _sort(tokens, index)
        found.append(sort)
        if tokens[index] == ("sym", ","):
            index += 1
        elif tokens[index] == ("sym", "}"):
            return tuple(found), index + 1
        else:
            raise KoreError("',' or '}' expected in sort parameters")


def parse(text: str) -> Node:
    """Parse one KORE pattern. Iterative, so the nesting depth of the pattern is not limited."""
    tokens = _tokens(text)
    if not tokens:
        raise KoreError("empty pattern")
    tokens.append(("end", ""))
    index = 0
    root: list[Node] = []
    stack: list[tuple[str, tuple[str, ...], list[Node]]] = []
    expect_value = True
    while True:
        if expect_value:
            kind, value = tokens[index]
            if kind == "str":
                node: Node = Str(decode_string(value[1:-1]))
                index += 1
            elif kind == "id":
                index += 1
                sorts: tuple[str, ...] = ()
                if tokens[index] == ("sym", "{"):
                    sorts, index = _sorts(tokens, index)
                if tokens[index] == ("sym", "("):
                    index += 1
                    if tokens[index] == ("sym", ")"):
                        node = App(value, sorts, ())
                        index += 1
                    else:
                        stack.append((value, sorts, []))
                        continue
                elif tokens[index] == ("sym", ":") and not sorts:
                    sort, index = _sort(tokens, index + 1)
                    node = Var(value, sort)
                else:
                    raise KoreError(f"application or variable expected after {value}")
            else:
                raise KoreError(f"pattern expected, found {value!r}")
            (stack[-1][2] if stack else root).append(node)
            expect_value = False
            continue
        if not stack:
            if tokens[index][0] != "end" or len(root) != 1:
                raise KoreError("text after the pattern")
            return root[0]
        kind, value = tokens[index]
        if (kind, value) == ("sym", ","):
            index += 1
            expect_value = True
        elif (kind, value) == ("sym", ")"):
            index += 1
            name, sorts, args = stack.pop()
            (stack[-1][2] if stack else root).append(App(name, sorts, tuple(args)))
        else:
            raise KoreError(f"',' or ')' expected, found {value!r}")


def _walk(node: Node):
    pending = [node]
    while pending:
        current = pending.pop()
        yield current
        if isinstance(current, App):
            pending.extend(reversed(current.args))


def _int_value(node: Node) -> int:
    if (isinstance(node, App) and node.name == DOMAIN_VALUE and node.sorts == ("SortInt{}",)
            and len(node.args) == 1 and isinstance(node.args[0], Str)):
        text = node.args[0].value
        if re.fullmatch(r"-?[0-9]+", text):
            return int(text)
    raise KoreError("concrete integer expected")


def _child(account: App, name: str) -> App:
    matches = [arg for arg in account.args if isinstance(arg, App) and arg.name == name]
    if len(matches) != 1 or len(matches[0].args) != 1:
        raise KoreError(f"account has {len(matches)} {name} cells")
    return matches[0]


def _code(cell: App) -> bytes | None:
    value = cell.args[0]
    if (isinstance(value, App) and value.name == INJECTION and value.sorts == CODE_INJECTION_SORTS
            and len(value.args) == 1):
        inner = value.args[0]
        if (isinstance(inner, App) and inner.name == DOMAIN_VALUE and inner.sorts == ("SortBytes{}",)
                and len(inner.args) == 1 and isinstance(inner.args[0], Str)):
            return string_bytes(inner.args[0].value)
    return None


@dataclass(frozen=True)
class Account:
    account: int
    code: bytes | None

    @property
    def concrete(self) -> bool:
        return self.code is not None


def accounts(text: str) -> dict[int, Account]:
    """Every account of an accounts cell, keyed by account identifier."""
    tree = parse(text)
    if not (isinstance(tree, App) and tree.name in MAP_ROOTS):
        raise KoreError("the pattern is not an accounts cell")
    found: dict[int, Account] = {}
    for node in _walk(tree):
        if not isinstance(node, App):
            continue
        if node.name == MAP_ITEM:
            if len(node.args) != 2 or not isinstance(node.args[0], App) or node.args[0].name != ACCOUNT_ID:
                raise KoreError("malformed account map item")
            key = _int_value(node.args[0].args[0])
            value = node.args[1]
            if not (isinstance(value, App) and value.name == ACCOUNT):
                raise KoreError("account map item without an account")
            if _int_value(_child(value, ACCOUNT_ID).args[0]) != key:
                raise KoreError(f"account map key {key} names another account")
        elif node.name == ACCOUNT:
            identifier = _int_value(_child(node, ACCOUNT_ID).args[0])
            if identifier in found:
                raise KoreError(f"account {identifier} repeated")
            found[identifier] = Account(identifier, _code(_child(node, CODE)))
    return found


def frame_account(text: str) -> int:
    """The account identifier of a frame identifier cell."""
    return _int_value(parse(text))
