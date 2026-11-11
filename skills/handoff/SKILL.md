---
name: handoff
description: Write a handoff note so the next session can pick up this work. Use when the user says handoff, wrap up, save progress, or is about to end or switch sessions.
---

# Handoff

Write one note that lets a fresh session continue without asking what happened.

## Steps

1. Find the handoffs folder. If the file `~/.config/agent-handoff/handoffs-dir` exists, its first line is the folder. Otherwise use `~/.config/agent-handoff/handoffs/`.
2. Name the project: the basename of the git root, or of the current directory if there is no repo.
3. Take the UTC time now as `YYYY-MM-DDTHHMMSSZ`.
4. Write `<folder>/<project>/<timestamp>-handoff.md`. Create the folder if needed.
5. Tell the user the path.

Never put secrets, tokens, or passwords in the note.

## Note format

Use exactly these sections, in this order.

## Goal
What the work is trying to achieve, in one or two lines.

## Done
What is finished and verified. Name the checks that passed.

## In progress
What is half done, and its exact state.

## Next
The next steps, in order. Start with the first command or file to open.

## Open questions
Decisions or facts still unknown, and who can answer.

## Files touched
One path per line, with a few words on what changed.
