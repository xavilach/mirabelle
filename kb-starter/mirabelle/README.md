# mirabelle, seen from inside a container

mirabelle is the tool on the PC that starts this container. It knows nothing about how you work; it only provides the container, the account, the git identity, the firewall, and this kb.

## What you can see

| Path | What | Access |
|---|---|---|
| `/work/<project>` | the project folder | read-write |
| `/kb` | the shared kb (same in every project) | read-write |
| `/session` | your own configuration and conversations for this project | read-write |
| `/identity` | git name, email, hosts, trusted certificates | read-only |
| `/identity-secret` | git tokens for those hosts | read-only |
| `/lock-run` | the firewall's lists for this container | read-only |

Nothing else from the PC is visible. You are not root and cannot become root.

## Network

Everything goes through a filter at `127.0.0.1:3128` (already set in `HTTPS_PROXY`). It allows only the domains in `/lock-run/allowed.txt` (subdomains included). Direct connections, and the local network except the listed git hosts, are refused. You cannot change this.

## When you need something

- **A site that is blocked:** tell the user which domain and why. They add it with `mirabelle site add <domain>` and `mirabelle lock`.
- **A tool that is missing:** tell the user what and why. You cannot install system packages here. Tools are added to the image in the upgrade project.
- Write the request in this kb too (for example in `/kb/projects/$MIRABELLE_PROJECT/`), so it is not lost.

## The upgrade project

The user starts it with `mirabelle upgrade`. There, `/work/upgrade` is mirabelle's full source (a copy called "proposed"). You may change anything in it and commit. Nothing takes effect until the user runs `mirabelle apply` on the PC, which shows every change and asks.

Inside `/work/upgrade`:
- `image/Dockerfile` and `image/install-claude.sh`: the image (tools go here);
- `sites.txt`: sites for all projects; `projects/<name>/sites.txt`: for one project;
- `projects/<name>/Dockerfile`: an extra image layer for one project (starts with `ARG BASE` and `FROM ${BASE}`);
- `lock/`: the firewall; `bin/`, `lib/`: the tool; `docs/`: the design and reference.

Keep `docs/REFERENCE.md` true when you change behaviour. Keep tool versions pinned where they matter. After an image change, the user runs `mirabelle build`.
