#!/bin/sh
# Runs every tests/test_*.sh; exits non-zero if any fail.
here=$(cd "$(dirname "$0")" && pwd)
rc=0
for t in "$here"/test_*.sh; do
  sh "$t" || rc=1
done
exit $rc
