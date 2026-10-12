#!/usr/bin/env python3
"""Regenerates 0005-stack-budget-guard.patch against a pristine gumbo-parser.

    python3 c_src/patches/gumbo-parser/0005-stack-budget-guard.py
"""

import difflib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "c_src" / "gumbo-parser" / "src"
SCRATCH = Path("/tmp/gumbo-patch-0005")
PATCH = Path(__file__).resolve().parent / "0005-stack-budget-guard.patch"

HEADER = """From: patched for this project, not from upstream
Subject: [PATCH 5/5] Stop parsing when the stack budget is nearly spent

Everything else in this series removes a recursion or bounds a cost. This one is for
the recursion nobody has found yet: a depth-proportional walk in code we do not own,
whose depth is a function of the input and whose frame size is unknown, is the one
failure this library cannot rule out by construction. The alternative — a nesting-depth
cap, which is what Blink, WebKit, Gecko and Nokogiri's gumbo do — would bound it, at the
price of refusing or reshaping documents this library parses today, and the budget
below already keeps those documents affordable.

So the parse is told how much stack it has and stops before it runs out. The caller
knows the number: this library's NIF measures the thread's stack for the sized-thread
decision in c_src/gumbo_parse_stack.c, and passes what is left after a reserve.
GumboOptions.stack_budget is that number, zero meaning no guard.

The check happens in three places, and the places are the interesting part:

  * handle_token, once per token. That covers any recursion that spans tokens, which
    is nearly all of them — the frameset body-removal walk that used to kill the VM
    was the exception, and patch 0001 removed it.
  * clone_node_recursively, which is the one recursion still known to be
    depth-proportional: it returns NULL, which its caller already handles, and the
    shape stops growing.
  * the parse loop's condition, which is where the parse actually stops. It is the
    same exit as stop_on_first_error, so finish_parsing and teardown run as usual and
    the tree stays consistent; GumboOutput.too_deep reports what happened, and this
    library answers {:error, :too_deep} rather than handing back a partial tree.

A guard cannot cover a recursion that goes deep inside one token's handling without
passing through those three places, and saying so is the honest half of this patch.
What it does cover is every recursion whose depth the parser can observe, which is what
"the budget with a detector" means: the guard is what turns a mis-estimated budget from
a crash into a refusal.
---
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

    # This patch is cumulative: unlike 0001-0004 it edits text those patches introduced
    # (GumboOptions.max_attributes, GumboParserState._open_p_count, GumboOutput's flags),
    # so the earlier series has to be applied first. git apply with the scratch directory
    # as the working directory is how the build applies them too.
    for earlier in sorted(Path(__file__).resolve().parent.glob("000[1-4]-*.patch")):
        subprocess.run(
            ["git", "apply", "-p1", str(earlier)], cwd=str(SCRATCH), check=True
        )

    # Snapshot what this patch starts from, *now*: the diff at the end is against the
    # tree with 0001-0004 applied, and taking the snapshot after the edits below would
    # make it empty. That is exactly what the first version of this script did, and it
    # produced a patch with no hunks in it.
    for name in ("gumbo.h", "parser.c"):
        before_dir = SCRATCH / "before"
        before_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["cp", str(SCRATCH / "src" / name), str(before_dir / name)], check=True
        )

    header = SCRATCH / "src" / "gumbo.h"
    parser = SCRATCH / "src" / "parser.c"

    text = header.read_text()
    text = sub(
        text,
        """  unsigned int max_attributes;
} GumboOptions;""",
        """  unsigned int max_attributes;

  /**
   * How much C stack the parse may use, in bytes, or 0 for no limit. The parser
   * stops parsing when it comes within a frame of exhausting this, and reports it
   * through GumboOutput.too_deep. It exists for the recursion nobody has found: a
   * depth-proportional walk whose frame size is unknown cannot be ruled out by
   * arithmetic, so it is caught by a guard instead. The caller is the one who knows
   * the number, because the caller is the one that chose the thread.
   */
  size_t stack_budget;
} GumboOptions;

/**
 * Defined so that a harness compiled against this header and one compiled against the
 * pinned header can tell each other apart at compile time: the field above does not exist
 * there, and a differential harness has to be built against both.
 */
#define GUMBO_HAS_STACK_GUARD 1""",
    )
    text = sub(
        text,
        """  bool too_many_attributes;""",
        """  bool too_many_attributes;

  /**
   * True if the parse stopped early because it reached GumboOptions.stack_budget. The
   * tree is whatever had been built, which is why this library refuses the parse
   * rather than returning it.
   */
  bool too_deep;""",
    )
    header.write_text(text)

    text = parser.read_text()
    text = sub(
        text,
        """    8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML, 1024};""",
        """    8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML, 1024, 0};""",
    )
    text = sub(
        text,
        """  output->root = NULL;
  output->too_many_attributes = false;""",
        """  output->root = NULL;
  output->too_many_attributes = false;
  output->too_deep = false;""",
    )

    # The parser state carries the limit as a pointer, computed once, so that the
    # checks are a compare against it rather than arithmetic anywhere else.
    text = sub(
        text,
        """  unsigned int _open_p_count;""",
        """  unsigned int _open_p_count;

  /**
   * Where the stack budget runs out, or NULL when there is no guard. The parse
   * compares the address of one of its own locals against it: below this line there
   * is not enough stack left to finish parsing and tear the tree down, so it stops.
   */
  const char* _stack_limit;""",
    )
    text = sub(
        text,
        """  gumbo_vector_init(parser, 10, &parser_state->_open_elements);
  parser_state->_open_p_count = 0;""",
        """  gumbo_vector_init(parser, 10, &parser_state->_open_elements);
  parser_state->_open_p_count = 0;
  parser_state->_stack_limit = NULL;""",
    )
    text = sub(
        text,
        """static void parser_state_init(GumboParser* parser) {""",
        """/* True when the parse has come within a frame of the budget, in which case it stops:
   what is left of the stack is what finish_parsing and the teardown need. The address
   of a local in this function is one frame deeper than the caller's, which errs on the
   side of stopping early. */
// noinline, and that is load-bearing rather than an optimisation hint: this function has
// to own a frame for its frame address to mean anything. Inlined, the builtin reports the
// caller's frame instead, and a compiler that can see it is loop-invariant hoists it out of
// the token loop — which is exactly how the first version of this guard compiled to a
// comparison that was always false at -O2 while working at -O0.
__attribute__((noinline)) static bool stack_budget_spent(GumboParser* parser) {
  const char* limit = parser->_parser_state->_stack_limit;
  if (limit == NULL) {
    return false;
  }
  /* The frame address, not the address of a local: a local that is not used again has a
     dead slot, and the optimiser is free to hand it to the next call, which is how the
     first two versions of this guard came to compare two identical addresses and never
     fire. A frame address is fresh in every frame and cannot be shared. */
  if ((const char*) __builtin_frame_address(0) < limit) {
    parser->_output->too_deep = true;
    return true;
  }
  return false;
}

static void parser_state_init(GumboParser* parser) {""",
    )

    # Armed where the budget is known to be relative to, and checked at the three
    # places described in the patch header.
    # The limit is taken from a local of the parse entry point, not from a helper: a
    # helper's frame dies when it returns and the optimiser is free to hand its slot to the
    # next call, which is exactly what it did. The first version armed the limit from a
    # local inside arm_stack_budget, and the check inside handle_token then read the *same*
    # address out of the reused slot, so the guard could never fire however small the budget
    # was — the entry frame is alive for the whole parse and nothing it calls can reuse its
    # locals.
    text = sub(
        text,
        """  gumbo_tokenizer_state_init(&parser, buffer, length);
  parser_state_init(&parser);""",
        """  gumbo_tokenizer_state_init(&parser, buffer, length);
  parser_state_init(&parser);
  parser._parser_state->_stack_limit = options->stack_budget
                                           ? (const char*) __builtin_frame_address(0) -
                                                 options->stack_budget
                                           : NULL;""",
    )
    text = sub(
        text,
        """static bool handle_token(GumboParser* parser, GumboToken* token) {""",
        """static bool handle_token(GumboParser* parser, GumboToken* token) {
  if (stack_budget_spent(parser)) {
    return false;
  }""",
    )
    text = sub(
        text,
        """static GumboNode* clone_node_recursively(GumboParser* parser, const GumboNode* src) {
  if (!src) {
    return NULL;
  }""",
        """static GumboNode* clone_node_recursively(GumboParser* parser, const GumboNode* src) {
  if (!src) {
    return NULL;
  }
  if (stack_budget_spent(parser)) {
    /* The caller appends the clone only when this is non-NULL, so returning NULL
       stops the subtree growing instead of half-building it. */
    return NULL;
  }""",
    )
    text = sub(
        text,
        """  } while ((token.type != GUMBO_TOKEN_EOF || state->_reprocess_current_token) &&
           !(options->stop_on_first_error && has_error));""",
        """  } while ((token.type != GUMBO_TOKEN_EOF || state->_reprocess_current_token) &&
           !(options->stop_on_first_error && has_error) &&
           !parser._output->too_deep);""",
    )

    parser.write_text(text)

    body = ""
    for name in ("gumbo.h", "parser.c"):
        after = (SCRATCH / "src" / name).read_text().splitlines(keepends=True)
        before = (SCRATCH / "before" / name).read_text().splitlines(keepends=True)
        body += "".join(
            difflib.unified_diff(before, after, f"a/src/{name}", f"b/src/{name}")
        )
    body = re.sub(r"^(--- a/src/\S+)\t.*$", r"\1", body, flags=re.M)
    body = re.sub(r"^(\+\+\+ b/src/\S+)\t.*$", r"\1", body, flags=re.M)
    if not body.endswith("\n"):
        body += "\n"

    PATCH.write_text(HEADER + body)
    print(f"wrote {PATCH} ({body.count(chr(10))} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
