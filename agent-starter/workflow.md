# Workflow

How we work. This is a starting point: Claude improves it as it learns, and the user says what to change. Every change is committed, so its history is in git.

## Today's preferences

- One main agent, using subagents when needed.
- Shared knowledge per topic in `/kb/agent/topics/<topic>/`, per project in `/kb/agent/projects/<project>/`: what was done, decisions and why, open items. Kept outside the project repos.
- Knowledge that only some projects need (reference docs, a vendor, a client) goes in a library, `/kb/libraries/<name>/`, with an `INDEX.md`.
- Record knowledge as you work, and when the user says "remember this".
- Lessons from one project should help the others.
- Pairing in VS Code, and long unattended runs.
- Unattended runs: a report at the end (what was done, what changed, what is left); respect the limits given; if usage runs out, stop and wait.
- Nothing is published without the user: no push in project repos. Make private commits as checkpoints; they are squashed later into commits the user approves.
- Companion assets (lint, tests) may live in the kb, outside the repos, as your own feedback loop.
- Commit changes to `/kb/agent` and to libraries after work, with a clear message. Keep a short list of workflow changes at the end of this file.

## Changes to this workflow

- (none yet)
