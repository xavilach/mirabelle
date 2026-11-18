#!/bin/bash
# install.sh: sets up mirabelle on this PC, once. Run by hand, without Claude.
#
#   git clone <home>/mirabelle.git ~/mirabelle/setup
#   ~/mirabelle/setup/install.sh
#
# It prints every step. It installs nothing system-wide and edits none of your
# shell files. What it creates, all under ~/mirabelle/ (the folder holding
# setup/), plus one link:
#   kb/agent/        the shared part of the kb (cloned from the home if it is there, else new)
#   kb/libraries/    the libraries listed in setup/libraries.txt (cloned or new)
#   sessions/        Claude's conversations per project (cloned or new)
#   secrets/    tokens, readable only by you
#   local/      files for this PC only
#   rescue.sh   standalone rollback (a copy of setup/rescue.sh)
#   ~/.local/bin/mirabelle -> setup/bin/mirabelle
set -euo pipefail

say()  { printf '%s\n' "$*"; }
step() { printf '%-10s %s\n' "$1" "$2"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
gitm() { git -c user.name=mirabelle -c user.email=mirabelle@localhost "$@"; }

SETUP=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
ROOT=$(dirname "$SETUP")

[[ "$(id -u)" != 0 ]] || die "run install.sh as your normal user, not as root"
[[ "$(basename "$SETUP")" == setup ]] || die "this folder must be called 'setup' (it is $SETUP); clone it as ~/mirabelle/setup"
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

[[ -d "$SETUP/.git" ]] || die "$SETUP is not a git repo; clone it with git instead of copying it"

# --- where the other repos come from ------------------------------------------
home=""
origin=$(git -C "$SETUP" remote get-url origin 2>/dev/null || true)
if [[ "$origin" == */mirabelle.git ]]; then home=${origin%/mirabelle.git}; step home "$home"
else step home "none yet (set it later: mirabelle home <path-or-url>)"
fi

make_repo() {   # make_repo <folder> <name at the home> <initial content dir or "">
  local dir="$ROOT/$1" from=$3 url=""
  [[ -n "$home" ]] && url="$home/$2"
  if [[ -e "$dir" ]]; then step "$1" "already there, left as is ($dir)"; return; fi
  if [[ -n "$url" ]] && git ls-remote "$url" >/dev/null 2>&1 && [[ -n "$(git ls-remote "$url")" ]]; then
    git clone -q "$url" "$dir"
    step "$1" "cloned from $url"
    return
  fi
  git init -q -b main "$dir"
  if [[ -n "$from" ]]; then cp -r "$from"/. "$dir"/; fi
  gitm -C "$dir" add -A
  gitm -C "$dir" commit -q --allow-empty -m "start"
  [[ -n "$url" ]] && git -C "$dir" remote add origin "$url"
  step "$1" "created ($dir)${url:+, home $url}"
}

mkdir -p "$ROOT/kb"
make_repo kb/agent agent.git "$SETUP/agent-starter"

tmp_sessions=$(mktemp -d)
cat > "$tmp_sessions/README.md" <<'EOF'
# sessions

Claude's conversations and state, one folder per project name. Each folder is
Claude's configuration folder inside that project's container (/session).
Written by Claude; committed by `mirabelle save`.
EOF
make_repo sessions sessions.git "$tmp_sessions"
rm -rf "$tmp_sessions"

# Libraries listed in setup/libraries.txt (none on a first install).
if [[ -f "$SETUP/libraries.txt" ]]; then
  mkdir -p "$ROOT/kb/libraries"
  while read -r lib; do
    [[ -n "$lib" ]] || continue
    tmp_lib=$(mktemp -d)
    printf '# Library: %s\n\nWhat this library holds, and where.\n' "$lib" > "$tmp_lib/INDEX.md"
    make_repo "kb/libraries/$lib" "library-$lib.git" "$tmp_lib"
    rm -rf "$tmp_lib"
  done < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$SETUP/libraries.txt" | grep -v '^$' || true)
fi

# --- mark the installed version, so that the first apply can be rolled back -----
if [[ -z "$(git -C "$SETUP" tag -l 'install-*' 'apply-*' 'rollback-*')" ]]; then
  tag="install-$(date +%Y%m%d-%H%M%S)"
  gitm -C "$SETUP" tag -a "$tag" -m "installed"
  step tag "$tag (the version installed; mirabelle rollback can return to it)"
fi

# --- folders and links ----------------------------------------------------------
mkdir -p "$ROOT/secrets/accounts" "$ROOT/secrets/identities" "$ROOT/local"
chmod 700 "$ROOT/secrets" "$ROOT/secrets/accounts" "$ROOT/secrets/identities"
step secrets "$ROOT/secrets (readable only by you)"
step local "$ROOT/local"

cp "$SETUP/rescue.sh" "$ROOT/rescue.sh"; chmod +x "$ROOT/rescue.sh"
step rescue "$ROOT/rescue.sh"

mkdir -p "$HOME/.local/bin"
ln -sfn "$SETUP/bin/mirabelle" "$HOME/.local/bin/mirabelle"
step link "$HOME/.local/bin/mirabelle -> $SETUP/bin/mirabelle"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) say "note: $HOME/.local/bin is not on your PATH. Add this line to ~/.bashrc:"
     say "        export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

say ""
say "Done. Next:"
say "  mirabelle build                         build the image (a few minutes)"
say "  mirabelle account add <name>            add a Claude account"
say "  mirabelle identity add <name>           add a git identity"
say "  mirabelle host add <name> https://...   give it a git host"
say ""
say "Once, on Windows: install VS Code and its 'Dev Containers' extension, and"
say "turn on the Dev Containers setting 'Execute in WSL'."
