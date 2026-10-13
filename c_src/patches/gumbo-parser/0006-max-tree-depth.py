#!/usr/bin/env python3
"""Regenerates 0006-max-tree-depth.patch.

    python3 c_src/patches/gumbo-parser/0006-max-tree-depth.py

Unlike its predecessors this generator does not diff the pristine pin: the hunk it
needs is inside the token loop, whose exit condition patch 0005 already rewrote, so
a pin-based diff would carry pre-0005 context and fail `git apply` when the build
applies 0001 through 0006 in order. It therefore copies the pin, applies 0001-0005
into that copy with the same `git apply -p1` the build uses, and diffs the result
against its own substitutions. The substitutions still assert occurrence counts, so
a pin bump that moves any of this fails here instead of producing a patch that
applies with a different meaning.
"""

import difflib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "c_src" / "gumbo-parser" / "src"
PATCH_DIR = Path(__file__).resolve().parent
SCRATCH = ROOT / "priv" / "obj" / "patch-0006"
SCRATCH_REL = "priv/obj/patch-0006"
PATCH = PATCH_DIR / "0006-max-tree-depth.patch"

HEADER = """From: patched for this project, not from upstream
Subject: [PATCH 6/6] Cap the parse tree's depth, the lever Nokogiri's gumbo exposes

Upstream gumbo has no ceiling on the parse tree's depth, and this library does not
need one: the parse's recursion follows the input's nesting depth for its stack, not
for its time, so a 200 000-level body fragment parses in 78 ms, linear in depth, and
c_src/gumbo_parse_stack.c sizes or refuses the stack it needs. What this patch adds
is the lever an application needs when it wants the tree its reference implementation
builds: Nokogiri's vendored gumbo carries `max_tree_depth` (400 by default, and its
Ruby layer translates a negative value to UINT_MAX and adds one for a fragment, to
account for the implied `<html>`), and an application pinned to that reference cannot
ask this parser for the same behaviour without it.

So GumboOptions.max_tree_depth sets how many open elements the parse may have, and
GumboOutput.tree_too_deep reports that it stopped because of it. Exceeding the limit
terminates the token stream as if EOF had been reached, exactly as the reference
does, because breaking out of the loop mid-parse leaves the document in an
inconsistent state. Nothing else changes: the default is no limit, so a parse that
sets nothing is bit-identical to the pin, which is what `make check-parity` asserts.
"""


def sub(text: str, old: str, new: str, count: int = 1) -> str:
    found = text.count(old)
    if found != count:
        sys.exit(f"FAIL: expected {count} occurrence(s), found {found} of:\n{old[:400]}")
    return text.replace(old, new)


def main() -> int:
    subprocess.run(["rm", "-rf", str(SCRATCH)], check=True)
    SCRATCH.mkdir(parents=True)
    subprocess.run(["cp", "-R", str(SRC), str(SCRATCH / "src")], check=True)

    for prior in sorted(PATCH_DIR.glob("000[1-5]-*.patch")):
        subprocess.run(
            ["git", "apply", "-p1", f"--directory={SCRATCH_REL}", str(prior)],
            check=True,
            cwd=ROOT,
        )

    header = SCRATCH / "src" / "gumbo.h"
    parser = SCRATCH / "src" / "parser.c"

    before = {
        name: (SCRATCH / "src" / name).read_text()
        for name in ("gumbo.h", "parser.c")
    }

    text = header.read_text()
    text = sub(
        text,
        """  size_t stack_budget;
} GumboOptions;""",
        """  size_t stack_budget;

  /**
   * The largest number of open elements the parse may have, or UINT_MAX (the -1
   * this library passes for it) for no limit. The comparison is against the parser's
   * open-element stack, so an implied <html> counts and a fragment's context element
   * counts too: a caller meaning "400 levels of content" passes 401 for a fragment,
   * which is what the reference implementation's Ruby layer does. Exceeding it
   * terminates the token stream as if EOF, so the tree is truncated at that point and
   * GumboOutput.tree_too_deep is set. There is no default ceiling here on purpose:
   * this patch adds a lever, and a parse that sets nothing must build exactly what
   * the unpatched parser builds.
   */
  unsigned int max_tree_depth;
} GumboOptions;""",
    )
    text = sub(
        text,
        """  bool too_deep;
} GumboOutput;""",
        """  bool too_deep;

  /**
   * True if the parse stopped because the open-element stack went past
   * GumboOptions.max_tree_depth. The tree is what had been built when the limit was
   * reached, which differs from what the parser builds without the cap, so this
   * library refuses such a parse rather than returning it.
   */
  bool tree_too_deep;
} GumboOutput;""",
    )
    header.write_text(text)

    text = parser.read_text()
    text = sub(
        text,
        """const GumboOptions kGumboDefaultOptions = {&malloc_wrapper, &free_wrapper, NULL,
    8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML, 1024, 0};""",
        """const GumboOptions kGumboDefaultOptions = {&malloc_wrapper, &free_wrapper, NULL,
    8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML, 1024, 0,
    (unsigned int) -1};""",
    )
    text = sub(
        text,
        """  output->too_deep = false;""",
        """  output->too_deep = false;
  output->tree_too_deep = false;""",
    )
    text = sub(
        text,
        """  int loop_count = 0;

  GumboToken token;""",
        """  int loop_count = 0;
  const unsigned int max_tree_depth = options->max_tree_depth;

  GumboToken token;""",
    )
    text = sub(
        text,
        """      has_error = !gumbo_lex(&parser, &token) || has_error;
    }""",
        """      // If the tree depth limit has been exceeded, proceed as if EOF has been
      // reached: the loop is left to finish the parse normally, because breaking out
      // of it here leaves the document in an inconsistent state.
      if (state->_open_elements.length > max_tree_depth) {
        parser._output->tree_too_deep = true;
        token.type = GUMBO_TOKEN_EOF;
      } else {
        has_error = !gumbo_lex(&parser, &token) || has_error;
      }
    }""",
    )
    text = sub(
        text,
        """           !(options->stop_on_first_error && has_error) &&
           !parser._output->too_deep);""",
        """           !(options->stop_on_first_error && has_error) &&
           !parser._output->too_deep &&
           !parser._output->tree_too_deep);""",
    )
    parser.write_text(text)

    body = ""
    for name in ("gumbo.h", "parser.c"):
        after = (SCRATCH / "src" / name).read_text().splitlines(keepends=True)
        body += "".join(
            difflib.unified_diff(
                before[name].splitlines(keepends=True), after, f"a/src/{name}", f"b/src/{name}"
            )
        )
    if not body.endswith("\n"):
        body += "\n"

    PATCH.write_text(HEADER + body)
    subprocess.run(["rm", "-rf", str(SCRATCH)], check=True)
    print(f"wrote {PATCH} ({body.count(chr(10))} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
