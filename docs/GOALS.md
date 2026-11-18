# mirabelle — what I want (goals, v19)

This document says **what** I want, not how. The technical spec (`SPEC.md`) is written from it.

---

## The split

There are two things, and they must stay apart.

| | **The setup** (mirabelle) | **The workflow** (the kb) |
|---|---|---|
| What it is | Plumbing: containers, accounts, identities, sync | How Claude and I work, and what we know |
| Who maintains it | Claude, guided by me, when something is needed | Me and Claude, continuously |
| Where it lives | The `mirabelle` tool | Files in the kb |
| How it changes | Claude changes it from inside a container; I apply the change | By editing files; no tool change needed |

**Rule: mirabelle knows nothing about the workflow.** It does not know what a journal, a decision, a report, a checkpoint or a subagent is. It gives the workflow a safe place to run and a durable place to live, and nothing more.

**Test:** I can change everything about how Claude works without touching mirabelle.

**The reverse is allowed and wanted:** the workflow knows about mirabelle. The kb contains a description of how the setup works, and Claude maintains mirabelle itself (see "mirabelle is maintained by Claude").

---

## Part 1 — The setup (what mirabelle must do)

### Why
1. **Safe autonomy.** Claude can work freely without putting my computer, my network or my secrets at risk.
2. **A durable kb.** Whatever the workflow and knowledge become, they persist, are available everywhere, and are never lost.
3. **Reproducibility.** Backup, duplication on another computer, mirroring. For me only.

### Projects
- A project is a folder containing one or more repos. I organize it freely.
- **One command, any folder.** I go into any folder, call mirabelle with the options I want (account, identity, …), and the container is running with everything needed. Then I use VS Code or the terminal, as I like.
- No separate step to declare a project first.
- **I give the options each time.** mirabelle does not remember them per folder.
- **mirabelle never modifies a project folder and never adds files to it.** It starts a container and mounts the folder inside it; everything mirabelle needs to know about the project is stored on mirabelle's side.
- Different projects can run at the same time. One Claude at a time per project.
- On another computer I clone my repos myself and call mirabelle; the project's conversations come back by its name.
- **Kind of work:** mostly embedded development and standalone programs. Projects need compilers, linkers, unit tests and similar tools, all in the image.
- **No services:** no databases, no docker compose. A project never starts other containers.
- **No hardware:** Claude builds and tests inside the container. I flash and debug boards myself.
- If Claude runs something with a web page, I can open it in my browser.
- **Long runs keep going** when I close VS Code or the terminal. I can list what is running and reattach to see or steer it.

### Three kinds of repo
| Kind | What | Where it lives |
|---|---|---|
| Work code | Project repos for work | Their own remotes |
| Personal code | Project repos of my own | Their own remotes |
| **mirabelle** | The setup **and the kb** | Its own private home, separate from any project repo |

- **Plain git only.** mirabelle's sync is basic `push` and `pull`. No pull requests, no reviews, nothing that depends on GitHub, Gitea or any other hosting service.
- mirabelle's home can therefore be **any plain git remote** (a bare repo on a disk, a NAS or a server). Which one is **not decided yet**, and it must be easy to change later.
- mirabelle's sync and backup never touch project code, and project repos never contain mirabelle or the kb.

### Safety (enforced by the setup, whatever the workflow says)
- Claude **always** runs inside a container. It is **never installed and never runs in WSL or on Windows directly**: not the command-line tool, not the VS Code extension, not for logging in to an account, not for maintaining mirabelle.
- Claude cannot break my PC or OS, or delete files outside what it was given.
- Claude cannot reach resources it was not given: my computer, other projects' files, or my **local network** (except hosts I list, such as my Gitea).
- **The firewall is always on.** Only listed sites are reachable (GitHub, Claude, package sources, plus sites I add). There is no mode without it and no bypass.
- **Secrets: least access.** Claude only gets the secrets that project needs, and can only reach the places that project is allowed to reach.
- Malicious text in a repo, a package or a web page cannot cause harm to my PC, my network or other projects' files.
- **The kb is the one shared thing.** A tricked Claude in one project could write bad instructions into it. This is accepted: every change is versioned, so I can trace and undo it.
- **Normal projects never have any privileges.** They cannot change mirabelle, the firewall, or anything outside their own folder and the kb.
- Inside that boundary, Claude works without asking permission for every step.

### Accounts and identities
- **Claude accounts are for usage limits.** When one runs out I switch to another, and back later.
  - Switching is quick, in the middle of a project.
  - Switching is **per project**: I switch each project myself.
  - Switching loses nothing: the project's conversations continue under the other account.
- Several git identities and credentials (GitHub, Gitea over HTTPS), chosen per project.

### The kb, as the setup sees it
The setup treats the kb as **content it does not interpret**. It guarantees that:
- the kb is **present in every project**, in the same place, readable and writable by Claude;
- there is **one kb** for everything;
- every change to it is **kept and versioned**, so anything can be traced and undone;
- Claude's conversations (transcripts) are **kept forever** alongside it;
- it can hold anything the workflow wants to put there (notes, rules, scripts, tests, tools);
- **there is one kb, not one per project.** Shared and per-project knowledge are folders inside it, organized by the workflow. The whole kb is visible in every project; there is no selection per project;
- the only thing mirabelle tells the workflow is the **project name**.

### mirabelle is maintained by Claude
The main idea: Claude always runs in a container, mirabelle is the plumbing that makes that easy, and **Claude is the one who maintains and updates mirabelle**.

- **mirabelle can be modified from inside a container that mirabelle made.** Claude never needs to run on my PC to work on it.
- **One predefined "upgrade" project** is the only place where mirabelle can be changed. **A single command** runs Claude in a container with all the access needed to upgrade mirabelle.
- **Claude knows how mirabelle works.** The kb holds a "mirabelle" knowledge section: what the setup is, how it is built, how to change it.
- **When something is needed, Claude changes mirabelle in the upgrade project and I apply it.** Example: a tool is missing, I start the upgrade, Claude adds it to the image, and I apply and rebuild.
- **The first install is manual but easy:** clone a repo, run a script. It does not need Claude.
- **One install, then nothing more on my PC.** Once mirabelle is installed, no further installs are needed on the PC. Any tool Claude needs is added to the image, never to the PC.
- **After the first install, I should not have to edit mirabelle by hand.**
- **Nothing Claude changes takes effect until I apply it** (rebuild the container or update the tool) from outside the container.
- **When I apply:** everything that would change is shown, and it needs my yes.
- **Who gets a change:** Claude chooses whether it is for this project only or for all projects, and tells me which.
- Every change to mirabelle is versioned like the rest, so it can be traced and undone.
- **I can survive without Claude.** If an update breaks mirabelle, one manual command returns to the last working version, and a README explains how to operate and repair mirabelle by hand.

### Nothing hidden, everything recoverable
- **Easy does not mean hidden.** mirabelle does nothing behind my back:
  - nothing runs unless I typed a command; no background processes on the PC;
  - every command says what it did, and can show exactly what it runs;
  - everything mirabelle remembers is in plain text files I can read.
- Everything that persists is in visible folders I can inspect.
- **Images** are the one thing kept by Docker rather than in a folder. So:
  - I can list them and delete the ones I no longer need;
  - every build leaves a readable record of what the image contains, in which versions;
  - the tools that matter have fixed versions, so a rebuild on another day or another computer gives the same tools;
  - updating Claude Code and unpinned tools is something I ask for explicitly;
  - after going back to an earlier mirabelle, I can still start from the image that worked, without rebuilding.
- I can rebuild this PC quickly after a reinstall.
- I can duplicate mirabelle and the kb on another computer, or mirror them.
- I use one machine at a time, and moving between them is an **easy sync** (git-like).
- mirabelle and the kb are backed up somewhere other than this PC, in a **private** place (transcripts may contain secrets).
- **Project code stays put.** The sync and backup cover mirabelle and the kb only. Project code moves only through its own repos, when I publish.
  - Accepted consequence: unpublished project work (private commits, uncommitted changes) exists only on this PC. It is not backed up and does not follow me to the other computer.
- **Secrets are re-entered by hand** after a rebuild or on another computer. They are never in the backup or the sync.

### Feel
- A command-line tool called `mirabelle`, with Docker-style commands.
- **One command does one thing.** Two exceptions, both visible in the output: starting a container also sets its firewall, and the upgrade command starts its container and opens Claude.
- VS Code as the main window; it also works from a plain terminal.

---

## Part 2 — The workflow (not part of mirabelle)

The workflow is **free**. It lives in the kb, starts simple, and evolves with me:
- Claude improves it on its own as it learns.
- I guide it by saying what to improve or do differently.
- No approval step. Every change is versioned, so I can follow how it evolved and undo a change.

### Where my thinking is today
These are **current preferences, not requirements**. They are the starting content of the workflow and may all change. mirabelle must not depend on any of them.

- One main agent, using subagents when needed.
- Knowledge per project or per topic, kept outside the project repos: what was done, decisions and why, open items.
- Claude records knowledge automatically as it works, and when I say "remember this".
- Lessons from one project help in the others.
- Pairing in VS Code, and long unattended runs.
- Unattended runs: a report at the end; limits I can set or remove; if usage runs out, stop and wait for me.
- Nothing is published without me. Claude makes private commits as checkpoints, squashed later into commits I approve.
- Claude may maintain companion assets outside the repos (lint, tests) as its own feedback loop.
- A readable list of what changed in the workflow.

---

## Out of scope
- Several Claudes working on the same project at once.
- Steering work from a phone or away from the PC.
- A wall between work and personal.
- Sharing the setup with other people.
- Two machines working at the same time.
- Databases, docker compose, or containers started by a project.
- Hardware access from the container (flashing, debug probes, serial ports).
- Backing up or syncing unpublished project code.

---

## Guarantees and habits

- **Guarantees** are everything under "Safety" in Part 1. The setup enforces them and the workflow cannot weaken them on its own. Claude can prepare a change to mirabelle only in the upgrade project, and it takes effect only after I see it and confirm it when I apply it.
- The guarantees protect my PC, my network and other projects' files. They do **not** protect the kb from a project (accepted, see Safety).
- **Habits** are everything in Part 2. Claude follows them because the workflow says so, and they can change.

**"Nothing is published without me" is a habit.** The setup does not block pushing; the workflow tells Claude not to. This is a known, accepted risk: a mistake or a malicious instruction could still push with the project's git credentials. The way to limit that is to give each project credentials that only reach what that project needs.

## Still open

1. **mirabelle's home.** Which plain git remote holds mirabelle and the kb. Not needed to start the design; it must be easy to set and change.
