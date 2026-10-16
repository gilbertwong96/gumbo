# Nokogiri compatibility mode (branch `nokogiri-compat`)

This branch makes the binding reproduce **Nokogiri's gumbo** — the parser the Rails
reference uses — for the shapes where the two Generations disagree, so a Rails port can
reach byte parity without touching `main`. `main` keeps the current spec; this branch is
the legacy side of the same library.

## Why a branch, not an option

The divergence is not a knob, it is a whole insertion mode: whatwg/html#10548 removed
the **"in select"** insertion mode, and 0.14.1 follows that removal (`GUMBO_INSERTION_MODE_IN_SELECT`
is gone from `src/insertion_mode.h`). Reproducing Nokogiri means re-adding the mode, which
changes tree construction — fine on a branch, not fine as `main`'s default.

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

So "revert patch 0007" is **not** enough: the target needs the removed mode itself.

## Reference implementation (the rules, not invented here)

The Rust port vendors html5ever 0.35 precisely because *"later releases also adopt the
customizable-`<select>` parsing rules, which Gumbo doesn't, so upgrading isn't an option"*
(`crates/richtext/vendor/html5ever/Cargo.toml`). Its `InSelect` arm
(`src/tree_builder/rules.rs:1130`) is the rule list to mirror, and html5ever has the
matching `InSelectInTable` arm at `:1224` with the entry conditions at `:692`.

The arm, in short: characters and comments insert; `<html>` goes to in-body; `<option>`
pops a current `option` then inserts; `<optgroup>` pops a current `option` and `optgroup`
then inserts; `<hr>` pops both, inserts, pops; `</optgroup>`/`</option>` pop their own;
`<select>` (nested) and `</select>` **pop to the select** and reset the insertion mode;
`<input>`, `<keygen>` and `<textarea>` pop to the select, reset, and reprocess the token;
`<script>`/`<template>` go to in-head; EOF goes to in-body; **anything else is a parse
error and the token is ignored** — which is exactly the "the element is dropped and the
text merges" behaviour the corpus expects.

## Where it goes (confirmed against this tree)

`handle_html_content` (`src/parser.c:4133`) is a one-line dispatch through a table:

```c
return kTokenHandlers[(unsigned int) parser->_parser_state->_insertion_mode](parser, token);
```

so a mode is three edits plus two hooks:

1. `src/insertion_mode.h` — append `GUMBO_INSERTION_MODE_IN_SELECT` and
   `GUMBO_INSERTION_MODE_IN_SELECT_IN_TABLE` to the enum (**append**, so the existing
   `kTokenHandlers` indices keep their meaning).
2. `src/parser.c` — add `handle_in_select()` (and `handle_in_select_in_table()`) next to the
   other handlers, with the arm above; append both to `kTokenHandlers` in the same order.
3. `src/parser.c:3288` — the in-body `<select>` start tag: `reconstruct_active_formatting_elements`,
   insert the element, `set_frameset_not_ok`, then `set_insertion_mode(IN_SELECT)`; when the
   current mode is `IN_TABLE`/`IN_CAPTION`/`IN_ROW`/`IN_CELL`, use `IN_SELECT_IN_TABLE`
   (html5ever `rules.rs:692`).
4. `src/parser.c:612` — `get_appropriate_insertion_mode`: a `select` on the open-element
   stack resets to `IN_SELECT` (the old spec's clause; `main` deliberately has no such case).
5. Fragment parsing with `fragment_context = select`: start in `IN_SELECT`
   (`fragment_parser_init` sets the mode; `main` has the related check at `parser.c:3222`).

## Delivering it the way this repo does

Everything above is a **patch**, not a submodule edit: write
`c_src/patches/gumbo-parser/0012-legacy-in-select.exs` (a generator: `%{priors:, header:,
substitutions:}` with the C as heredocs, as 0007 does), run `mix gumbo.patches` to write the
`.patch`, and let `make check-patch` keep the pair honest. `c_src/gumbo-parser` stays
byte-identical to its pin. A test belongs next to patch 0007's, e.g.
`test/gumbo/select_in_select_test.exs`, holding the three behaviours above.

## Acceptance gate

1. Point `once-campfire-elixir`'s `{:gumbo, path: ...}` at this worktree and run its corpus:
   `mix test test/richtext_corpus_test.exs` → **0 differences** (58 with `main`).
2. `mix test` and `mix credo --strict` in this repository.
3. `make check-patch`, `make check-parity`, `make check-teardown` — the patch series must
   still apply and the pinned/patched comparisons must still hold for every document the
   parity corpus generates (patch 0007 set that precedent; this one narrows it further, so
   the exclusions need to be stated in the patch header as it does).
4. Re-run the port's load benchmark once, to confirm the legacy mode does not cost throughput
   (the mode only runs for documents that contain a `<select>`).

## Status

Branch created from `main` (`1a991cd`, 0.3.0) plus this note. The mode itself is not
implemented yet; the change list above is the work, with html5ever 0.35's arms as the
reference and the port's corpus as the gate.
