# mirabelle — reference (matches the code, spec v2.0)

Summary, glossary, every command with what it does and which files it reads and writes, and a map of all files.

**Status:** built; see `SPEC.md` §13 for what was tested.

---

## 1. Summary

**mirabelle** is a small command-line tool for WSL. It starts one container per project folder, in which Claude works autonomously behind a firewall, with one shared kb.

- **How you use it:** `cd` into any folder, `mirabelle run -a <account> -i <identity>`, then `mirabelle code` or `mirabelle claude`. Nothing is written in the folder.
- **Two halves:** the *setup* (mirabelle: containers, accounts, identities, firewall, git plumbing) and the *workflow* (the kb: how you and Claude work, and what you know). mirabelle does not interpret the kb.
- **Safety:** Claude runs only in containers, as an ordinary user. A container sees its folder, the kb, its own conversations, one account token and one git identity. The firewall is always on and allows only listed sites.
- **Upgrading mirabelle:** only from the predefined upgrade project (`mirabelle upgrade`). Claude edits a proposed copy; nothing changes until `mirabelle apply` shows it and you say yes.
- **Three git repos** (setup, kb, sessions), saved, pushed and pulled with plain git to a home you choose.
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
| **Setup** | Repo 1, `~/mirabelle/setup`: the mirabelle tool, the image definition, the firewall, the lists. The PC runs mirabelle from here |
| **Proposed** | `~/mirabelle/proposed`: a copy of setup that Claude can edit in the upgrade project. The PC never runs anything from it |
| **kb** | Repo 2, `~/mirabelle/kb`: free content, present in every container at `/kb`. Holds the workflow, the knowledge and Claude's configuration. There is one, shared by all projects |
| **Workflow** | How you and Claude work. It lives in the kb and is not part of mirabelle |
| **`MIRABELLE_PROJECT`** | A variable inside the container holding the project name. The workflow uses it to find that project's knowledge |
| **Sessions** | Repo 3, `~/mirabelle/sessions`: one folder per project name with Claude's conversations and state |
| **Home** | The place the three repos are pushed to and pulled from: a folder, a NAS or any git server |
| **Account** | A Claude account, used for usage limits. Stored as one token |
| **Token** | A secret string that proves who you are: one per Claude account, one per git host |
| **Identity** | A git identity: name, email, the git hosts it may use and their tokens |
| **Host** | A git server an identity may use, e.g. `https://github.com` or your Gitea |
| **Site** | An internet address the firewall allows |
| **List** | A plain text file of allowed sites: one for all projects, optionally one per project name |
| **Firewall** | What limits the container's network: kernel rules plus a filter. Always on |
| **Filter** | The program inside the container (tinyproxy, on `127.0.0.1:3128`) that checks each destination against the lists |
| **Lock** | The name of the firewall's folder (`setup/lock/`) and of the command that re-applies the firewall (`mirabelle lock`) |
| **`dev`** | The ordinary user everything runs as inside a container. Not root |
| **`gate`** | The separate user the filter runs as. Only this user may send traffic out |
| **Upgrade project** | The one predefined project (name `upgrade`) where mirabelle's source is visible and writable |
| **Apply** | Bringing the proposed changes into setup, after you have seen them and said yes |
| **Tag** | A named point in setup's history, made at each apply, so you can return to it |
| **Secrets** | `~/mirabelle/secrets`: tokens. Never in git, never pushed |
| **Local** | `~/mirabelle/local`: generated and cache files for this PC only. Never in git |
| **`rescue.sh`** | A standalone script that undoes the last apply with plain git, for when mirabelle itself is broken |
| **tmux** | The program Claude runs inside, so that a session survives closing the window and can be reattached |
| **Attach** | Connecting VS Code or a terminal to a container that is already running |

---

## 3. Commands

Notes that apply to all of them:

- `-v` prints the exact `docker` and `git` commands. `--dry-run` prints them and runs nothing.
- Commands that act on a container use the current folder's name, or `-n <name>`.
- "Refuses when" means: prints the reason and the command to run instead, and changes nothing.
- Paths are relative to `~/mirabelle/` unless they start with `/` (inside the container) or `~`.

### 3.1 Install and image

#### `~/mirabelle/setup/install.sh`
Sets up the PC, once.

1. Checks that `git` and Docker are present and usable. If not, prints the official install steps and stops; it installs nothing system-wide.
2. For the kb and for sessions: if setup was cloned from a home that also holds `kb.git` / `sessions.git`, clones them. Otherwise creates new repos, the kb with the starter content (`setup/kb-starter/`).
3. Tags the installed version of setup `install-<date>`, so the first apply can be undone.
4. Creates `secrets/` (private to you), `local/`, and copies `setup/rescue.sh` to `rescue.sh`.
5. Links `~/.local/bin/mirabelle` to `setup/bin/mirabelle`. If that folder is not on your PATH, prints the line to add; it does not edit your shell files.
6. Prints what is left for you to do.

- **Reads:** `setup/`, the address setup was cloned from.
- **Writes:** `kb/`, `sessions/`, `secrets/`, `local/`, `rescue.sh`, `~/.local/bin/mirabelle`, one tag in `setup/`.
- **Refuses when:** `~/mirabelle/kb` or `sessions` already exist (it leaves them as they are and says so).

#### `mirabelle build [--fresh] [-n <project>]`
Builds the image.

1. Without `-n`: builds the base image `mirabelle` from `setup/image/`. With `-n shop`: builds the extra layer `mirabelle-shop` from `setup/projects/shop/Dockerfile`, on top of the base image.
2. Without `--fresh`, reuses the build steps that did not change. With `--fresh`, rebuilds everything from scratch, which also fetches the newest Claude Code and the newest version of any tool that is not pinned.
3. If an image of that name already exists, renames it to `previous` (replacing an older `previous`), together with its build record.
4. Writes the build record of the new image.
5. Prints the image's size, its Claude Code version, and what changed compared with the previous build record.

- Uses the PC's normal internet access. The build sees only the folder it builds from.
- **Reads:** `setup/image/` or `setup/projects/<name>/Dockerfile`; your user and group ids.
- **Writes:** Docker images (the new one, and the renamed previous one); `local/images/<image>.txt` and `local/images/<image>.previous.txt`.
- **Does not:** rebuild project layers when the base changes (`status` and `images` show which are older), or restart any container.
- **Refuses when:** `-n` is given and the base image or the project's Dockerfile is missing.

#### `mirabelle images`
Lists mirabelle's images: name, current or previous, date, size, Claude Code version, the setup version it was built from, which running containers use it, and whether it is older than its definition (or, for a project layer, older than the base).

- **Reads:** Docker's image and container lists, `local/images/`, `setup/image/`, `setup/projects/`. **Writes:** nothing.

#### `mirabelle prune`
Deletes the previous images and their build records, after listing them and your yes. Current images are never deleted.

- **Writes:** removes Docker images; deletes `local/images/*.previous.txt`.
- **Refuses, per image, when:** a running container uses it.

### 3.2 Accounts, identities, hosts, sites

#### `mirabelle account add <name>`
Adds a Claude account.

1. Starts a temporary container with the firewall on.
2. Runs Claude's token login in it. You open the address it shows in your browser and approve.
3. Asks you to paste the token it displays (input hidden) and stores it.
4. Removes the temporary container.

- **Reads:** the image, `setup/sites.txt`, `setup/lock/`.
- **Writes:** `secrets/accounts/<name>`.
- **Refuses when:** that account name exists, or the image is missing.

#### `mirabelle account ls`
Lists account names. Never prints a token. **Reads:** `secrets/accounts/`. **Writes:** nothing.

#### `mirabelle account rm <name>`
Deletes an account after your yes. **Writes:** deletes `secrets/accounts/<name>`. Running containers keep the token they were started with until stopped.

#### `mirabelle identity add <name>`
Adds a git identity. Asks for the git name and email.

- **Writes:** `setup/identities/<name>/gitconfig`, an empty `setup/identities/<name>/hosts.txt`, the folder `secrets/identities/<name>/`.
- **Refuses when:** that identity name exists.

#### `mirabelle identity ls`
Lists identities with their name and email. **Reads:** `setup/identities/`. **Writes:** nothing.

#### `mirabelle identity rm <name>`
Deletes an identity after your yes. **Writes:** deletes `setup/identities/<name>/` and `secrets/identities/<name>/`.

#### `mirabelle host add <identity> <https-url>`
Allows an identity to use a git host.

1. Asks for the user name and the token (input hidden).
2. Connects to the host from the PC to read its certificate. If it is not publicly trusted, shows who it belongs to and its fingerprint, and asks whether to trust it.
3. Looks up the host's address. If it is a private address (your LAN), records it so the firewall will allow exactly that address and port.

- **Reads:** `setup/identities/<identity>/`.
- **Writes:** a line in `setup/identities/<identity>/hosts.txt`; a line in `secrets/identities/<identity>/git-credentials`; if you chose to trust a certificate, `setup/identities/<identity>/ca/<host>.crt`.
- **Does not:** test the token, or change a running container (run `mirabelle lock` for that).
- **Refuses when:** the identity does not exist, the address is not `https://`, or the host is already listed.

#### `mirabelle host ls <identity>`
Lists the identity's hosts. Never prints a token. **Reads:** `hosts.txt`. **Writes:** nothing.

#### `mirabelle host rm <identity> <https-url>`
Removes a host after your yes. **Writes:** removes its lines from `hosts.txt` and `git-credentials`, and its certificate file.

#### `mirabelle site add <domain> [-n <project>]`
Adds a site to a list. **Writes:** a line in `setup/sites.txt`, or in `setup/projects/<name>/sites.txt` with `-n` (created if missing). **Does not** change a running container.

#### `mirabelle site ls [-n <project>]`
Prints the list for all projects, and the project's own list with `-n`. **Reads:** those files. **Writes:** nothing.

#### `mirabelle site rm <domain> [-n <project>]`
Removes a site from a list. **Writes:** that list file.

### 3.3 Working in a folder

#### `mirabelle run -a <account> -i <identity> [-p <port>] [-n <name>] [--previous]`
Starts this folder's container, with its firewall. Every step is printed.

1. Takes the project name from the folder name, or from `-n`.
2. Chooses the image: `mirabelle-<name>` if it exists, otherwise `mirabelle`. With `--previous`, the previous one of that image.
3. Creates `sessions/<name>/` and `local/vscode-server/<name>/` if they do not exist.
4. Writes the firewall's list for this container: the list for all projects, plus this project's list, plus the identity's hosts.
5. Starts the container `mirabelle-<name>`: user `dev`, `--cap-drop ALL`, `no-new-privileges`, the mounts below, and the port on the PC's `localhost` if `-p` was given. Environment: the account token (`CLAUDE_CODE_OAUTH_TOKEN`, passed through Docker's environment, never on the command line), `MIRABELLE_PROJECT`, `CLAUDE_CONFIG_DIR=/session`, `DISABLE_AUTOUPDATER=1`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, the proxy settings (`HTTPS_PROXY` …), `GIT_CONFIG_GLOBAL=/identity/gitconfig`, and the certificate bundle (`SSL_CERT_FILE` …).
6. Sets the firewall: `lock/apply.sh`, sent on standard input to one privileged `docker exec`. Then tests it: `lock/test.sh`, as `dev`, without privileges. If either fails, removes the container.
7. Runs `lib/inside/start.sh` as `dev`: builds the certificate bundle (the system's plus the identity's), links every entry of `/kb/claude/` into `/session`, writes `/session/.gitignore`.
8. Runs `/kb/start` if it exists and is executable. If it fails, says so; the container keeps running.
9. Prints the summary and the next commands.

| Mounted in the container | From the PC | Access |
|---|---|---|
| `/work/<name>` | the current folder | read-write |
| `/kb` | `kb/` | read-write |
| `/session` | `sessions/<name>/` | read-write |
| `/identity` | `setup/identities/<identity>/` | read-only |
| `/identity-secret` | `secrets/identities/<identity>/` | read-only |
| `/lock-run` | `local/lock/<name>/` | read-only |
| `~/.vscode-server` | `local/vscode-server/<name>/` | read-write |

- **Reads:** `secrets/accounts/<account>`, `setup/identities/<identity>/`, `setup/sites.txt`, `setup/projects/<name>/sites.txt`, `setup/lock/`, `setup/lib/inside/start.sh`, `kb/claude/`, `kb/start`.
- **Writes:** `local/lock/<name>/` (`allowed.txt`, `filter`, `private.txt`, `ports.txt`, `tinyproxy.conf`); the folders in step 3; links and `.gitignore` inside `sessions/<name>/`; one Docker container. Nothing in the project folder.
- **Refuses when:** a container with that name already exists, the image is missing, or the account or identity does not exist.

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
- **Claude itself** reads its configuration from the kb, writes its conversations to `sessions/<name>/`, and reads and writes `/work/<name>` and `/kb` as the work requires.
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
2. Prepares `proposed/`: creates it as a copy of setup if it does not exist; if it exists with no pending change, brings it up to date with setup; if it has pending changes, keeps them. Prints which.
3. Creates `sessions/upgrade/` if needed and writes the firewall's list (the list for all projects only).
4. Starts the container `mirabelle-upgrade` with `proposed/` at `/work/upgrade` (read-write), the kb, its session folder, the account token and `MIRABELLE_PROJECT=upgrade`. No identity, no Docker access.
5. Sets and tests the firewall, links the kb's configuration, runs `/kb/start`, as `run` does.
6. Opens Claude.

- **Reads:** `setup/` (to copy), `secrets/accounts/<account>`, `setup/sites.txt`, `setup/lock/`, `kb/`.
- **Writes:** `proposed/`, `sessions/upgrade/`, `local/lock/upgrade/`, `local/vscode-server/upgrade/`; one Docker container.
- **Refuses when:** the image is missing or the account does not exist.

#### `mirabelle status`
Shows what is pending. It does not contact the home.

- Files that differ between `proposed/` and `setup/`.
- Uncommitted changes in setup, kb and sessions.
- Commits not yet pushed, as of the last push or pull.
- Whether an image is older than its definition, or a project layer older than the base image.
- **Reads:** the three repos and `proposed/`, Docker's image list. **Writes:** nothing.

#### `mirabelle apply`
Brings the proposed changes into setup.

1. Shows every difference between `proposed/` and `setup/`, grouped: tool, image, firewall, lists, identities, documentation.
2. Waits for your yes.
3. Records the changes in setup as one commit and tags it.
4. Tells you what to run next: `mirabelle build` if the image changed, `mirabelle lock` if the firewall or a list changed.

- **Reads:** `proposed/`, `setup/`.
- **Writes:** `setup/` (files, one commit, one tag); `proposed/` (its pending edits are committed there).
- **Does not:** build, restart or re-lock anything.
- **Refuses when:** there is nothing to apply; setup has uncommitted changes (run `mirabelle save` first); or the same lines changed on both sides (nothing is changed, and it names the files).

#### `mirabelle discard`
Throws the proposed changes away after your yes. **Writes:** `proposed/` becomes a copy of setup again.

#### `mirabelle rollback [<tag>]`
Undoes the last apply that has not been undone yet, after showing it and your yes. With a tag, undoes every apply after that tag.

1. Lists the applies, and which ones will be undone.
2. Shows what changes.
3. Reverts each of those apply commits (git revert): exactly what the apply changed is undone; everything you saved since (identities, sites, …) is kept.
4. In a site list (`sites.txt`, `projects/<name>/sites.txt`) changed both by the apply and later by you: removes the lines the apply added, puts back those it removed, keeps yours.
5. Records one commit `rollback: undo N apply(s)` with a line `Reverts: <commit>` per apply, and tags it `rollback-<date>`. Running rollback again undoes the apply before.

- **Reads / writes:** `setup/`; `proposed/` is reset to setup if it had nothing pending.
- **Does not:** rebuild the image (it tells you about `mirabelle run … --previous` and `mirabelle build`).
- **Refuses when:** setup has unsaved changes; there is no apply to undo; another file changed again since the apply (it names it, and changes nothing).

#### `~/mirabelle/rescue.sh`
Undoes the last apply not yet undone, with plain git and without using mirabelle. For when mirabelle itself no longer runs. Shows the apply, asks, keeps uncommitted changes in `git stash`, refuses if the undo is not clean. **Reads / writes:** `setup/`.

### 3.5 Save, push, pull

#### `mirabelle home [<path-or-url>]`
Without an argument, prints the current home. With one, sets where the three repos are pushed and pulled: `<home>/mirabelle.git`, `<home>/kb.git`, `<home>/sessions.git`. If the home is a folder and those repos do not exist there, offers to create them.

- **Writes:** the remote address in each repo's git configuration; possibly three empty repos at the home.

#### `mirabelle save`
Commits what is uncommitted in setup, kb and sessions, and lists the files. It does not contact the home.

- **Reads / writes:** the three repos.
- In sessions, a keep-list decides what is recorded: conversations and Claude's own state. Links and caches are left out.

#### `mirabelle push`
Pushes the three repos to the home, one after the other, and prints each result. It never forces. A refused push is reported and the others continue.

- **Reads:** the three repos. **Writes:** the home.
- **Does not:** commit. It tells you if something is not saved.

#### `mirabelle pull`
Pulls the three repos from the home. For each repo it only moves forward to what the home has; it never merges or rewrites.

- **Reads:** the home. **Writes:** the three repos.
- **Refuses, per repo, when:** the repo has unsaved changes, or has commits the home does not have. It names the repo and leaves it untouched.

---

## 4. Map of all files

| Path under `~/mirabelle/` | What it is | In git | Written by | Visible in containers |
|---|---|---|---|---|
| `setup/bin/`, `setup/lib/` | The mirabelle tool | setup | `apply`, `rollback` | No |
| `setup/README.md`, `setup/install.sh` | Manual and installer | setup | `apply` | No |
| `setup/image/` | Image definition | setup | `apply` | No |
| `setup/lock/` | The firewall's two scripts: `apply.sh` (privileged) and `test.sh` (as `dev`) | setup | `apply`, `rollback` | No (sent on standard input) |
| `setup/lib/inside/start.sh` | What runs in a container at start, as `dev` | setup | `apply`, `rollback` | No (sent on standard input) |
| `setup/kb-starter/` | Content of a new kb | setup | `apply` | No |
| `setup/sites.txt` | Sites for all projects | setup | `site`, `apply` | No (its content is copied into the container's list) |
| `setup/projects/<name>/sites.txt` | Sites for one project name | setup | `site`, `apply` | No (same) |
| `setup/projects/<name>/Dockerfile` | Extra image layer for one project name | setup | `apply` | No |
| `setup/identities/<name>/gitconfig` | Git name, email, settings | setup | `identity` | Read-only, at `/identity`, for containers started with that identity |
| `setup/identities/<name>/hosts.txt` | Git hosts of the identity | setup | `host` | Same |
| `setup/identities/<name>/ca/` | Certificates you chose to trust | setup | `host` | Same |
| `proposed/` | Copy of setup for Claude to edit | its own copy of setup's history | `upgrade`, `apply`, `discard`, Claude | Only in the upgrade container, at `/work/upgrade` |
| `kb/` | The kb | kb | Claude, you, `save` (commits) | Read-write, at `/kb`, in every container |
| `kb/claude/` | Claude's configuration | kb | Claude, you | Same |
| `kb/start` | Optional start script | kb | Claude, you | Same |
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
| The home | The three repos | `home` (creation), `push` |
| Docker's own storage | The images and the running containers | `build`, `prune`, `run`, `upgrade`, `account add`, `stop` |
| VS Code's settings on Windows | Its note about an attached container | VS Code |
