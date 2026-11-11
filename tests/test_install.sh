#!/bin/sh
# Install and verify tests. Every test runs install.sh in a throwaway HOME whose path contains a space.
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=$(cd "$HERE/.." && pwd)
FX="$HERE/fixtures"
unset CLAUDE_CONFIG_DIR CODEX_HOME AGENT_HANDOFF_JSON_TOOL

fail() { echo "    $*" >&2; exit 1; }

setup() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/agent-handoff-test.XXXXXX") || exit 1
  trap 'rm -rf "$T"' EXIT
  H="$T/my home"
  mkdir -p "$H/.claude" "$H/.codex"
  export HOME="$H"
}

install() { sh "$KIT/install.sh" "$@" > "$T/install.out" 2>&1; }
verify() { sh "$KIT/verify.sh" "$@" > "$T/verify.out" 2>&1; }
want_pass() { verify "$@" || fail "verify failed: $(cat "$T/verify.out")"; grep -q '^FAIL' "$T/verify.out" && fail "FAIL line: $(cat "$T/verify.out")"; return 0; }
count() { grep -oF -- "$1" "$2" | wc -l | tr -d ' '; }

test_fresh_install_verifies() {
  install || fail "install failed: $(cat "$T/install.out")"
  want_pass
  for c in hooks-installed guard-blocks-env guard-blocks-cat-env guard-allows-example guard-allows-cat-readme \
    handoffs-dir claude-skills claude-hooks codex-skills codex-hooks; do
    grep -q "^PASS $c\$" "$T/verify.out" || fail "no PASS $c: $(cat "$T/verify.out")"
  done
  [ -f "$H/.claude/skills/handoff/SKILL.md" ] && [ -f "$H/.agents/skills/resume/SKILL.md" ] || fail "skills not copied"
}

test_dry_run_writes_nothing() {
  install --dry-run || fail "dry run failed"
  [ ! -e "$H/.config" ] && [ ! -e "$H/.agents" ] && [ ! -e "$H/.claude/settings.json" ] && [ ! -e "$H/.claude/skills" ] \
    || fail "dry run wrote files"
  grep -q 'would' "$T/install.out" || fail "dry run printed no plan"
}

test_rerun_is_safe() {
  install || fail "first install failed"
  install || fail "second install failed: $(cat "$T/install.out")"
  want_pass
  [ "$(count secrets-guard.sh "$H/.claude/settings.json")" -eq 1 ] || fail "claude hook duplicated"
  [ "$(count secrets-guard.sh "$H/.codex/hooks.json")" -eq 1 ] || fail "codex hook duplicated"
  [ ! -d "$H/.config/agent-handoff/backups" ] || fail "re-run made backups: $(ls "$H/.config/agent-handoff/backups")"
}

test_existing_settings_keep_other_entries() {
  printf '%s\n' '{"theme":"dark","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo mine"}]}],"Stop":[{"hooks":[{"type":"command","command":"echo done"}]}]}}' > "$H/.claude/settings.json"
  install || fail "install failed: $(cat "$T/install.out")"
  f="$H/.claude/settings.json"
  grep -qF '"theme"' "$f" && grep -qF 'echo mine' "$f" && grep -qF 'echo done' "$f" || fail "other entries lost: $(cat "$f")"
  grep -qF 'secrets-guard.sh' "$f" || fail "guard hook not added"
  b=$(find "$H/.config/agent-handoff/backups" -name settings.json | head -n 1)
  [ -n "$b" ] && grep -qF 'echo mine' "$b" || fail "no backup of the original settings.json"
  want_pass
}

test_existing_settings_python_fallback() {
  printf '%s\n' '{"theme":"dark","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$H/.claude/settings.json"
  AGENT_HANDOFF_JSON_TOOL=python3 install || fail "install failed: $(cat "$T/install.out")"
  f="$H/.claude/settings.json"
  grep -qF '"theme"' "$f" && grep -qF 'echo mine' "$f" && grep -qF 'secrets-guard.sh' "$f" || fail "merge wrong: $(cat "$f")"
  want_pass
}

test_invalid_settings_not_touched() {
  printf '%s\n' '{ not json' > "$H/.claude/settings.json"
  if install; then fail "install should stop on invalid JSON"; fi
  [ "$(cat "$H/.claude/settings.json")" = '{ not json' ] || fail "invalid settings file was changed"
}

test_settings_symlink_survives() {
  mkdir -p "$T/dot"
  printf '%s\n' '{"theme":"dark"}' > "$T/dot/settings.json"
  ln -s "$T/dot/settings.json" "$H/.claude/settings.json"
  install || fail "install failed: $(cat "$T/install.out")"
  [ -L "$H/.claude/settings.json" ] || fail "symlink replaced"
  grep -qF 'secrets-guard.sh' "$T/dot/settings.json" || fail "change did not land in the link target"
}

test_existing_skill_backed_up() {
  mkdir -p "$H/.claude/skills/handoff"
  echo MINE > "$H/.claude/skills/handoff/SKILL.md"
  install || fail "install failed"
  b=$(find "$H/.config/agent-handoff/backups" -path '*skills/handoff/SKILL.md' | head -n 1)
  [ -n "$b" ] && grep -q MINE "$b" || fail "own skill not backed up"
  grep -q '^name: handoff$' "$H/.claude/skills/handoff/SKILL.md" || fail "skill not replaced"
}

test_guard_blocks_cat_env_allows_readme() {
  install || fail "install failed"
  # run the hook exactly as the agent would: the command string from settings.json, with this HOME
  cmd='sh "$HOME/.config/agent-handoff/hooks/secrets-guard.sh"'
  grep -qF 'secrets-guard.sh' "$H/.claude/settings.json" || fail "no hook entry"
  sh -c "$cmd" < "$FX/bash_cat_env.json" > /dev/null 2> "$T/err"
  [ $? -eq 2 ] || fail "cat .env not blocked"
  grep -q 'secrets-guard: blocked' "$T/err" || fail "no block reason"
  printf '%s\n' '{"cwd":"/p","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat README.md"}}' > "$T/readme.json"
  sh -c "$cmd" < "$T/readme.json" > /dev/null 2>&1
  [ $? -eq 0 ] || fail "cat README.md blocked"
}

test_handoffs_dir_option() {
  install --handoffs-dir "$T/my notes" || fail "install failed: $(cat "$T/install.out")"
  [ -d "$T/my notes" ] || fail "folder not made"
  [ "$(cat "$H/.config/agent-handoff/handoffs-dir")" = "$T/my notes" ] || fail "handoffs-dir file wrong"
  want_pass
}

test_verify_fails_without_hook() {
  install || fail "install failed"
  rm "$H/.config/agent-handoff/hooks/secrets-guard.sh"
  if verify; then fail "verify passed without the hook"; fi
  grep -q '^FAIL hooks-installed' "$T/verify.out" || fail "no FAIL hooks-installed"
}

test_verify_fails_when_settings_lack_hook() {
  install || fail "install failed"
  printf '%s\n' '{"hooks":{}}' > "$H/.claude/settings.json"
  if verify --agent claude; then fail "verify passed without the settings entry"; fi
  grep -q '^FAIL claude-hooks' "$T/verify.out" || fail "no FAIL claude-hooks"
}

test_agent_flag_limits_scope() {
  rm -rf "$H/.codex"
  install --agent claude || fail "install failed"
  [ ! -e "$H/.agents" ] || fail "codex skills installed"
  want_pass --agent claude
  grep -q codex "$T/verify.out" && fail "verify --agent claude mentioned codex"
  return 0
}

pass=0; failed=0
names=$(sed -n 's/^\(test_[a-z0-9_]*\)().*/\1/p' "$0")
for name in $names; do
  if ( setup; "$name" ) < /dev/null; then
    pass=$((pass + 1)); echo "PASS ${name#test_}"
  else
    failed=$((failed + 1)); echo "FAIL ${name#test_}"
  fi
done
echo "test_install: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
