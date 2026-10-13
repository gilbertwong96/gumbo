#!/bin/sh
# The allocation-failure paths are reached only when an allocation fails, and no test can cause one,
# so the tests cause the failure instead: this builds the library twice and runs the sweep twice.
#
# The first run is what makes the second mean anything. With a failure turning into a plain 42 -- a
# value a map cannot tell from a term, which is the defect the plan is about -- the sweep must fail
# and name the index. A green run there would say the sweep cannot see a swallow at all, which is
# the only failure that matters for a sweep like this.
#
# The build happens here rather than being left to mix. mix links its build's priv to this one, and
# those links are made before elixir_make runs make, so a library built by that make is newer than
# the link that points at it. That is how a sweep came to be run, twice, against a library with no
# hook in it while reporting that it had found nothing.
#
# Usage: fault-paths.sh FAULT_FILE

set -e

fault_file=$1

if [ -z "$fault_file" ]; then
  echo "usage: fault-paths.sh FAULT_FILE" >&2
  exit 2
fi

base="-O2 -DGUMBO_TEST_FAULTS -DGUMBO_FAULT_FILE_PATH_RAW=$fault_file"

build() {
  log=$1
  extra=$2

  if ! make clean > /dev/null 2>&1; then
    echo "FAIL: make clean" >&2
    exit 1
  fi

  # CFLAGS is not silenced: a fault build that does not compile is invisible otherwise, and this
  # harness has already spent two cycles learning that. The path is passed unquoted and stringified
  # in the header, so no shell has to keep a pair of quotes alive across three of them.
  if ! make CFLAGS="$base $extra" > "$log" 2>&1; then
    echo "FAIL: the fault build did not compile:" >&2
    cat "$log" >&2
    exit 1
  fi

  if ! nm -g priv/gumbo_nif.so | grep -q gumbo_fault_arm; then
    echo "FAIL: the library that was just built has no hook in it" >&2
    exit 1
  fi
}

canary_log=$(mktemp)
sweep_log=$(mktemp)

status=0

build "$canary_log" -DGUMBO_FAULT_SWALLOW

GUMBO_FAULT_FILE="$fault_file" elixir -S mix test --only fault_paths > "$canary_log" 2>&1 ||
  status=$?

if [ "$status" -eq 0 ]; then
  echo "FAIL: a failure that came back as a plain 42 did not make the sweep fail, so the sweep" >&2
  echo "cannot see a swallow, and its green runs mean nothing:" >&2
  cat "$canary_log" >&2
  status=1
elif ! grep -q 'instead of raising' "$canary_log"; then
  echo "FAIL: the sweep failed in the canary build, but not by finding a swallow:" >&2
  cat "$canary_log" >&2
  status=1
else
  echo "canary: a swallowed failure is caught, and the index is named"
  status=0
fi

if [ "$status" -eq 0 ]; then
  build "$sweep_log"
  GUMBO_FAULT_FILE="$fault_file" elixir -S mix test --only fault_paths || status=$?
fi

rm -f "$canary_log" "$sweep_log" "$fault_file" "$fault_file.armed"
make clean > /dev/null 2>&1 || true
make > /dev/null 2>&1 || true

exit "$status"
