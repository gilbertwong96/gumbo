/* The teardown the destructor runs, in one shared unit so the probe
   (c_src/test/teardown_probe.c) executes the exact code the destructor
   does — the probe's whole point is to catch the destructor regressing, so
   a private copy of the loop would be hollow.

   Teardown runs on a GC/scheduler thread, possibly on the dirty CPU
   scheduler's small stack, so it must not recurse. gumbo's own
   destroy_node recurses once per tree level and 0.14.1 has no nesting cap;
   its per-node work is therefore reimplemented here iteratively in reverse
   preorder: preorder puts a parent before all its descendants, so
   descending index order frees every child before its parent.

   Emptying each children vector as we go also makes the destroy_node call
   inside gumbo_destroy_output bottom out at depth 1, where it frees only
   the document node, the doctype strings, the error vector and the output
   struct. Note: merely emptying the vectors is NOT enough — stopping
   destroy_node's loop also stops its traversal, so the whole subtree below
   the document would leak. This is why the probe asserts a counting
   allocator's balance is exactly zero, not merely that the process
   survived. */

#include <string.h>

#include "attribute.h" /* gumbo_destroy_attribute */
#include "gumbo.h"
#include "gumbo_teardown.h"
#include "parser.h" /* GumboParser, for the stack-local parser */
#include "util.h"  /* gumbo_parser_deallocate */

/* parser.h and util.h are internal to gumbo-parser and are depended on only
   for the stack-local GumboParser, exactly as gumbo_destroy_output and
   gumbo_destroy_node do. Acceptable because the submodule pins the version.
   This unit includes no ERTS header, so it links into both the NIF and the
   standalone probe. */

void gumbo_teardown_pass(const GumboOptions* options, GumboOutput* output,
                         GumboNode** nodes, size_t node_count) {
  GumboParser parser;
  memset(&parser, 0, sizeof(parser));
  parser._options = options;

  for (size_t i = node_count; i-- > 0;) {
    GumboNode* node = nodes[i];
    GumboVector* children = NULL;

    switch (node->type) {
      case GUMBO_NODE_ELEMENT:
      case GUMBO_NODE_TEMPLATE: {
        GumboVector* attributes = &node->v.element.attributes;
        unsigned int j;
        for (j = 0; j < attributes->length; ++j) {
          gumbo_destroy_attribute(&parser, attributes->data[j]);
        }
        gumbo_parser_deallocate(&parser, attributes->data);
        attributes->data = NULL;
        attributes->length = 0;
        attributes->capacity = 0;
        children = &node->v.element.children;
        break;
      }
      case GUMBO_NODE_DOCUMENT:
        children = &node->v.document.children;
        break;
      default: /* TEXT, CDATA, COMMENT, WHITESPACE, PROCESSING_INSTRUCTION */
        gumbo_parser_deallocate(&parser, (void*)node->v.text.text);
        break;
    }

    if (children != NULL) {
      /* Free the pointer array and zero all three fields by hand;
         gumbo_vector_destroy is not a substitute because it leaves
         length set, and the zeroed vector is what stops destroy_node's
         double-free in gumbo_destroy_output. */
      gumbo_parser_deallocate(&parser, children->data);
      children->data = NULL;
      children->length = 0;
      children->capacity = 0;
    }
    /* gumbo_destroy_output's destroy_node frees the document node itself;
       compare pointers rather than indices so this stays correct if the
       table build ever changes. */
    if (node != output->document) {
      gumbo_parser_deallocate(&parser, node);
    }
  }

  gumbo_destroy_output(options, output);
}
