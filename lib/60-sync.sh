# shellcheck shell=bash
# Save, push, pull, home: plain git on the repos (setup, kb/agent, sessions, libraries).
#   setup               -> <home>/mirabelle.git
#   kb/agent            -> <home>/agent.git
#   sessions            -> <home>/sessions.git
#   kb/libraries/<name> -> <home>/library-<name>.git   (see 45-library.sh)

home_name() {   # repo folder -> name at the home
  case "$1" in
    setup) echo mirabelle.git ;;
    kb/agent) echo agent.git ;;
    kb/libraries/*) echo "library-${1#kb/libraries/}.git" ;;
    *) echo "$1.git" ;;
  esac
}

repo_branch() { git -C "$MB_ROOT/$1" symbolic-ref --short HEAD; }

cmd_home() {
  [[ $# -le 1 ]] || die "usage: mirabelle home [<path-or-url>]"
  local r
  local -a MB_REPOS; mapfile -t MB_REPOS < <(all_repos)
  if [[ $# -eq 0 ]]; then
    for r in "${MB_REPOS[@]}"; do
      printf '%-10s %s\n' "$r" "$(git -C "$MB_ROOT/$r" remote get-url origin 2>/dev/null || echo '(no home set)')"
    done
    return 0
  fi
  local home=${1%/} local_path=0
  case "$home" in
    /*) local_path=1 ;;
    ~*) home=${home/#\~/$HOME}; local_path=1 ;;
    ./*|../*) home=$(readlink -f "$home"); local_path=1 ;;
  esac

  if (( local_path )); then
    local missing=()
    for r in "${MB_REPOS[@]}"; do [[ -d "$home/$(home_name "$r")" ]] || missing+=("$home/$(home_name "$r")"); done
    if (( ${#missing[@]} )); then
      say "These repos do not exist at the home yet:"; printf '  %s\n' "${missing[@]}"
      if confirm "Create them (empty)?"; then
        local m; for m in "${missing[@]}"; do run git init -q --bare -b main "$m"; line created "$m"; done
      else
        say "not created; push will fail until they exist"
      fi
    fi
  fi
  for r in "${MB_REPOS[@]}"; do
    local url; url="$home/$(home_name "$r")"
    if git -C "$MB_ROOT/$r" remote get-url origin >/dev/null 2>&1; then
      run git -C "$MB_ROOT/$r" remote set-url origin "$url"
    else
      run git -C "$MB_ROOT/$r" remote add origin "$url"
    fi
    printf '%-10s %s\n' "$r" "$url"
  done
}

cmd_save() {
  [[ $# -eq 0 ]] || die "save takes no options"
  local r n any=0
  local -a MB_REPOS; mapfile -t MB_REPOS < <(all_repos)
  for r in "${MB_REPOS[@]}"; do
    [[ -d "$MB_ROOT/$r/.git" ]] || continue
    n=$(git -C "$MB_ROOT/$r" status --porcelain | wc -l)
    if (( n == 0 )); then printf '%-10s nothing to save\n' "$r"; continue; fi
    any=1
    printf '%-10s %s file(s):\n' "$r" "$n"
    git -C "$MB_ROOT/$r" status --porcelain | sed 's/^/             /'
    git_mb -C "$MB_ROOT/$r" add -A
    git_mb -C "$MB_ROOT/$r" commit -q -m "save: $(date '+%Y-%m-%d %H:%M') ($n file(s))"
    printf '%-10s committed %s\n' "" "$(git -C "$MB_ROOT/$r" rev-parse --short HEAD 2>/dev/null)"
  done
  (( any )) && next "mirabelle push"
  return 0
}

cmd_push() {
  [[ $# -eq 0 ]] || die "push takes no options"
  local r b fail=0
  local -a MB_REPOS; mapfile -t MB_REPOS < <(all_repos)
  for r in "${MB_REPOS[@]}"; do
    [[ -d "$MB_ROOT/$r/.git" ]] || continue
    if ! git -C "$MB_ROOT/$r" remote get-url origin >/dev/null 2>&1; then
      printf '%-10s no home set (mirabelle home <path-or-url>)\n' "$r"; fail=1; continue
    fi
    [[ -z "$(git -C "$MB_ROOT/$r" status --porcelain)" ]] || printf '%-10s has unsaved changes, not pushed (mirabelle save)\n' "$r"
    b=$(repo_branch "$r")
    local out rc
    out=$(run git -C "$MB_ROOT/$r" push -q --follow-tags -u origin "$b" 2>&1) && rc=0 || rc=$?
    [[ -n "$out" ]] && sed 's/^/           /' <<<"$out"
    if (( rc == 0 )); then
      printf '%-10s pushed %s\n' "$r" "$b"
    elif grep -qE 'rejected|fetch first|non-fast-forward' <<<"$out"; then
      printf '%-10s NOT pushed: the home has commits this computer does not (mirabelle pull first)\n' "$r"; fail=1
    else
      printf '%-10s NOT pushed: cannot reach %s (does that repo exist at the home?)\n' "$r" "$(git -C "$MB_ROOT/$r" remote get-url origin)"; fail=1
    fi
  done
  return $fail
}

cmd_pull() {
  [[ $# -eq 0 ]] || die "pull takes no options"
  local r b before after fail=0
  local -a MB_REPOS=(setup)
  pull_repos || fail=1
  # setup's libraries.txt may now name libraries this computer does not have.
  local n
  while read -r n; do
    [[ -n "$n" && ! -d "$MB_LIBRARIES/$n" ]] || continue
    [[ -d "$MB_LIBRARIES" ]] || run mkdir -p "$MB_LIBRARIES"
    library_clone "$n" || { printf '%-10s %s\n' "kb/libraries/$n" "listed in setup but not at the home"; fail=1; }
  done < <(library_names)
  mapfile -t MB_REPOS < <(all_repos | grep -vx setup)
  pull_repos || fail=1
  return $fail
}

pull_repos() {   # pulls the repos in MB_REPOS
  local r b before after fail=0
  for r in "${MB_REPOS[@]}"; do
    [[ -d "$MB_ROOT/$r/.git" ]] || continue
    if ! git -C "$MB_ROOT/$r" remote get-url origin >/dev/null 2>&1; then
      printf '%-10s no home set (mirabelle home <path-or-url>)\n' "$r"; fail=1; continue
    fi
    if [[ -n "$(git -C "$MB_ROOT/$r" status --porcelain)" ]]; then
      printf '%-10s NOT pulled: unsaved changes (mirabelle save, then pull)\n' "$r"; fail=1; continue
    fi
    b=$(repo_branch "$r")
    if ! run git -C "$MB_ROOT/$r" fetch -q --tags origin; then
      printf '%-10s NOT pulled: the home is unreachable\n' "$r"; fail=1; continue
    fi
    if ! git -C "$MB_ROOT/$r" rev-parse -q --verify "origin/$b" >/dev/null; then
      printf '%-10s nothing at the home yet\n' "$r"; continue
    fi
    before=$(git -C "$MB_ROOT/$r" rev-parse HEAD)
    if run git -C "$MB_ROOT/$r" merge -q --ff-only "origin/$b" 2>/dev/null; then
      after=$(git -C "$MB_ROOT/$r" rev-parse HEAD)
      if [[ "$before" == "$after" ]]; then printf '%-10s already up to date\n' "$r"
      else printf '%-10s moved forward %s commit(s)\n' "$r" "$(git -C "$MB_ROOT/$r" rev-list --count "$before..$after")"
      fi
      git -C "$MB_ROOT/$r" branch -q --set-upstream-to "origin/$b" 2>/dev/null || true
    else
      printf '%-10s NOT pulled: this computer and the home both have commits the other does not. Nothing changed.\n' "$r"; fail=1
    fi
  done
  return $fail
}
