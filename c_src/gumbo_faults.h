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
   nothing. A fault build can only read the file its own build named, so being
   told the path is not optional — without it this refuses to build, which is
   the only way a fault build can be wrong loudly instead of reading a path
   nobody wrote. There is deliberately no fallback: an earlier version defaulted
   to /tmp, which is a POSIX path in a header that has no business naming one
   and had to be taught about Windows for it. */
#define GUMBO_FAULT_STRINGIZE_(x) #x
#define GUMBO_FAULT_STRINGIZE(x) GUMBO_FAULT_STRINGIZE_(x)

#ifndef GUMBO_FAULT_FILE_PATH_RAW
#error \
    "a fault build must be told where its index file is: -DGUMBO_FAULT_FILE_PATH_RAW=<path>"
#endif

#define GUMBO_FAULT_FILE_PATH GUMBO_FAULT_STRINGIZE(GUMBO_FAULT_FILE_PATH_RAW)

/* What a failed extraction answers, in the convention every extractor now uses:
   a 0 the caller must turn into a badarg. In the canary build it answers 1
   after storing a plain 42 instead, which is what a failure looks like when it
   is reported as success and carried into a map that cannot tell it from a
   term. The sweep must catch that and name the index, or it cannot see a
   swallow. */
#ifdef GUMBO_FAULT_SWALLOW
#define GUMBO_FAULT_FAILURE(env, out) (*(out) = enif_make_int(env, 42), 1)
#else
#define GUMBO_FAULT_FAILURE(env, out) 0
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
