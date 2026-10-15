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
    {:gumbo, "~> 0.1.0"}
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
```

An element whose tag gumbo cannot name — `tag: :unknown`, which is a custom
element and also an SVG tag like `clipPath` — carries `tag_name` as well, so
the name as written survives in this shape. Every other element is named by
its atom, which is that same name, and does not repeat it.

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
