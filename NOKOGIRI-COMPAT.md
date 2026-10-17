# Nokogiri compatibility mode (branch `nokogiri-compat`)

This branch makes the binding reproduce **Nokogiri's gumbo** — the parser the Rails
reference uses — for the shapes where the two Generations disagree, so a Rails port can
reach byte parity without touching `main`. `main` keeps the current spec; this branch is
the legacy side of the same library.

## Why a branch, not an option

The divergence is not a knob, it is a whole insertion mode: whatwg/html#10548 removed
the **"in select"** insertion mode, and 0.14.1 follows that removal
(`GUMBO_INSERTION_MODE_IN_SELECT` is gone from `src/insertion_mode.h`). Reproducing
Nokogiri means re-adding the mode, which changes tree construction — fine on a branch, not
fine as `main`'s default. It also reaches outside the vendored copy: the mode's two enum
members are part of the enum a parser error reports, so `c_src/gumbo_atoms.c`'s member
list, its count literal and `lib/gumbo/types.ex` move with it. None of those three files is
part of the copy the patch series patches, so this is a branch's worth of change rather
than one file's.

## What actually differs (measured)

`once-campfire-elixir` keeps a 1,058-case stored rich-text corpus whose expected output comes
from the pinned Rails reference. With `main` it reports **58 differences in 43 cases**
(presentation 4, plain text 41, mentions 13); every one of them is inside a `<select>`.

Three behaviours exist for the same input, `<p><select>https://example.com/&lt;b</p>/p>`:

| parser | tree |
|---|---|
| Nokogiri's gumbo (old spec, **this branch's target**) | `</p>` is **ignored**, text stays one node: `[{"p", [], [{"select", [], ["https://example.com/<b/p>"]}]}]` |
| 0.14.1's pinned base, unpatched | `</p>` closes the **outer** `p`, the trailing text escapes as a sibling — no version of the spec produces this |
| `main` (patch 0007 + 0.14.1) | an empty `p` is inserted **inside** the select and closed: Chrome's behaviour |

So "revert patch 0007" is **not** enough: the target needs the removed mode itself. This
branch produces the first row; the port's corpus is what holds it to it.

## Reference implementation (the rules, not invented here)

The mode is upstream's own code, restored: gumbo's history carries the commit that removed
it — `7811944` ("fix parser to comply with most recent spec changes to `<select>` logic",
2025-09-17, whatwg/html#10557) — and `git show 7811944^:src/parser.c` is the source of every
line 0012 puts back: `handle_in_select`, `handle_in_select_in_table`,
`has_an_element_in_select_scope`, `close_current_select`, the `select` case of
`get_appropriate_insertion_mode`, and the in-body `<select>` start tag that switches into the
mode. The three in-body rules that commit wrote in the mode's place are removed again,
because the mode answers for a select itself.

The other difference whose mechanism is known is text-node splitting. Upstream `41a0f3e`
("spec: fix foster parented text not being merged into preceding text node", 2026-08-15) made a
flushed text run merge into the text node before the adjusted insertion location; Nokogiri's fork
predates it and inserts the run as it stands. Patch 0013 is the reverse of that commit, and the
shapes it moves are upstream's own: `41a0f3e^`'s `MisnestedTable2` expected three children where
the merged version expects two.

Both are worth reading next to the reference's sources here rather than in the abstract: the port
keeps them at `native/vendor/gumbo/`, unmodified, with the gem's SHA in `PROVENANCE.md`, and its
`Campfire.HtmlParserReference` runs them.

Two independent confirmations that this generation is the one the reference runs:

* The Rust port vendors html5ever 0.35 precisely because *"later releases also adopt the
  customizable-`<select>` parsing rules, which Gumbo doesn't, so upgrading isn't an option"*
  (`crates/richtext/vendor/html5ever/Cargo.toml`). Its `InSelect` arm
  (`src/tree_builder/rules.rs:1130`) and the table arm at `:1224`, with the entry conditions at
  `:692`, are the same rule list 7811944 removed — worth reading the diff beside them.
* The port's corpus: the tables the mode produces for its cases are the reference's output
  (0 differences, below).

## Where it goes, as built

`handle_html_content` is a one-line dispatch through a table indexed by the mode
(`kTokenHandlers[(unsigned int) _insertion_mode]`), so the mode is:

1. `src/insertion_mode.h` — two members back **between `IN_CELL` and `IN_TEMPLATE`**, where
   Nokogiri's gumbo has them. Their position is observable: a parser error reports
   `insertion_mode`, so the numbering is part of this binding's output.
2. `src/parser.c` — `handle_in_select()` and `handle_in_select_in_table()` back beside the
   other handlers, with their entries in `kTokenHandlers` in the same position.
3. `src/parser.c` — the in-body `<select>` start tag switches into the mode again, and the
   `<input>`, `<hr>`, `<option>`/`<optgroup>` rules 7811944 added are removed.
4. `src/parser.c` — `get_appropriate_insertion_mode` answers `IN_SELECT` for a `select` on
   the open-element stack, which is also what makes a fragment whose context element is a
   `select` start in the mode: the context stands in for the last open element.
5. `c_src/gumbo_atoms.c`, `c_src/gumbo_atoms.h`, `lib/gumbo/types.ex` — the member list and
   count literal that travel with the enum, on the branch rather than in the patch, because
   they are not part of the vendored copy.

## Delivering it the way this repo does

`c_src/patches/gumbo-parser/0012-legacy-in-select.exs` and `0013-legacy-text-merge.exs` are
generators like 0007's, so
`mix gumbo.patches` writes the patches, `make check-patch` keeps the series applicable, and
`make check-generators` keeps the pairs honest. `c_src/gumbo-parser` stays byte-identical to
its pin; `c_src/patches/README.md` carries the rows and why 0012 is cumulative.

It is the only cumulative patch whose diff is against a **patched** tree (it anchors a helper
after `has_an_element_in_table_scope`, whose body 0002 rewrote), so `BEHAVIOUR_PATCHES` cannot
list it and `make check-parity` compares its baseline against the shipped build per document:
a difference is allowed only in a document whose tree holds a `select`, and the check fails if
none moves. On this branch that is 454 of the 1,000 corpus documents — the mode applies to
every document with a select in it, not only to the shapes 0007, 0010 and 0011 repaired.
0013 has the opposite shape: its text is the pin's own, it applies to the pin on its own, and it
stands with 0007-0011 in `BEHAVIOUR_PATCHES`, whose bound the gate now states with a `table` in
the list — a table is the context a run has to be foster parented out of. That widened the
documents the pin alone may differ in from 167 to 232 of the 1,000.

## Acceptance gate

1. `once-campfire-elixir` with `{:gumbo, path: ...}` pointed at this worktree:
   `mix test test/richtext_corpus_test.exs` → **0 differences** (58 with `main`).
   `parity/results/richtext-corpus-differences.json` is `[]`.
2. This repository: `mix test` green, `mix format --check-formatted`, `mix credo --strict`.
3. `make check-patch`, `make check-generators`, `make check-parity`, `make check-c-format`,
   `make check-c-lint`, `make check-teardown`, `make check-sanitizers`.
4. The port's parse benchmark, to confirm the mode costs nothing on documents without a
   select — it is reached only through the dispatch table, and the tables it adds run only
   where a select is open. Measured over the port's 1,058 bodies, five passes each, min/mean
   microseconds per body: `main` 47.17/50.19, this branch 47.26/48.28 and 49.59/51.57 in two
   runs (the runs bracket each other, so the difference is noise).

5. A tree-level comparison against the reference's own parser rather than its rendered output:
   the port vendors Nokogiri 1.19.4's unmodified gumbo sources (`native/vendor/gumbo/`, gem SHA
   in its `PROVENANCE.md`) behind a fault-isolated fallback parser
   (`Campfire.HtmlParserReference`), which is the reference's tree builder with the reader's own
   `body` fragment context. Comparing that tree with this branch's over the 1,058 bodies with the
   port's own classifier (`var/classify_diffs.exs`), by category (bodies whose first divergence is
   of that kind):

   | category | `main` | 0012 | 0012 + 0013 |
   |---|---|---|---|
   | no surviving divergence | 938 | 992 | 1012 |
   | `scope` (a table, `li`, `ul`, `dl`, the select family) | 52 | 2 | 1 |
   | `other` (the tag-name and attribute shapes) | 39 | 39 | 27 |
   | `limit` (a parser limit on either side) | 16 | 16 | 16 |
   | `unicode` | 5 | 5 | 0 |
   | `bogus_comment` (the processing-instruction shapes) | 5 | 2 | 2 |
   | `template` | 3 | 2 | 0 |

   The two `scope` cases 0012 leaves are `fuzz 275` and `fuzz 343`, and they move to 0013: both
   are a foster-parented run, which is why merging text nodes on both sides in that same
   comparison made them — and `unicode` and `template` with them — read as no divergence at all.
   The one `scope` case left is `fuzz 33`, which `main` has too and which is not this branch's: its
   first divergence happens to sit under a table, and the difference itself is one of the
   documented ones. Nothing here is visible to the rendered corpus, which reads 0 either way —
   that is what `:rendered_only` above means.

## Status

Implemented on this branch, with 0012 and 0013 as described above. Evidence so far: the port's
1,058-case corpus reports no unresolved difference (`0` in
`parity/results/richtext-corpus-differences.json`, 92 raw-unequal rows that the normalized
comparison resolves), the gumbo suite is green (335 tests, 19 environment-tagged exclusions),
`mix format --check-formatted`, `mix credo --strict` and a warnings-as-errors compile pass, and
`check-patch`, `check-generators`, `check-parity`, `check-c-format`, `check-c-lint`,
`check-clean-build`, `check-teardown` and `check-sanitizers` all pass. Gates 4 and 5's numbers
are above. The mode's own shapes are held by `test/gumbo/select_in_select_test.exs`
(the mode's edges, including the two error states that would notice the enum moving),
`test/gumbo/select_scope_test.exs` (the corpus shapes where an end tag or an element's text is
at stake) and the six recorded trees in `test/gumbo/select_tree_construction_test.exs` (the
html5lib cases the mode moves away from upstream's expectations); 0013's by
`test/gumbo/foster_text_test.exs`, whose first two shapes are upstream's own from before the
merge it reverses.

What gate 5 leaves is 46 bodies and every one of them is one of the differences `main` has
too: the tag-name and attribute shapes, the parser limits, the processing-instruction shapes,
and one first divergence that happens to sit under a table. No shape whose mechanism is known is
open. The next thing to identify, if it is wanted, is the mechanism behind the `other` bucket —
none of those is a select shape or a text split, and each needs its own reading of the reference's
sources, which are on disk in the port.

Two things are not claimed. What the branch restores is `main`'s opposite, so a consumer that
wants one cannot use the other: the port depends on this branch. And the divergence is
documented against Nokogiri's sources and behavior rather than a Nokogiri *run* in this
repository: the port's own reference parser is the comparison, and its stored corpus is what the
rendered contract is held to.
