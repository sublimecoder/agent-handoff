# 00. Interview

## Goal

Know which agents and which OS before you change anything.

## Do

Ask the user these, one message, and wait for the answers:

1. **Which agents do you use?** Claude Code, Codex, both, or another agent. Setup supports Claude Code and Codex. For another agent, tell the user the skills are plain `SKILL.md` folders in `skills/` that they can copy to that agent's skills folder, and the hook is not wired for it.
2. **Which OS?** Linux, macOS, or Windows. On Windows, check that Git for Windows is installed and run everything in Git Bash. Tell the user Windows is untested.
3. **Where should handoff notes go?** The default is `~/.config/agent-handoff/handoffs/`. The user may name another folder, for example one inside a repo they already sync. A folder they name is passed to the installer as `--handoffs-dir`.

Then check the machine:

```sh
command -v git jq python3 claude codex
```

The installer needs `jq` or `python3` when a `settings.json` or `hooks.json` already exists. `git` is needed by the skills to name the project, but they work without a repo.

## Check

You have the agent list, the OS and the handoffs folder. Nothing is changed yet.
