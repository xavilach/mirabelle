# mirabelle — reference (matches the code, spec v2.0)

Summary, glossary, every command with what it does and which files it reads and writes, and a map of all files.

**Status:** built; see `SPEC.md` §13 for what was tested.

---

## 1. Summary

**mirabelle** is a small command-line tool for WSL. It starts one container per project folder, in which Claude works autonomously behind a firewall, with a kb made of the agent (shared) and libraries (picked per project).

- **How you use it:** `cd` into any folder, `mirabelle run -a <account> -i <identity>`, then `mirabelle code` or `mirabelle claude`. Nothing is written in the folder.
- **Two halves:** the *setup* (mirabelle: containers, accounts, identities, firewall, git) and the *workflow* (the kb: how you and Claude work, and what you know). mirabelle does not interpret the kb.
- **The kb** is the *agent* (one, shared, in every container) plus *libraries* (picked per run with `-l`, invisible to other projects).
- **Safety:** Claude runs only in containers, as an ordinary user. A container sees its folder, the agent, the libraries picked for it, its own conversations, one account token and one git identity. The firewall is always on and allows only listed sites.
- **Upgrading mirabelle:** only from the predefined upgrade project (`mirabelle upgrade`). Claude edits a proposed copy; nothing changes until `mirabelle apply` shows it and you say yes.
- **Three tiers:** the *plumbing* (the tool, on GitHub), *your local data* (config, kb/agent, sessions, one repo per library, pushed with plain git to a home you choose), and *project content* (only in the project folder).
- **Two rules:** nothing hidden; one command does one thing.
- **On the PC:** Docker, git, VS Code and mirabelle.

---

## 2. Glossary

| Term | Meaning |
|---|---|
| **PC** | Your WSL environment on Windows. mirabelle runs here; Claude never does |
| **Container** | An isolated Linux environment started by Docker. Claude always runs inside one |
| **Image** | The template containers are started from: the operating system, the tools, Claude Code, the firewall programs |
| **Previous image** | The image as it was before the last build. Kept until you prune it |
| **Build record** | A plain text file written by each build, listing what the image contains and in which versions |
| **Pinned version** | An exact tool version named in the image definition, so every build installs the same one |
| **Project** | A folder you run mirabelle in. It holds one or more of your repos |
| **Project name** | The folder's name, or the name given with `-n`. It decides the container name (`mirabelle-<name>`) and where the conversations are kept |
| **Setup** | Repo 1, `~/mirabelle/plumbing`: the mirabelle tool, the image definition, the firewall, the lists. The PC runs mirabelle from here |
| **Plumbing** | Repo `~/mirabelle/plumbing`, cloned from GitHub: the mirabelle tool itself (commands, image, firewall, starters, docs). Holds nothing of yours. The PC runs mirabelle from here |
| **Config** | Repo `~/mirabelle/config`: your configuration of the plumbing (sites, identities, per-project sites and image layers, the list of libraries). Pushed to your home, never to GitHub |
| **Proposed** | `~/mirabelle/proposed/plumbing` and `proposed/config`: copies that Claude can edit in the upgrade project. The PC never runs anything from them |
| **kb** | The knowledge base: the agent plus the libraries, under `~/mirabelle/kb/` |
| **Agent** | Repo `~/mirabelle/kb/agent`: the shared part of the kb, present in every container at `/kb/agent`. Holds the workflow, the shared knowledge and Claude's configuration |
| **Library** | Repo `~/mirabelle/kb/libraries/<name>`: knowledge only some projects need (reference docs, topic notes, reusable code, client material). Mounted at `/kb/libraries/<name>` only when picked with `run -l <name>` |
| **`MIRABELLE_LIBRARIES`** | A variable inside the container holding the names of the libraries picked for it |
| **Workflow** | How you and Claude work. It lives in the agent and is not part of mirabelle |
| **`MIRABELLE_PROJECT`** | A variable inside the container holding the project name. The workflow uses it to find that project's knowledge |
| **Sessions** | Repo 3, `~/mirabelle/sessions`: one folder per project name with Claude's conversations and state |
| **Home** | Where your local data (config, kb/agent, sessions, libraries) is pushed to and pulled from: a folder, a NAS or any git server. The plumbing has its own origin, GitHub |
| **Account** | A Claude account, used for usage limits. Stored as one token |
| **Token** | A secret string that proves who you are: one per Claude account, one per git host |
| **Identity** | A git identity: name, email, the git hosts it may use and their tokens |
| **Host** | A git server an identity may use, e.g. `https://github.com` or your Gitea |
| **Site** | An internet address the firewall allows |
| **List** | A plain text file of allowed sites: one for all projects, optionally one per project name |
| **Firewall** | What limits the container's network: kernel rules plus a filter. Always on |
| **Filter** | The program inside the container (tinyproxy, on `127.0.0.1:3128`) that checks each destination against the lists |
| **Lock** | The name of the firewall's folder (`plumbing/lock/`) and of the command that re-applies the firewall (`mirabelle lock`) |
| **`dev`** | The ordinary user everything runs as inside a container. Not root |
| **`gate`** | The separate user the filter runs as. Only this user may send traffic out |
| **Upgrade project** | The one predefined project (name `upgrade`) where mirabelle's source is visible and writable |
| **Apply** | Bringing the proposed changes into plumbing and config, after you have seen them and said yes |
| **Tag** | A named point in plumbing's and config's history (`apply-<date>`, `rollback-<date>`), the same name in both |
| **Secrets** | `~/mirabelle/secrets`: tokens. Never in git, never pushed |
| **Local** | `~/mirabelle/local`: generated and cache files for this PC only. Never in git |
| **`rescue.sh`** | A standalone script that undoes the last apply with plain git, for when mirabelle itself is broken |
| **tmux** | The program Claude runs inside, so that a session survives closing the window and can be reattached |
| **Attach** | Connecting VS Code or a terminal to a container that is already running |

---

## 3. Commands

Notes that apply to all of them:

- `-v` prints the exact `docker` and `git` commands. `--dry-run` prints them and runs nothing.
- `-f` / `--force` (on `run`, `account add`, `host add` and every `rm`) overrides a refusal. On `run` and `add` it replaces what already exists; on `rm` it removes something a container still uses (and, for a library, work not pushed). It never skips a yes/no question, and never bypasses the firewall test.
- Commands that act on a container use the current folder's name, or `-n <name>`.
- "Refuses when" means: prints the reason and the command to run instead, and changes nothing.
- Paths are relative to `~/mirabelle/` unless they start with `/` (inside the container) or `~`.

### 3.1 Install and image

#### `~/mirabelle/plumbing/install.sh [<home>]`
Sets up the PC, once. The plumbing must have been cloned from GitHub as `~/mirabelle/plumbing`.

1. Checks that `git` and Docker are present and usable. If not, prints the official install steps and stops; it installs nothing system-wide.
2. For your config, the agent, sessions and every library in `config/libraries.txt`: with a `<home>` that holds `config.git` / `agent.git` / `sessions.git` / `library-<name>.git`, clones them. Otherwise creates new repos (config from `plumbing/config-starter/`, the agent from `plumbing/agent-starter/`, a library with an `INDEX.md`), with their home set if you gave one.
3. Creates `secrets/` (private to you), `local/`, and copies `plumbing/rescue.sh` to `rescue.sh`.
4. Links `~/.local/bin/mirabelle` to `plumbing/bin/mirabelle`. If that folder is not on your PATH, prints the line to add; it does not edit your shell files.
5. Prints what is left for you to do.

- **Reads:** `plumbing/`, the home if given.
- **Writes:** `config/`, `kb/agent/`, `kb/libraries/`, `sessions/`, `secrets/`, `local/`, `rescue.sh`, `~/.local/bin/mirabelle`.
- **Leaves as they are** (and says so): any of these repos that already exists.

#### `mirabelle build [--fresh] [-n <project>]`
Builds the image.

1. Without `-n`: builds the base image `mirabelle` from `plumbing/image/`. With `-n shop`: builds the extra layer `mirabelle-shop` from `config/projects/shop/Dockerfile`, on top of the base image.
2. Without `--fresh`, reuses the build steps that did not change. With `--fresh`, rebuilds everything from scratch, which also fetches the newest Claude Code and the newest version of any tool that is not pinned.
3. If an image of that name already exists, renames it to `previous` (replacing an older `previous`), together with its build record.
4. Writes the build record of the new image.
5. Prints the image's size, its Claude Code version, and what changed compared with the previous build record.

- Uses the PC's normal internet access. The build sees only the folder it builds from.
- **Reads:** `plumbing/image/` or `config/projects/<name>/Dockerfile`; your user and group ids.
- **Writes:** Docker images (the new one, and the renamed previous one); `local/images/<image>.txt` and `local/images/<image>.previous.txt`.
- **Does not:** rebuild project layers when the base changes (`status` and `images` show which are older), or restart any container.
- **Refuses when:** `-n` is given and the base image or the project's Dockerfile is missing.

#### `mirabelle images`
Lists mirabelle's images: name, current or previous, date, size, Claude Code version, the plumbing (or, for a project layer, config) version it was built from, which running containers use it, and whether it is older than its definition (or, for a project layer, older than the base).

- **Reads:** Docker's image and container lists, `local/images/`, `plumbing/image/`, `config/projects/`. **Writes:** nothing.

#### `mirabelle prune`
Deletes the previous images and their build records, after listing them and your yes. Current images are never deleted.

- **Writes:** removes Docker images; deletes `local/images/*.previous.txt`.
- **Refuses, per image, when:** a running container uses it.

### 3.2 Accounts, identities, hosts, sites

#### `mirabelle account add [-f] <name>`
Adds a Claude account. With `-f`, logs in again for an existing account and replaces its token.

1. Starts a temporary container with the firewall on.
2. Runs Claude's token login in it. You open the address it shows in your browser and approve.
3. Asks you to paste the token it displays (input hidden) and stores it.
4. Removes the temporary container.

- **Reads:** the image, `config/sites.txt`, `plumbing/lock/`.
- **Writes:** `secrets/accounts/<name>` (with `-f`, only once the new token is pasted: the old one is kept if you stop before).
- **Refuses when:** that account name exists (unless `-f`), or the image is missing.

#### `mirabelle account ls`
Lists account names. Never prints a token. **Reads:** `secrets/accounts/`. **Writes:** nothing.

#### `mirabelle account rm [-f] <name>`
Deletes an account after your yes. **Writes:** deletes `secrets/accounts/<name>`.
- **Refuses when** a mirabelle container uses the account (it names them). With `-f`, deletes it anyway; those containers keep the token they were started with until stopped.

#### `mirabelle identity add <name>`
Adds a git identity. Asks for the git name and email.

- **Writes:** `config/identities/<name>/gitconfig`, an empty `config/identities/<name>/hosts.txt`, the folder `secrets/identities/<name>/`.
- **Refuses when:** that identity name exists.

#### `mirabelle identity ls`
Lists identities with their name and email. **Reads:** `config/identities/`. **Writes:** nothing.

#### `mirabelle identity rm [-f] <name>`
Deletes an identity after your yes. **Writes:** deletes `config/identities/<name>/` and `secrets/identities/<name>/`.
- **Refuses when** a mirabelle container uses the identity. With `-f`, deletes it anyway (those containers lose its files).

#### `mirabelle host add [-f] <identity> <https-url>`
Allows an identity to use a git host. With `-f`, replaces an existing host: new user name, token and certificate (for an expired or rotated token).

1. Asks for the user name and the token (input hidden).
2. Connects to the host from the PC to read its certificate. If it is not publicly trusted, shows who it belongs to and its fingerprint, and asks whether to trust it.
3. Looks up the host's address. If it is a private address (your LAN), records it so the firewall will allow exactly that address and port.

- **Reads:** `config/identities/<identity>/`.
- **Writes:** a line in `config/identities/<identity>/hosts.txt`; a line in `secrets/identities/<identity>/git-credentials`; if you chose to trust a certificate, `config/identities/<identity>/ca/<host>.crt`.
- **Does not:** test the token, or change a running container (run `mirabelle lock` for that).
- **Refuses when:** the identity does not exist, the address is not `https://`, or the host is already listed (unless `-f`; the old entry is removed only once the new one is complete).

#### `mirabelle host ls <identity>`
Lists the identity's hosts. Never prints a token. **Reads:** `hosts.txt`. **Writes:** nothing.

#### `mirabelle host rm [-f] <identity> <https-url>`
Removes a host after your yes. **Writes:** removes its lines from `hosts.txt` and `git-credentials`, and its certificate file.
- **Refuses when** a mirabelle container uses the identity. With `-f`, removes it anyway; run `mirabelle lock` in those containers to drop its firewall entry.

#### `mirabelle site add <domain> [-n <project>]`
Adds a site to a list. **Writes:** a line in `config/sites.txt`, or in `config/projects/<name>/sites.txt` with `-n` (created if missing). **Does not** change a running container.

#### `mirabelle site ls [-n <project>]`
Prints the list for all projects, and the project's own list with `-n`. **Reads:** those files. **Writes:** nothing.

#### `mirabelle site rm <domain> [-n <project>]`
Removes a site from a list. **Writes:** that list file.

#### `mirabelle library add <name>`
Adds a library.

1. If the home has `library-<name>.git`, clones it into `kb/libraries/<name>/`.
2. Otherwise creates a new git repo there with an `INDEX.md`, and sets its home to `<home>/library-<name>.git`. On a folder home, also creates that empty repo at the home; on a server home, tells you to create it.
3. Adds the name to `config/libraries.txt` (record it with `mirabelle save`).

- **Writes:** `kb/libraries/<name>/`, `config/libraries.txt`, possibly `<home>/library-<name>.git`.
- **Refuses when:** the name is not valid, or the library already exists on this computer.

#### `mirabelle library ls`
Lists the libraries: listed in config and present, listed but not on this computer, or present but not listed; number of files; unsaved changes. **Reads:** `config/libraries.txt`, `kb/libraries/`. **Writes:** nothing.

#### `mirabelle library rm [-f] <name>`
Removes a library from this computer and from `config/libraries.txt`, after your yes. Its copy at the home is kept.

- **Writes:** deletes `kb/libraries/<name>/`; one line of `config/libraries.txt`.
- **Refuses when** removing it would lose something: unsaved changes, commits not pushed, never pushed, no home (this computer holds its only copy), or still mounted in a container. It lists what would be lost.
- **`-f` / `--force`:** removes it anyway. It still lists what will be lost and asks for your yes.

### 3.3 Working in a folder

#### `mirabelle run [-f] -a <account> -i <identity> [-l <library>]... [-p <port>] [-n <name>] [--previous]`
Starts this folder's container, with its firewall. Every step is printed.

1. Takes the project name from the folder name, or from `-n`.
2. Chooses the image: `mirabelle-<name>` if it exists, otherwise `mirabelle`. With `--previous`, the previous one of that image.
3. Creates `sessions/<name>/` and `local/vscode-server/<name>/` if they do not exist.
4. Writes the firewall's list for this container: the list for all projects, plus this project's list, plus the identity's hosts.
5. Starts the container `mirabelle-<name>`: user `dev`, `--cap-drop ALL`, `no-new-privileges`, the mounts below, and the port on the PC's `localhost` if `-p` was given. Environment: the account token (`CLAUDE_CODE_OAUTH_TOKEN`, passed through Docker's environment, never on the command line), `MIRABELLE_PROJECT`, `MIRABELLE_LIBRARIES`, `CLAUDE_CONFIG_DIR=/session`, `DISABLE_AUTOUPDATER=1`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, the proxy settings (`HTTPS_PROXY` …), `GIT_CONFIG_GLOBAL=/identity/gitconfig`, and the certificate bundle (`SSL_CERT_FILE` …).
6. Sets the firewall: `lock/apply.sh`, sent on standard input to one privileged `docker exec`. Then tests it: `lock/test.sh`, as `dev`, without privileges. If either fails, removes the container.
7. Runs `lib/inside/start.sh` as `dev`: builds the certificate bundle (the system's plus the identity's), links every entry of `/kb/agent/claude/` into `/session`, writes `/session/.gitignore`, lists the libraries mounted.
8. Runs `/kb/agent/start` if it exists and is executable. If it fails, says so; the container keeps running.
9. Prints the summary and the next commands.

| Mounted in the container | From the PC | Access |
|---|---|---|
| `/work/<name>` | the current folder | read-write |
| `/kb/agent` | `kb/agent/` | read-write |
| `/kb/libraries/<library>` | `kb/libraries/<library>/`, one per `-l` | read-write |
| `/session` | `sessions/<name>/` | read-write |
| `/identity` | `config/identities/<identity>/` | read-only |
| `/identity-secret` | `secrets/identities/<identity>/` | read-only |
| `/lock-run` | `local/lock/<name>/` | read-only |
| `~/.vscode-server` | `local/vscode-server/<name>/` | read-write |

- **Reads:** `secrets/accounts/<account>`, `config/identities/<identity>/`, `config/sites.txt`, `config/projects/<name>/sites.txt`, `plumbing/lock/`, `plumbing/lib/inside/start.sh`, `kb/agent/claude/`, `kb/agent/start`.
- **Writes:** `local/lock/<name>/` (`allowed.txt`, `filter`, `private.txt`, `ports.txt`, `tinyproxy.conf`); the folders in step 3; links and `.gitignore` inside `sessions/<name>/`; one Docker container. Nothing in the project folder.
- **`-f`:** if a container with that name exists, removes it first (a Claude session running in it ends; its conversation is kept), then starts the new one.
- **Refuses when:** a container with that name already exists (unless `-f`), the image is missing, the account, identity or a library does not exist, or a library name is not valid.

#### `mirabelle lock [-n <name>]`
Re-applies the firewall to a running container, after a list changed.

1. Writes the container's list again from the current list files.
2. Reloads the filter and the kernel rules with one privileged command from the PC.
3. Tests the firewall and prints the list and the result. If the test fails, stops and removes the container.

- **Reads:** the same list files as `run`; the identity name recorded on the container.
- **Writes:** `local/lock/<name>/allowed.txt`.
- **Refuses when:** the container is not running.

#### `mirabelle code [-n <name>]`
Opens VS Code attached to the running container, at `/work/<name>`.

- **Reads / writes (mirabelle):** nothing.
- **VS Code itself** then writes its server and extensions into `local/vscode-server/<name>/`, and keeps a small configuration for this container in its own settings on Windows. That last file is VS Code's, outside `~/mirabelle/`.
- **Refuses when:** the container is not running.

#### `mirabelle claude [-n <name>]`
Opens Claude in the running container. If a Claude session is already running there, reattaches to it.

- **Reads / writes (mirabelle):** nothing.
- **Claude itself** reads its configuration from the agent, writes its conversations to `sessions/<name>/`, and reads and writes `/work/<name>`, `/kb/agent` and the picked libraries as the work requires.
- **Refuses when:** the container is not running.

#### `mirabelle shell [-n <name>]`
Opens a shell as `dev` in the running container. **Reads / writes (mirabelle):** nothing. **Refuses when:** the container is not running.

#### `mirabelle stop [-n <name>]`
Stops and removes the container. A running Claude session ends; its conversation is already on disk.

- **Writes:** deletes `local/lock/<name>/`. Removes one Docker container.
- **Does not:** commit anything.
- **Refuses when:** there is no such container.

#### `mirabelle ps`
Lists running mirabelle containers: project name, account, identity, folder, since when. **Reads:** Docker. **Writes:** nothing.

#### `mirabelle inspect [-n <name>]`
Shows everything about one running container: account, identity, image, every mount, the allowed sites, and the firewall's rules and test result.

- **Reads:** Docker, `local/lock/<name>/allowed.txt`; runs one privileged read-only command to list the rules.
- **Writes:** nothing.
- **Refuses when:** the container is not running.

#### `mirabelle logs [-n <name>]`
Shows what the firewall allowed and refused since the container started. **Reads:** the filter's log inside the container, `/run/mirabelle/gate/tinyproxy.log` (not kept after `stop`). **Writes:** nothing.

### 3.4 Upgrading mirabelle

#### `mirabelle upgrade -a <account>`
Starts the upgrade container and opens Claude in it.

1. If the upgrade container is already running, reattaches to Claude and does nothing else.
2. Prepares `proposed/plumbing` and `proposed/config`: each is created as a git clone of the real repo if it does not exist; if it exists with no pending change, it is brought up to date; if it has pending changes, it is kept. Prints which.
3. Creates `sessions/upgrade/` if needed and writes the firewall's list (the plumbing's and your sites, no identity hosts).
4. Starts the container `mirabelle-upgrade` with `proposed/` at `/work/upgrade` (read-write: `/work/upgrade/plumbing` and `/work/upgrade/config`), the agent (`/kb/agent`, no libraries), its session folder, the account token and `MIRABELLE_PROJECT=upgrade`. No identity, no Docker access.
5. Sets and tests the firewall, links the agent's configuration, runs `/kb/agent/start`, as `run` does.
6. Opens Claude.

- **Reads:** `plumbing/`, `config/` (to copy), `secrets/accounts/<account>`, the site lists, `plumbing/lock/`, `kb/agent/`.
- **Writes:** `proposed/`, `sessions/upgrade/`, `local/lock/upgrade/`, `local/vscode-server/upgrade/`; one Docker container.
- **Refuses when:** the image is missing or the account does not exist.

#### `mirabelle status`
Shows what is pending. It does not contact the home or GitHub.

- Files that differ in `proposed/plumbing` and `proposed/config`, each with its part (tool, image, firewall, lists, identities, documentation).
- Uncommitted changes in plumbing, config, kb/agent, sessions and each library.
- Commits not yet pushed, as of the last push or pull.
- Whether an image is older than its definition, or a project layer older than the base image.
- **Reads:** the repos and `proposed/`, Docker's image list. **Writes:** nothing (it refreshes each proposed copy's view of its origin).

#### `mirabelle apply`
Brings the proposed changes into plumbing and config.

1. Commits, in each proposed copy, what Claude left uncommitted.
2. Shows every difference, per repo and grouped: tool, image, firewall, lists, identities, documentation; then the full diff.
3. Waits for your yes.
4. Merges each changed repo. If either cannot merge cleanly, neither is changed.
5. Records one commit in each changed repo, with the same tag `apply-<date>` in each, and resets the proposed copies.
6. Tells you what to run next: `mirabelle build` if the image changed, `mirabelle lock` if the firewall or a list changed, `mirabelle push` to send the plumbing to GitHub and the config to your home.

- **Reads:** `proposed/`, `plumbing/`, `config/`.
- **Writes:** `plumbing/` and/or `config/` (files, one commit, one tag each); `proposed/`.
- **Does not:** build, restart, re-lock or push anything.
- **Refuses when:** there is nothing to apply; plumbing or config has uncommitted changes (run `mirabelle save` first); or the same lines changed on both sides (nothing is changed, and it names the files).

#### `mirabelle discard`
Throws the proposed changes away (both copies) after your yes. **Writes:** `proposed/plumbing` and `proposed/config` become copies of the real repos again.

#### `mirabelle rollback [<tag>]`
Undoes the last apply that has not been undone yet, in plumbing and config, after showing it and your yes. With an apply tag, undoes every apply after that tag.

1. Lists the applies not undone yet (with the repos each one changed), and which will be undone.
2. Shows what changes.
3. Reverts each of those apply commits (git revert) in each repo: exactly what the apply changed is undone; everything you saved since (identities, sites, …) is kept.
4. In a list file (`sites.txt`, `projects/<name>/sites.txt`, `libraries.txt`) changed both by the apply and later by you: removes the lines the apply added, puts back those it removed, keeps yours.
5. Records one commit `rollback: undo N apply(s)` in each changed repo, with a line `Undoes: apply-<date>` per apply, tagged `rollback-<date>`. Running rollback again undoes the apply before.

- **Reads / writes:** `plumbing/`, `config/`; a proposed copy is reset if it had nothing pending.
- **Does not:** rebuild the image (it tells you about `mirabelle run … --previous` and `mirabelle build`), or push.
- **Refuses when:** plumbing or config has unsaved changes; there is no apply to undo; another file changed again since the apply (it names it, and changes nothing).

#### `~/mirabelle/rescue.sh`
Undoes the last apply not yet undone, in plumbing and config, with plain git and without using mirabelle. For when mirabelle itself no longer runs. Shows the apply, asks, keeps uncommitted changes in `git stash`, refuses if the undo is not clean. **Reads / writes:** `plumbing/`, `config/`.

### 3.5 Save, push, pull

#### `mirabelle home [<path-or-url>]`
Without an argument, prints where each repo is pushed (the plumbing's origin, GitHub, and your home for the rest). With one, sets your home: `<home>/config.git`, `<home>/agent.git`, `<home>/sessions.git`, `<home>/library-<name>.git`. If the home is a folder and those repos do not exist there, offers to create them. It never changes the plumbing's origin.

- **Writes:** the remote address in each of your repos' git configuration; possibly empty repos at the home.

#### `mirabelle save`
Commits what is uncommitted in plumbing, config, kb/agent, sessions and each library, and lists the files. It does not contact the home.

- **Reads / writes:** those repos.
- In sessions, a keep-list decides what is recorded: conversations and Claude's own state. Links and caches are left out.

#### `mirabelle push`
Pushes, one after the other: the plumbing to its origin (GitHub, with your normal git login on the PC), and config, kb/agent, sessions and the libraries to your home. Prints each result. It never forces. A refused push is reported, telling apart a repo that does not exist at the home from one that has newer commits, and the others continue.

- **Reads:** the repos. **Writes:** GitHub (plumbing), the home (the rest).
- **Does not:** commit. It tells you if something is not saved.

#### `mirabelle pull`
Pulls the plumbing (from GitHub) and config first; then clones from the home every library listed in `config/libraries.txt` that this computer does not have; then pulls kb/agent, sessions and the libraries. For each repo it only moves forward; it never merges or rewrites.

- **Reads:** GitHub, the home. **Writes:** the repos, `kb/libraries/`.
- **Refuses, per repo, when:** the repo has unsaved changes, or has commits its remote does not have. It names the repo and leaves it untouched.

---

## 4. Map of all files

| Path under `~/mirabelle/` | What it is | In git | Written by | Visible in containers |
|---|---|---|---|---|
| `plumbing/bin/`, `plumbing/lib/` | The mirabelle tool | plumbing (GitHub) | `apply`, `rollback`, `pull` | No |
| `plumbing/README.md`, `plumbing/install.sh`, `plumbing/rescue.sh` | Manual, installer, standalone rollback | plumbing | `apply`, `pull` | No |
| `plumbing/image/` | Image definition | plumbing | `apply`, `pull` | No |
| `plumbing/lock/` | The firewall's two scripts: `apply.sh` (privileged) and `test.sh` (as `dev`) | plumbing | `apply`, `rollback`, `pull` | No (sent on standard input) |
| `plumbing/lib/inside/start.sh` | What runs in a container at start, as `dev` | plumbing | `apply`, `rollback`, `pull` | No (sent on standard input) |
| `plumbing/sites.txt` | Sites the plumbing itself needs (Claude, VS Code) | plumbing | `apply`, `pull` | No (copied into the container's list) |
| `plumbing/agent-starter/`, `plumbing/config-starter/` | Content of a new agent, of a new config | plumbing | `apply` | No |
| `config/sites.txt` | Your sites for all projects | config (home) | `site`, `apply` | No (copied into the container's list) |
| `config/libraries.txt` | The list of libraries | config | `library add\|rm`, `apply` | No |
| `config/projects/<name>/sites.txt` | Sites for one project name | config | `site`, `apply` | No (same) |
| `config/projects/<name>/Dockerfile` | Extra image layer for one project name | config | `apply` | No |
| `config/identities/<name>/gitconfig` | Git name, email, settings | config | `identity` | Read-only, at `/identity`, for containers started with that identity |
| `config/identities/<name>/hosts.txt` | Git hosts of the identity | config | `host` | Same |
| `config/identities/<name>/ca/` | Certificates you chose to trust | config | `host` | Same |
| `proposed/plumbing`, `proposed/config` | Copies for Claude to edit | their own clones | `upgrade`, `apply`, `discard`, Claude | Only in the upgrade container, at `/work/upgrade/…` |
| `kb/agent/` | The agent: shared part of the kb | kb/agent | Claude, you, `save` (commits) | Read-write, at `/kb/agent`, in every container |
| `kb/agent/claude/` | Claude's configuration | kb/agent | Claude, you | Same |
| `kb/agent/start` | Optional start script | kb/agent | Claude, you | Same |
| `kb/libraries/<name>/` | One library | its own | Claude, you, `save` (commits) | Read-write, at `/kb/libraries/<name>`, only in containers started with `-l <name>` |
| `sessions/<name>/` | Conversations and Claude's state for one project name | sessions | Claude, `run` (links), `save` (commits) | Read-write, at `/session`, in that project's container only |
| `secrets/accounts/<name>` | Claude account token | No | `account` | As an environment variable, in containers started with that account |
| `secrets/identities/<name>/git-credentials` | Git tokens of the identity | No | `host` | Read-only, at `/identity-secret`, in containers started with that identity |
| `local/lock/<name>/` | The firewall's lists and filter settings for one running container | No | `run`, `lock`, `upgrade`; deleted by `stop` | Read-only, at `/lock-run` |
| `local/images/<image>.txt` | Build record of an image: contents and versions | No | `build`; deleted by `prune` | No |
| `local/vscode-server/<name>/` | VS Code's server and extensions for one project name | No | VS Code | Read-write |
| `rescue.sh` | Standalone rollback | No | `install.sh` | No |

Outside `~/mirabelle/`:

| Path | What | Written by |
|---|---|---|
| Your project folders | Your code | You and Claude. Never mirabelle |
| `~/.local/bin/mirabelle` | Link to the tool | `install.sh` |
| GitHub | The plumbing | `push` (plumbing only) |
| The home | config, kb/agent, sessions, libraries | `home` (creation), `push` |
| Docker's own storage | The images and the running containers | `build`, `prune`, `run`, `upgrade`, `account add`, `stop` |
| VS Code's settings on Windows | Its note about an attached container | VS Code |
