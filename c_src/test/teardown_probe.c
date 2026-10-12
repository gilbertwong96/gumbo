/* Two-mode teardown-contract probe, built by the Makefile's check-teardown
   target.

   Both modes are hard gates. The vendored destroy_node is iterative as of
   c_src/patches/0001-make-destroy_node-iterative.patch, so neither a clean
   survival on a small stack nor a zero allocator balance is a coincidence any
   more: either one failing means the patch is gone (a submodule bump that stopped
   applying it, or the file deleted) and the crash is back.

   "balance": parse with a counting allocator installed via GumboOptions, then
   call gumbo_destroy_output — the same call the NIF destructor makes — and
   require the balance to be exactly zero. The input is chosen to exercise every
   branch of that walk: doctype strings, attributes, text, comment, template
   contents, the children and attributes vectors, and the error vector (the
   duplicate attribute produces one error, and the unclosed <div> makes
   handle_in_body's EOF branch add a parser error whose tag_stack holds the open
   elements, so gumbo_error_destroy's parser branch frees a populated by-value
   vector rather than a NULL one). The balance is an exact integer: no RSS
   thresholds, no timing.

   Liveness is not reclamation. That distinction is the first defect this project
   shipped — a teardown that survived every test and leaked 70% of the tree — so
   both properties are asserted here rather than one standing in for the other.
   Until 2026-10-13 this mode ran the disarm pass in c_src/gumbo_teardown.c instead;
   that unit is gone, and the walk it disarmed is our patch now, which makes this
   the only test of the code we added.

   "canary [levels]": the same walk on a document `levels` deep, run by the
   Makefile under `ulimit -s 320` — a stack a recursive walk of this depth cannot
   survive (measured: the unpatched walk dies at 8 000 levels on a 320 KB stack,
   and this default is 20 000). The probe cannot assert its own survival, so the
   Makefile turns a signal death into a failure; that is also why a non-zero
   *error* exit from this mode has to be told apart from a death, which is all the
   Makefile's status handling is doing. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gumbo.h"

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

static int gumbo_probe_balance_mode(void) {
  GumboOptions options = kGumboDefaultOptions;
  options.allocator = gumbo_probe_alloc;
  options.deallocator = gumbo_probe_dealloc;

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

  gumbo_destroy_output(&options, output);

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
