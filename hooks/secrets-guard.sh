#!/bin/sh
# PreToolUse: block access to secrets files. Exit 2 + reason on stderr blocks
# in Claude Code and Codex. Every string value inside tool_input is checked,
# at any nesting depth, for any tool name, except values under content or
# session keys (`skip` below) and a few per-tool prose or regex fields
# (`toolskip` below). Patch text (apply_patch input, or element 2 of a
# tool_input.command array whose element 1 is "apply_patch") is checked only
# on its file-header lines. Malformed input is allowed. A token
# ending .pub or whose last path component ends .env.example is exempt; every
# other token is checked. A .pem/.key/.p12/.pfx token passes only when a
# source-code suffix follows (messages.key.ts). Commands are not shell-parsed
# for exemptions: a key-like word such as jq .key or obj.key blocks. Each
# checked value is read twice: split at shell punctuation, and again with
# quotes and backslashes removed and one-character classes collapsed, because
# the shell joins quoted pieces (.e""nv) and expands [v] to v. Globs with * or
# ?, longer classes and names built at run time are not resolved. No helper file is sourced, so a missing
# lib.sh cannot turn the guard off, and a failed scan blocks.
INPUT=$(cat)

# The JSON is walked structurally: escaped backslashes and quotes are masked
# first, so splitting on '"' alternates structural text (odd parts) and string
# bodies (even parts). A string followed by ':' is a key. ck[d] is the current
# key at container depth d, so a value's key path is ck[1..d]. tool_name is
# read only at depth 1 and may follow tool_input, so values are collected
# during the walk and emitted at the end.
tokens=$(printf '%s' "$INPUT" | tr '\n\r' '  ' | awk '
  function decode(s,   out, h, n) {
    gsub(/\\n/, "\n", s); gsub(/\\t/, "\t", s); gsub(/\\r/, "\r", s)
    gsub(/\\[bf]/, " ", s); gsub(/\\\//, "/", s)
    out = ""
    while (match(s, /\\u00[0-7][0-9a-fA-F]/)) {
      h = tolower(substr(s, RSTART + 4, 2))
      n = index("0123456789abcdef", substr(h, 1, 1)) * 16 \
        + index("0123456789abcdef", substr(h, 2, 1)) - 17
      out = out substr(s, 1, RSTART - 1) sprintf("%c", n)
      s = substr(s, RSTART + RLENGTH)
    }
    s = out s
    gsub(/\001/, "\\", s); gsub(/\002/, "\"", s)
    return s
  }
  function in_scope(   i) {
    if (d < 1 || ck[1] != "tool_input") return 0
    for (i = 1; i <= d; i++) if (ck[i] in skip) return 0
    return 1
  }
  function emit(v, patch,   n, a, i, line) {
    if (patch) {
      n = split(v, a, "\n")
      for (i = 1; i <= n; i++) {
        line = a[i]
        if (sub(/^[^!-~]*\*\*\*[ \t]*(Add File|Update File|Delete File|Move to):[ \t]*/, "", line)) print line
      }
      return
    }
    n = split(v, a, "[][;|&<>()$`\"\047, \t\r\n]+")
    for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
    w = v
    gsub(/\\\n/, "", w)
    gsub("[\"\047\\\\]", "", w)
    while (match(w, /\[.\]/)) w = substr(w, 1, RSTART - 1) substr(w, RSTART + 1, 1) substr(w, RSTART + 3)
    if (w != v) {
      n = split(w, a, "[][{}:;|&<>()$`, \t\r\n]+")
      for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
    }
  }
  BEGIN {
    RS = "\001"
    split("content new_string old_string cwd transcript_path session_id model hook_event_name tool_use_id permission_mode", k, " ")
    for (i in k) skip[k[i]] = 1
    # tool:path under tool_input; [] is any array element.
    split("Agent:prompt Agent:description Task:prompt Task:description Bash:description NotebookEdit:new_source TodoWrite:todos/[]/activeForm ExitPlanMode:plan WebSearch:query WebFetch:prompt Grep:pattern", k, " ")
    for (i in k) toolskip[k[i]] = 1
  }
  {
    s = $0
    gsub(/\\\\/, "\001", s)
    gsub(/\\"/, "\002", s)
    n = split(s, part, "\"")
    d = 0; nv = 0; tool = ""
    for (j = 1; j <= n; j++) {
      if (j % 2) {
        m = length(part[j])
        for (c = 1; c <= m; c++) {
          ch = substr(part[j], c, 1)
          if (ch == "{" || ch == "[") { d++; ck[d] = ""; arr[d] = (ch == "["); idx[d] = 0; first[d] = "" }
          else if ((ch == "}" || ch == "]") && d > 0) d--
          else if (ch == "," && d > 0 && arr[d]) idx[d]++
        }
      } else if (part[j + 1] ~ /^[ \t]*:/) {
        if (d > 0) ck[d] = decode(part[j])
      } else {
        # Decode only what is used: skipped values (file content) can be large.
        scoped = in_scope()
        if (!scoped && !(d == 1 && ck[1] == "tool_name") && !(d > 0 && arr[d] && idx[d] == 0)) continue
        v = decode(part[j])
        if (d == 1 && ck[1] == "tool_name") tool = v
        else if (scoped) {
          nv++; val[nv] = v; path[nv] = ""
          for (i = 2; i <= d; i++) path[nv] = path[nv] (i > 2 ? "/" : "") (arr[i] ? "[]" : ck[i])
          ispatch[nv] = (d == 3 && ck[2] == "command" && arr[3] && idx[3] == 1 && first[3] == "apply_patch")
        }
        if (d > 0 && arr[d] && idx[d] == 0) first[d] = v
      }
    }
    for (i = 1; i <= nv; i++) {
      if ((tool ":" path[i]) in toolskip) continue
      emit(val[i], tool == "apply_patch" || ispatch[i])
    }
  }') || {
  echo "secrets-guard: the scan failed, so this call is blocked. Run verify.sh, or ask the user." >&2
  exit 2
}

[ -n "$tokens" ] || exit 0
names=$(printf '%s\n' "$tokens" | tr '[:upper:]' '[:lower:]' \
  | awk '
      $0 == "" { next }
      /\.pub$/ { next }
      { n = split($0, p, "/") }
      p[n] ~ /\.env\.example$/ { next }
      # process.env.X / import.meta.env.X are code, not files
      /^(process|import\.meta)\.env(\.[a-z0-9_]+)*$/ { next }
      # a source file named after a key (messages.key.ts) is not a key
      { sub(/\.(pem|key)\.(ts|tsx|js|jsx|mjs|cjs|py|rb|go|rs|ex|exs)$/, "") }
      { print }') || {
  echo "secrets-guard: the scan failed, so this call is blocked. Run verify.sh, or ask the user." >&2
  exit 2
}
match=$(printf '%s\n' "$names" \
  | grep -Eo '(^|[^a-z0-9_.-])\.env([^a-z0-9_]|$)|[a-z0-9_-]\.env([^a-z0-9_]|$)|(^|[^a-z0-9])id_(rsa|ed25519|ecdsa|dsa)|\.(pem|key|p12|pfx)([^a-z0-9_]|$)|(^|[^a-z0-9_])\.netrc([^a-z0-9_]|$)' \
  | head -n 1)
[ -n "$match" ] || exit 0

match=$(printf '%s' "$match" | sed -E 's/^[^a-z._]+//; s/[^a-z0-9]+$//')
echo "secrets-guard: blocked access to a secrets file ($match). Ask the user before touching it." >&2
exit 2
