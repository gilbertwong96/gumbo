/* See gumbo_faults.h. Compiled to nothing without GUMBO_TEST_FAULTS; the
   typedef below keeps the translation unit non-empty, which C99 requires. */

#include "gumbo_faults.h"

typedef int gumbo_faults_unit_is_not_empty;

#ifdef GUMBO_TEST_FAULTS

#include <stdlib.h>

static unsigned int fault_count;
static unsigned int fault_at;

void gumbo_fault_arm(void) {
  const char* value = getenv("GUMBO_FAULT_AT");
  fault_count = 0;
  fault_at = value == NULL ? 0 : (unsigned int)strtoul(value, NULL, 10);
}

int gumbo_fault_should_fail(void) { return ++fault_count == fault_at; }

#endif
