# Gumbo

[![CI](https://github.com/gilbertwong96/gumbo/actions/workflows/ci.yml/badge.svg)](https://github.com/gilbertwong96/gumbo/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/gilbertwong96/gumbo/graph/badge.svg)](https://codecov.io/gh/gilbertwong96/gumbo)
[![Elixir](https://img.shields.io/badge/elixir-1.20+-purple.svg)](https://elixir-lang.org)
[![OTP](https://img.shields.io/badge/otp-27_%7C_29-blue.svg)](https://github.com/gilbertwong96/gumbo/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

An Elixir binding to [gumbo-parser 0.14.1](https://codeberg.org/gumbo-parser/gumbo-parser/src/tag/0.14.1),
Google's C99 HTML5 parser.

Gumbo is a **faithful binding**, not an opinionated HTML library. Everything
gumbo can tell you about a document is reachable from Elixir: attribute
namespaces, parse flags, source positions, original source text, the
quirks-mode verdict, and gumbo's own parse errors. If you read `gumbo.h` and
then these docs, the mapping is total. Query layers (CSS selectors,
traversal helpers beyond the accessors) belong in a library on top of this
one.

## Installation

Add `gumbo` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:gumbo, "~> 0.2.0"}
  ]
end
```

### Precompiled binaries

The NIF is precompiled for these targets, so most installations never run a C compiler. Each
archive is built on the platform it is for and the test suite passes there before it is packaged:

| Target | Built and tested on |
| --- | --- |
| `x86_64-linux-gnu` | `ubuntu-24.04` |
| `aarch64-linux-gnu` | `ubuntu-24.04-arm` |
| `x86_64-apple-darwin` |  `macos-15-intel` |
| `aarch64-apple-darwin` | `macos-15` |
| `x86_64-windows` | `windows-2025` |

`elixir_make` downloads the archive for your host from the GitHub release of the version you are
installing and verifies it against the `checksum.exs` in the package. When no archive matches, it
compiles from source instead — which is why the package also carries the pinned parser's sources and
the patch series applied to them.

The Linux archives are built against glibc 2.39 (Ubuntu 24.04), so an older distribution compiles
from source rather than downloading a binary it cannot load. If that matters to you, the release
workflow is one runner label away from a wider floor.

Building requires only a C compiler and Erlang — gumbo-parser is vendored in
the package, so Hex consumers need no git and no separate download.

## Quick start

There are two paths, and both come from one parse. The **lazy path** returns
an opaque handle: the tree stays native, and walking it costs one NIF call
per step.

```elixir
{:ok, output} = Gumbo.parse(~s(<p class="intro">Hello, <em>world</em>!</p>))

nodes = output |> Gumbo.Output.root() |> Gumbo.Node.descendants()
#=> [%Gumbo.Node{}, ...]  # html, head, body, p, "Hello, ", em, "world", "!"

p = Enum.find(nodes, &(Gumbo.Node.tag_name(&1) == "p"))

Gumbo.Node.tag_name(p)                              #=> "p"
Gumbo.Node.attribute_map(p)                         #=> %{"class" => "intro"}
Gumbo.Node.text(Enum.at(Gumbo.Node.children(p), 0)) #=> "Hello, "
```

The **eager path** converts a handle, a node, a list of nodes, or `nil` into
plain nested Elixir data in a single NIF call:

```elixir
{:ok, output} = Gumbo.parse("<!doctype html><p>Hello, <em>world</em>!</p>")

Gumbo.materialize(output)
#=> %{
#     document: %{type: :document, has_doctype: true, quirks_mode: :no_quirks, ...},
#     root: %{type: :element, tag: :html, children: [...]},
#     errors: []
#   }

Gumbo.materialize(output, detail: :content)[:root][:children]
#=> [
#     %{type: :element, tag: :head, attributes: %{}, children: [], namespace: :html},
#     %{type: :element, tag: :body, ...}
#   ]

Gumbo.materialize(output, detail: :tree)[:root][:children]
#=> [
#     %{type: :element, tag_name: "head", attributes: [], children: []},
#     %{type: :element, tag_name: "body", ...}
#   ]
```

The three levels differ only in what they keep:

- `detail: :full` (the default) — every gumbo field.
- `detail: :tree` — the tree a caller *processes* rather than queries: the name
  as written on every element, and attributes as an ordered list of
  `{name, value}`, with the prefix the parser split off composed back on
  (`xlink:href`, not `href` plus a namespace). Text-like, comment and
  processing-instruction nodes are the `:content` ones.
- `detail: :content` — a usable tree without the source bookkeeping, with
  attributes as a map.

An element whose tag gumbo cannot name — `tag: :unknown`, which is a custom
element and also an SVG tag like `clipPath` — carries `tag_name` as well, so
the name as written survives in this shape. Every other element is named by
its atom, which is that same name, and does not repeat it.

`tag` is the enum gumbo resolved, `:unknown` where it resolved none (the one
value `gumbo_normalized_tagname/1` has no name for), and `tag_name` is the name
as written. `:tree` carries that name on every element, so a caller processing
a tree never has to tell the two apart.

`materialize/2`'s `:full` values agree with the lazy accessors — they are
built by the same C extractors — under the materialized shape's own key
names (`:start_position` for `position/1`, `:name` for `doctype_name/1`).

Parsing a fragment works the same way, but note what the root is:

```elixir
{:ok, output} = Gumbo.parse_fragment("<circle/>", :svg, fragment_namespace: :svg)

Gumbo.Output.fragment_nodes(output)
#=> [%Gumbo.Node{...}]  # the <circle/> element
```

Fragment parsing roots at gumbo's parser-inserted **implied `<html>`
element**, not the context element — the context element lives in gumbo's
internal parser state and never appears in the tree. `Gumbo.Output.root/1`
is that implied `<html>`; `Gumbo.Output.fragment_nodes/1` is its children,
which is what callers almost always want. `Gumbo.parse_fragment/3` is the
*checked* path: it rejects a `fragment_namespace:` that disagrees with the
namespace the context tag implies (`:svg` implies `:svg`, `:math` implies
`:mathml`, everything else `:html`). `Gumbo.parse/2` with the same options
performs no such check — it is the unchecked escape hatch for combinations
the convenience function refuses.

## API

| Function | Returns | Notes |
|---|---|---|
| `Gumbo.parse/2`, `parse!/2` | `{:ok, Gumbo.Output.t()}` | parse HTML into an opaque handle |
| `Gumbo.parse_fragment/3`, `parse_fragment!/3` | `{:ok, Gumbo.Output.t()}` | fragment parse; roots at the implied `<html>` |
| `Gumbo.materialize/2` | nested maps | handle, node, list of nodes, or `nil` → plain data |
| `Gumbo.Output.document/1` | `Gumbo.Node.t()` | the `:document` node |
| `Gumbo.Output.root/1` | `Gumbo.Node.t() \| nil` | `<html>`, or the implied one in fragment mode |
| `Gumbo.Output.fragment_nodes/1` | `[Gumbo.Node.t()]` | children of `root/1` — the fragment result |
| `Gumbo.Output.errors/1` | `[Gumbo.Error.t()]` | gumbo's parse errors, in source order |
| `Gumbo.Output.input/1`, `options/1`, `node_count/1` | binary / struct / integer | the exact input, the options, the cached node count |
| `Gumbo.Node` accessors | various | every `GumboNode` field; see `h Gumbo.Node` |
| `Gumbo.Attribute` accessors | various | every `GumboAttribute` field |
| `Gumbo.Error` accessors | various | gumbo's `GumboError` union, plus `message/1`, `caret/1` |
| `Gumbo.Position` | plain struct | `line`, `column`, `offset` |
| `Gumbo.Options` | plain struct | validated in `new/1` |
| `Gumbo.Tag` | standalone helpers | tag names, void elements, SVG case-correction |
| `Gumbo.Types` | typespecs | every gumbo enum as atoms |

The exact accessor lists are tabulated in the moduledocs of `Gumbo.Node`,
`Gumbo.Attribute` and `Gumbo.Error`, each of which has doctests for every
public function.

Behaviours a caller will hit, and none is obvious:

- `Gumbo.Tag.name(:unknown) == ""` is gumbo's own behaviour —
  `GUMBO_TAG_UNKNOWN` normalizes to the empty string. `Gumbo.Node.tag_name/1`
  is the accessor that resolves a real name for an unknown tag (from the
  source text, with SVG case-correction). `detail: :content` carries that
  `:tag_name` for exactly those elements and leaves it off every other one,
  since those are the elements whose atom does not already say the name.
- `Gumbo.Node.attribute_map/1` is **lossy**: it keys by name, so it folds
  namespaces away (`xlink:href` and `href` collide) and cannot represent
  duplicate names. `attributes/1` is the lossless path.
- `Gumbo.Output.root/1` can return `nil`: with `stop_on_first_error: true`,
  a parse that halts before any element exists has no root. That is faithful
  to gumbo, which leaves `output->root` NULL. The same applies to
  `materialize/2`'s output map (`root: nil`) and to `fragment_nodes/1`
  (returns `[]`).
- `Gumbo.Output.errors/1` returns gumbo's own parse errors — descriptions of
  malformations the parser recovered from, capped by `:max_errors` and
  `:stop_on_first_error`. An empty list does **not** mean "valid HTML":
  plenty of sloppy-but-legal markup produces no errors, and not every
  malformation produces one.

## Scheduler behaviour

Large work must not block normal BEAM schedulers, so both heavy entry points
dispatch on a workload size:

- `Gumbo.parse/2` runs on a **dirty CPU scheduler** when the input is
  **20 480 bytes (20 KiB) or more**.
- `Gumbo.materialize/2` runs on a **dirty CPU scheduler** when the handle's
  node count is **20 480 or more** — the size proxy is the cached node
  count, so the decision costs no NIF call.

Below the threshold the work stays on the calling scheduler, avoiding the
dirty-queue hop. The `dirty:` option overrides the rule:

```elixir
Gumbo.parse(html)                  # :auto — dispatch on 20 480 bytes
Gumbo.parse(html, dirty: false)    # force the normal scheduler
Gumbo.parse(html, dirty: true)     # force the dirty CPU scheduler

Gumbo.materialize(output, dirty: true)  # same override on the node-count rule
```

On a VM built without dirty schedulers, a `:dirty` dispatch falls back to
the normal scheduler invisibly. The threshold is
`Gumbo.Options.dirty_threshold/0`.

## Type conversion

Every gumbo enum maps to atoms by one mechanical rule: strip the family
prefix, lowercase ASCII, keep underscores.

**Node types** (`t:Gumbo.Types.node_type/0`):

| C | Elixir |
|---|---|
| `GUMBO_NODE_DOCUMENT` | `:document` |
| `GUMBO_NODE_ELEMENT` | `:element` |
| `GUMBO_NODE_TEXT` | `:text` |
| `GUMBO_NODE_CDATA` | `:cdata` |
| `GUMBO_NODE_COMMENT` | `:comment` |
| `GUMBO_NODE_WHITESPACE` | `:whitespace` |
| `GUMBO_NODE_TEMPLATE` | `:template` |
| `GUMBO_NODE_PROCESSING_INSTRUCTION` | `:processing_instruction` |

A `<?…?>` run is a processing instruction on the current spec, which
[whatwg/html#12118](https://github.com/whatwg/html/pull/12118) added and
0.14.0 implements: `<?pi?>` and `<?php echo 1; ?>` carry
`:processing_instruction`, whose `target` and `data` are the spec's two parts
(`"pi"` with `""`, `"php"` with `"echo 1; "`), while `text` keeps the pair
in the one string the C library stores. A target the spec disallows or cannot
read — `<?xml …?>`, `<?1?>` — is a `:comment` whose text is the whole run,
question mark included, and an unterminated `<?…` produces no node at all.
Browsers do not render a processing instruction, so a renderer that drops
comments must drop these too rather than write their text out.

**Namespaces** (`t:Gumbo.Types.namespace/0`): `GUMBO_NAMESPACE_HTML` → `:html`,
`GUMBO_NAMESPACE_SVG` → `:svg`, `GUMBO_NAMESPACE_MATHML` → `:mathml`.

**Attribute namespaces** (`t:Gumbo.Types.attribute_namespace/0`):
`GUMBO_ATTR_NAMESPACE_NONE` → `:none`, `GUMBO_ATTR_NAMESPACE_XLINK` →
`:xlink`, `GUMBO_ATTR_NAMESPACE_XML` → `:xml`, `GUMBO_ATTR_NAMESPACE_XMLNS`
→ `:xmlns`.

**Quirks modes** (`t:Gumbo.Types.quirks_mode/0`): `GUMBO_DOCTYPE_NO_QUIRKS` →
`:no_quirks`, `GUMBO_DOCTYPE_QUIRKS` → `:quirks`,
`GUMBO_DOCTYPE_LIMITED_QUIRKS` → `:limited_quirks`.

**Parse flags** (`t:Gumbo.Types.parse_flag/0`) — single bits, so a node's
`parse_flags/1` is a subset, not a single member:

| C | Elixir |
|---|---|
| `GUMBO_INSERTION_BY_PARSER` | `:by_parser` |
| `GUMBO_INSERTION_IMPLICIT_END_TAG` | `:implicit_end_tag` |
| `GUMBO_INSERTION_IMPLIED` | `:implied` |
| `GUMBO_INSERTION_CONVERTED_FROM_END_TAG` | `:converted_from_end_tag` |
| `GUMBO_INSERTION_FROM_ISINDEX` | `:from_isindex` |
| `GUMBO_INSERTION_FROM_IMAGE` | `:from_image` |
| `GUMBO_INSERTION_RECONSTRUCTED_FORMATTING_ELEMENT` | `:reconstructed_formatting_element` |
| `GUMBO_INSERTION_ADOPTION_AGENCY_CLONED` | `:adoption_agency_cloned` |
| `GUMBO_INSERTION_ADOPTION_AGENCY_MOVED` | `:adoption_agency_moved` |
| `GUMBO_INSERTION_FOSTER_PARENTED` | `:foster_parented` |

An explicit start tag produces `[]` (`GUMBO_INSERTION_NORMAL`); only
parser-inserted nodes carry flags, e.g. an implied root reports
`[:by_parser, :implicit_end_tag, :implied]`.

**Error types** (`t:Gumbo.Types.error_type/0`): the `GUMBO_ERR_` enum, e.g.
`:utf8_invalid`, `:duplicate_attr`, `:parser`,
`:unacknowledged_self_closing_tag`. The full list is in `Gumbo.Types`.

## The small stack, and why `mix test.small_stack` matters

The Erlang VM gives dirty CPU scheduler threads a ~320 KB stack. gumbo's
own tree teardown (`destroy_node`) recurses once per tree level, and
0.14.1 has no nesting cap, so a ~20 000-deep document segfaults the VM when
the handle is garbage collected. This library disarms that recursion: the
destructor first runs an iterative reverse-preorder pass over the node
table that reimplements `destroy_node`'s per-node work, so teardown is O(n)
in time with constant C stack.

```console
$ mix test.small_stack
```

runs the 12-shape depth matrix (nesting to depth 20 000 and beyond, a
1 000 056-node document, 200 000 siblings) in a child VM whose dirty-CPU
stack is deliberately lowered to the minimum (`+sssdcpu 20`), so a
recursion mistake kills the VM loudly instead of marginally. Every shape is
parsed, materialized, walked, and then **dropped and garbage collected** —
the assertion that matters is that the VM survives teardown.

```console
$ make check-teardown
```

compiles and runs the teardown-contract probe, which has two modes. The
balance mode parses a small document that exercises every teardown branch
(doctype strings, attributes, text, comment, template content, and a parse
error) through counting allocators, runs the destructor's shared teardown
pass, and fails the build if any allocation is outstanding afterward. The
canary mode parses a 20 000-deep document with gumbo's default allocators,
calls gumbo's own recursive teardown directly under a deliberately small
stack, and only reports whether it still recurses — it never fails the
build. Surviving proves liveness, balancing proves reclamation, and
neither alone is sufficient: this project once shipped a teardown that
satisfied the first while violating the second.

## Differences from Nokogiri's gumbo

Rails parses with Nokogiri, and Nokogiri parses HTML5 with its own copy of gumbo.
That copy is not the one this library vendors: Nokogiri carries an internal fork of
lua-gumbo's gumbo — its own `gumbo-parser/src/README.md` says "This is an internal fork
of the libgumbo library … See `lua-gumbo` commit `0a04728`", and lists what the fork
changed — while this library vendors the 0.14.1 tag of the maintained continuation
(see [Licence](#licence)) plus the patch series in `c_src/patches/README.md`. The two
disagree where one side took a change the other did not, and a caller porting from
Rails sees a different tree for those shapes.

Known and measured, with the reference's own sources read for its side of the table:

| shape | this library | Nokogiri's gumbo |
|---|---|---|
| `<?pi x?>`, `<?COMMENT?>` | a `:processing_instruction` node, split into `target` and `data` | a comment — the spec's bogus-comment path, so `<?COMMENT?>` is `<!-- ?COMMENT? -->` |
| `<?` with nothing after it | nothing in the tree | a comment, `<!-- ? -->` |
| a control character in text (`\x07`, `\x1b`, `\x7f`, U+0085) | kept, with `:control_character_in_input_stream` | kept — the same, since patch 0009, which stopped writing U+FFFD for these |
| a noncharacter in text (U+FDD0) | kept, with `:noncharacter_in_input_stream` | kept — the same, since patch 0009 |
| `:max_tree_depth` | no ceiling unless one is asked for | 400 by default |
| `:max_attributes` | 1024 by default, counting the names read for one element — a name counts as the tokenizer reaches it, so a tag that never closes is refused too | 400 by default, counting the same way |
| a `<form>` inside template contents, and a `<frameset>` after an implied `<body>` (the cases in the pinned base's own `tests/tree_construction/template.dat`, four of them fragments whose context is a `template`) | the 2026 template rules: the nested form is not ignored when the parser is parsing template contents, and leaving an implied `<body>` behind keeps `frameset-ok` ok | the rules before them — Nokogiri's fork has the half of "parsing template contents" that is `has_open_element(template)` and not the fragment-context half, and no `frameset_ok` assignment after leaving an implied `<body>` behind |
| an element inside `<select>` (`<select><source id="i">tail</select>`) | kept: the "in select" insertion modes were removed by [whatwg/html#10548](https://github.com/whatwg/html/pull/10548), so a select's content is parsed as body content, and a void element such as `source` is inserted and immediately popped. The pinned base already keeps these; no patch here is what does it | ignored — Nokogiri's fork still has the mode (`GUMBO_INSERTION_MODE_IN_SELECT`, in its `insertion_mode.h`), and `handle_in_select` ends in a parse error and `ignore_token`, so the element is not in the tree |
| an end tag inside `<select>` (`<p><select>https://example.com/&lt;b</p>/p>`) | the same removal puts the end tag in body, where `</p>` with no `p` open for it inserts an empty `p` inside the select and closes that one — patch 0007, which is what makes `select` bound a scope query (whatwg/html#10548) | ignored — by the same catch-all, so the text on either side stays one text node |

The processing-instruction rows are the ones to decide on before a port. The spec gained
processing instructions in 2026 — whatwg/html#12908 and #12911, which the pinned base
follows: its own `tests/tree_construction/tests1.dat` expects `| <?COMMENT ?>` for
`<?COMMENT?>`, where it used to expect `<!-- ?COMMENT? -->`. Nokogiri's gumbo has no
processing-instruction path at all, so it still answers with the comment, and a document
that relies on that answer will not get it here. The parser is asked for the processing
instruction, and `target` and `data` are split the way the spec names them.

Not promised: the table is what is known and measured, not a contract. The pinned base
tracks the spec's newest text — that is what the continuation is maintained for — while
Nokogiri's fork was imported from lua-gumbo earlier, so a difference here can mean either
side moved, and a shape that is not listed may differ either way. What keeps the two-step
claim in `make check-parity` honest is that it parses with the pinned sources and with the
shipped build and permits only the differences the patches in `c_src/patches/README.md`
exist for.

A second axis is a browser rather than Nokogiri, and there the pinned base can be the side
that has moved. The spec's `</form>` rule has two branches: the first works through the
`form` element pointer, and the second — taken whenever the parser is parsing template
contents — ends *Pop elements from the stack of open elements until a `form` element has
been popped from the stack*. With `body` as the fragment context,
`<template><em><center></center><form><tbody></tbody><table>x</table><summary>y</form></em>`
keeps the `form` inside the `em` here, which is the second branch. Chrome 155 puts the
`form` beside the `em` in the `template` instead, which is the first branch — the one taken
when the parser is not parsing template contents. [#12](https://github.com/gilbertwong96/gumbo/issues/12)
reported it from a reader's corpus: `make check-parity` compares this library against the
pin, so a browser is the one side that has to be asked rather than compiled.

## Deliberate omissions

Four gumbo symbols are deliberately not exposed, so nobody hunts for them:

| gumbo symbol | Why it is not exposed |
|---|---|
| `gumbo_string_equals` | plain byte equality — `a == b` in Elixir |
| `gumbo_string_equals_ignore_case` | `String.downcase/1` then compare |
| `gumbo_vector_index_of` | vectors are surfaced as lists; `Enum.find_index/2` |
| `gumbo_destroy_node` | internal lifetime management — a node struct cannot outlive its tree, and freeing a subtree of a live tree would be use-after-free |

`gumbo_destroy_output` is likewise not callable from Elixir: it runs as the
handle's resource destructor, behind the disarming pass described above.

## Licence

Apache License 2.0 — see `LICENSE`.

gumbo-parser is Copyright 2010 Google Inc., maintained by Grigory Kirillov
<me@txgk.in>, and is vendored **unpatched** at tag 0.14.1 under
`c_src/gumbo-parser/`; its licence text ships with it at
`c_src/gumbo-parser/doc/COPYING` (the repo has no top-level LICENSE file).
See `NOTICE` for the attribution.
