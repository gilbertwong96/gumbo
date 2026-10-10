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
- A 12-shape small-stack regression matrix (`mix test.small_stack`) and a
  teardown-contract probe (`make check-teardown`).

### Notes

gumbo-parser 0.14.1's own `gumbo_destroy_output` frees the tree with
`destroy_node`, which recurses once per tree level, and 0.14.1 has no
maximum nesting depth: a ~20 000-deep document segfaults the VM when the
handle is garbage collected. The destructor therefore disarms the tree
first with an iterative reverse-preorder pass that reimplements
`destroy_node`'s per-node work, so teardown is O(n) in time with constant
C stack on any depth.
