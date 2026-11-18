# shellcheck shell=bash
# Upgrading mirabelle: upgrade, status, apply, discard, rollback.
#
# Two repos can be upgraded: the plumbing (the tool, from GitHub) and your
# config. proposed/plumbing and proposed/config are git clones of them (their
# "origin" is the real repo). Claude edits them in the upgrade container, at
# /work/upgrade/plumbing and /work/upgrade/config. The PC never runs anything
# from proposed/. `apply` brings the changes into the real repos after showing
# them and getting your yes.
#
# One apply is one commit in each repo it changes, with the same tag in each:
#   apply-YYYYMMDD-HHMMSS
# A rollback is one commit in each repo it changes, tagged rollback-..., with
# one line "Undoes: apply-..." per apply it undid.

UPG_REPOS=(plumbing config)

repo_dir() {   # repo_dir plumbing|config
  case "$1" in plumbing) printf '%s\n' "$MB_PLUMBING" ;; config) printf '%s\n' "$MB_CONFIG" ;; esac
}

repo_clean() { [[ -z "$(git -C "$(repo_dir "$1")" status --porcelain)" ]]; }

# True if proposed/<repo> differs from the repo's current commit.
proposed_pending() {   # proposed_pending <repo>
  local p="$MB_PROPOSED/$1" d; d=$(repo_dir "$1")
  [[ -d "$p/.git" ]] || return 1
  [[ -n "$(git -C "$p" status --porcelain)" ]] && return 0
  [[ "$(git -C "$p" rev-parse HEAD)" != "$(git -C "$d" rev-parse HEAD)" ]] &&
    ! git -C "$d" merge-base --is-ancestor "$(git -C "$p" rev-parse HEAD)" HEAD 2>/dev/null
}

# A tag name not used yet in plumbing or config: <prefix>-YYYYMMDD-HHMMSS,
# with -2, -3... added if two happen in the same second.
new_tag() {   # new_tag apply|rollback
  local base t n=2 r used
  base="$1-$(date +%Y%m%d-%H%M%S)"; t=$base
  while :; do
    used=0
    for r in "${UPG_REPOS[@]}"; do git -C "$(repo_dir "$r")" rev-parse -q --verify "refs/tags/$t" >/dev/null && used=1; done
    (( used )) || break
    t="$base-$n"; n=$((n + 1))
  done
  printf '%s\n' "$t"
}

any_pending() { local r; for r in "${UPG_REPOS[@]}"; do proposed_pending "$r" && return 0; done; return 1; }

proposed_reset() {   # make proposed/<repo> an exact copy of the repo's current commit
  local p="$MB_PROPOSED/$1" d; d=$(repo_dir "$1")
  git_mb -C "$p" fetch -q origin
  git_mb -C "$p" reset -q --hard "origin/$(git -C "$d" symbolic-ref --short HEAD)"
  git_mb -C "$p" clean -q -fd
}

proposed_prepare() {   # create, keep or refresh proposed/<repo>
  local r=$1 p="$MB_PROPOSED/$1" d; d=$(repo_dir "$1")
  if [[ ! -d "$p/.git" ]]; then
    run mkdir -p "$MB_PROPOSED"
    run git clone -q "$d" "$p"
    line proposed "$r: created as a copy ($p)"
  elif proposed_pending "$r"; then
    line proposed "$r: kept, it has changes not applied yet (see: mirabelle status)"
  else
    proposed_reset "$r"
    line proposed "$r: brought up to date"
  fi
}

cmd_upgrade() {
  local account=""
  local -a pass=()
  while (( $# )); do
    case "$1" in
      -a) account=${2:?-a needs an account}; shift 2 ;;
      --) shift; pass=("$@"); break ;;
      *) die "upgrade: unknown option '$1' (usage: mirabelle upgrade -a <account>)" ;;
    esac
  done
  need_docker; need_not_root
  local c; c=$(container_of upgrade)

  if container_running "$c"; then
    line upgrade "the upgrade container is already running"
    cmd_claude -n upgrade -- "${pass[@]}"
    return
  fi
  [[ -n "$account" ]] || die "upgrade: -a <account> is required (see: mirabelle account ls)"
  [[ -f "$MB_SECRETS/accounts/$account" ]] || die "no account '$account' (see: mirabelle account ls)"
  image_exists mirabelle:latest || die "the image does not exist yet: run mirabelle build first"
  container_exists "$c" && { run docker rm -f "$c" >/dev/null; line removed "stopped container $c"; }

  local r
  for r in "${UPG_REPOS[@]}"; do proposed_prepare "$r"; done

  line project upgrade
  line account "$account"
  line image mirabelle:latest
  line mounts "$MB_PROPOSED/plumbing → /work/upgrade/plumbing  rw  (the tool, the image, the firewall)"
  more "$MB_PROPOSED/config → /work/upgrade/config  rw  (your sites, identities, projects, libraries list)"
  more "$MB_AGENT → /kb/agent  rw"
  more "$MB_SESSIONS/upgrade → /session  rw"
  more "no identity, no libraries, no Docker access; the firewall is on"

  prepare_dirs upgrade
  lock_write upgrade ""
  local -a extra=(
    --mount "type=bind,src=$MB_PROPOSED,dst=/work/upgrade"
    -e "GIT_AUTHOR_NAME=Claude (upgrade)" -e "GIT_AUTHOR_EMAIL=upgrade@mirabelle.local"
    -e "GIT_COMMITTER_NAME=Claude (upgrade)" -e "GIT_COMMITTER_EMAIL=upgrade@mirabelle.local"
    -w /work/upgrade)
  ( cd "$MB_PROPOSED" && start_container upgrade upgrade "$c" mirabelle:latest "$account" "" "${extra[@]}" ) || exit 1
  (( MB_DRY )) && return 0
  cmd_claude -n upgrade -- "${pass[@]}"
}

# Groups changed paths into the parts shown by status and apply.
part_of() {   # part_of <repo> <path>
  case "$1:$2" in
    plumbing:bin/*|plumbing:lib/*|plumbing:install.sh|plumbing:rescue.sh) echo tool ;;
    plumbing:image/*|config:projects/*/Dockerfile)                       echo image ;;
    plumbing:lock/*)                                                      echo firewall ;;
    *:sites.txt|config:projects/*/sites.txt|config:libraries.txt)         echo lists ;;
    config:identities/*)                                                  echo identities ;;
    plumbing:docs/*|plumbing:README.md|plumbing:*-starter/*)              echo documentation ;;
    *)                                                                    echo other ;;
  esac
}

cmd_status() {
  [[ $# -eq 0 ]] || die "status takes no options"
  say "proposed (changes waiting for mirabelle apply):"
  local r p files base f shown=0
  for r in "${UPG_REPOS[@]}"; do
    p="$MB_PROPOSED/$r"
    [[ -d "$p/.git" ]] || continue
    proposed_pending "$r" || continue
    query git -C "$p" fetch -q origin
    base=$(git -C "$p" merge-base HEAD "origin/$(git -C "$(repo_dir "$r")" symbolic-ref --short HEAD)")
    files=$( { git -C "$p" diff --name-only "$base"; git -C "$p" ls-files --others --exclude-standard; } | sort -u)
    while read -r f; do [[ -n "$f" ]] && { printf '  %-14s %s/%s\n' "$(part_of "$r" "$f")" "$r" "$f"; shown=1; }; done <<<"$files"
  done
  if (( ! shown )); then
    if [[ -d "$MB_PROPOSED" ]]; then say "  nothing pending"; else say "  no proposed copy yet (it is created by: mirabelle upgrade)"; fi
  fi

  say "not saved (mirabelle save):"
  local n any=0
  local -a repos; mapfile -t repos < <(all_repos)
  for r in "${repos[@]}"; do
    [[ -d "$MB_ROOT/$r/.git" ]] || continue
    n=$(git -C "$MB_ROOT/$r" status --porcelain | wc -l)
    (( n )) && { printf '  %-10s %s changed file(s)\n' "$r" "$n"; any=1; }
  done
  (( any )) || say "  nothing"

  say "not pushed (mirabelle push), as of the last push or pull:"
  any=0
  for r in "${repos[@]}"; do
    [[ -d "$MB_ROOT/$r/.git" ]] || continue
    if ! git -C "$MB_ROOT/$r" rev-parse -q --verify '@{upstream}' >/dev/null 2>&1; then
      git -C "$MB_ROOT/$r" remote get-url origin >/dev/null 2>&1 || { printf '  %-10s no home set (mirabelle home <path-or-url>)\n' "$r"; any=1; continue; }
      printf '  %-10s never pushed\n' "$r"; any=1; continue
    fi
    n=$(git -C "$MB_ROOT/$r" rev-list --count '@{upstream}..HEAD')
    (( n )) && { printf '  %-10s %s commit(s)\n' "$r" "$n"; any=1; }
  done
  (( any )) || say "  nothing"

  if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    say "images:"
    cmd_images | sed 's/^/  /'
  fi
}

cmd_apply() {
  [[ $# -eq 0 ]] || die "apply takes no options"
  [[ -d "$MB_PROPOSED" ]] || die "there is no proposed copy (it is created by: mirabelle upgrade)"
  local r d p
  for r in "${UPG_REPOS[@]}"; do
    repo_clean "$r" || die "$r has unsaved changes; save them first: mirabelle save"
  done

  for r in "${UPG_REPOS[@]}"; do
    p="$MB_PROPOSED/$r"
    [[ -d "$p/.git" && -n "$(git -C "$p" status --porcelain)" ]] || continue
    git_mb -C "$p" add -A
    git_mb -C "$p" commit -q -m "upgrade: changes not committed in the upgrade container"
    line proposed "$r: committed the changes Claude had not committed"
  done
  (( MB_DRY )) && { say "(dry run: would show the changes and ask)"; return 0; }

  # What changes, per repo (FETCH_HEAD of each repo = its proposed copy).
  local -a changed=()
  local -A base=()
  for r in "${UPG_REPOS[@]}"; do
    d=$(repo_dir "$r"); p="$MB_PROPOSED/$r"
    [[ -d "$p/.git" ]] || continue
    query git -C "$d" fetch -q "$p" HEAD
    base[$r]=$(git -C "$d" merge-base HEAD FETCH_HEAD)
    git -C "$d" diff --quiet "${base[$r]}" FETCH_HEAD || changed+=("$r")
  done
  if (( ${#changed[@]} == 0 )); then
    say "nothing to apply: proposed has no change"
    return 0
  fi

  say "Changes proposed (from the upgrade project), by part:"
  local f parts="" pt
  for r in "${changed[@]}"; do
    d=$(repo_dir "$r")
    while read -r f; do
      pt=$(part_of "$r" "$f"); printf '  %-14s %s/%s\n' "$pt" "$r" "$f"
      [[ " $parts " == *" $pt "* ]] || parts+=" $pt"
    done < <(git -C "$d" diff --name-only "${base[$r]}" FETCH_HEAD)
  done
  say ""
  for r in "${changed[@]}"; do
    d=$(repo_dir "$r")
    say "Full changes in $r:"
    git -C "$d" --no-pager diff --stat "${base[$r]}" FETCH_HEAD
    git -C "$d" --no-pager diff "${base[$r]}" FETCH_HEAD
    say ""
  done
  confirm "Apply these changes?" || { say "nothing applied (the changes stay in proposed)"; return 0; }

  # Merge everything first; commit only if every repo merged cleanly.
  for r in "${changed[@]}"; do
    d=$(repo_dir "$r")
    if ! git_mb -C "$d" merge -q --squash FETCH_HEAD >/dev/null 2>&1; then
      local conflicts; conflicts=$(git -C "$d" diff --name-only --diff-filter=U | sed "s#^#$r/#" | paste -sd' ')
      local x; for x in "${changed[@]}"; do git_mb -C "$(repo_dir "$x")" reset -q --hard HEAD; done
      die "the same lines changed in $r and in its proposed copy: $conflicts. Nothing applied. (Run mirabelle upgrade and ask Claude to redo the change on the current version.)"
    fi
  done
  local tag; tag=$(new_tag apply)
  for r in "${changed[@]}"; do
    d=$(repo_dir "$r")
    git_mb -C "$d" commit -q -m "apply:${parts}" -m "From the upgrade project. Tag: $tag"
    git_mb -C "$d" tag -a "$tag" -m "apply:${parts}"
    line applied "$r is now at $(git -C "$d" rev-parse --short HEAD), tag $tag"
  done
  for r in "${UPG_REPOS[@]}"; do [[ -d "$MB_PROPOSED/$r/.git" ]] && proposed_reset "$r"; done
  line proposed "now the same as plumbing and config"

  [[ " $parts " == *" image "* ]] && next "the image definition changed: mirabelle build (and mirabelle build -n <project> for project layers)"
  [[ " $parts " == *" firewall "* || " $parts " == *" lists "* || " $parts " == *" identities "* ]] && next "the firewall or a list changed: mirabelle lock, in each running project"
  [[ " $parts " == *" tool "* ]] && next "the tool changed: it takes effect from your next mirabelle command"
  [[ " ${changed[*]} " == *" plumbing "* ]] && next "mirabelle push sends the plumbing to GitHub (and the config to your home)"
  return 0
}

cmd_discard() {
  [[ $# -eq 0 ]] || die "discard takes no options"
  any_pending || { say "nothing to discard"; return 0; }
  confirm "Throw away every change in proposed (plumbing and config)?" || { say "nothing discarded"; return 0; }
  local r
  for r in "${UPG_REPOS[@]}"; do [[ -d "$MB_PROPOSED/$r/.git" ]] && proposed_reset "$r"; done
  line discarded "proposed is the same as plumbing and config again"
}

# --- rollback ----------------------------------------------------------------

# Apply tags not undone yet, newest first. A rollback commit lists the applies
# it undid as "Undoes: apply-..." lines.
applies_not_undone() {
  local -A undone=()
  local r t
  while read -r t; do [[ -n "$t" ]] && undone[$t]=1; done < <(
    for r in "${UPG_REPOS[@]}"; do git -C "$(repo_dir "$r")" log --format=%B 2>/dev/null; done |
      sed -n 's/^Undoes: \(apply-[0-9-]*\)$/\1/p')
  for r in "${UPG_REPOS[@]}"; do git -C "$(repo_dir "$r")" tag -l 'apply-*' 2>/dev/null; done |
    sort -u -r | while read -r t; do [[ -z "${undone[$t]:-}" ]] && printf '%s\n' "$t"; done
  return 0
}

# For a list file (one domain or name per line) changed both by an apply and
# later: take the current lines, remove those the apply added, put back those
# it removed. Exact for lists, whatever the order of the lines.
undo_list_lines() {   # undo_list_lines <repo dir> <apply commit> <file>
  local d=$1 c=$2 f=$3 tmp
  tmp=$(mktemp -d)
  git -C "$d" show "$c^:$f" > "$tmp/before" 2>/dev/null || : > "$tmp/before"
  git -C "$d" show "$c:$f"  > "$tmp/after"  2>/dev/null || : > "$tmp/after"
  git -C "$d" show "HEAD:$f" > "$tmp/now"   2>/dev/null || : > "$tmp/now"
  awk 'FILENAME==ARGV[1]{b[$0]=1; next} FILENAME==ARGV[2]{a[$0]=1; next}
       FILENAME==ARGV[3]{ if (($0 in a) && !($0 in b)) next; print }' "$tmp/before" "$tmp/after" "$tmp/now" > "$tmp/result"
  awk 'FILENAME==ARGV[1]{a[$0]=1; next} FILENAME==ARGV[2]{n[$0]=1; next}
       FILENAME==ARGV[3]{ if (!($0 in a) && !($0 in n)) print }' "$tmp/after" "$tmp/result" "$tmp/before" > "$tmp/restore"
  cat "$tmp/result" "$tmp/restore" > "$d/$f"
  rm -rf "$tmp"
  git_mb -C "$d" add "$f"
  line merged "$f: removed what that apply added, kept your later lines"
}

is_list_file() { [[ "$1" == sites.txt || "$1" == projects/*/sites.txt || "$1" == libraries.txt ]]; }

cmd_rollback() {
  [[ $# -le 1 ]] || die "usage: mirabelle rollback [<tag>]"
  local r d t
  for r in "${UPG_REPOS[@]}"; do
    repo_clean "$r" || die "$r has unsaved changes; save them first: mirabelle save"
  done
  local since=${1:-}
  local -a all todo
  mapfile -t all < <(applies_not_undone)
  if [[ -n "$since" ]]; then
    [[ "$since" == apply-* ]] || die "give an apply tag (see the list printed by: mirabelle rollback)"
    for t in "${all[@]}"; do [[ "$t" > "$since" ]] && todo+=("$t"); done
  else
    (( ${#all[@]} )) && todo=("${all[0]}")
  fi
  (( ${#todo[@]} )) || die "there is no apply to undo${since:+ after $since}"

  say "Applies not undone yet (newest first):"
  for t in "${all[@]:0:8}"; do
    local where=""
    for r in "${UPG_REPOS[@]}"; do git -C "$(repo_dir "$r")" rev-parse -q --verify "refs/tags/$t" >/dev/null && where+=" $r"; done
    printf '  %s  %-30s in:%s%s\n' "$t" "$(for r in "${UPG_REPOS[@]}"; do git -C "$(repo_dir "$r")" tag -l --format='%(subject)' "$t"; done | head -1)" \
      "$where" "$([[ " ${todo[*]} " == *" $t "* ]] && echo '   <- will be undone')"
  done
  say "Changes this rollback makes:"
  for t in "${todo[@]}"; do
    for r in "${UPG_REPOS[@]}"; do
      d=$(repo_dir "$r")
      git -C "$d" rev-parse -q --verify "refs/tags/$t" >/dev/null || continue
      say "  $r ($t):"; git -C "$d" --no-pager diff --stat "$t" "$t^" | sed 's/^/  /'
    done
  done
  say "Changes you saved after those applies (identities, sites, ...) are kept."
  confirm "Undo ${#todo[@]} apply(s)?" || { say "nothing changed"; return 0; }

  local -a touched=()
  for r in "${UPG_REPOS[@]}"; do
    d=$(repo_dir "$r")
    local any=0
    for t in "${todo[@]}"; do
      git -C "$d" rev-parse -q --verify "refs/tags/$t" >/dev/null || continue
      any=1
      local c; c=$(git -C "$d" rev-parse "$t^{commit}")
      git_mb -C "$d" revert --no-commit "$c" >/dev/null 2>&1 && continue
      local f bad=""
      while read -r f; do
        [[ -n "$f" ]] || continue
        if is_list_file "$f"; then undo_list_lines "$d" "$c" "$f"; else bad+=" $r/$f"; fi
      done < <(git -C "$d" diff --name-only --diff-filter=U)
      if [[ -n "$bad" ]]; then
        local x; for x in "${UPG_REPOS[@]}"; do git_mb -C "$(repo_dir "$x")" reset -q --hard HEAD; done
        die "cannot undo cleanly:$bad changed again since. Nothing changed."
      fi
    done
    (( any )) && touched+=("$r")
  done

  local tag; tag=$(new_tag rollback)
  local trailer=""; for t in "${todo[@]}"; do trailer+="Undoes: $t"$'\n'; done
  for r in "${touched[@]}"; do
    d=$(repo_dir "$r")
    git_mb -C "$d" commit -q --allow-empty -m "rollback: undo ${#todo[@]} apply(s)" -m "Tag: $tag" -m "${trailer%$'\n'}"
    git_mb -C "$d" tag -a "$tag" -m "rollback: undo ${#todo[@]} apply(s)"
    line undone "$r is at $(git -C "$d" rev-parse --short HEAD), tag $tag (nothing erased from history)"
  done
  for r in "${UPG_REPOS[@]}"; do
    [[ -d "$MB_PROPOSED/$r/.git" ]] && ! proposed_pending "$r" && proposed_reset "$r"
  done
  next "if the image definition changed: mirabelle run ... --previous (the image that worked), or mirabelle build"
  [[ " ${touched[*]} " == *" plumbing "* ]] && next "mirabelle push sends the plumbing rollback to GitHub"
  return 0
}
