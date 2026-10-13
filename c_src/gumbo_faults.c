/* See gumbo_faults.h. Compiled to nothing without GUMBO_TEST_FAULTS; the
   typedef below keeps the translation unit non-empty, which C99 requires. */

#include "gumbo_faults.h"

typedef int gumbo_faults_unit_is_not_empty;

#ifdef GUMBO_TEST_FAULTS

#include <stdio.h>
#include <stdlib.h>

static unsigned int fault_count;
static unsigned int fault_at;

void gumbo_fault_arm(void) {
  unsigned int index = 0;

  fault_count = 0;
  fault_at = 0;

  /* The index cannot come from the environment: this process's getenv does not
     follow System.put_env, which was measured by arming a sweep and watching
     nothing fail. The path is compiled in and the index is read from the file
     at that path, so the sweep writes a file and the next parse reads it. */
  FILE* file = fopen(GUMBO_FAULT_FILE_PATH, "r");
  if (file != NULL) {
    if (fscanf(file, "%u", &index) != 1) {
      index = 0;
    }
    fclose(file);
    fault_at = index;
  }

  /* The sweep's canary, and the only place it can come from: this function
     exists only in a fault build, so the file it leaves behind says the library
     that ran is one. A green run without it is a run against a library with no
     hook, which is a thing that happened. */
  char armed[sizeof(GUMBO_FAULT_FILE_PATH) + 8];
  int written =
      snprintf(armed, sizeof(armed), "%s.armed", GUMBO_FAULT_FILE_PATH);
  if (written > 0 && (size_t)written < sizeof(armed)) {
    FILE* sentinel = fopen(armed, "w");
    if (sentinel != NULL) {
      fclose(sentinel);
    }
  }
}

int gumbo_fault_should_fail(void) { return ++fault_count == fault_at; }

#endif
