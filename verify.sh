#!/bin/sh
# Verify the agent-handoff install. Usage: sh verify.sh [--agent claude|codex|all]
# Prints PASS/FAIL/SKIP per check; exits 1 if any check failed. POSIX sh, no jq.

agent=all
if [ "$1" = "--agent" ]; then
  agent=$2
  shift 2
fi
case "$agent" in
  claude | codex | all) ;;
  *) echo "usage: sh verify.sh [--agent claude|codex|all]" >&2; exit 2 ;;
esac

CFG=$HOME/.config/agent-handoff
HOOKS="$CFG/hooks"
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
CODEX_SKILLS=$HOME/.agents/skills
FAILS=0

TMP=$(mktemp -d "${TMPDIR:-/tmp}/agent-handoff-verify.XXXXXX") || { echo "FAIL setup: cannot make temp dir"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

pass() { echo "PASS $1"; }
skip() { echo "SKIP $1: $2"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS + 1)); }

# agent_present <command> <dir>
agent_present() { command -v "$1" > /dev/null 2>&1 || [ -d "$2" ]; }

# ---- hooks-installed
missing=
for f in secrets-guard.sh; do
  [ -f "$HOOKS/$f" ] || missing="$missing${missing:+, }$f"
done
if [ -n "$missing" ]; then fail hooks-installed "missing under $HOOKS: $missing"; else pass hooks-installed; fi

# ---- guard
guard_rc() { # guard_rc <Read|Bash> <file path or command>; prints the guard's exit code
  if [ "$1" = Bash ]; then
    printf '{"cwd":"/p","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}\n' "$2" > "$TMP/guard.json"
  else
    printf '{"cwd":"/p","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"%s"}}\n' "$2" > "$TMP/guard.json"
  fi
  sh "$HOOKS/secrets-guard.sh" < "$TMP/guard.json" > /dev/null 2>&1
  echo $?
}
guard_check() { # guard_check <id> <want> <tool> <input>
  rc=$(guard_rc "$3" "$4")
  if [ "$rc" = "$2" ]; then pass "$1"; else fail "$1" "$3 of '$4' exited $rc, want $2"; fi
}
if [ ! -f "$HOOKS/secrets-guard.sh" ]; then
  for id in guard-blocks-env guard-blocks-cat-env guard-allows-example guard-allows-cat-readme; do
    fail "$id" "secrets-guard.sh missing"
  done
else
  guard_check guard-blocks-env 2 Read /x/app/.env
  guard_check guard-blocks-cat-env 2 Bash "cat .env"
  guard_check guard-allows-example 0 Read /x/app/.env.example
  guard_check guard-allows-cat-readme 0 Bash "cat README.md"
fi

# ---- handoffs folder
dir=$CFG/handoffs
if [ -f "$CFG/handoffs-dir" ]; then dir=$(head -n 1 "$CFG/handoffs-dir"); fi
if [ -d "$dir" ] && [ -w "$dir" ]; then pass handoffs-dir; else fail handoffs-dir "$dir is not a writable folder"; fi

# ---- agents
# json_strings <file>: one line per string value, "<key path><TAB><value>"; keys
# joined with "/", array elements as [index]. Prints INVALID and nothing else on
# bad structure (odd quotes, mismatched or unbalanced brackets, no top object).
json_strings() {
  tr '\n\r' '  ' < "$1" | awk '
    function dec(s) { gsub(/\002/, "\"", s); gsub(/\001/, "\\", s); return s }
    BEGIN { RS = "\001" }
    {
      s = $0
      gsub(/\\\\/, "\001", s)
      gsub(/\\"/, "\002", s)
      n = split(s, part, "\"")
      if (n % 2 == 0) { print "INVALID"; exit }
      d = 0; seen = 0; nout = 0
      for (j = 1; j <= n; j++) {
        if (j % 2) {
          m = length(part[j])
          for (c = 1; c <= m; c++) {
            ch = substr(part[j], c, 1)
            if (ch == "{" || ch == "[") {
              if (d == 0 && (seen || ch != "{")) { print "INVALID"; exit }
              d++; seen = 1; stk[d] = ch; ck[d] = ""; idx[d] = 0
            } else if (ch == "}" || ch == "]") {
              if (d < 1 || stk[d] != (ch == "}" ? "{" : "[")) { print "INVALID"; exit }
              d--
            } else if (ch == "," && d > 0 && stk[d] == "[") idx[d]++
          }
        } else if (part[j + 1] ~ /^[ \t]*:/) {
          if (d < 1 || stk[d] != "{") { print "INVALID"; exit }
          ck[d] = dec(part[j])
        } else {
          p = ""
          for (i = 1; i <= d; i++) p = p (i > 1 ? "/" : "") (stk[i] == "[" ? "[" idx[i] "]" : ck[i])
          out[++nout] = p "\t" dec(part[j])
        }
      }
      if (d != 0 || !seen) { print "INVALID"; exit }
      for (i = 1; i <= nout; i++) print out[i]
    }'
}

# hooks_check <id> <file> <PreToolUse matcher>: an entry with that matcher runs secrets-guard.sh.
hooks_check() {
  id=$1; file=$2; matcher=$3
  if [ ! -f "$file" ]; then fail "$id" "$file missing"; return; fi
  json_strings "$file" > "$TMP/json.$id"
  if [ "$(head -n 1 "$TMP/json.$id")" = INVALID ] || [ ! -s "$TMP/json.$id" ]; then
    fail "$id" "$file: invalid JSON"; return
  fi
  MT=$matcher C1="sh \"\$HOME/.config/agent-handoff/hooks/secrets-guard.sh\"" C2="sh \"$HOOKS/secrets-guard.sh\"" \
    awk -F'\t' '
      BEGIN { mt = ENVIRON["MT"]; c1 = ENVIRON["C1"]; c2 = ENVIRON["C2"]; pre = "^hooks/PreToolUse/\\[[0-9]+\\]/" }
      $1 ~ pre "matcher$" { e = $1; sub(/^hooks\/PreToolUse\/\[/, "", e); sub(/\].*/, "", e); matcher[e] = $2 }
      $1 ~ pre "hooks/\\[[0-9]+\\]/command$" && ($2 == c1 || $2 == c2) {
        e = $1; sub(/^hooks\/PreToolUse\/\[/, "", e); sub(/\].*/, "", e); cmd[e] = 1 }
      END { for (e in cmd) if ((e in matcher) && matcher[e] == mt) exit 0; exit 1 }' "$TMP/json.$id" \
    && pass "$id" || fail "$id" "$file has no PreToolUse entry with matcher $matcher running secrets-guard.sh"
}

# skills_check <id> <skills dir>
skills_check() {
  miss=
  for s in handoff resume; do
    grep -qx "name: $s" "$2/$s/SKILL.md" 2> /dev/null || miss="$miss${miss:+, }$s"
  done
  if [ -n "$miss" ]; then fail "$1" "no SKILL.md for: $miss under $2"; else pass "$1"; fi
}

if [ "$agent" = all ] || [ "$agent" = claude ]; then
  if [ "$agent" = claude ] || agent_present claude "$CLAUDE_DIR"; then
    skills_check claude-skills "$CLAUDE_DIR/skills"
    hooks_check claude-hooks "$CLAUDE_DIR/settings.json" "*"
  else
    skip claude-skills "claude not installed"
    skip claude-hooks "claude not installed"
  fi
fi

if [ "$agent" = all ] || [ "$agent" = codex ]; then
  if [ "$agent" = codex ] || agent_present codex "$CODEX_DIR"; then
    skills_check codex-skills "$CODEX_SKILLS"
    hooks_check codex-hooks "$CODEX_DIR/hooks.json" ".*"
  else
    skip codex-skills "codex not installed"
    skip codex-hooks "codex not installed"
  fi
fi

[ "$FAILS" -eq 0 ]
