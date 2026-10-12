/* A deliberate use-after-free, and the only file in this repository that is
   supposed to be broken.

   The static-analysis gate analyzes every C file this repository owns and
   requires be said about them, which on its own cannot tell a clean codebase
   from a silent analyzer — and this project has already shipped one guard that
   could never fire because of exactly that confusion between "nothing found"
   and "nothing looked for". So the gate also analyzes this file and requires
   the analyzer to report it.

   It is not compiled by anything: the NIF's source list is a wildcard over the
   top level of c_src, the probe and the differential harness name their sources
   explicitly, and the test directory
   is outside all of them. If that ever changes, this file will show up as a
   leak in a gate rather than as a bug in production. */

#include <stdlib.h>

/* Declared before they are defined, so that -Wmissing-prototypes is satisfied
   without making them static: the analyzer prunes unreachable code, and a
   static function nothing calls is exactly the dead code that made the first
   two attempts at verifying the analyzer gate look like a clean codebase. */
static int* analyzer_canary_alloc(void);
int analyzer_canary_use_after_free(void);

static int* analyzer_canary_alloc(void) {
  int* value = malloc(sizeof(int));
  *value = 1;
  return value;
}

int analyzer_canary_use_after_free(void) {
  int* value = analyzer_canary_alloc();
  free(value);
  return *value;
}
