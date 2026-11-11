#!/bin/sh
# Install agent-handoff: the handoff and resume skills and the secrets guard hook.
# Usage: sh install.sh [--dry-run] [--agent claude|codex|all] [--handoffs-dir PATH]
# POSIX sh. Safe to run again. Anything it would change is copied to
# ~/.config/agent-handoff/backups/<UTC timestamp>/ first.

usage() {
  echo "usage: sh install.sh [--dry-run] [--agent claude|codex|all] [--handoffs-dir PATH]" >&2
  exit "${1:-2}"
}
die() { echo "error: $*" >&2; exit 1; }

DRY=0
AGENT=all
HDIR=
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --agent) [ $# -ge 2 ] || usage; AGENT=$2; shift ;;
    --handoffs-dir) [ $# -ge 2 ] || usage; HDIR=$2; shift ;;
    -h | --help) usage 0 ;;
    *) usage ;;
  esac
  shift
done
case "$AGENT" in claude | codex | all) ;; *) usage ;; esac

KIT=$(cd "$(dirname "$0")" && pwd)
CFG=$HOME/.config/agent-handoff
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
CODEX_SKILLS=$HOME/.agents/skills
BACKUP=$CFG/backups/$(date -u +%Y%m%dT%H%M%SZ)

real() { [ "$DRY" -eq 0 ]; }

# JSON merge tool: jq if present, else python3. AGENT_HANDOFF_JSON_TOOL forces one (used by the tests).
TOOL=${AGENT_HANDOFF_JSON_TOOL:-}
if [ -z "$TOOL" ]; then
  if command -v jq > /dev/null 2>&1; then TOOL=jq
  elif command -v python3 > /dev/null 2>&1; then TOOL=python3
  fi
fi

TMPF=$(mktemp "${TMPDIR:-/tmp}/agent-handoff-install.XXXXXX") || die "cannot make a temp file"
trap 'rm -f "$TMPF"' EXIT

backup() {
  case "$1" in
    "$HOME"/*) rel=${1#"$HOME"/} ;;
    *) rel=$(printf '%s' "$1" | sed 's|^/*||') ;;
  esac
  if real; then
    mkdir -p "$BACKUP/$(dirname "$rel")" && cp -RP "$1" "$BACKUP/$rel" || die "backup of $1 failed"
    echo "backed up $1 to $BACKUP/$rel"
  else
    echo "would back up $1 to $BACKUP/$rel"
  fi
}

copy_file() { # copy_file <src> <dest>
  if [ -f "$2" ] && cmp -s "$1" "$2"; then echo "kept $2"; return; fi
  [ -e "$2" ] && backup "$2"
  if real; then
    mkdir -p "$(dirname "$2")" && cp "$1" "$2" || die "cannot write $2"
    echo "installed $2"
  else
    echo "would install $2"
  fi
}

copy_skill() { # copy_skill <name> <skills dir>
  src=$KIT/skills/$1
  dest=$2/$1
  if [ -L "$dest" ]; then echo "kept $dest (a link; not replaced)"; return; fi
  if [ -d "$dest" ] && diff -r "$src" "$dest" > /dev/null 2>&1; then echo "kept $dest"; return; fi
  [ -e "$dest" ] && backup "$dest"
  if real; then
    rm -rf "$dest" && mkdir -p "$2" && cp -R "$src" "$dest" || die "cannot write $dest"
    echo "installed $dest"
  else
    echo "would install $dest"
  fi
}

# merged <target> <fragment>: prints the target with the fragment's hook groups
# added to the same event arrays, unless a group there already runs the same command.
merged() {
  case "$TOOL" in
    jq)
      jq -s '
        .[0] as $mine | .[1] as $ours
        | reduce ($ours.hooks | keys_unsorted[]) as $ev ($mine;
            .hooks[$ev] = ((.hooks[$ev] // []) as $cur
              | $cur + [ $ours.hooks[$ev][]
                  | select(.hooks[0].command as $c
                      | ($cur | map(.hooks[]?.command) | index($c)) == null) ]))
      ' "$1" "$2" ;;
    python3)
      python3 -I -c '
import json, sys
mine = json.load(open(sys.argv[1]))
ours = json.load(open(sys.argv[2]))
if not isinstance(mine, dict):
    raise SystemExit("not a JSON object")
hooks = mine.setdefault("hooks", {})
for ev, groups in ours["hooks"].items():
    cur = hooks.setdefault(ev, [])
    have = {h.get("command") for g in cur for h in g.get("hooks", [])}
    for g in groups:
        if g["hooks"][0]["command"] not in have:
            cur.append(g)
print(json.dumps(mine, indent=2))
' "$1" "$2" ;;
    *) return 1 ;;
  esac
}

merge_hooks() { # merge_hooks <settings file> <fragment>
  if [ ! -e "$1" ]; then
    if real; then
      mkdir -p "$(dirname "$1")" && cp "$2" "$1" || die "cannot write $1"
      echo "created $1"
    else
      echo "would create $1"
    fi
    return
  fi
  if grep -qF 'agent-handoff/hooks/secrets-guard.sh' "$1"; then echo "kept $1 (hook already there)"; return; fi
  [ -n "$TOOL" ] || die "need jq or python3 to merge $1. Merge $2 into it by hand."
  merged "$1" "$2" > "$TMPF" 2> /dev/null && [ -s "$TMPF" ] || die "$1 is not valid JSON, or could not be merged. Not changed. Fix it or merge $2 into it by hand."
  backup "$1"
  if real; then
    # '>' writes through a symlinked settings file; mv would replace the link.
    cat "$TMPF" > "$1" || die "cannot write $1"
    echo "updated $1 (hook added, your other entries kept)"
  else
    echo "would update $1 (add the hook, keep your other entries)"
  fi
}

present() { # present <command> <dir>
  command -v "$1" > /dev/null 2>&1 || [ -d "$2" ]
}

do_claude() {
  echo "-- Claude Code ($CLAUDE_DIR)"
  copy_skill handoff "$CLAUDE_DIR/skills"
  copy_skill resume "$CLAUDE_DIR/skills"
  merge_hooks "$CLAUDE_DIR/settings.json" "$KIT/templates/claude-hooks.json"
}

do_codex() {
  echo "-- Codex ($CODEX_DIR)"
  copy_skill handoff "$CODEX_SKILLS"
  copy_skill resume "$CODEX_SKILLS"
  if [ -f "$CODEX_DIR/config.toml" ] && grep -qE '^[[:space:]]*\[\[?hooks([].]|$)' "$CODEX_DIR/config.toml"; then
    echo "NOTE: $CODEX_DIR/config.toml has inline hooks. hooks.json not touched."
    echo "      Add the secrets-guard entry there by hand (see setup/01-install.md). verify.sh will FAIL codex-hooks until you do."
  else
    merge_hooks "$CODEX_DIR/hooks.json" "$KIT/templates/codex-hooks.json"
  fi
  if [ -f "$CODEX_DIR/config.toml" ] && grep -qE '^[[:space:]]*(codex_)?hooks[[:space:]]*=[[:space:]]*false' "$CODEX_DIR/config.toml"; then
    echo "NOTE: $CODEX_DIR/config.toml turns hooks off. Not changed; ask yourself before enabling them."
  fi
  echo "NOTE: Codex skips new or changed hooks until you trust them. Start Codex, type /hooks, review the secrets guard, trust it."
}

[ "$DRY" -eq 1 ] && echo "dry run: nothing will be written"

echo "-- hooks ($CFG/hooks)"
copy_file "$KIT/hooks/lib.sh" "$CFG/hooks/lib.sh"
copy_file "$KIT/hooks/secrets-guard.sh" "$CFG/hooks/secrets-guard.sh"

echo "-- handoffs folder"
if real; then mkdir -p "$CFG/handoffs" || die "cannot make $CFG/handoffs"; fi
echo "default folder: $CFG/handoffs"
if [ -n "$HDIR" ]; then
  printf '%s\n' "$HDIR" > "$TMPF"
  copy_file "$TMPF" "$CFG/handoffs-dir"
  if real; then mkdir -p "$HDIR" || die "cannot make $HDIR"; fi
fi

case "$AGENT" in
  claude | all) if [ "$AGENT" = claude ] || present claude "$CLAUDE_DIR"; then do_claude; else echo "-- Claude Code: not found, skipped"; fi ;;
esac
case "$AGENT" in
  codex | all) if [ "$AGENT" = codex ] || present codex "$CODEX_DIR"; then do_codex; else echo "-- Codex: not found, skipped"; fi ;;
esac

echo "done. Next: sh verify.sh"
