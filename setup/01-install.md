# 01. Install and verify

## Goal

The `handoff` and `resume` skills and the secrets guard run for the agents the user named. Their own settings and hooks stay as they were.

## Do

`KIT` is the absolute path of the folder that holds `README.md`.

1. **Show the plan.** Run the dry run with the agents from step 00 and show the user its output:

   ```sh
   sh "$KIT/install.sh" --dry-run --agent claude    # or codex, or all
   ```

   Add `--handoffs-dir <folder>` if the user named one. The plan lists every file that would be created, replaced or backed up. **Wait for the user's yes.**

2. **Install.**

   ```sh
   sh "$KIT/install.sh" --agent claude    # same flags as the dry run
   ```

   It copies the hook scripts to `~/.config/agent-handoff/hooks/`, copies the two skills into each agent's skills folder, and adds one `PreToolUse` entry to `~/.claude/settings.json` and/or `~/.codex/hooks.json` (under `$CLAUDE_CONFIG_DIR` or `$CODEX_HOME` when those are set). Anything it replaces is copied to `~/.config/agent-handoff/backups/<UTC time>/` first. If a settings file is a symlink, the change lands in the file it points to; tell the user.

3. **Codex only.**
   - If the installer printed a `NOTE` that `config.toml` has inline hooks, add the guard there yourself, in the TOML form the Codex hooks docs give: a `PreToolUse` hook with matcher `.*` that runs `sh "$HOME/.config/agent-handoff/hooks/secrets-guard.sh"`. `verify.sh` reads only `hooks.json`, so its `codex-hooks` check will FAIL in this case. Report that to the user as expected and say why.
   - If a `NOTE` says hooks are turned off in `config.toml`, tell the user and ask before changing it.
   - Codex skips new or changed hooks until they are trusted. Ask the user to start Codex, type `/hooks`, review the secrets guard, and trust it. A later change to the entry needs another review.
   - Confirm `".*"` as the match-everything matcher against the current Codex hooks docs. If Codex rejects it, use the form the docs give, tell the user, and note that `verify.sh` checks for `".*"`.

4. **Windows.** Claude Code runs hook commands through Git Bash. If it cannot find bash, merge `{ "env": { "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe" } }` into `settings.json` with the real path, keeping any `env` keys the user has. Without Git Bash a shell hook runs in PowerShell, where this script fails.

5. **Tell the user the limits of the guard**, in your own words and without softening them:
   - It is a guardrail, not a security boundary. Shell globbing, such as `cat .e*`, gets past it, and so does any command that builds the name at run time. Codex's hooks docs say the same of hooks in general.
   - It has false positives. A command that only mentions a secrets file name, such as `echo .env >> .gitignore`, is blocked, and so is any command that mentions a key-like name, such as `jq .key package.json`, `node -e "console.log(obj.key)"` or `redis-cli GET session.key`. The agent stops and asks.
   - Real secrets still need a secrets manager, file permissions, and the agent's own sandbox and approval settings.

6. **Verify.**

   ```sh
   sh "$KIT/verify.sh"
   ```

   It prints PASS, FAIL or SKIP per check: hooks installed, the guard blocks `.env` and `cat .env`, the guard allows `.env.example` and `cat README.md`, the handoffs folder is writable, and per agent the skills and the hook entry. A SKIP is fine only for an agent the user does not have. Fix every FAIL and run it again. Use `--agent claude` or `--agent codex` if the user declined one.

## Check

Run these in a new session, because agents read hook settings at session start.

- **Skills.** In Claude Code, type `/` and look for `handoff` and `resume`. In Codex, check its skills list.
- **Guard.** In a scratch folder, ask the agent to read a file named `.env`. The file does not need to exist. The call should be blocked with `secrets-guard: blocked access to a secrets file`.
- **Round trip.** In a git repo, say "write a handoff note". A `*-handoff.md` file should appear in `<handoffs folder>/<project>/` with the six sections. Start another new session in the same repo, in the same agent or the other one, and say "resume". It should summarize the note, compare it with `git status`, and ask before doing anything. Delete the test note afterwards if the user wants.

## If it breaks

- **No hook fires in Claude Code.** Run `/hooks` to see what it loaded. Check that `settings.json` is the one in `$CLAUDE_CONFIG_DIR` or `~/.claude`.
- **Codex hooks do not run.** Open `/hooks`. New or changed hooks are skipped until trusted. Check `[features]` in `config.toml`.
- **The installer says a file is not valid JSON.** It changed nothing. Show the user the file and the error. Do not rewrite it.
- **The guard blocks a command that only mentions a secrets file.** Expected. Ask the user. Write such lines with your file tool instead of the shell, since the guard does not read file contents.
- **Every tool call is blocked on Windows** with a message about Git Bash. Install Git for Windows or set `CLAUDE_CODE_GIT_BASH_PATH` as above, then start a new session.

## Docs

- Claude Code hooks: https://code.claude.com/docs/en/hooks
- Claude Code settings: https://code.claude.com/docs/en/settings
- Claude Code skills: https://code.claude.com/docs/en/skills
- Claude Code on Windows and Git Bash: https://code.claude.com/docs/en/setup
- Codex hooks (events, matchers, `/hooks` trust): https://learn.chatgpt.com/docs/hooks
- Codex skills: https://learn.chatgpt.com/docs/build-skills
