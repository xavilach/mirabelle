#!/bin/bash
# install.sh: sets up mirabelle on this PC, once. Run by hand, without Claude.
#
#   git clone https://github.com/xavilach/mirabelle.git ~/mirabelle/plumbing
#   ~/mirabelle/plumbing/install.sh [<home>]
#
# <home> is where your own data lives (a folder, a NAS, any git server). With
# it, your config, agent, sessions and libraries are cloned from there (those
# that exist); without it, they are created new and you can set the home later
# with `mirabelle home <home>`.
#
# It prints every step. It installs nothing system-wide and edits none of your
# shell files. What it creates, all under ~/mirabelle/ (the folder holding
# plumbing/), plus one link:
#   config/          your configuration: sites, identities, projects, libraries list
#   kb/agent/        the shared part of the kb
#   kb/libraries/    the libraries listed in config/libraries.txt
#   sessions/        Claude's conversations per project
#   secrets/         tokens, readable only by you (never in git)
#   local/           files for this PC only (never in git)
#   rescue.sh        standalone rollback (a copy of plumbing/rescue.sh)
#   ~/.local/bin/mirabelle -> plumbing/bin/mirabelle
set -euo pipefail

say()  { printf '%s\n' "$*"; }
step() { printf '%-14s %s\n' "$1" "$2"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
gitm() { git -c user.name=mirabelle -c user.email=mirabelle@localhost "$@"; }

PLUMBING=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
ROOT=$(dirname "$PLUMBING")

[[ $# -le 1 ]] || die "usage: install.sh [<home>]"
home=${1:-}
home=${home%/}
case "$home" in
  ~*) home=${home/#\~/$HOME} ;;
  ./*|../*) home=$(readlink -f "$home") ;;
esac

[[ "$(id -u)" != 0 ]] || die "run install.sh as your normal user, not as root"
[[ "$(basename "$PLUMBING")" == plumbing ]] || die "this folder must be called 'plumbing' (it is $PLUMBING); clone it as ~/mirabelle/plumbing"
step root "$ROOT"

# --- what the PC needs -------------------------------------------------------
command -v git >/dev/null || die "git is missing. On Ubuntu: sudo apt install git"
step git "$(git --version)"
if ! command -v docker >/dev/null; then
  say "Docker Engine is missing. Install it (official instructions):"
  say "  https://docs.docker.com/engine/install/ubuntu/"
  say "then let your user use it without sudo:"
  say "  sudo usermod -aG docker \$USER     (then close and reopen the terminal)"
  say "and run install.sh again."
  exit 1
fi
docker info >/dev/null 2>&1 || die "Docker is installed but not usable by you: is it running, and are you in the 'docker' group? (sudo usermod -aG docker \$USER, then reopen the terminal)"
step docker "$(docker --version)"
if command -v openssl >/dev/null; then step openssl "found (used by: mirabelle host add)"
else say "note: openssl not found; host add will not check certificates"
fi
[[ -d "$PLUMBING/.git" ]] || die "$PLUMBING is not a git repo; clone it with git instead of copying it"
step plumbing "$PLUMBING ($(git -C "$PLUMBING" remote get-url origin 2>/dev/null || echo 'no origin'))"
if [[ -n "$home" ]]; then step home "$home"
else step home "none yet (set it later: mirabelle home <path-or-url>)"
fi

# --- your data: cloned from the home, or new ------------------------------------
make_repo() {   # make_repo <folder under root> <name at the home> <starter dir or "">
  local dir="$ROOT/$1" from=$3 url=""
  [[ -n "$home" ]] && url="$home/$2"
  if [[ -e "$dir" ]]; then step "$1" "already there, left as is"; return; fi
  if [[ -n "$url" ]] && [[ -n "$(git ls-remote "$url" 2>/dev/null)" ]]; then
    git clone -q "$url" "$dir"
    step "$1" "cloned from $url"
    return
  fi
  mkdir -p "$(dirname "$dir")"
  git init -q -b main "$dir"
  if [[ -n "$from" ]]; then cp -r "$from"/. "$dir"/; fi
  gitm -C "$dir" add -A
  gitm -C "$dir" commit -q --allow-empty -m "start"
  [[ -n "$url" ]] && git -C "$dir" remote add origin "$url"
  step "$1" "created${url:+, home $url (create it there before mirabelle push, or run mirabelle home $home)}"
}

make_repo config config.git "$PLUMBING/config-starter"
make_repo kb/agent agent.git "$PLUMBING/agent-starter"

tmp=$(mktemp -d)
cat > "$tmp/README.md" <<'EOF'
# sessions

Claude's conversations and state, one folder per project name. Each folder is
Claude's configuration folder inside that project's container (/session).
Written by Claude; committed by `mirabelle save`.
EOF
make_repo sessions sessions.git "$tmp"
rm -rf "$tmp"

if [[ -f "$ROOT/config/libraries.txt" ]]; then
  while read -r lib; do
    [[ -n "$lib" ]] || continue
    tmp=$(mktemp -d)
    printf '# Library: %s\n\nWhat this library holds, and where.\n' "$lib" > "$tmp/INDEX.md"
    make_repo "kb/libraries/$lib" "library-$lib.git" "$tmp"
    rm -rf "$tmp"
  done < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ROOT/config/libraries.txt" | grep -v '^$' || true)
fi

# --- folders and links ----------------------------------------------------------
mkdir -p "$ROOT/secrets/accounts" "$ROOT/secrets/identities" "$ROOT/local"
chmod 700 "$ROOT/secrets" "$ROOT/secrets/accounts" "$ROOT/secrets/identities"
step secrets "$ROOT/secrets (readable only by you)"
step local "$ROOT/local"

cp "$PLUMBING/rescue.sh" "$ROOT/rescue.sh"; chmod +x "$ROOT/rescue.sh"
step rescue "$ROOT/rescue.sh"

mkdir -p "$HOME/.local/bin"
ln -sfn "$PLUMBING/bin/mirabelle" "$HOME/.local/bin/mirabelle"
step link "$HOME/.local/bin/mirabelle -> $PLUMBING/bin/mirabelle"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) say "note: $HOME/.local/bin is not on your PATH. Add this line to ~/.bashrc:"
     say "        export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

say ""
say "Done. Next:"
say "  mirabelle build                         build the image (a few minutes)"
say "  mirabelle account add <name>            add a Claude account"
say "  mirabelle identity add <name>           add a git identity (if not cloned from your home)"
say "  mirabelle host add <name> https://...   give it a git host (tokens are never cloned)"
[[ -z "$home" ]] && say "  mirabelle home <path-or-url>            where your config, agent, sessions and libraries go"
say ""
say "Once, on Windows: install VS Code and its 'Dev Containers' extension, and"
say "turn on the Dev Containers setting 'Execute in WSL'."
