# Code style

RuboCop (Standard's rules plus every rubocop-performance cop) settles the layout. This page covers what it can't:
how we name, cut and comment code. Upstream code copied verbatim keeps its own style.

## Keep it simple

The best code is the code you don't write. Stop at the first rung that holds: not needed, don't write it; the
standard library does it; Rails or an installed dependency does it; one line; only then, the minimum that works.
Input validation at the gem's boundary, data loss and security are never cut.

## Naming

- Spell identifiers in full. Blocks name their parameter; `_1` only in a one-expression block where a name adds
  nothing (no bare `it` while Ruby 3.3 is supported).
- In `rescue`, the variable is `exception`, never `e`.
- A hash keyed by X is `<what>_by_<key>` (`width_by_glyph`, `count_by_state`).
- Predicates end in `?` and read affirmatively (`bot?`, `current?`), boolean keywords too (`strict: true`).
- Constants carry their unit (`READ_TIMEOUT_SECONDS`, `MAX_GLYPHS_PER_RUN`).
- No placeholder names (`data`, `result`, `tmp`, `obj`): say what it holds.

## Methods

- Memoize with `@name`, not `@_name`.
- Keep a private method called once when its name says something its body doesn't; inline it when the name only
  paraphrases the body.
- New methods use `def`/`end`, not the endless form; existing ones stay until you touch them.
- Guard clauses for early exits, the modifier form for short conditions, but a balanced two-branch `if/else` stays.
- `map`, `filter_map`, `flat_map` first; an explicit loop when a chain needs nil-filtering or `.then` gymnastics.
- Don't abstract until the pattern repeats; reserve `yield` for genuine around-style wrappers.

## Comments

None by default: make the code say it. A comment earns its place only if removing it would make a careful reader
break the code. Three things a name cannot carry:

- **Outside vocabulary**: a spec's field order, a format's magic number, quoted verbatim from its source.
- **The reason for a number**: why 65,535 and not 65,536.
- **The trap that looks like a mistake**: a workaround for another library's bug, a rewrite we deliberately refused.

One line on the surprising line, four at most, dated when it may expire (`# 2026-11: Ruby 3.3's strscan lacks
peek_byte`). Never a header restating a name, narration of the next line, history of the change (that goes in the
commit), or commented-out code.

## Dead code

Leave code cleaner than you found it: remove dead code, unused files and guards against impossible states
(`nil` checks on values that can't be `nil`, bare `rescue`, unreachable fallbacks). A guard stays when the state is
reachable, or when it protects against corrupt input: say which on its line.
