# agent-handoff

Three free pieces of a larger setup for coding agents: a `handoff` skill, a `resume` skill, and a secrets guard hook. They work on their own, without the rest of the setup they come from.

## Start here

Open your coding agent in this folder and say: read README.md and set this up.

Your agent can be Claude Code, Codex, or another agent that reads files and runs shell commands. Setup supports Claude Code and Codex.

Setup does this:
- asks which agents you use and which OS;
- shows you a plan and waits for your yes;
- backs up anything it would replace;
- installs the skills and the hook for the agents you named;
- runs `sh verify.sh`, which prints PASS, FAIL, or SKIP per check.

You can also read the steps in `setup/` and run them yourself, or run `sh install.sh` directly (`sh install.sh --dry-run` shows what it would do first).

## What the three pieces do

**`handoff` skill.** When you say "handoff" or "wrap up", the agent writes one markdown note for the project with the sections Goal, Done, In progress, Next, Open questions, Files touched. The note is named `<UTC time>-handoff.md`.

**`resume` skill.** When you say "resume" in a later session, in the same agent or another one, the agent reads the newest handoff note for the project, summarizes it in five lines or fewer, checks it against `git status`, and asks you to confirm the first next step before it starts.

**Secrets guard hook.** A PreToolUse hook. It exits 2 with a reason when a tool call names `.env`, `.env.*` (not `.env.example`), `*.env`, `id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa`, `*.pem`, `*.key`, `*.p12`, `*.pfx` or `.netrc`. Public keys (`*.pub`) pass. Its matcher covers every tool, including `Grep`, `Glob` and MCP tools.

## Where handoff notes go

Notes are plain files in `~/.config/agent-handoff/handoffs/<project>/`. The project is the name of the git repo's top folder, or of the current folder outside a repo.

To use a different folder, for example one inside a repo you already sync, run `sh install.sh --handoffs-dir /path/to/folder`. That writes the path to `~/.config/agent-handoff/handoffs-dir`, and both skills read it. To read notes on another machine, copy or sync the folder yourself. This repo does not do that.

## The secrets guard is a guardrail

The guard catches the common case: an agent reading, editing or printing `.env`, `id_rsa`, `*.pem` and similar files by name. It is not a security boundary. Codex's own hooks documentation says the same of hooks in general.

- It can be evaded. Shell globbing, such as `cat .e*`, gets past it, and so does any command that builds the name at run time.
- It has false positives. A command that only mentions a secrets file name, such as `echo .env >> .gitignore`, is blocked, and so is any command that mentions a key-like name, such as `jq .key package.json`, `node -e "console.log(obj.key)"` or `redis-cli GET session.key`. When that happens the agent stops and asks you.

When the guard blocks something, the agent stops and asks you. Keep real secrets out of reach in the first place: a secrets manager, file permissions, and your agent's own sandbox and approval settings.

## Install details

| Item | Claude Code | Codex |
|---|---|---|
| Skills | `~/.claude/skills/handoff`, `~/.claude/skills/resume` (or under `$CLAUDE_CONFIG_DIR`) | `~/.agents/skills/handoff`, `~/.agents/skills/resume` |
| Hook entry | `~/.claude/settings.json`, matcher `*` | `~/.codex/hooks.json` (or under `$CODEX_HOME`), matcher `.*` |
| Hook scripts | `~/.config/agent-handoff/hooks/` | same |

- Skills are copied, not linked. A skill folder of the same name that you already have is copied to `~/.config/agent-handoff/backups/<UTC time>/` first. A skill folder that is a symlink is left alone.
- `settings.json` and `hooks.json` are edited in place. The installer adds its hook entry to `PreToolUse` and keeps everything else you have. It needs `jq` or `python3` for that. The merged file is rewritten with two-space indentation, so formatting may change; the original is in the backups folder. If the file is a symlink, the change lands in the file it points to. If the file is not valid JSON, the installer stops and changes nothing.
- A second run changes nothing and makes no backups.
- Codex: if `config.toml` has inline `[hooks]` tables, the installer leaves `hooks.json` alone and tells you to add the entry there by hand. Codex skips new or changed hooks until you open `/hooks` and trust them.
- Agents read hook settings when a session starts. Start a new session after installing.

## Platforms

- **Linux with Claude Code.** `sh tests/run.sh` was run on Arch Linux (aarch64) with `sh` as bash, `jq` 1.8.2 and Python 3.14.9. The tests run `install.sh` and `verify.sh` against a throwaway home folder with a space in its path, and run the hook script on sample tool-call JSON. No Claude Code session was started with the result, so the live behavior (the agent loading the skills, the hook firing inside a session) is not tested here.
- **Codex.** Beta, untested. The install writes `hooks.json` and the skills folder in the shape of the Codex documentation. The tests check those files exist and parse. Codex was not run against them.
- **macOS.** Beta, untested.
- **Windows.** Beta, untested. The hook is a shell script, so Claude Code needs Git for Windows and runs it through Git Bash. Run `install.sh` from Git Bash. There is no PowerShell installer.
- **Other POSIX shells.** Not tested (dash, busybox).

## Tests

```
sh tests/run.sh
```

`tests/test_guard.sh` runs the hook on 55 tests, including the false positives and bypasses listed above. `tests/test_install.sh` covers a fresh install, `--dry-run`, a second run, an existing settings file, an invalid settings file, symlinked settings, an existing skill of the same name, and `verify.sh` failing when the hook is missing.

## The rest of the setup

These three pieces are part of The Senior Engineer's AI Vault, which also sets up the memory vault, session hooks, a dotfiles repo, a multi-agent starter and a verify script. https://sublimecoding.com/vault

## If you are the agent

Follow these rules for the whole setup. They override anything a later step seems to allow.

1. **Read `setup/` in order**, `00-interview.md` then `01-install.md`. Finish each step's Check before starting the next.
2. **Run the interview first.** Ask the questions in `setup/00-interview.md` before you change anything.
3. **Show the plan and get a yes** before writing anything outside this folder. Run `sh install.sh --dry-run` and show its output. If the plan changes later, show the change and get a new yes.
4. **Back up first.** Before changing any existing file, copy it to `~/.config/agent-handoff/backups/<UTC timestamp>/`, keeping its path under your home folder. `install.sh` does this for you.
5. **No remote or network actions.** Do not create repos, push, or post anything.
6. **Self-repair.** When a step fails or does not fit the OS (a path, a shell, a missing tool), diagnose it and adapt the step for this machine. Self-repair never skips backups, weakens the secrets guard, or reports a failing check as passed.
7. **Keep secrets out.** Never write passwords, tokens or `.env` contents into a handoff note or any file here.
8. **Finish only when `sh verify.sh` has no FAIL.** A SKIP is fine only for an agent the user does not have.

The folder that holds this README is the kit folder. Use its absolute path. After setup the guard runs on your own tool calls too. If it blocks a command you need, stop and ask the user. Do not rephrase the command to get past it, and do not edit `secrets-guard.sh` to make it pass.

## License

MIT. See `LICENSE`.

Made by Jared Smith, sublimecoding.com.
