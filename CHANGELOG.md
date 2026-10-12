# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Changed

- `:max_errors` now defaults to `100` instead of gumbo's `-1`, which disables
  the cap. gumbo records one error per unclosed element at EOF and each of those
  carries a copy of the open-element tag stack, so an N-deep unclosed document
  cost N² pointers: a 100 KB document allocated 3.2 GB and 200 KB would have taken
  ~12.8 GB, reachable from input 80x smaller than the accepted input limit. The
  cap makes that memory `cap * depth` instead, which is ~203 MiB for anything that
  finishes inside a minute. `max_errors: -1` still returns every error.

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

### Notes

gumbo-parser 0.14.1's own `gumbo_destroy_output` frees the tree with
`destroy_node`, which recurses once per tree level, and 0.14.1 has no
maximum nesting depth. Two call sites reach that recursion.

The destructor's: a ~7 000-deep document segfaults the VM when the handle is
garbage collected. The destructor therefore disarms the tree first with an
iterative reverse-preorder pass that reimplements `destroy_node`'s per-node
work, so teardown is O(n) in time with constant C stack at any depth.

And `handle_in_body`'s, which runs *inside* the parse: a deeply nested document
followed by a `<frameset>` start tag makes gumbo destroy the body subtree at
input depth mid-parse, which no disarm from outside `parser.c` can intercept.
`<!doctype html>` followed by 8 000 `<div>`s and a `<frameset>` — a 40 KB
document — killed the VM inside `Gumbo.parse/1`, before the parse returned.
The parse now runs on a C stack sized from the input's length
(`c_src/gumbo_parse_stack.c`): depth is bounded by input because a nesting level
costs at least a three-byte start tag, and the worst frame in that recursion is
64 bytes. Documents small enough for the calling thread's own stack parse on it
as before; larger ones run on a thread of the size the input needs. Inputs over
16 MiB are refused with `{:error, :input_too_large}`, since that is where the
sized stack stops being a reasonable reservation.
