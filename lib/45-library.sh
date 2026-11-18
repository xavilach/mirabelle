# shellcheck shell=bash
# Libraries: extra knowledge you pick per project with `run -l <name>`.
#
# The kb is two parts: kb/agent (shared, always mounted) and the libraries.
# Each library is its own git repo, like kb/agent:
#   ~/mirabelle/kb/libraries/<name>/   (with its .git inside: Claude can commit)
#   <home>/library-<name>.git          (where push and pull go)
# The list of libraries is setup/libraries.txt, so another computer knows
# which ones exist (`pull` and install.sh clone the missing ones).
# A container sees only the libraries selected with -l, read-write, at
# /kb/libraries/<name>.

MB_LIBRARY_LIST="$MB_SETUP/libraries.txt"

library_names() {   # names in setup/libraries.txt
  [[ -f "$MB_LIBRARY_LIST" ]] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$MB_LIBRARY_LIST" | grep -v '^$' || true
}

# The home, from kb/agent's remote (".../agent.git").
home_base() {
  local url
  url=$(git -C "$MB_AGENT" remote get-url origin 2>/dev/null) || return 1
  [[ "$url" == */agent.git ]] || return 1
  printf '%s\n' "${url%/agent.git}"
}

# Every repo mirabelle saves, pushes and pulls, as paths under ~/mirabelle.
all_repos() {
  printf '%s\n' setup kb/agent sessions
  local d
  for d in "$MB_LIBRARIES"/*/; do
    [[ -d "$d/.git" ]] && printf 'kb/libraries/%s\n' "$(basename "$d")"
  done
  return 0
}

library_list_add() {   # add a name to setup/libraries.txt
  library_names | grep -qx "$1" && return 0
  [[ -f "$MB_LIBRARY_LIST" ]] ||
    printf '%s\n' "# Libraries: one name per line. Each is a git repo in ~/mirabelle/kb/libraries/<name>." \
                  "# Written by mirabelle library add|rm; read by pull and install.sh." > "$MB_LIBRARY_LIST"
  printf '%s\n' "$1" >> "$MB_LIBRARY_LIST"
}

library_list_rm() {
  local tmp; tmp=$(mktemp)
  awk -v n="$1" '{ x=$0; sub(/#.*/, "", x); gsub(/[[:space:]]/, "", x); if (x != n) print }' "$MB_LIBRARY_LIST" > "$tmp"
  cat "$tmp" > "$MB_LIBRARY_LIST"; rm -f "$tmp"
}

# Clones a library from the home if it is there; returns 1 if not.
library_clone() {   # library_clone <name>
  local name=$1 home url
  home=$(home_base) || return 1
  url="$home/library-$name.git"
  [[ -n "$(git ls-remote "$url" 2>/dev/null)" ]] || return 1
  run git clone -q "$url" "$MB_LIBRARIES/$name"
  line cloned "library $name from $url"
}

cmd_library() {
  local sub=${1:-}; shift || true
  case "$sub" in
    add) library_add "$@" ;;
    ls)  library_ls "$@" ;;
    rm)  library_rm "$@" ;;
    *)   die "usage: mirabelle library add|ls|rm [-f] <name>" ;;
  esac
}

library_add() {
  local name=${1:-}; [[ -n "$name" && $# -eq 1 ]] || die "usage: mirabelle library add <name>"
  need_name library "$name"
  local dir="$MB_LIBRARIES/$name"
  [[ ! -e "$dir" ]] || die "library '$name' already exists ($dir)"
  [[ -d "$MB_LIBRARIES" ]] || run mkdir -p "$MB_LIBRARIES"

  if ! library_clone "$name"; then
    run git init -q -b main "$dir"
    if (( ! MB_DRY )); then
      cat > "$dir/INDEX.md" <<EOF
# Library: $name

What this library holds, and where. Keep this index short and up to date:
Claude reads it first.

## Contents

- (nothing yet)
EOF
    fi
    git_mb -C "$dir" add -A
    git_mb -C "$dir" commit -q -m "start library $name"
    local home
    if home=$(home_base); then
      local url="$home/library-$name.git"
      run git -C "$dir" remote add origin "$url"
      line created "library $name ($dir), home $url"
      if [[ "$url" == /* ]]; then
        if [[ ! -d "$url" ]]; then run git init -q --bare -b main "$url"; line created "$url (empty, at the home)"; fi
      else
        say "           create the empty repo library-$name at the home before: mirabelle push"
      fi
    else
      line created "library $name ($dir), no home yet (mirabelle home <path-or-url>)"
    fi
  fi
  (( MB_DRY )) || library_list_add "$name"
  line listed "$name in $MB_LIBRARY_LIST"
  next "mirabelle run ... -l $name    (and mirabelle save, to record the list)"
}

library_ls() {
  [[ $# -eq 0 ]] || die "usage: mirabelle library ls"
  local -a rows=() names=()
  local n state
  mapfile -t names < <( { library_names; for d in "$MB_LIBRARIES"/*/; do [[ -d "$d/.git" ]] && basename "$d"; done; } | sort -u)
  if (( ${#names[@]} == 0 )); then say "no library yet (add one: mirabelle library add <name>)"; return 0; fi
  for n in "${names[@]}"; do
    if [[ ! -d "$MB_LIBRARIES/$n/.git" ]]; then state="listed, not on this computer (mirabelle pull)"
    elif ! library_names | grep -qx "$n"; then state="on this computer, not listed"
    else
      state="$(git -C "$MB_LIBRARIES/$n" ls-files | wc -l) file(s)"
      [[ -n "$(git -C "$MB_LIBRARIES/$n" status --porcelain)" ]] && state+=", unsaved changes"
    fi
    rows+=("$n"$'\t'"$state")
  done
  { printf 'LIBRARY\tSTATE\n'; printf '%s\n' "${rows[@]}"; } | table
}

library_rm() {
  local name="" force=0
  while (( $# )); do
    case "$1" in
      -f|--force) force=1; shift ;;
      -*) die "library rm: unknown option '$1' (usage: mirabelle library rm [-f] <name>)" ;;
      *)  [[ -z "$name" ]] || die "usage: mirabelle library rm [-f] <name>"; name=$1; shift ;;
    esac
  done
  [[ -n "$name" ]] || die "usage: mirabelle library rm [-f] <name>"
  local dir="$MB_LIBRARIES/$name"
  library_names | grep -qx "$name" || [[ -d "$dir" ]] || die "no library '$name'"

  # What removing it would lose. Without -f, any of these refuses.
  local -a lost=()
  local used; used=$(containers_using mirabelle.libraries "$name" | paste -sd' ')
  [[ -n "$used" ]] && lost+=("its folder, still mounted in: $used (they would see it empty)")
  if [[ -d "$dir/.git" ]]; then
    local n
    n=$(git -C "$dir" status --porcelain | wc -l)
    (( n )) && lost+=("$n unsaved change(s) (mirabelle save, then push)")
    if git -C "$dir" rev-parse -q --verify '@{upstream}' >/dev/null 2>&1; then
      n=$(git -C "$dir" rev-list --count '@{upstream}..HEAD')
      (( n )) && lost+=("$n commit(s) not pushed (mirabelle push)")
    elif git -C "$dir" remote get-url origin >/dev/null 2>&1; then
      lost+=("everything: it was never pushed (mirabelle push), so this is its only copy")
    else
      lost+=("everything: it has no home, so this computer has its only copy")
    fi
  fi
  if (( ${#lost[@]} )); then
    if (( ! force )); then
      say "library '$name' would lose:"; printf '  %s\n' "${lost[@]}"
      die "not removed (to remove it anyway and lose that: mirabelle library rm -f $name)"
    fi
    say "-f: removing library '$name' LOSES:"; printf '  %s\n' "${lost[@]}"
  fi
  confirm "Remove library '$name' from this computer and from the list? (its copy at the home is kept)" || { say "nothing removed"; return 0; }
  [[ -d "$dir" ]] && run rm -rf "$dir"
  (( MB_DRY )) || library_list_rm "$name"
  line removed "library $name ($dir) and its line in $MB_LIBRARY_LIST"
  say "Its copy at the home, if any, is untouched."
}
