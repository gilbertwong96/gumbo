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

/* The path is compiled in unquoted and stringified here, so that no shell has
   to keep a pair of quotes alive across three layers: that is how a fault build
   once failed to compile in silence while a sweep reported that it had found
   nothing. A fault build can only read the file its own build named. */
#define GUMBO_FAULT_STRINGIZE_(x) #x
#define GUMBO_FAULT_STRINGIZE(x) GUMBO_FAULT_STRINGIZE_(x)

#ifdef GUMBO_FAULT_FILE_PATH_RAW
#define GUMBO_FAULT_FILE_PATH GUMBO_FAULT_STRINGIZE(GUMBO_FAULT_FILE_PATH_RAW)
#else
#define GUMBO_FAULT_FILE_PATH "/tmp/gumbo-fault-at"
#endif

/* What a failed extraction answers. The default is the one a caller can act on:
   a badarg, which reaches it instead of a value. The canary build turns it into
   a plain 42, which is what a failure looks like when it is carried into a map
   that cannot tell it from a term -- and then the sweep must fail and name the
   index, or the sweep cannot see a swallow at all. */
#ifdef GUMBO_FAULT_SWALLOW
#define GUMBO_FAULT_FAILURE_VALUE(env) enif_make_int(env, 42)
#else
#define GUMBO_FAULT_FAILURE_VALUE(env) enif_make_badarg(env)
#endif

/* Reads the index from the file named at build time and restarts the count, so
   that each parse in a sweep arms itself. Called from the parse entry point,
   under the same flag. A missing file or an unreadable index means never, so a
   fault build with no sweep running is inert. */
void gumbo_fault_arm(void);

/* 1 when this extraction is the one the sweep asked to fail, 0 otherwise. */
int gumbo_fault_should_fail(void);

#endif

#endif
