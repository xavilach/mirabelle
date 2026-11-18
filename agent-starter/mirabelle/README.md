# mirabelle, seen from inside a container

mirabelle is the tool on the PC that starts this container. It knows nothing about how you work; it only provides the container, the account, the git identity, the firewall, and the kb (`/kb/agent` and the selected `/kb/libraries/<name>`).

## What you can see

| Path | What | Access |
|---|---|---|
| `/work/<project>` | the project folder | read-write |
| `/kb/agent` | the shared part of the kb (same in every project), a git repo | read-write |
| `/kb/libraries/<name>` | the libraries selected for this project (`$MIRABELLE_LIBRARIES`), each a git repo | read-write |
| `/session` | your own configuration and conversations for this project | read-write |
| `/identity` | git name, email, hosts, trusted certificates | read-only |
| `/identity-secret` | git tokens for those hosts | read-only |
| `/lock-run` | the firewall's lists for this container | read-only |

Nothing else from the PC is visible: other libraries are not mounted, so material for one client never reaches another client's project. You are not root and cannot become root.

## Network

Everything goes through a filter at `127.0.0.1:3128` (already set in `HTTPS_PROXY`). It allows only the domains in `/lock-run/allowed.txt` (subdomains included). Direct connections, and the local network except the listed git hosts, are refused. You cannot change this.

## When you need something

- **A site that is blocked:** tell the user which domain and why. They add it with `mirabelle site add <domain>` and `mirabelle lock`.
- **A tool that is missing:** tell the user what and why. You cannot install system packages here. Tools are added to the image in the upgrade project.
- Write the request in the kb too (for example in `/kb/agent/projects/$MIRABELLE_PROJECT/`), so it is not lost.
- **A library you need is not mounted:** tell the user its name; they restart with `mirabelle run ... -l <name>`. A new library is created with `mirabelle library add <name>`.

## The upgrade project

The user starts it with `mirabelle upgrade`. There, `/work/upgrade` holds copies (called "proposed") of the two repos that make up mirabelle's setup. You may change anything in them and commit. Nothing takes effect until the user runs `mirabelle apply` on the PC, which shows every change and asks.

- `/work/upgrade/plumbing`: **the tool itself**, shared on GitHub. Changes here reach every user of this plumbing, so keep them general.
  - `image/Dockerfile` and `image/install-claude.sh`: the image (tools go here);
  - `sites.txt`: the sites the plumbing itself needs (Claude, VS Code);
  - `lock/`: the firewall; `bin/`, `lib/`: the tool; `docs/`: the design and reference;
  - `agent-starter/`, `config-starter/`: what a new install starts with.
- `/work/upgrade/config`: **the user's own configuration**, pushed to their home, never to GitHub.
  - `sites.txt`: the user's sites for all projects; `projects/<name>/sites.txt`: for one project;
  - `projects/<name>/Dockerfile`: an extra image layer for one project (starts with `ARG BASE` and `FROM ${BASE}`);
  - `libraries.txt`: the list of libraries; `identities/`: git identities (no tokens).

Keep `plumbing/docs/REFERENCE.md` true when you change behaviour. Keep tool versions pinned where they matter. After an image change, the user runs `mirabelle build`.
