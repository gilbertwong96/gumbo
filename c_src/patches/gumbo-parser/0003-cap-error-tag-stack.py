#!/usr/bin/env python3
"""Regenerates 0003-cap-error-tag-stack.patch against a pristine gumbo-parser.

Same contract as 0002-open-element-queries.py: run it from the repository root,
it rewrites the .patch next to itself, and every substitution asserts a count so a
submodule bump that moves any of this fails here instead of producing a patch that
applies with a different meaning.

    python3 c_src/patches/gumbo-parser/0003-cap-error-tag-stack.py
"""

import difflib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "c_src" / "gumbo-parser" / "src"
SCRATCH = Path("/tmp/gumbo-patch-0003")
PATCH = Path(__file__).resolve().parent / "0003-cap-error-tag-stack.patch"

HEADER = """From: patched for this project, not from upstream
Subject: [PATCH 3/3] Cap what one error keeps of the open-element stack

gumbo records one parser error per unclosed element at EOF, and one per unmatched
end tag, and each error copied the whole open-element stack into itself. With the
stack as deep as the document is nested, an input of n bytes could therefore cost
n^2 entries: measured with a counting allocator, 100 KB of unclosed <div> produced
20 000 errors and 400 040 000 stack entries (3.2 GB), and the same depth followed by
20 000 unmatched </p> produced 800 080 000 entries (6.4 GB) — neither is a corner
case, and neither is bounded by a limit on the input's length.

Only the innermost stack entries are kept now, at most 32 of them, so the cost of
the error vector is bounded by the number of errors gumbo is willing to record
(`max_errors`, 100 by default in this library) times 32 entries. The alternative —
bounding the nesting depth, which is what Blink, WebKit, Gecko and Nokogiri's gumbo
do — would bound this too, but it changes which documents parse.

This is a change to what an error carries, not to what the parser builds: the
differential harness in c_src/test/parity_dump.c compares trees and error positions,
not tag stacks, and `make check-parity` still passes. The cap is visible to a caller
that asks for the stack: `Gumbo.Error.parser_error/1` returns at most 32 tags for an
error deep in a document, and the rendered message lists at most those.
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

    parser = SCRATCH / "src" / "parser.c"
    text = parser.read_text()

    text = sub(
        text,
        """static void* malloc_wrapper(void* unused, size_t size) { return malloc(size); }""",
        """/* How much of the stack of open elements one error keeps. An error used to
   keep all of it, and errors arrive one per unclosed element or unmatched end tag,
   which made the error vector cost the square of the input: 100 KB of unclosed
   <div> measured 400 040 000 entries and 3.2 GB. */
#define GUMBO_ERROR_TAG_STACK_LIMIT 32

static void* malloc_wrapper(void* unused, size_t size) { return malloc(size); }""",
    )

    text = sub(
        text,
        """  GumboParserState* state = parser->_parser_state;
  extra_data->parser_state = state->_insertion_mode;
  gumbo_vector_init(
      parser, state->_open_elements.length, &extra_data->tag_stack);
  for (unsigned int i = 0; i < state->_open_elements.length; ++i) {
    const GumboNode* node = state->_open_elements.data[i];
    assert(
        node->type == GUMBO_NODE_ELEMENT || node->type == GUMBO_NODE_TEMPLATE);
    gumbo_vector_add(
        parser, (void*) node->v.element.tag, &extra_data->tag_stack);
  }
  return error;""",
        """  GumboParserState* state = parser->_parser_state;
  extra_data->parser_state = state->_insertion_mode;
  /* The innermost entries, which are the error's own context; the outer ones are
     the document's skeleton and are the same for every error in it. The vector is
     sized for what is kept, not for the stack, so a deep error allocates 32 entries
     and not one per level. */
  unsigned int stack_length = state->_open_elements.length;
  unsigned int kept = (stack_length < GUMBO_ERROR_TAG_STACK_LIMIT)
                          ? stack_length
                          : (unsigned int) GUMBO_ERROR_TAG_STACK_LIMIT;
  gumbo_vector_init(parser, kept, &extra_data->tag_stack);
  for (unsigned int i = stack_length - kept; i < stack_length; ++i) {
    const GumboNode* node = state->_open_elements.data[i];
    assert(
        node->type == GUMBO_NODE_ELEMENT || node->type == GUMBO_NODE_TEMPLATE);
    gumbo_vector_add(
        parser, (void*) node->v.element.tag, &extra_data->tag_stack);
  }
  return error;""",
    )

    parser.write_text(text)

    before = (SRC / "parser.c").read_text().splitlines(keepends=True)
    after = (SCRATCH / "src" / "parser.c").read_text().splitlines(keepends=True)
    body = "".join(difflib.unified_diff(before, after, "a/src/parser.c", "b/src/parser.c"))
    body = re.sub(r"^(--- a/src/\S+)\t.*$", r"\1", body, flags=re.M)
    body = re.sub(r"^(\+\+\+ b/src/\S+)\t.*$", r"\1", body, flags=re.M)
    if not body.endswith("\n"):
        body += "\n"

    PATCH.write_text(HEADER + body)
    print(f"wrote {PATCH} ({body.count(chr(10))} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
