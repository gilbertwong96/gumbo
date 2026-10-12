/* Allocation failure is the only way these paths are reached, and no test can
   cause one, so the tests cause the failure instead: an extraction is made to
   fail on purpose and the caller's answer is asserted to be the same one a
   forged handle gets.

   Everything here compiles out unless GUMBO_TEST_FAULTS is defined, which only
   `make check-fault-paths` does. A release build therefore cannot arm the hook,
   and a test cannot pass because the hook was inert — which is the failure this
   exists to avoid, since the whole subject of this work is a guard that could
   never fire. */

#ifndef GUMBO_FAULTS_H_
#define GUMBO_FAULTS_H_

#ifdef GUMBO_TEST_FAULTS

/* Reads GUMBO_FAULT_AT and restarts the count, so that each parse in a sweep
   arms itself. Called from the parse entry point, under the same flag. */
void gumbo_fault_arm(void);

/* 1 when this extraction is the one the sweep asked to fail, 0 otherwise. */
int gumbo_fault_should_fail(void);

#endif

#endif
