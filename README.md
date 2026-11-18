# mirabelle

Run Claude Code in a container, one per project folder, behind a firewall, with one shared knowledge folder (the **kb**).

- Claude never runs on your PC: only in containers, as an ordinary user without privileges.
- A container sees its project folder, the kb, its own conversations, one Claude account and one git identity. Nothing else.
- The firewall is always on: only listed sites are reachable; your PC and local network are refused except the git hosts you list.
- Nothing is written into your project folders.
- Everything mirabelle keeps is plain files under `~/mirabelle/`, in three git repos you can push to any git remote.
- mirabelle itself is changed only through one upgrade container, and nothing takes effect until you `mirabelle apply`.

Design: [docs/GOALS.md](docs/GOALS.md) (what and why), [docs/SPEC.md](docs/SPEC.md) (how), [docs/REFERENCE.md](docs/REFERENCE.md) (every command, every file).

---

## Install (once)

Needs, in WSL (Ubuntu): **git** and **Docker Engine**, with your user allowed to use Docker.

```bash
git clone <home>/mirabelle.git ~/mirabelle/setup
~/mirabelle/setup/install.sh
mirabelle build
```

`install.sh` prints every step. It creates `~/mirabelle/{kb,sessions,secrets,local,rescue.sh}` and the link `~/.local/bin/mirabelle`. Nothing else is installed on the PC, then or later: every tool Claude needs goes into the image.

Once, on Windows: install VS Code with the **Dev Containers** extension, and turn on its setting **Execute in WSL**.

## Declare who you are (once)

```bash
mirabelle account add work                     # Claude login, in a temporary container
mirabelle identity add me                      # git name and email
mirabelle host add me https://github.com       # asks for a token
mirabelle host add me https://gitea.lan:3000   # also checks the certificate
```

## Daily use

```bash
cd ~/code/shop
mirabelle run -a work -i me
mirabelle code          # VS Code attached to the container
mirabelle claude        # or Claude in the terminal; run again to reattach
```

- Closing VS Code or the terminal does not stop Claude. `mirabelle ps` lists what runs; `mirabelle claude` reattaches.
- Usage limit reached: `mirabelle stop`, then `mirabelle run -a personal -i me`. The conversations are still there.
- A site is blocked: `mirabelle site add docs.example.org -n shop`, then `mirabelle lock`.
- A tool is missing: `mirabelle upgrade -a work`, ask Claude, then `mirabelle apply` and `mirabelle build`.
- Before leaving this computer: `mirabelle save` and `mirabelle push`. On the other one: `mirabelle pull`.

Every command accepts `-v` (show the exact docker and git commands) and `--dry-run` (show them, change nothing). `mirabelle help` lists all commands.

---

## Where things are

```
~/mirabelle/
├── setup/      this repo: the tool, the image, the firewall, the lists, identities (no secrets)
├── proposed/   the copy of setup that Claude edits in the upgrade container
├── kb/         the shared kb, mounted at /kb in every container
├── sessions/   Claude's conversations, one folder per project name
├── secrets/    tokens (accounts/, identities/), readable only by you, never in git
├── local/      this PC only: the firewall's lists per running container, build records, VS Code caches
└── rescue.sh   undoes the last apply with plain git
```

Docker keeps the images (`mirabelle images`) and the running containers (`mirabelle ps`). There are no Docker volumes.

---

## Operating without mirabelle

Everything mirabelle does is plain Docker and git. `mirabelle <command> --dry-run` prints the exact commands. The essentials, by hand:

**A broken apply.** `~/mirabelle/rescue.sh` undoes the last apply. By hand:

```bash
cd ~/mirabelle/setup
git log --author=mirabelle --grep='^apply:' --format='%h %cd %s'
git revert --no-edit <commit>
```

**See and stop containers.**

```bash
docker ps --filter label=mirabelle.project
docker rm -f mirabelle-<project>
```

**Open a shell or Claude in a running container.**

```bash
docker exec -it -u dev -w /work/<project> mirabelle-<project> bash
docker exec -it -u dev mirabelle-<project> tmux attach -t claude
```

**Re-apply the firewall** (the only privileged command mirabelle uses):

```bash
docker exec -i -u root --privileged mirabelle-<project> bash -s < ~/mirabelle/setup/lock/apply.sh
docker exec -i -u dev mirabelle-<project> bash -s < ~/mirabelle/setup/lock/test.sh
```

**Build the image.**

```bash
docker build -t mirabelle:latest --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) ~/mirabelle/setup/image
```

**Files you can edit directly** (then `mirabelle save`):

- `setup/sites.txt`
- `setup/projects/<name>/sites.txt`
- `setup/identities/<name>/gitconfig`
- `secrets/accounts/<name>`: one line, the token
- `secrets/identities/<name>/git-credentials`: `https://user:token@host` lines

**Sync with plain git:** `git -C ~/mirabelle/<setup|kb|sessions> pull|push`. If both computers changed the same repo, `push` and `pull` refuse. Resolve it in that repo with `git pull` (a normal merge), then `mirabelle push`.

---

## Troubleshooting

| Symptom | What to do |
|---|---|
| `run` says the firewall test failed | The container was removed on purpose. Run with `-v` to see each step. `mirabelle logs` is empty after removal; run again and check `apply.sh`'s output |
| Something cannot reach a site | `mirabelle logs` shows each refused domain. Add it with `mirabelle site add`, then `mirabelle lock` |
| VS Code cannot install its server or extensions | Same as above: the domains it needs show in `mirabelle logs` |
| `mirabelle code` does nothing | In VS Code: *Dev Containers: Attach to Running Container…* → `mirabelle-<project>`, open `/work/<project>` |
| `push`/`pull` refuse | See "Sync with plain git" above |
| Files created in the container are writable by everyone | Docker's own umask is 0000. `mirabelle claude`/`shell` and VS Code terminals set 022; check `umask` in other tools |
