# mirabelle — design spec (v2.1, as built)

Written from `GOALS.md` v19.

**Status:** built and tested in a Linux sandbox with real Docker (see §13 for what was and was not tested). `REFERENCE.md` has the glossary, every command in full, and the map of files. The code is in `bin/`, `lib/`, `lock/`, `image/`.

---

## 1. The design in one page

- **One command in any folder.** `cd` into a folder, run `mirabelle run -a <account> -i <identity> [-l <library>]...`, and its container is up with the kb (the agent and the libraries you picked), the account and the identity. Then `mirabelle code` or `mirabelle claude`.
- **One single container per project**, created with plain `docker run`. No helper containers.
- **The firewall is always on.** It is inside the container but out of Claude's reach: mirabelle sets it from the PC when the container starts.
- **Normal projects never have any privileges.** They cannot see or change mirabelle.
- **One predefined upgrade project.** `mirabelle upgrade` is the only way Claude can change mirabelle, and nothing takes effect until you run `mirabelle apply`.
- **Git repos**, pushed and pulled with plain git to one home:
  - **setup**: the `mirabelle` tool, the image, the lists (sites, libraries).
  - **kb/agent**: the shared part of the kb (workflow, Claude's configuration, shared knowledge). mirabelle does not interpret it.
  - **kb/libraries/<name>**: one repo per library, extra knowledge picked per project with `-l`.
  - **sessions**: Claude's conversations per project.
- **Accounts are tokens.** Conversations belong to the project, so switching account loses nothing.
- **Nothing is written into your project folders.**
- **On the PC:** Docker, git, VS Code and mirabelle. Nothing else, ever.

### Rule 1: nothing hidden
- Nothing runs unless you typed a command. No background process, no timer, no service.
- Every command says what it did, in plain words.
- `-v` shows the exact `docker` and `git` commands. `--dry-run` shows them without running them.
- mirabelle remembers nothing about a folder. You give the options each time.
- What mirabelle stores is plain text under `~/mirabelle/`.
- The agent, the libraries and sessions are ordinary git repos.

### Rule 2: one command does one thing
- A command never does a second thing quietly. If something else is needed, it says which command to run next.
- Two exceptions, both printed in the output:
  - `mirabelle run` starts the container **and** sets its firewall. A container must never exist without it.
  - `mirabelle upgrade` starts the upgrade container **and** opens Claude in it.

---

## 2. Folders on the PC

```
~/mirabelle/
├── setup/          repo: the tool. The PC runs mirabelle from here. Never visible to normal projects.
│   ├── README.md           how to operate and repair mirabelle by hand
│   ├── install.sh          the one install
│   ├── bin/ lib/           the `mirabelle` command (Bash)
│   ├── image/              Dockerfile for the image (tools)
│   ├── lock/               the firewall: rules and filter configuration
│   ├── sites.txt           sites every project may reach
│   ├── identities/<name>/  git name/email, extra trusted certificates, private hosts (no secrets)
│   └── projects/<name>/    optional, per project name: extra sites, extra image layer
├── proposed/       a copy of setup that only the upgrade container can write
├── kb/
│   ├── agent/      repo: the shared part of the kb, mounted in every container
│   └── libraries/  one repo per library, mounted only where picked with -l
├── sessions/       repo 3: one folder per project name = Claude's conversations for it
├── secrets/        NOT git, chmod 700: account tokens, git credentials
├── local/          NOT git: per running container, the firewall's list; per image, its build record; per project, VS Code's server cache
└── rescue.sh       undoes the last apply with plain git, without using mirabelle
```

Everything that persists is in this folder or in your project folders. There are no Docker volumes.

---

## 3. What a running project looks like

```
        your PC (WSL)
 ┌───────────────────────────────────────────────────┐
 │  container  mirabelle-shop                        │
 │  ┌─────────────────────────────────────────────┐  │
 │  │ user "dev":  Claude, VS Code server, tools  │  │
 │  │      │ may only talk to the filter          │  │
 │  │      ▼                                      │  │
 │  │ user "gate": the filter (allow-list)  ──────┼──┼──►  listed sites only
 │  │ kernel rules: only "gate" may go out        │  │
 │  └─────────────────────────────────────────────┘  │
 └───────────────────────────────────────────────────┘
```

### What a normal project container can see

| In the container | From the PC | Access |
|---|---|---|
| `/work/<project>` | the folder you ran mirabelle in | read-write |
| `/kb/agent` | `~/mirabelle/kb/agent` | read-write |
| `/kb/libraries/<name>` | `~/mirabelle/kb/libraries/<name>`, only for the libraries picked with `-l` | read-write |
| `/session` | `~/mirabelle/sessions/<project>` | read-write (Claude's config directory) |
| `/identity` | `setup/identities/<identity>/` (git name, email, hosts, trusted certificates) | read-only |
| `/identity-secret` | `secrets/identities/<identity>/` (the git tokens) | read-only |
| `/lock-run` | `local/lock/<project>/` (the firewall's lists, generated by `run`) | read-only |
| `~/.vscode-server` | `~/mirabelle/local/vscode-server/<project>` | read-write |
| account token | the account you named | environment variable `CLAUDE_CODE_OAUTH_TOKEN` |

The scripts mirabelle runs in the container (`lock/apply.sh`, `lock/test.sh`, `lib/inside/start.sh`) are not mounted: they are sent from the PC on standard input each time, so they always come from the applied setup.

Nothing else from the PC is visible: not your home folder, not other projects, not other accounts or identities, **not mirabelle's source**, not the Docker socket.

### Container rules (all containers, including upgrade)
- Everything runs as the user `dev`, with your user and group ids. No root, no `sudo`, no extra privileges, no access to Docker.
- Claude runs inside `tmux`, so a run continues when you close the terminal or VS Code.
- The project name is the folder name (or `-n <name>`). The folder is always mounted at `/work/<name>`, on every computer, and its conversations are in `sessions/<name>`. That is why they survive an account switch and come back on another computer.
- mirabelle gives the project name to the container as the variable `MIRABELLE_PROJECT`. It is the only thing the workflow is told about where it runs.
- `mirabelle stop` stops and removes the container. Nothing is lost: everything that persists is mounted from the PC.

---

## 4. The firewall

### Always on
There is no option to run without it and no bypass. Inside the container, two things enforce it:

- **Kernel rules** that let only the user `gate` send anything out of the container. The user `dev` (Claude) can talk only to the filter.
- **A filter** (tinyproxy, an allow-list proxy on `127.0.0.1:3128`) running as the user `gate`, started with no capabilities at all. It allows:
  - sites in `setup/sites.txt` (Claude, GitHub, package sources, VS Code);
  - sites in `setup/projects/<name>/sites.txt`;
  - private hosts listed in the identity (e.g. your Gitea on the LAN).
- Every other address is refused, including your PC and your LAN.
- The filter does not decrypt traffic; it only decides by destination. Only HTTP(S) gets out, which fits git over HTTPS.
- The kernel rules are set before the filter starts: if the filter fails, the container is closed, not open.
- Containers start with `--cap-drop ALL` and `no-new-privileges`, so nothing in them can gain rights (no `su`, no `sudo`).
- IPv6 is turned off in the container where the PC's kernel has it.

### Why Claude cannot undo it
- **mirabelle sets it from the PC**, with one privileged command when the container starts, before Claude or anything from the agent runs. The rules and the list come from the applied setup on the PC, mounted read-only.
- The container itself is created **without** the right to change network rules.
- Claude is `dev`: not root, unable to become root, unable to stop another user's process, unable to edit the read-only configuration.
- After setting it, mirabelle **tests it**, as `dev`, without privileges (`lock/test.sh`): no direct internet, no direct local network, an unlisted site refused, the filter running as `gate`, the rules unreadable and unchangeable by `dev`, the filter impossible to stop. If any check fails, the container is removed.
- `mirabelle run` prints the list size and the test result.
- After changing a list, `mirabelle lock` re-applies it to a running container and prints the new list and the test result.

### Limits to know
- **The firewall relies on the image.** Its programs are part of the image. A deliberately harmful change to the image could weaken it. Such a change can only come through the upgrade project and `apply`, where you see it and confirm it.
- A container is not a virtual machine. A flaw in Docker or the Linux kernel could in theory be used to escape.
- Claude can read the secrets its project was given (the account token, that identity's git token).
- Publishing is a habit, as you decided: GitHub is on the list, so a tricked Claude could push there with the project's token.

---

## 5. The kb and sessions

**The kb is the agent plus the libraries.**

### The agent: what mirabelle does with it
mirabelle knows exactly two things about the agent (`kb/agent`):

1. **`kb/agent/claude/` is Claude Code's user configuration.** At container start, every file and folder in it is linked into Claude's config directory. mirabelle does not care what it contains.
2. **`kb/agent/start`, if it exists and is executable, is run at container start.**

Both are printed by `mirabelle run`. Everything else in the agent is free.

- **One live copy.** Every container mounts the same `kb/agent` folder. A change made in one project is visible in the others immediately.
- **Per-project notes** are folders inside the agent, organized by the workflow. The workflow finds them from `MIRABELLE_PROJECT`.

### Libraries
- **One git repo per library:** `~/mirabelle/kb/libraries/<name>/`, at the home `library-<name>.git`. Created with `mirabelle library add <name>`, which starts it with an `INDEX.md`.
- **Picked per run:** `mirabelle run … -l stm32 -l client-x`. Only those are mounted, read-write, at `/kb/libraries/<name>`; their names are in `MIRABELLE_LIBRARIES`. A project never sees a library it was not started with, so one client's material does not reach another client's project.
- **The list** is `setup/libraries.txt`, so another computer knows which libraries exist: `install.sh` and `mirabelle pull` clone the missing ones from the home.
- On a folder home, `library add` also creates the library's empty repo at the home. On a server home, you create `library-<name>` there.
- `mirabelle library rm` removes a library from this computer and from the list, only if everything in it is pushed; `-f` removes it anyway, after listing what will be lost and asking. Its copy at the home is kept.

### For both the agent and the libraries
- **Ordinary git repos.** Their `.git` is inside, so Claude can commit, read the history and undo a change.
- **Who commits:** Claude, as a habit of the workflow. `mirabelle save` commits whatever is left uncommitted, and lists it. Nothing else commits.
- **Protection of the history:** `mirabelle push` never forces. If the history was rewritten inside a container, the push is refused and says so. What you already pushed stays safe at the home.

### Starter agent
The install creates a small starter agent (from `setup/agent-starter/`). It is yours to change completely:
- `claude/CLAUDE.md`: where things are (`/work`, `/kb/agent`, `/kb/libraries`), and that this project's notes go in `/kb/agent/projects/$MIRABELLE_PROJECT/`;
- `claude/settings.json`: work without permission prompts;
- `mirabelle/`: how mirabelle works, and how to ask for a change to it;
- `workflow.md`: your current preferences from the goals (Part 2), as a starting point;
- `topics/` and `projects/`: empty folders for knowledge per topic and per project. A suggestion only.

### Sessions
- `sessions/<project>/` is Claude's config directory for that project name: conversations, transcripts, history. Kept forever.
- `mirabelle save` commits it. A container sees only its own project's folder, without the repo's `.git`.
- Caches and anything secret are git-ignored there.

---

## 6. Accounts and identities

### Claude accounts
- `mirabelle account add work` starts a throwaway container that runs Claude's own long-lived token login (`claude setup-token`). You approve in your browser and the token is saved in `secrets/accounts/work`. The firewall is on there too.
- You name the account each time: `mirabelle run -a work …`. The token is given to that container as an environment variable.
- **Switching** when usage runs out is two commands: `mirabelle stop`, then `mirabelle run -a personal …`. The conversation is still there.
- Claude is never logged in on the PC.

### Git identities
- `mirabelle identity add me` asks for the git name and email.
- `mirabelle host add me https://gitea.lan:3000` asks for the token (hidden), checks the certificate (offers to save it if it is not publicly trusted), and records a private address so the firewall allows it for that identity.
- Tokens are in `secrets/`; the rest is in `setup/identities/`.
- Inside the container git uses only that identity's config and tokens, read-only.
- Use narrow tokens: limited to the repos you need.

---

## 7. Upgrading mirabelle

```
mirabelle upgrade -a <account>   ──►   Claude edits the proposed copy
mirabelle apply                  ──►   you see every change, say yes, setup is updated
mirabelle build                  ──►   the image is rebuilt (only if the image changed)
```

### The upgrade project
- It is predefined: the name is `upgrade`, and there is exactly one.
- **`mirabelle upgrade -a <account>`** starts its container and opens Claude in it. Running it again reattaches.
- What that container sees, **in addition to nothing else**:

| In the container | From the PC | Access |
|---|---|---|
| `/work/upgrade` | `~/mirabelle/proposed` (mirabelle's full source) | read-write |
| `/kb/agent` | `~/mirabelle/kb/agent` | read-write |
| `/session` | `~/mirabelle/sessions/upgrade` | read-write |

- "All necessary access" means: the whole source of mirabelle is writable there (tool, image, firewall, lists). It does **not** mean access to Docker, to your secrets other than the account token, or to the internet beyond the list. The firewall is on, as everywhere.
- If `proposed` has no pending change, `upgrade` first makes it an exact copy of the current setup, and says so. If it has pending changes, it keeps them, and says so.
- The PC never runs anything from `proposed`.

### How a normal project asks for something
A normal project cannot touch mirabelle. If Claude needs a tool or a site there, it says so (and may write it down in the agent). You then run `mirabelle upgrade`, or add the site yourself with `mirabelle site add`.

### Applying
- `mirabelle status` shows whether `proposed` differs from setup, and which files.
- **`mirabelle apply`** shows every change, waits for your yes, brings the changes into setup and tags the result. It does nothing else. It then tells you if `mirabelle build` or `mirabelle lock` is needed. It refuses if setup has unsaved changes.
- `mirabelle discard` throws the pending changes away.
- **Going back:** `mirabelle rollback` **undoes the last apply** exactly (a git revert of that apply's commit). Changes you saved since (identities, sites) are kept. Running it again undoes the apply before. `mirabelle rollback <tag>` undoes every apply after that tag. In a site list changed both by the apply and by you, it removes what the apply added and keeps your lines. Any other overlap refuses and names the files. If mirabelle itself is broken, `~/mirabelle/rescue.sh` undoes the last apply with plain git, and the README gives the manual steps.
- `install.sh` tags the installed version (`install-…`), so the first apply can be undone.
- **This project or all projects:** in `proposed`, `image/Dockerfile` and `sites.txt` are for everyone; `projects/<name>/…` is for one project name.

Image builds run on the PC with normal internet access. The build only sees the `image/` folder, which contains no secrets.

---

## 8. Save, push, pull

- `mirabelle home <path-or-url>` sets where the repos live: `<home>/mirabelle.git`, `<home>/agent.git`, `<home>/sessions.git`, and `<home>/library-<name>.git` per library. A folder on a disk or NAS works; so does any git server.
- `mirabelle save` commits what is uncommitted in the repos (setup, kb/agent, sessions, libraries), and lists it.
- `mirabelle push` pushes the repos (setup, kb/agent, sessions, libraries). It never forces.
- `mirabelle pull` pulls the repos (setup, kb/agent, sessions, libraries). It only moves forward to what the home has; if a repo has unsaved or unpushed work, it leaves that repo untouched and names it.
- **Never pushed:** project code, `secrets/`, `local/`.
- **New or rebuilt computer:** clone setup, run `install.sh` (it clones the agent, sessions and the listed libraries from the same home), `mirabelle build`, add accounts and tokens again, clone your project repos yourself.

---

## 9. Commands

Every command accepts `-v` and `--dry-run`. Commands that act on a container use the current folder's name, or `-n <name>`.

| Command | The one thing it does |
|---|---|
| `mirabelle build [--fresh] [-n <project>]` | Builds the image, or with `-n` one project's extra layer |
| `mirabelle images` | Lists mirabelle's images |
| `mirabelle prune` | Deletes the images that are no longer current |
| `mirabelle account add \| ls \| rm <name>` | Adds, lists or removes a Claude account |
| `mirabelle identity add \| ls \| rm <name>` | Adds, lists or removes a git identity |
| `mirabelle host add \| ls \| rm <identity> <https-url>` | Adds, lists or removes a git host for an identity |
| `mirabelle site add \| ls \| rm <domain> [-n <project>]` | Edits a list of allowed sites |
| `mirabelle library add \| ls \| rm [-f] <name>` | Adds, lists or removes a library (`-f`: remove even with work not pushed) |
| `mirabelle run -a <account> -i <identity> [-l <library>]... [-p <port>] [-n <name>] [--previous]` | Starts this folder's container, with its firewall |
| `mirabelle lock` | Re-applies the firewall to the running container |
| `mirabelle code` | Opens VS Code attached to the running container |
| `mirabelle claude` | Opens Claude in the running container (again to reattach) |
| `mirabelle shell` | Opens a shell in the running container |
| `mirabelle stop` | Stops and removes the container |
| `mirabelle ps` | Lists running containers |
| `mirabelle inspect` | Shows the container's options, mounts, allowed sites and firewall state |
| `mirabelle logs` | Shows what the firewall allowed and refused |
| `mirabelle upgrade -a <account>` | Starts the upgrade container and opens Claude in it |
| `mirabelle status` | Shows pending changes in `proposed`, and what is not saved or pushed |
| `mirabelle apply` | Shows the pending changes and, on your yes, brings them into setup |
| `mirabelle discard` | Throws the pending changes away |
| `mirabelle rollback [<tag>]` | Undoes the last apply (or every apply after a tag), keeping your later changes |
| `mirabelle home <path-or-url>` | Sets where push and pull go |
| `mirabelle save` | Commits what is uncommitted in the repos (setup, kb/agent, sessions, libraries) |
| `mirabelle push` | Pushes the repos (setup, kb/agent, sessions, libraries) |
| `mirabelle pull` | Pulls the repos (setup, kb/agent, sessions, libraries) |

- `code`, `claude`, `shell`, `lock` and `inspect` fail with a clear message if the container is not running. They do not start it.
- `run` fails if a container with that name is already running, or if the image is missing, and says which command to run.
- `-p 8080` makes a container port reachable on the PC's `localhost`, for use outside VS Code.
- `--previous` starts from the image as it was before the last build.

---

## 10. Use cases

### First install
```bash
git clone <home>/mirabelle.git ~/mirabelle/setup
~/mirabelle/setup/install.sh
mirabelle build
```

### Declare who you are (once)
```bash
mirabelle account add work
mirabelle identity add me
mirabelle host add me https://gitea.lan:3000
```

### Work in a folder
```bash
cd ~/code/shop
mirabelle run -a work -i me
mirabelle code          # or: mirabelle claude
```

```
project    shop                  (from the folder name)
account    work                  (-a)
identity   me                    (-i)
mounts     ~/code/shop                → /work/shop    rw
           ~/mirabelle/kb/agent       → /kb/agent     rw
           ~/mirabelle/sessions/shop  → /session      rw
           identity "me"              → /identity     ro
started    container mirabelle-shop
kb         linked kb/agent/claude (6 entries)
libraries  none selected
kb         no kb/agent/start
firewall   set, 14 sites allowed, test passed
```

### Long run, come back later
```bash
mirabelle ps
mirabelle claude
```

### The work account runs out of usage
```bash
mirabelle stop
mirabelle run -a personal -i me
mirabelle claude
```

### A tool is missing
```bash
mirabelle upgrade -a work      # tell Claude what is needed
mirabelle status
mirabelle apply
mirabelle build
mirabelle stop                 # in the project folder
mirabelle run -a work -i me
```

### A project needs a library
```bash
mirabelle library add client-x          # once
mirabelle stop
mirabelle run -a work -i me -l client-x -l stm32
```

### A site is not on the list
```bash
mirabelle site add docs.zephyrproject.org -n shop
mirabelle lock
```

### End of day, or moving to the other computer
```bash
mirabelle save
mirabelle push
```
On the other computer:
```bash
mirabelle pull
```

### Something broke after an apply
```bash
mirabelle rollback
mirabelle run -a work -i me --previous    # the image that worked, without rebuilding
```
If mirabelle itself no longer runs: `~/mirabelle/rescue.sh`.

---

## 11. The image

### What is in it
- Ubuntu 24.04 LTS (pinned by digest), git, tmux, curl, openssl, common build tools (gcc, make, cmake, ninja, pkg-config, Python). Everything else is added when needed, through the upgrade project.
- Claude Code, from the official npm package for the platform (`@anthropic-ai/claude-code-linux-x64`), which holds the native binary: no Node needed. The download is checked against the registry's sha512. It is installed root-owned in `/usr/local/bin`, so it cannot be modified from inside. It does not update itself. The version is `stable` by default; an exact version is a pin.
- The Claude Code VS Code extension is declared in the image, so it is installed inside the container when VS Code attaches. It is never installed in VS Code on Windows or WSL.
- The firewall programs. There is no second image.
- One base image for all projects (`mirabelle`), plus an optional layer per project name (`mirabelle-<name>`). A large toolchain can go in either; Claude chooses in the upgrade project and tells you.

### Building
- `mirabelle build` reuses the steps that did not change: it is fast and the tools stay the same.
- `mirabelle build --fresh` rebuilds everything from scratch. This is how Claude Code and unpinned tools get updated.
- **Pinned versions.** The base system is pinned by digest. Tools that matter can be pinned with exact versions in the definition (`gcc-13=…`, `CLAUDE_CODE_VERSION=2.1.311`). Keeping the pins is part of maintaining mirabelle in the upgrade project.
- **Same definition, same image.** Builds use `SOURCE_DATE_EPOCH` (the time of the last commit that changed the definition) and no provenance record, and the image's labels change only with the definition. Rebuilding an unchanged definition gives the identical image, so `previous` is not pushed out by a rebuild that changed nothing.
- **Build record.** Each build writes a plain text file, `local/images/<image>.txt`: the date, the setup version it was built from, the Claude Code version, and every installed package with its version. Two builds can be compared with any diff tool.

### Where images live, and cleaning up
- Images are in Docker's own storage, not under `~/mirabelle/`. They are never pushed; on another computer you build them.
- `mirabelle images` lists them: name, date, size, Claude Code version, whether a container uses it, and whether it is older than its definition.
- **The previous image is kept.** Before a build, the current image gets a temporary name; if the build produces a different image, that one becomes `previous`. After a `rollback` you can start from the image that worked with `mirabelle run … --previous`, without rebuilding.
- `mirabelle prune` deletes the previous images and their build records, after listing them and your yes.

---

## 12. The install

`install.sh`, run once, by hand, without Claude:

1. Checks git and Docker Engine in WSL. If Docker is missing or not usable, it prints the official install steps and stops (it installs nothing system-wide).
2. Clones the agent, sessions and the libraries listed in `setup/libraries.txt` from the home setup was cloned from, if they exist there. Otherwise creates them, the agent with the starter content.
3. Tags the installed version of setup (`install-…`).
4. Creates `secrets/`, `local/`, copies `rescue.sh`, and links `~/.local/bin/mirabelle`. It edits none of your shell files.
5. Prints what is left for you to do: `mirabelle build`, and on Windows once, install VS Code with the Dev Containers extension and enable its "Execute in WSL" setting.

It prints every step. After this, nothing more is installed on the PC.

---

## 13. What was tested, and what was not

Tested in a Linux sandbox with real Docker 29 (containerd image store), as a non-root user (uid 1000), with a fresh install from a git home:

- install from a home; build (and unchanged rebuild = same image); images; prune; project layers (`build -n`);
- the firewall: no direct internet or local network, unlisted and lookalike domains refused, a listed local git host reachable through the filter only, other local hosts refused, `dev` unable to read or change the rules, stop the filter, write the lists, or gain rights;
- one privileged command from the PC setting the firewall in a container started without any right (former assumption 6: confirmed);
- run, claude (tmux, survives closing the window, reattaches), shell, stop, ps, inspect, logs, lock, site add, `-v`, `--dry-run`;
- identity and host add against a local HTTPS git server with a self-signed certificate: certificate shown and trusted on yes, private address allowed, `git clone` through the filter, commits with the identity, tokens used read-only;
- upgrade, status, apply (with a real 3-way merge), discard, rollback (including a site list changed on both sides), rescue.sh;
- save, home, push, pull between two simulated computers; refusals when both changed the same repo or when there are unsaved changes.

Not tested here (needs your PC, a browser or a real account). Each has a fallback:

| # | Assumption | If it fails |
|---|---|---|
| 1 | `account add`: Claude's token login (`claude setup-token`) in the temporary container, and the token working for interactive use and for the VS Code extension | Log in with `claude` inside a container and keep that login file per account |
| 2 | Claude Code, the VS Code server and its extensions work through the firewall with the sites in `sites.txt` | `mirabelle logs` shows what was refused; add those sites. No bypass |
| 3 | `mirabelle code` opens VS Code attached to the container from WSL, and the extension declared in the image is installed on attach | Attach by hand from VS Code ("Attach to Running Container"), two clicks |
| 4 | Claude keeps the link when it saves `settings.json` | `run` keeps a real file in place and says so; move the change into `kb/agent/claude/` |
| 5 | A conversation resumes after an account switch and on another computer | The transcripts are kept anyway; resume becomes "start a new conversation with the old one as context" |
| 6 | Reaching a LAN host from a container on your WSL network setup | `mirabelle host add` records the address it finds; check it with `mirabelle inspect` |

---

## 14. Build order (done)

All five steps are built. From now on, Claude maintains mirabelle from the upgrade project.

---

## 15. How each goal is met

| Goal | Where |
|---|---|
| Claude never on the PC | §3, §6: every Claude process, including login, runs in a container |
| Cannot reach PC, LAN, other projects | §3 mounts, §4 firewall |
| Firewall always on | §4 |
| Normal projects never have privileges | §3: no root, no Docker, no mirabelle source |
| One upgrade project, one command | §7 |
| Nothing takes effect until I apply | §7 |
| Survive without Claude | §7 rollback, `rescue.sh`, README |
| Switch account, lose nothing | §3 project name, §5 sessions, §6 |
| One agent, present everywhere, versioned | §5 |
| Libraries picked per project, invisible elsewhere | §5 Libraries, §3 mounts |
| mirabelle knows nothing about the workflow | §5: two rules, plus the project name |
| Shared knowledge and per-project knowledge | §5: folders in the agent, found through `MIRABELLE_PROJECT`; libraries for knowledge some projects need |
| Nothing hidden | §1 rule 1 |
| One command does one thing | §1 rule 2, §9 |
| One install, nothing more on the PC | §12 |
| Long runs keep going; reattach | §3 tmux |
| Plain git, any home | §8 |
| Project folders never modified | §2, §3 |
