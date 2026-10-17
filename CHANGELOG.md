# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- The "in table" character rule asks for its current node, as the spec words it: a character token
  goes to "in table text" when the current node is a `table`, `tbody`, `template`, `tfoot`, `thead`
  or `tr` element, and is otherwise handled by the "anything else" arm — parse error, foster
  parenting, the in-body rules (parsing.html#parsing-main-intable). The pinned base took the first
  route for every character token in the mode, which split a run wherever a token the parser
  ignored followed it (`<table><r>x</h>e` read `["x", "e"]` instead of `["xe"]`) and never recorded
  the parse error the other route asks for. On `nokogiri-compat` as patch 0012: a Rails port's tree
  comparison against the reference's own parser read 0 divergences on a scope path with it and 1
  without, and the fix is the spec's rather than the fork's, so it can move to `main` unchanged.

### Fixed

- A duplicate attribute name is reset out of the tag buffer where it is dropped, not inside the
  error it records: `add_duplicate_attr_error` returned before that reset when no error could be
  recorded, which is what a capped error list — `max_errors: 0` — produces, and the dropped name
  then stayed in the buffer for the next attribute name to be appended to (`<p a=1 a b=2>` read
  `{"ab", "2"}` instead of `{"b", "2"}`). Patch 0015 moves the reset to the call site, where
  Nokogiri's fork has it. Six of a Rails port's 1,058 stored bodies read differently before it,
  and its reference parser agrees with the trees after it.

### Changed

- On the `nokogiri-compat` branch only: what the 0.3.0 entry above moved — an element written
  inside a `<select>`, and an end tag written inside one — moves back, because Nokogiri's fork of
  gumbo still has the "in select" insertion mode the spec removed (whatwg/html#10548). A Rails port
  that has to reach Nokogiri's trees needs that mode, it is a whole mode rather than a knob, and
  `NOKOGIRI-COMPAT.md` is the branch's own note, including what it costs `make check-parity`.
- Also on that branch: text foster parented out of a table is a node of its own again, the reverse
  of the merge upstream 41a0f3e added, for the same reason — Nokogiri's fork predates it. Rendering
  does not show the difference, a tree comparison does, and so does anything acting per text node.

## [0.3.0] - 2026-10-16

### Added

- `Gumbo.materialize/2` takes `detail: :tree`: the tree without source bookkeeping, with the tag
  name on every element — the name as written, so a custom element is never left nameless — and
  attributes as an ordered list of `{name, value}`, with any prefix the parser split off composed
  back on (`xlink:href`, `xmlns:xlink`). Text-like, comment and processing-instruction nodes are
  the ones `detail: :content` returns.
- A processing instruction carries `target` and `data` — the two parts the spec gives that payload,
  and the pair a browser reports — in both the `:full` and `:content` shapes, through
  `Gumbo.Node.target/1` and `Gumbo.Node.data/1`. `text` still carries the one string the C library
  stores.
- The README's "Differences from Nokogiri's gumbo" section: what each side vendors, and the shapes
  measured to differ — processing instructions, template handling, and the two option defaults that
  differ.

### Changed

- `</p>` inside a `<select>` closes the empty `p` the parser inserts there, not the `p` around the
  `select`, so the text after it stays where it was written. The spec removed the "in select"
  insertion mode and lists `select` among the types that bound a scope query (whatwg/html#10548); a
  `<source>` inside a `<select>` was already kept, which that change makes correct rather than a
  divergence.

### Fixed

- An end tag inside a `<select>` that names `applet`, `marquee` or `object` no longer reaches past
  the select and takes it and everything under it: those end tags ask for the element in scope, and
  the parser asked in table scope, whose boundaries are only `html`, `table` and `template`
  ([#9](https://github.com/gilbertwong96/gumbo/issues/9)).
- An end tag inside a `<select>` that names no open element — `</option>` is the common one — no
  longer walks past the select and closes what sits above it, which moved everything written after
  that end tag out of the select
  ([#10](https://github.com/gilbertwong96/gumbo/issues/10), [#11](https://github.com/gilbertwong96/gumbo/issues/11)).
- Control characters and noncharacters in the input stream are kept in the tree, as the spec and
  the reference keep them, instead of coming back as U+FFFD. They are reported for what they are —
  `:control_character_in_input_stream` and `:noncharacter_in_input_stream` — and their `codepoint/1`
  is the code point the decoder read, not the bytes under the cursor. A byte sequence that is not
  valid UTF-8 is still replaced.
- An unknown end tag that names no open element no longer closes the first element with an unknown
  name it meets, which moved the text after it out of that element: `</fidiv>` no longer closes an
  open `<f&#igure>`. Reported as #3, on the pasted custom-element markup a chat application receives.
- `:max_attributes` counts the attribute names read for one element, a repeated name included, so an
  element at the limit with one repeated name is refused with `{:error, :too_many_attributes}`, the
  way the reference refuses it; and it is enforced while a start tag is still being read, so the name
  the tokenizer has reached counts even when end of input abandons the tag. Either way a document
  past the bound is refused instead of answered with a tree. Reported as #8.

## [0.2.0] - 2026-10-15

### Changed

- `detail: :content` carries `:tag_name` for an element whose `tag` is `:unknown` — a custom
  element such as `<my-tag>`, or an SVG tag the enum does not carry such as `clipPath` — so the name
  as written survives in that shape. Elements gumbo can name are unchanged: their tag atom is that
  same name, and they carry no `:tag_name`.

## [0.1.0] - 2026-10-14

First release. `gumbo` is a faithful binding to the C library of the same name, and the surface is
deliberately the library's own: what gumbo can say about a document is reachable from Elixir, and
nothing is layered on top of it.

Add it with `{:gumbo, "~> 0.1.0"}`. Precompiled NIFs are published for `x86_64-linux-gnu`,
`aarch64-linux-gnu`, `x86_64-apple-darwin`, `aarch64-apple-darwin` and `x86_64-windows`; any other
platform compiles from the sources carried in the package. Each archive is built on the platform it
is for and that platform's suite passes before it is packaged — the README has the table and how to
read it. The vendored parser stays byte-identical to its 0.14.1 pin: the six patches below are
applied to a copy.

### Added

- `Gumbo.parse/2` and `Gumbo.parse!/2` — parse HTML into an opaque
  `Gumbo.Output` handle backed by a NIF resource; the tree stays native and
  is walked lazily through `Gumbo.Node` accessors.
- `Gumbo.parse_fragment/3` and `Gumbo.parse_fragment!/3` — fragment parsing
  with a context tag and namespace, with the checked/unchecked conflict
  contract (`parse_fragment/3` checks, `parse/2` does not).
- `Gumbo.materialize/2` — convert a handle, node, list of nodes, or `nil`
  into plain nested Elixir data in a single iterative NIF walk, at
  `detail: :full` or `detail: :content`.
- `Gumbo.Output` — the opaque handle: `document/1`, `root/1`, `errors/1`,
  `input/1`, `options/1`, `node_count/1`, `fragment_nodes/1`.
- `Gumbo.Node` — accessors for every `GumboNode` field, including
  `tag_name/1` for unknown tags and `descendants/1` as an iterative walk.
- `Gumbo.Attribute` — accessors for every `GumboAttribute` field.
- `Gumbo.Error` — gumbo's parse errors as structured data, plus
  `message/1` and `caret/1` rendered by gumbo itself.
- `Gumbo.Position`, `Gumbo.Options`, `Gumbo.Tag`, `Gumbo.Types` — the plain
  data structures, the standalone tag API, and the enum type unions.
- Scheduler-aware dispatch: parses of 20 480 bytes or more and
  materializations of 20 480 nodes or more run on a dirty CPU scheduler,
  with a `dirty: :auto | true | false` override.
- A 13-shape small-stack regression matrix (`mix test.small_stack`) and a
  teardown-contract probe (`make check-teardown`).
- `:max_tree_depth` — the depth ceiling Nokogiri's gumbo exposes, for callers
  pinned to that reference. It counts the parser's open elements, so a fragment's
  implied `<html>` is one of them and 401 means 400 levels of content; it defaults
  to `-1` for no limit, because this library's stack budget is what bounds depth
  here, and a document past it is refused with `{:error, :tree_too_deep}` rather
  than handed back truncated.

### Changed

- **A failed extraction inside the NIF can no longer reach a caller as a value.** The extractors
  answered a term for both outcomes, so an allocation failure was a value a detail map could not tell
  from a term, and a caller read it back as the integer `42`. They answer a status with the term written
  through an out parameter now, and every entry point turns a failure into the same `badarg` the VM
  surfaces as `ArgumentError`. Outside those paths — which are OOM-only — nothing a caller sees has changed.
- No C in this library reports a failure with a term any more: a failure is a status the caller turns
  into a `badarg`, so it cannot be stored in a map or a list and read back as a number later.
- `mix ci` also runs `make check-failure-returns`, which fails if a failure value is ever stored rather
  than returned, or if a numeric literal is used where a term is expected.
- `cert-err33-c` is on for the C that ships: it is what found the disregarded returns above. `mix ci`
  also runs the fault-injection sweep, `mix test.fault_paths`, as a step of its own — it arms an
  extraction to fail by index and requires every one of them to reach the caller.

- `:max_errors` now defaults to `100` instead of gumbo's `-1`, which disables
  the cap. gumbo records one error per unclosed element at EOF and each of those
  carries a copy of the open-element tag stack, so an N-deep unclosed document
  cost N² pointers: a 100 KB document allocated 3.2 GB and 200 KB would have taken
  ~12.8 GB, reachable from input 80x smaller than the accepted input limit. A later
  patch caps what one error keeps at its innermost 32 open-element tags, so a capped
  run holds at most `cap * 32` entries rather than `cap * depth`.
  `max_errors: -1` still returns every error.

- **`materialize/2`'s error maps no longer carry `caret`.** gumbo renders a caret
  as the whole source line with column padding, so one caret costs O(line length),
  and materialize builds one map per error: measured, 40 002 errors on a 420 KB
  single-line document cost 426 KB of fresh binaries per 1 000 errors, a 12.7 s
  call, and a ~17 GB term. `Gumbo.Error.caret/1` still renders it for any live
  error, one at a time and bounded by a single line, and `Gumbo.Error.details/1`
  still returns all ten fields for a single error. A materialized error map is that
  map minus `:caret`.

  Together these made `mix test.small_stack` 6.7x faster (38.1 s -> 5.7 s): its
  three "does not nest" rows produce 40 002 errors each on a one-line document, and
  the suite materializes every error.

- The build now applies
  `c_src/patches/gumbo-parser/0001-make-destroy_node-iterative.patch` to a copy of
  the vendored sources under `priv/obj`, leaving the submodule byte-identical to
  its 0.14.1 pin. The patch is upstream's own fix for the recursive teardown
  (google/gumbo-parser#387, which Nokogiri ships): `destroy_node` no longer
  recurses, so a deeply nested document is freed safely instead of by luck of
  the stack, and the `<frameset>` path that used to die inside the parse now
  survives at any depth. `mix ci` runs `make check-patch`, so a patch that stops
  applying to a new pin is a red build rather than a build that quietly drops
  the fix; `make check-clean-build` builds a throwaway copy of the build inputs
  from an empty object directory, so the fresh-clone path cannot rot either.

- The destructor no longer runs a disarming pass of its own: `c_src/gumbo_teardown.c`
  existed to make gumbo's recursive teardown safe, and the patch above removes the
  recursion instead. The probe that shared it is retargeted at
  `gumbo_destroy_output`, and its crash canary is now a hard gate rather than an
  informational note.

- The parse is no longer quadratic in nesting depth, and neither is the error
  vector. Two more patches in `c_src/patches/gumbo-parser` answer the two per-tag
  queries over the stack of open elements in O(1) instead of by walking it, and cap
  what one error keeps of that stack at its innermost 32 entries. Measured:
  `<div>` x 40 000 parses in 6.7 ms instead of 1 223 ms and `<b>` x 40 000 in 6.3 ms
  instead of 287 ms, so every shape in the matrix is linear; a 100 KB unclosed
  document allocates 9.3 MB instead of 3.2 GB, and 20 000 unmatched `</p>` at depth
  20 000 allocates 18.7 MB instead of 6.4 GB. Tree construction is unchanged —
  `make check-parity` asserts that over a seeded corpus against the pinned sources —
  but an error deep in a document now reports at most 32 open-element tags.

- `mix ci` grew a sanitizer gate: the same differential harness, built against the
  patched sources with AddressSanitizer and UndefinedBehaviorSanitizer, over the
  corpus and ten adversarial shapes. It is the only net there is for a memory-safety
  bug inside gumbo itself, and it found one in the fourth patch as soon as it ran —
  the new attribute index was read as uninitialised memory on the first tag of every
  parse, which was invisible to builds that happened to get zeroed pages.

- The toolchain is declared rather than inherited: `.mise.toml` pins erlang, elixir and
  clang, and points at the Homebrew LLVM prefixes because Homebrew's llvm is keg-only and
  ships `clang-format` and `clang-tidy` off PATH. The C gates ask PATH first and mise
  second, so they behave the same in an activated shell and a plain one. `mise trust`
  once, then `mise install`.

- The C now also runs under `clang-tidy`, with the checks in `.clang-tidy` and the vendored
  sources and ERTS headers passed as system headers so that findings are attributed to this
  library's own code — the first run's 125 reports were all inside `gumbo.h`. Twelve
  findings fixed (signed literals in shifts and bitwise operations, and four size constants
  multiplied as `unsigned int`), five resolved on their merits, and the rest excluded with
  their counts and reasons written down.

- The C now gets the treatment the Elixir has had all along: `mix ci` runs
  `clang-format` against a checked-in `.clang-format` (Google's style, because that is
  what gumbo is written in, so a patch and the file it patches read the same way) and
  compiles this library's own C with warnings as errors and fifteen warning classes,
  including the implicit sign conversions the ERTS API invites. Our files only: the
  vendored copy is pinned and reformatting it would break every patch. Between them the
  two gates found five things, all fixed — a function that should have been static, an
  `int` where an enum bit was meant, a shell glob inside a block comment, a format string
  forwarded without an attribute saying so, and hand-aligned comments the checker would
  not accept.

- `mix ci` also runs `clang --analyze` over this library's own C, which is the newest
  and least exercised code here and the only place AddressSanitizer cannot look:
  instrumenting the NIF would mean instrumenting the VM. Its canary file is a deliberate
  use-after-free and the gate requires the analyzer to report it, because a gate that
  cannot fail proves nothing — which took two failed attempts to verify, recorded in the
  ledger, including the finding that the analyzer cannot model `enif_alloc`/`enif_free` as
  a pair.

- A stack budget guard, so a recursion nobody has measured is refused rather than
  fatal: the parse is told how much stack it has (this library already measures the
  thread for the sized-thread decision) and stops before it runs out, reporting
  `{:error, :too_deep}`. It is a backstop under the arithmetic, not a limit a caller
  has to think about, and `make check-stack-guard` is what holds it to firing when it
  should — including the measurement that no document makes the C stack grow with its
  nesting depth any more.

### Notes

**Attribute counts, measured and then fixed, 2026-10-13.** An element's attributes used
to cost the square of their count, because `finish_attribute_name` looked for a
duplicate name by scanning the attributes already collected: 80 000 distinct names
(0.7 MB of input) took 13.6 s, and the input cap allows about 2.4 million. They are
indexed now (`c_src/patches/gumbo-parser/0004-max-attributes.patch`, a per-tag FNV-1a
hash into buckets that double as the attributes outnumber them), so the same input
is linear: 80 000 in 21 ms, 800 000 in 306 ms. The same patch adds
`:max_attributes`, 1024 by default — the lever Nokogiri's gumbo exposes under the
same name — and exceeding it returns `{:error, :too_many_attributes}` rather than
dropping attributes, so a caller never receives a tree that differs from what the
pinned parser builds.

gumbo-parser 0.14.1's own `gumbo_destroy_output` frees the tree with
`destroy_node`, which recurses once per tree level, and 0.14.1 has no
maximum nesting depth. Two call sites reach that recursion.

The destructor's: a ~7 000-deep document segfaults the VM when the handle is
garbage collected — a 320 KB stack holds 320 KiB / 48 = 6 826 levels of the
48-byte frame.

And `handle_in_body`'s, which runs *inside* the parse: a deeply nested document
followed by a `<frameset>` start tag makes gumbo destroy the body subtree at
input depth mid-parse. `<!doctype html>` followed by 8 000 `<div>`s and a
`<frameset>` — a 40 KB document — killed the VM inside `Gumbo.parse/1`, before
the parse returned.

Both are now fixed at the source rather than worked around: the build applies
`c_src/patches/gumbo-parser/0001-make-destroy_node-iterative.patch`, upstream's own
fix from google/gumbo-parser#387, to a **copy** of the pinned sources, so
`destroy_node` no longer recurses and the submodule stays byte-identical to its
0.14.1 pin. The same document that died at 8 000 levels now survives 50 000 on the
same stack.

The parse still runs on a C stack sized from the input's length
(`c_src/gumbo_parse_stack.c`), because the patch fixes the recursions that are
known and not the class: depth is bounded by input — a nesting level costs at least
a three-byte start tag, and the worst frame in that recursion measures 64 bytes —
so documents small enough for the calling thread's own stack parse as before and
larger ones run on a thread of the size the input needs. Inputs over 16 MiB are
refused with `{:error, :input_too_large}`, since that is where the sized stack stops
being a reasonable reservation. `make check-teardown` holds the teardown to both
properties that matter — the allocator balance is exactly zero, and a 20 000-level
tree survives a 320 KB stack — and `make check-clean-build` builds from an empty
object directory, which is what a fresh clone or a hex consumer does.

[Unreleased]: https://github.com/gilbertwong96/gumbo/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/gilbertwong96/gumbo/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/gilbertwong96/gumbo/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gilbertwong96/gumbo/releases/tag/v0.1.0
