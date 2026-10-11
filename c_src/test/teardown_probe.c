/* Two-mode teardown-contract probe, built by the Makefile's check-teardown
   target.

   "balance": deterministic check that the NIF destructor's teardown frees
   everything gumbo allocated. Parse with a counting allocator installed via
   GumboOptions, build the preorder node table, run the same shared
   gumbo_teardown_pass the destructor runs (c_src/gumbo_teardown.c), and
   require the allocator balance to be exactly zero. The balance is an exact
   integer, so there are no RSS thresholds or timing here, and this mode
   fails the build on a non-zero balance.

   Liveness is not reclamation: the small-stack test proves the VM survives
   teardown, but only this probe proves teardown actually frees the tree —
   and because the destructor and this probe call the same
   gumbo_teardown_pass, deleting a free from the pass fails this probe
   instead of passing by private copy.

   "canary [levels]": the complementary property. Build a deep document,
   call gumbo_destroy_output WITHOUT the pass, and report whether the
   process dies under a deliberately small stack (ulimit -s 320). Surviving
   proves liveness, balancing proves reclamation — together they are the
   contract. The three outcomes are told apart by exit status: 0 means
   survived, a signal death (status >= 128) means teardown still recurses,
   and a small non-zero status is a canary error — a parse or allocation
   failure that proves nothing either way — which the Makefile fails the
   build on rather than reporting as recursion. If upstream ever makes
   teardown non-recursive that is not a bug, and the pass stays correct
   either way, so a clean survival or a signal death never fails the build.

   The node-table build below must stay in sync with gumbo_node_table_build
   in gumbo_handle.c; the teardown itself is not duplicated here. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gumbo.h"
#include "gumbo_teardown.h"

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

static int gumbo_probe_balance_mode(void) {
  GumboOptions options = kGumboDefaultOptions;
  options.allocator = gumbo_probe_alloc;
  options.deallocator = gumbo_probe_dealloc;

  /* Exercises every teardown branch: doctype strings, attributes, text,
     comment, template content, element and document children vectors, and
     the error vector (the duplicate attribute produces one error, and the
     unclosed <div> makes handle_in_body's EOF branch add a parser error
     whose tag_stack holds the open elements — a populated by-value vector,
     so gumbo_error_destroy's parser branch frees real data, not a NULL
     vector). */
  const char* html = "<!DOCTYPE html PUBLIC \"pub\" \"sys\">"
                     "<div id=\"a\" class=\"b\" class=\"c\">text<!--c-->"
                     "<template><p>x</p></template>";

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

  gumbo_teardown_pass(&options, output, nodes, node_count);
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

/* Parses <span> nested `levels` deep and calls gumbo_destroy_output on it
   directly — deliberately no gumbo_teardown_pass — to find out whether
   gumbo's own teardown still recurses by tree depth. On a small stack the
   recursion dies and the process never reaches the second printf; the
   Makefile prints the "still recurses" branch from the shell, keyed on the
   signal-death exit status rather than any non-zero status, so a parse or
   allocation failure cannot masquerade as recursion. */
static int gumbo_probe_canary_mode(long levels) {
  size_t open_len = strlen("<span>");
  size_t close_len = strlen("</span>");
  size_t html_len = (open_len + close_len) * (size_t)levels;
  char* html = (char*)malloc(html_len + 1);
  if (html == NULL) {
    fprintf(stderr, "FAIL: canary input allocation failed\n");
    return 1;
  }
  char* cursor = html;
  for (long i = 0; i < levels; ++i) {
    memcpy(cursor, "<span>", open_len);
    cursor += open_len;
  }
  for (long i = 0; i < levels; ++i) {
    memcpy(cursor, "</span>", close_len);
    cursor += close_len;
  }
  *cursor = '\0';

  GumboOptions options = kGumboDefaultOptions;
  GumboOutput* output = gumbo_parse_with_options(&options, html, html_len);
  if (output == NULL) {
    fprintf(stderr, "FAIL: canary parse returned NULL\n");
    free(html);
    return 1;
  }

  printf("canary: parsed %ld levels; calling gumbo_destroy_output directly\n",
         levels);
  fflush(stdout);
  gumbo_destroy_output(&options, output);
  printf("canary: gumbo_destroy_output survived %ld levels\n", levels);
  free(html);
  return 0;
}

int main(int argc, char** argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s balance | canary [levels]\n", argv[0]);
    return 2;
  }
  if (strcmp(argv[1], "balance") == 0) {
    return gumbo_probe_balance_mode();
  }
  if (strcmp(argv[1], "canary") == 0) {
    long levels = (argc >= 3) ? strtol(argv[2], NULL, 10) : 20000;
    if (levels <= 0) {
      fprintf(stderr, "usage: %s canary [levels]\n", argv[0]);
      return 2;
    }
    return gumbo_probe_canary_mode(levels);
  }
  fprintf(stderr, "usage: %s balance | canary [levels]\n", argv[0]);
  return 2;
}
