#!/bin/sh
# Shared helper for secrets-guard.sh. Sourced, not run. POSIX sh, no jq.

# Hook JSON from stdin into $INPUT.
read_input() {
  INPUT=$(cat)
}
