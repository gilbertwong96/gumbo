/* Deterministic check that the NIF destructor's teardown frees everything
   gumbo allocated: parse with a counting allocator installed via
   GumboOptions, build the preorder node table, run the same teardown the
   destructor runs (c_src/gumbo_handle.c, gumbo_handle_dtor), and require the
   allocator balance to be exactly zero. The balance is an exact integer, so
   there are no RSS thresholds or timing in this probe.

   Liveness is not reclamation: the small-stack test proves the VM survives
   teardown, but only this probe proves teardown actually frees the tree.

   The node-table build below must stay in sync with gumbo_node_table_build
   and the teardown with gumbo_handle_dtor. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "attribute.h"
#include "gumbo.h"
#include "parser.h"
#include "util.h"

static long gumbo_probe_balance = 0;

static void* gumbo_probe_alloc(void* userdata, size_t size) {
  (void)userdata;
  gumbo_probe_balance += 1;
  return malloc(size);
}

static void gumbo_probe_dealloc(void* userdata, void* ptr) {
  (void)userdata;
  if (ptr != NULL) {
    gumbo_probe_balance -= 1;
  }
  free(ptr);
}

/* Children vector per node type; mirrors gumbo_node_children in
   gumbo_handle.c. */
static GumboVector* gumbo_probe_children(GumboNode* node) {
  switch (node->type) {
    case GUMBO_NODE_DOCUMENT:
      return &node->v.document.children;
    case GUMBO_NODE_ELEMENT:
    case GUMBO_NODE_TEMPLATE:
      return &node->v.element.children;
    default:
      return NULL;
  }
}

static int gumbo_probe_push(GumboNode*** stack, size_t* count,
                            size_t* capacity, GumboNode* node) {
  if (*count == *capacity) {
    size_t next = (*capacity == 0) ? 64 : *capacity * 2;
    GumboNode** grown =
        (GumboNode**)realloc(*stack, next * sizeof(GumboNode*));
    if (grown == NULL) {
      return 1;
    }
    *stack = grown;
    *capacity = next;
  }
  (*stack)[(*count)++] = node;
  return 0;
}

/* The probe's own table and stack use plain malloc/free, exactly as the NIF
   uses enif_alloc for its table and stack, so the counting balance covers
   only gumbo-parser allocations. */
static int gumbo_probe_table_build(GumboOutput* output, GumboNode*** out_nodes,
                                   size_t* out_count) {
  GumboNode** nodes = NULL;
  size_t node_count = 0;
  size_t node_capacity = 0;
  GumboNode** stack = NULL;
  size_t stack_count = 0;
  size_t stack_capacity = 0;

  if (output->document == NULL) {
    return 1;
  }
  if (gumbo_probe_push(&stack, &stack_count, &stack_capacity,
                       output->document) != 0) {
    free(stack);
    return 1;
  }

  while (stack_count > 0) {
    GumboNode* node = stack[--stack_count];

    if (node_count == node_capacity) {
      size_t next = (node_capacity == 0) ? 16 : node_capacity * 2;
      GumboNode** grown =
          (GumboNode**)realloc(nodes, next * sizeof(GumboNode*));
      if (grown == NULL) {
        free(nodes);
        free(stack);
        return 1;
      }
      nodes = grown;
      node_capacity = next;
    }
    nodes[node_count++] = node;

    GumboVector* children = gumbo_probe_children(node);
    if (children != NULL) {
      unsigned int i;
      for (i = children->length; i-- > 0;) {
        if (gumbo_probe_push(&stack, &stack_count, &stack_capacity,
                             children->data[i]) != 0) {
          free(nodes);
          free(stack);
          return 1;
        }
      }
    }
  }

  free(stack);
  *out_nodes = nodes;
  *out_count = node_count;
  return 0;
}

/* The teardown the destructor runs. Reverse preorder: preorder puts a parent
   before all its descendants, so descending index order frees every child
   before its parent. Emptying each children vector as we go makes the
   destroy_node call inside gumbo_destroy_output bottom out at depth 1, where
   it frees only the document node, the doctype strings, the error vector and
   the output struct. */
static void gumbo_probe_teardown(GumboOptions* options, GumboOutput* output,
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

int main(void) {
  GumboOptions options = kGumboDefaultOptions;
  options.allocator = gumbo_probe_alloc;
  options.deallocator = gumbo_probe_dealloc;

  /* Exercises every teardown branch: doctype strings, attributes, text,
     comment, template content, element and document children vectors, and
     the error vector (the duplicate attribute produces an error, and the
     premature EOF at the end of the tree produces a parser error with a
     tag_stack vector). */
  const char* html = "<!DOCTYPE html PUBLIC \"pub\" \"sys\">"
                     "<div id=\"a\" class=\"b\" class=\"c\">text<!--c-->"
                     "<template><p>x</p></template></div>";

  GumboOutput* output =
      gumbo_parse_with_options(&options, html, strlen(html));
  if (output == NULL) {
    fprintf(stderr, "FAIL: parse returned NULL\n");
    return 1;
  }

  long outstanding_after_parse = gumbo_probe_balance;
  if (outstanding_after_parse == 0) {
    fprintf(stderr, "FAIL: parse allocated nothing; probe is vacuous\n");
    return 1;
  }

  GumboNode** nodes = NULL;
  size_t node_count = 0;
  if (gumbo_probe_table_build(output, &nodes, &node_count) != 0) {
    fprintf(stderr, "FAIL: node table build failed\n");
    return 1;
  }

  gumbo_probe_teardown(&options, output, nodes, node_count);
  free(nodes);

  printf("allocations outstanding: %ld after parse, %ld after teardown\n",
         outstanding_after_parse, gumbo_probe_balance);

  if (gumbo_probe_balance != 0) {
    fprintf(stderr, "FAIL: %ld allocations leaked by teardown\n",
            gumbo_probe_balance);
    return 1;
  }
  printf("PASS: teardown balance is zero\n");
  return 0;
}
