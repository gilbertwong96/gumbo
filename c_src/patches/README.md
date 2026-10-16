# Patches against the vendored gumbo-parser

`c_src/gumbo-parser` is a submodule pinned to the upstream 0.14.1 tag. This
directory holds patches applied to a **copy** of it at build time.

Patching the submodule in place was the alternative, and it is rejected: an
edited submodule working tree is a `git status` that says `M c_src/gumbo-parser`
forever, `git submodule status` stops being a record of what we build, and
`git submodule update` silently throws the patch away. A copy keeps the pin
honest and makes the patch a reviewed, versioned file instead of a local edit.

## How the build applies them

From `Makefile`:

1. `$(OBJ_DIR)/gumbo-src/` (`priv/obj`, gitignored) gets a copy of
   `c_src/gumbo-parser/src`.
2. Every `*.patch` here is applied to that copy with
   `git apply -p1 --directory=$(OBJ_DIR)/gumbo-src` — in file-name order, so the
   numeric prefixes are the application order.
3. All twelve vendored objects are compiled from the copy, and `-I` points at
   the copy too, so `c_src/*.c`, which includes the vendored internals
   (`parser.h`, `util.h`, `attribute.h`), compiles against exactly what is
   linked.

A stamp file (`$(GUMBO_SRC_STAMP)`) drives the copy, so an unchanged tree does
no work, and editing either a patch or a vendored source re-copies and rebuilds
the twelve objects.

`--directory` must be **relative**; `git apply` rejects an absolute one
(`error: invalid path`). `git apply` itself works outside a git repository, so
building this package from a tarball, where the submodule is a plain directory,
works the same way.

## The rules for a patch

- One patch per file, numbered (`0001-`, `0002-`), unified diff with `a/` and
  `b/` prefixes so `-p1` applies it.
- Do not hand-write a patch. Generate it, or the hunk counts will not match and
  `git apply` will say `corrupt patch` — which is what happened the first time
  here. The recipe for the current one is below.
- Say *why* in the header file, since the patch cannot carry a commit message
  that survives `git apply`.

## How it is checked

`make check-patch` (wired into `mix ci` as `check.patch`) re-applies the whole
series to a pristine copy under `$(OBJ_DIR)/patch-check` and fails if it does not
apply, and fails if `c_src/gumbo-parser` has any tracked modification. The point
is a submodule bump: a new pin is a new set of files, and the gate turns "the
patch stopped applying" into a red build instead of a build that silently
compiles unpatched gumbo.

`make check-clean-build` (wired in as `check.clean_build`) copies `Makefile` and
`c_src` into a temporary directory and builds from an empty object directory,
which is what a fresh clone, a cold CI cache and a hex consumer all do, and what
a warm tree cannot test. Two real bugs lived only there: the object rule named the
copy's `.c` as a prerequisite make could not make (so a clean build silently
compiled none of the twelve vendored objects and linked against their absence),
and `-include` on a not-yet-written `.d` file made make reach for its built-in
`%: %.o` rule, which chained into the object rule with a nonsense stem. It also
exercises the tarball case, since a temporary directory is not a git repository.

`make check-teardown` (wired in as `test.teardown_contract`) holds the patched
teardown to both properties that matter: the allocator balance is exactly zero, and
a 20 000-level tree survives a 320 KB stack. Both are hard gates now — after this
patch, a signal death there can only mean the patch was lost.

`make check-parity` (wired in as `check.parity`) parses a seeded corpus with the
patched objects and with the pinned sources and compares the trees node by node,
including attribute order, namespace, text and error positions. It is the net for
the patches that change how the parser decides what to build: an answer that is off
by one does not crash or leak, it silently produces a different tree. It found two
silent-corruption bugs in 0002 while that patch was being written (a struct copy
that carried the new flag onto a clone, and a tenth place where the stack is
mutated, in adoption agency step 13.7).

0007, 0008 and 0009 are the patches that change what the parser builds on purpose, so the
claim is made in two steps rather than one. A third binary — the pin with those three applied
to it alone, and compiled against the pin's own headers — has to parse the whole corpus
identically to the shipped build, which is what still catches any of the other patches
moving a tree, and the pin alone may differ only in the documents whose tree holds a
`select` element, which is what bounds 0007's blast radius. The corpus keeps the
`<select>`, `<option>`, `<optgroup>` and `<selectedcontent>` shapes 0002's definitions
were written for rather than dropping them to make the old one-step comparison hold, and
it holds no document 0008 or 0009 moves: of the 1019 tree-construction documents in
html5lib's corpus, the four that carry two distinct unknown names at all are SVG or MathML,
which is the handler that already compares names, and none of them writes a control
character into text. 0008's and 0009's own shapes are held by
`test/gumbo/unknown_end_tag_test.exs` and `test/gumbo/control_characters_test.exs`, and the
corpus is where the fact that they move none of it is measured.

`make check-sanitizers` (wired in as `check.sanitizers`) builds the same harness
against the patched sources with AddressSanitizer and UndefinedBehaviorSanitizer and
runs the seeded corpus plus ten adversarial shapes through it. It is the only net
there is for a memory-safety bug inside gumbo itself — no amount of care on our side
of the boundary can prove the absence of one — and it is most of what `mix ci` now
costs (about 33 of its 50 seconds, the instrumented compile being the bulk).

It earned that immediately by finding a bug in **our own fourth patch**: the tokenizer
state is allocated rather than zeroed and the one function that would clear it is
compiled out without `NDEBUG`, so the new attribute index was read as uninitialised
memory on the first tag. Builds without ASan happened to get zeroed pages and never
noticed; ASan fills fresh bytes with a pattern, which turned a latent garbage pointer
into an assertion failure. It then found one in the throwaway harness itself — a heap
overflow in the shape builder, from trusting its own bytes-per-level arithmetic —
which is why the shipped builder appends through a bounds-checked `emit`.

What it does not cover: our own `erl_nif_*` plumbing, which cannot be sanitised without
instrumenting the VM itself, and the `enif_*` misuse class that killed the VM once
before.

`make check-teardown` (wired in as `test.teardown_contract`) holds the patched
teardown to both properties that matter: the allocator balance is exactly zero, and
a 20 000-level tree survives a 320 KB stack. Both are hard gates now — after the
0001 patch, a signal death there can only mean the patch was lost.

## The series

| patch | what it fixes | how it is verified |
|---|---|---|
| 0001 | `destroy_node` recursing per tree level, in the destructor and inside the parse | the teardown canary, and a 50 000-level tree on a 320 KB stack |
| 0002 | the two per-tag queries over the stack of open elements, i.e. the parse's quadratic time | `check-parity`, plus a timing test for those shapes |
| 0003 | every error keeping the whole open-element stack, i.e. the error vector's quadratic memory | `check-parity`, plus a bound asserted through `Gumbo.Error.parser_error/1` |
| 0004 | the duplicate-attribute scan, i.e. one element's quadratic attribute cost, and the absence of any ceiling on that count | `check-parity` (whose corpus now generates attribute clusters), plus a cap test and a timing test |
| 0005 | nothing that was measured: it is the backstop for a depth-proportional recursion nobody has found | `check-stack-guard`, which is the one gate that can only test the mechanism, because no document makes the C stack grow with its nesting depth any more |
| 0006 | nothing either: a lever Nokogiri's gumbo has and this one did not, for applications pinned to that reference | `check-parity` (whose corpus now nests past the reference's default ceiling), plus a cap test, a boundary test and this library's own refusal |
| 0007 | the scope queries not stopping at a `select`, i.e. `</p>` inside one closing the `p` outside it instead of the empty `p` it inserts there | the select shapes in `test/gumbo/select_scope_test.exs`, plus `check-parity` in its two-step form, which allows a difference against the pin only in documents that hold a select |
| 0008 | an end tag that names no open element closing the first element with an unknown name it meets, i.e. a name compared as `GumboTag` where every unknown name is `GUMBO_TAG_UNKNOWN`, so `<f&#igure>` is closed by `</fidiv>` | the shapes in `test/gumbo/unknown_end_tag_test.exs`, plus `check-parity` in its two-step form, which is also where the corpus is measured to hold no document this patch moves |
| 0009 | the input stream's decoder replacing the characters the spec only calls parse errors — controls and noncharacters — with U+FFFD, and reporting all of them as `UTF8_INVALID`, so a pasted control byte comes back as U+FFFD and a multi-byte one reported its bytes as its code point | the shapes in `test/gumbo/control_characters_test.exs`, plus `check-parity` in its two-step form, which is also where the corpus is measured to hold no document this patch moves |

Eight of the nine are generated. The definition next to a patch — `NNNN-name.exs` — lists the
substitutions that make it, each with the count it must find, and `mix gumbo.patches` applies the
earlier patches to a copy of the pin, runs the substitutions, and writes the patch back out as the
diff against the pinned tree. That is also how they are rebased after a submodule bump:

```sh
mix gumbo.patches            # rewrite the patches whose definitions no longer match
mix gumbo.patches --check    # assert the committed patches are what the definitions produce
```

Whether a patch is cumulative is part of its definition. 0005 and 0006 edit text that earlier
patches introduced, so their `priors: true` has the tool apply 0001-0004 and 0001-0005 first, while
0002, 0003, 0004, 0007, 0008 and 0009 were written against the pinned tree and say `priors: false`.

Each substitution asserts how many occurrences it must find, so a submodule bump that moves any of
the text fails there — naming the file and the snippet — rather than producing a patch that applies
with a different meaning. On top of that, `make check-generators` (in `mix ci`) regenerates every
generated patch and requires the result to be byte-identical to the committed file. The Python
tooling these were ported from had no such check, which is why the recipe above could go stale
without anything noticing. The port is Elixir for the same reason the rest of the tooling is: it is
the language this repository already requires, and the one the build already runs.

The diff is `Gumbo.Patches.Diff`, a port of Python's `difflib` rather than any equivalent algorithm,
because "the same patch" here means the same bytes: the patches are the build's input *and* the
record of what each change is, so a diff that merely said the same thing would rewrite all of them
the first time it ran. The port is checked against the committed patches themselves, and against a
corpus of generated cases.

## 0001-make-destroy_node-iterative.patch

`destroy_node` recursed once per tree level. Two call sites are reachable at
input depth — the destructor, on whichever thread runs the GC, and
`handle_in_body`'s `<frameset>` branch, *during the parse* — and neither the
recursion nor the nesting depth is capped in 0.14.1. Measured on a 320 KB stack
(the default for an Erlang dirty CPU scheduler thread, `+sssdcpu`'s 40
kilowords): a document survives 6 000 levels of nesting and dies at 8 000, and a
40 KB document reaches that. The frameset path is the one that cannot be worked
around from outside `parser.c`, because the call is static and mid-stream.

This is upstream's own fix, offered in google/gumbo-parser#387 and never merged
(the Codeberg continuation still has the recursion, and 0.14.1 is its newest
tag). Nokogiri's vendored gumbo ships it — its `gumbo-parser/src/README.md`
changelog lists "Make `destroy_node()` function non-recursive" twice — which is
also what let Nokogiri put a `max_tree_depth` on top. See the ledger entry of
2026-10-13 for the measurements and for what was checked about the alternatives.

To regenerate it:

```sh
rm -rf /tmp/gp && mkdir -p /tmp/gp/{a,b}/src
cp c_src/gumbo-parser/src/parser.c /tmp/gp/a/src/parser.c
cp /tmp/gp/a/src/parser.c /tmp/gp/b/src/parser.c
# edit /tmp/gp/b/src/parser.c: replace destroy_node's two recursive walks with a
# heap worklist, as the patch does
cd /tmp/gp
diff -u a/src/parser.c b/src/parser.c \
  | sed -E 's|^(--- a/src/parser\.c)\t.*|\1|; s|^(\+\+\+ b/src/parser\.c)\t.*|\1|' \
  > c_src/patches/gumbo-parser/0001-make-destroy_node-iterative.patch
```

(the `sed` drops the timestamps so regenerating twice gives the same file)
