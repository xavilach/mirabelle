# shellcheck shell=bash
# Shared helpers: output, running commands, checks, names, paths.

MB_AGENT="$MB_ROOT/kb/agent"        # the shared part of the kb
MB_LIBRARIES="$MB_ROOT/kb/libraries" # the libraries, picked per run
MB_SESSIONS="$MB_ROOT/sessions"
MB_SECRETS="$MB_ROOT/secrets"
MB_LOCAL="$MB_ROOT/local"
MB_PROPOSED="$MB_ROOT/proposed"

MB_VERBOSE=0   # -v: print every docker/git command before running it
MB_DRY=0       # --dry-run: print commands that would change something, run none

# --- output -----------------------------------------------------------------

say()  { printf '%s\n' "$*"; }
line() { printf '%-10s %s\n' "$1" "$2"; }            # "label     value"
more() { printf '%-10s %s\n' "" "$1"; }               # continuation of a line
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
next() { printf 'next:      %s\n' "$*"; }

# Aligns tab-separated lines into columns (no dependency on 'column').
table() {
  awk -F'\t' '{ for (i = 1; i <= NF; i++) { cell[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) }
                 if (NF > nf) nf = NF; n = NR }
               END { for (r = 1; r <= n; r++) { s = ""
                       for (i = 1; i <= nf; i++) s = s sprintf(i < nf ? "%-" w[i] + 2 "s" : "%s", cell[r, i])
                       print s } }'
}

# Prints a command so that it can be copied and run as is.
show_cmd() { local s; printf -v s '%q ' "$@"; printf '%s\n' "${s% }"; }

# Runs a command that changes something. Honours -v and --dry-run.
# The "would run" line goes to stderr, so it shows even when the command's own
# output is discarded.
run() {
  if (( MB_DRY )); then { printf 'would run: '; show_cmd "$@"; } >&2; return 0; fi
  if (( MB_VERBOSE )); then printf '+ ' >&2; show_cmd "$@" >&2; fi
  "$@"
}

# Runs a command that only reads. Honours -v; runs even with --dry-run.
query() {
  if (( MB_VERBOSE )); then printf '+ ' >&2; show_cmd "$@" >&2; fi
  "$@"
}

# Asks a yes/no question. Default is no. In --dry-run, never says yes.
confirm() {
  local answer
  if (( MB_DRY )); then say "(dry run: would ask \"$1\")"; return 1; fi
  read -r -p "$1 [y/N] " answer || return 1
  [[ "$answer" == y || "$answer" == Y || "$answer" == yes ]]
}

# Commits made by mirabelle itself are authored "mirabelle", so they are easy
# to tell apart from yours and Claude's.
git_mb() { run git -c user.name=mirabelle -c user.email=mirabelle@localhost "$@"; }

# --- checks -----------------------------------------------------------------

need_not_root() {
  [[ "$(id -u)" != 0 ]] || die "run mirabelle as your normal user, not as root"
}

need_docker() {
  command -v docker >/dev/null || die "docker is not installed (see README: Install)"
  docker info >/dev/null 2>&1 || die "cannot talk to Docker: is it running, and are you in the 'docker' group?"
}

need_name() {   # need_name <kind> <value>
  [[ "$2" =~ ^[a-z0-9][a-z0-9_.-]*$ ]] ||
    die "$1 name '$2' is not valid: use lowercase letters, digits, '.', '_' or '-'"
}

valid_domain() {
  [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$ ]]
}

is_private_ipv4() {
  local a b
  IFS=. read -r a b _ _ <<<"$1"
  [[ $a == 10 || $a == 127 || $a == 0 ]] && return 0
  [[ $a == 172 && $b -ge 16 && $b -le 31 ]] && return 0
  [[ $a == 192 && $b == 168 ]] && return 0
  [[ $a == 169 && $b == 254 ]] && return 0
  [[ $a == 100 && $b -ge 64 && $b -le 127 ]] && return 0
  return 1
}

# --- names ------------------------------------------------------------------

# Project name: -n <name>, or the current folder's name made safe.
project_name() {
  local given=${1:-} name
  if [[ -n "$given" ]]; then
    need_name project "$given"; printf '%s\n' "$given"; return
  fi
  name=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9_.-]/-/g' -e 's/^[^a-z0-9]*//')
  [[ -n "$name" ]] || die "cannot make a project name from folder '$(basename "$PWD")'; use -n <name>"
  printf '%s\n' "$name"
}

container_of() { printf 'mirabelle-%s\n' "$1"; }

container_exists()  { docker container inspect "$1" >/dev/null 2>&1; }
container_running() { [[ "$(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == true ]]; }
image_exists()      { docker image inspect "$1" >/dev/null 2>&1; }
label_of()          { docker container inspect -f "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null; }

need_running() {   # need_running <container>
  container_running "$1" || die "container $1 is not running (start it with: mirabelle run ...)"
}

# --- force -----------------------------------------------------------------

# take_force "$@": removes -f / --force from the arguments.
# Sets MB_FORCE (0 or 1) and MB_REST (the other arguments).
take_force() {
  MB_FORCE=0; MB_REST=()
  local a
  for a in "$@"; do
    case "$a" in
      -f|--force) MB_FORCE=1 ;;
      *) MB_REST+=("$a") ;;
    esac
  done
}

# Containers made by mirabelle (running or not) whose label <key> holds
# <value> (labels holding several names, like mirabelle.libraries, count
# each name). Prints their names. Prints nothing if Docker is not reachable.
containers_using() {   # containers_using <label key> <value>
  command -v docker >/dev/null && docker info >/dev/null 2>&1 || return 0
  docker ps -a --filter label=mirabelle.project --format "{{.Names}}\t{{.Label \"$1\"}}" |
    awk -F'\t' -v v="$2" '{ n = split($2, w, " "); for (i = 1; i <= n; i++) if (w[i] == v) { print $1; break } }'
}

# Refuses to remove something a container uses, unless -f.
#   guard_in_use <what> <label key> <value>
guard_in_use() {
  local what=$1 key=$2 value=$3 used
  if ! { command -v docker >/dev/null && docker info >/dev/null 2>&1; }; then
    warn "Docker is not reachable: could not check whether a container uses $what"
    return 0
  fi
  used=$(containers_using "$key" "$value" | paste -sd' ')
  [[ -n "$used" ]] || return 0
  if (( MB_FORCE )); then
    warn "$what is used by: $used (-f: going ahead; those containers keep what they already have until stopped)"
  else
    die "$what is used by: $used. Stop them first (mirabelle stop -n <project>), or use -f"
  fi
}

# --- global flags -----------------------------------------------------------

# Removes -v / --dry-run from anywhere in the arguments, up to a "--".
# Everything after "--" is kept as is (it is passed on, e.g. to claude).
# Result in MB_ARGS.
take_global_flags() {
  MB_ARGS=()
  local a rest=0
  for a in "$@"; do
    if (( rest )); then MB_ARGS+=("$a"); continue; fi
    case "$a" in
      --)           rest=1; MB_ARGS+=("$a") ;;
      -v|--verbose) MB_VERBOSE=1 ;;
      --dry-run)    MB_DRY=1 ;;
      *)            MB_ARGS+=("$a") ;;
    esac
  done
}
