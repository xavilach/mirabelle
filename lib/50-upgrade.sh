# shellcheck shell=bash
# Upgrading mirabelle: upgrade, status, apply, discard, rollback.
#
# proposed/ is a git clone of setup/ (its "origin" is ../setup). Claude edits
# it in the upgrade container. The PC never runs anything from it. `apply`
# brings its changes into setup/ after showing them and getting your yes.
# Each apply and rollback is one commit in setup/ with a tag:
#   apply-YYYYMMDD-HHMMSS / rollback-YYYYMMDD-HHMMSS
# install.sh tags the version first installed: install-YYYYMMDD-HHMMSS

setup_branch() { git -C "$MB_SETUP" symbolic-ref --short HEAD; }

setup_clean() { [[ -z "$(git -C "$MB_SETUP" status --porcelain)" ]]; }

proposed_pending() {   # true if proposed differs from setup's current commit
  [[ -d "$MB_PROPOSED/.git" ]] || return 1
  [[ -n "$(git -C "$MB_PROPOSED" status --porcelain)" ]] && return 0
  [[ "$(git -C "$MB_PROPOSED" rev-parse HEAD)" != "$(git -C "$MB_SETUP" rev-parse HEAD)" ]] &&
    ! git -C "$MB_SETUP" merge-base --is-ancestor "$(git -C "$MB_PROPOSED" rev-parse HEAD)" HEAD 2>/dev/null
}

proposed_reset() {   # make proposed an exact copy of setup's current commit
  git_mb -C "$MB_PROPOSED" fetch -q origin
  git_mb -C "$MB_PROPOSED" reset -q --hard "origin/$(setup_branch)"
  git_mb -C "$MB_PROPOSED" clean -q -fd
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

  if [[ ! -d "$MB_PROPOSED/.git" ]]; then
    run git clone -q "$MB_SETUP" "$MB_PROPOSED"
    line proposed "created as a copy of setup ($MB_PROPOSED)"
  elif proposed_pending; then
    line proposed "kept: it has changes not applied yet (see: mirabelle status)"
  else
    proposed_reset
    line proposed "brought up to date with setup"
  fi

  line project upgrade
  line account "$account"
  line image mirabelle:latest
  line mounts "$MB_PROPOSED → /work/upgrade  rw  (mirabelle's full source)"
  more "$MB_AGENT → /kb/agent  rw"
  more "$MB_SESSIONS/upgrade → /session  rw"
  more "no identity, no Docker access; the firewall is on"

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
part_of() {
  case "$1" in
    bin/*|lib/*|install.sh|rescue.sh) echo tool ;;
    image/*|projects/*/Dockerfile)    echo image ;;
    lock/*)                           echo firewall ;;
    sites.txt|projects/*/sites.txt|libraries.txt) echo lists ;;
    identities/*)                     echo identities ;;
    docs/*|README.md|agent-starter/*) echo documentation ;;
    *)                                echo other ;;
  esac
}

cmd_status() {
  [[ $# -eq 0 ]] || die "status takes no options"
  say "proposed (changes waiting for mirabelle apply):"
  if [[ ! -d "$MB_PROPOSED/.git" ]]; then
    say "  no proposed copy yet (it is created by: mirabelle upgrade)"
  elif ! proposed_pending; then
    say "  nothing pending"
  else
    local files base
    query git -C "$MB_PROPOSED" fetch -q origin
    base=$(git -C "$MB_PROPOSED" merge-base HEAD "origin/$(setup_branch)")
    files=$( { git -C "$MB_PROPOSED" diff --name-only "$base"; \
               git -C "$MB_PROPOSED" ls-files --others --exclude-standard; } | sort -u)
    local f; while read -r f; do [[ -n "$f" ]] && printf '  %-14s %s\n' "$(part_of "$f")" "$f"; done <<<"$files"
  fi

  say "not saved (mirabelle save):"
  local r n any=0
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
  [[ -d "$MB_PROPOSED/.git" ]] || die "there is no proposed copy (it is created by: mirabelle upgrade)"
  setup_clean || die "setup has unsaved changes; save them first: mirabelle save"

  if [[ -n "$(git -C "$MB_PROPOSED" status --porcelain)" ]]; then
    git_mb -C "$MB_PROPOSED" add -A
    git_mb -C "$MB_PROPOSED" commit -q -m "upgrade: changes not committed in the upgrade container"
    line proposed "committed the changes Claude had not committed"
  fi
  (( MB_DRY )) && { say "(dry run: would show the changes and ask)"; return 0; }

  query git -C "$MB_SETUP" fetch -q "$MB_PROPOSED" HEAD
  local base; base=$(git -C "$MB_SETUP" merge-base HEAD FETCH_HEAD)
  if git -C "$MB_SETUP" diff --quiet "$base" FETCH_HEAD; then
    say "nothing to apply: proposed has no change compared with setup"
    return 0
  fi

  say "Changes proposed (from the upgrade project), by part:"
  local f parts="" p
  while read -r f; do
    p=$(part_of "$f"); printf '  %-14s %s\n' "$p" "$f"
    [[ " $parts " == *" $p "* ]] || parts+=" $p"
  done < <(git -C "$MB_SETUP" diff --name-only "$base" FETCH_HEAD)
  say ""
  say "Full changes:"
  git -C "$MB_SETUP" --no-pager diff --stat "$base" FETCH_HEAD
  git -C "$MB_SETUP" --no-pager diff "$base" FETCH_HEAD
  say ""
  confirm "Apply these changes to setup?" || { say "nothing applied (the changes stay in proposed)"; return 0; }

  if ! git_mb -C "$MB_SETUP" merge -q --squash FETCH_HEAD >/dev/null 2>&1; then
    local conflicts; conflicts=$(git -C "$MB_SETUP" diff --name-only --diff-filter=U | paste -sd' ')
    git_mb -C "$MB_SETUP" reset -q --hard HEAD
    die "the same lines changed in setup and in proposed: $conflicts. Nothing applied. (Run mirabelle upgrade and ask Claude to redo the change on the current setup.)"
  fi
  local tag; tag="apply-$(date +%Y%m%d-%H%M%S)"
  git_mb -C "$MB_SETUP" commit -q -m "apply:${parts}" -m "From the upgrade project. Tag: $tag"
  git_mb -C "$MB_SETUP" tag -a "$tag" -m "apply:${parts}"
  line applied "setup is now at $(git -C "$MB_SETUP" rev-parse --short HEAD), tag $tag"
  proposed_reset
  line proposed "now the same as setup"

  [[ " $parts " == *" image "* ]] && next "the image definition changed: mirabelle build (and mirabelle build -n <project> for project layers)"
  [[ " $parts " == *" firewall "* || " $parts " == *" lists "* || " $parts " == *" identities "* ]] && next "the firewall or a list changed: mirabelle lock, in each running project"
  [[ " $parts " == *" tool "* ]] && next "the tool changed: it takes effect from your next mirabelle command"
  return 0
}

cmd_discard() {
  [[ $# -eq 0 ]] || die "discard takes no options"
  [[ -d "$MB_PROPOSED/.git" ]] || die "there is no proposed copy"
  proposed_pending || { say "nothing to discard"; return 0; }
  confirm "Throw away every change in proposed?" || { say "nothing discarded"; return 0; }
  proposed_reset
  line discarded "proposed is the same as setup again"
}

# Apply commits not undone yet, newest first. A rollback commit lists the
# applies it undid as "Reverts: <commit>" lines.
applies_not_undone() {   # applies_not_undone [<since tag>]
  local range=HEAD
  [[ -n "${1:-}" ]] && range="$1..HEAD"
  local -A undone=()
  local c
  while read -r c; do [[ -n "$c" ]] && undone[$c]=1; done < <(
    git -C "$MB_SETUP" log --format=%B "$range" | sed -n 's/^Reverts: \([0-9a-f]\{40\}\)$/\1/p')
  while read -r c; do
    [[ -n "$c" && -z "${undone[$c]:-}" ]] && printf '%s\n' "$c"
  done < <(git -C "$MB_SETUP" log --format=%H --author=mirabelle --grep='^apply:' "$range")
}

# For a list file (one domain per line) changed both by an apply and later:
# take the current lines, remove those the apply added, put back those it
# removed. Exact for lists, whatever the order of the lines.
undo_list_lines() {   # undo_list_lines <apply commit> <file>
  local c=$1 f=$2 tmp
  tmp=$(mktemp -d)
  git -C "$MB_SETUP" show "$c^:$f" > "$tmp/before" 2>/dev/null || : > "$tmp/before"
  git -C "$MB_SETUP" show "$c:$f"  > "$tmp/after"  2>/dev/null || : > "$tmp/after"
  git -C "$MB_SETUP" show "HEAD:$f" > "$tmp/now"   2>/dev/null || : > "$tmp/now"
  awk 'FILENAME==ARGV[1]{b[$0]=1; next} FILENAME==ARGV[2]{a[$0]=1; next}
       FILENAME==ARGV[3]{ if (($0 in a) && !($0 in b)) next; print; seen[$0]=1; next }
       END{}' "$tmp/before" "$tmp/after" "$tmp/now" > "$tmp/result"
  awk 'FILENAME==ARGV[1]{a[$0]=1; next} FILENAME==ARGV[2]{n[$0]=1; next}
       FILENAME==ARGV[3]{ if (!($0 in a) && !($0 in n)) print }' "$tmp/after" "$tmp/result" "$tmp/before" > "$tmp/restore"
  cat "$tmp/result" "$tmp/restore" > "$MB_SETUP/$f"
  rm -rf "$tmp"
  git_mb -C "$MB_SETUP" add "$f"
  line merged "$f: removed what that apply added, kept your later lines"
}

cmd_rollback() {
  [[ $# -le 1 ]] || die "usage: mirabelle rollback [<tag>]"
  setup_clean || die "setup has unsaved changes; save them first: mirabelle save"
  local since=${1:-} c
  local -a todo
  if [[ -n "$since" ]]; then
    git -C "$MB_SETUP" rev-parse -q --verify "refs/tags/$since" >/dev/null || die "no tag '$since' in setup"
    mapfile -t todo < <(applies_not_undone "$since")
  else
    mapfile -t todo < <(applies_not_undone | head -1)
  fi
  (( ${#todo[@]} )) || die "there is no apply to undo${since:+ after $since}"

  say "Applies of setup (newest first):"
  while read -r c; do
    local mark=""
    [[ " ${todo[*]} " == *" $c "* ]] && mark="   <- will be undone"
    printf '  %s  %s  %s%s\n' "$(git -C "$MB_SETUP" describe --tags --exact-match "$c" 2>/dev/null || git -C "$MB_SETUP" rev-parse --short "$c")" \
      "$(git -C "$MB_SETUP" log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M' "$c")" "$(git -C "$MB_SETUP" log -1 --format=%s "$c")" "$mark"
  done < <(applies_not_undone | head -8)
  say "Changes this rollback makes:"
  for c in "${todo[@]}"; do git -C "$MB_SETUP" --no-pager diff --stat "$c" "$c^"; done
  say "Changes you saved after those applies (identities, sites, ...) are kept."
  confirm "Undo ${#todo[@]} apply(s)?" || { say "nothing changed"; return 0; }

  for c in "${todo[@]}"; do
    git_mb -C "$MB_SETUP" revert --no-commit "$c" >/dev/null 2>&1 && continue
    local f bad=""
    while read -r f; do
      [[ -n "$f" ]] || continue
      if [[ "$f" == sites.txt || "$f" == projects/*/sites.txt ]]; then
        undo_list_lines "$c" "$f"
      else
        bad+=" $f"
      fi
    done < <(git -C "$MB_SETUP" diff --name-only --diff-filter=U)
    if [[ -n "$bad" ]]; then
      git_mb -C "$MB_SETUP" reset -q --hard HEAD
      die "cannot undo cleanly:$bad changed again since. Nothing changed."
    fi
  done
  local tag; tag="rollback-$(date +%Y%m%d-%H%M%S)"
  local -a msg=(-m "rollback: undo ${#todo[@]} apply(s)" -m "Tag: $tag")
  local trailer=""; for c in "${todo[@]}"; do trailer+="Reverts: $c"$'\n'; done
  msg+=(-m "${trailer%$'\n'}")
  git_mb -C "$MB_SETUP" commit -q --allow-empty "${msg[@]}"
  git_mb -C "$MB_SETUP" tag -a "$tag" -m "rollback: undo ${#todo[@]} apply(s)"
  line undone "${#todo[@]} apply(s); setup is at $(git -C "$MB_SETUP" rev-parse --short HEAD), tag $tag (nothing erased from history)"
  if [[ -d "$MB_PROPOSED/.git" ]] && ! proposed_pending; then proposed_reset; line proposed "now the same as setup"; fi
  next "if the image definition changed: mirabelle run ... --previous (the image that worked), or mirabelle build"
}
