#!/bin/bash
# rescue.sh: undo the last "mirabelle apply", with plain git, without using
# mirabelle. For when mirabelle itself no longer runs.
#
# install.sh copies this file to ~/mirabelle/rescue.sh, outside plumbing/, so
# a broken plumbing cannot break it.
#
# Usage:  ~/mirabelle/rescue.sh
#
# An apply is one commit, tagged apply-YYYYMMDD-HHMMSS, in each of plumbing/
# and config/ that it changed. What this does, step by step (you can type these
# yourself, in each of ~/mirabelle/plumbing and ~/mirabelle/config):
#   git tag -l 'apply-*'                     # the applies; the newest last
#   git log --format=%B | grep '^Undoes:'    # those already undone
#   git stash push -u -m rescue              # only if there are uncommitted changes
#   git revert --no-edit <apply tag>         # undo it; later changes are kept
set -euo pipefail

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
repos=()
for r in plumbing config; do [[ -d "$here/$r/.git" ]] && repos+=("$r"); done
(( ${#repos[@]} )) || { echo "rescue: no plumbing/ or config/ repo next to $0" >&2; exit 1; }

undone=$(for r in "${repos[@]}"; do git -C "$here/$r" log --format=%B; done | sed -n 's/^Undoes: \(apply-[0-9-]*\)$/\1/p' | sort -u)
target=$(for r in "${repos[@]}"; do git -C "$here/$r" tag -l 'apply-*'; done | sort -u -r | grep -vxF -f <(printf '%s\n' "$undone" | grep . || echo '#none#') | head -1 || true)
[[ -n "$target" ]] || { echo "rescue: there is no apply to undo" >&2; exit 1; }

echo "Last apply not undone yet: $target"
for r in "${repos[@]}"; do
  git -C "$here/$r" rev-parse -q --verify "refs/tags/$target" >/dev/null || continue
  echo "  in $r:"; git -C "$here/$r" --no-pager diff --stat "$target" "$target^" | sed 's/^/  /'
done
read -r -p "Undo it? [y/N] " a
[[ "$a" == y || "$a" == Y || "$a" == yes ]] || { echo "nothing changed"; exit 0; }

g() { git -c user.name=rescue -c user.email=rescue@localhost "$@"; }
tag_used() {   # true if rollback-<stamp> exists in plumbing or config
  local x
  for x in "${repos[@]}"; do git -C "$here/$x" rev-parse -q --verify "refs/tags/rollback-$1" >/dev/null && return 0; done
  return 1
}
stamp=$(date +%Y%m%d-%H%M%S); base=$stamp; n=2
while tag_used "$stamp"; do stamp="$base-$n"; n=$((n + 1)); done
done_in=()
for r in "${repos[@]}"; do
  d="$here/$r"
  git -C "$d" rev-parse -q --verify "refs/tags/$target" >/dev/null || continue
  if [[ -n "$(git -C "$d" status --porcelain)" ]]; then
    g -C "$d" stash push -u -m "rescue $(date '+%Y-%m-%d %H:%M')"
    echo "$r: uncommitted changes kept in: git -C $d stash list"
  fi
  if ! g -C "$d" revert --no-commit "$target^{commit}"; then
    g -C "$d" revert --abort || true
    for x in "${done_in[@]}"; do g -C "$here/$x" reset -q --hard HEAD~1; g -C "$here/$x" tag -d "rollback-$stamp" >/dev/null; done
    echo "rescue: cannot undo cleanly in $r (files changed again since). Nothing changed." >&2
    exit 1
  fi
  g -C "$d" commit -q -m "rollback: undo 1 apply(s) (rescue.sh)" -m "Tag: rollback-$stamp" -m "Undoes: $target"
  g -C "$d" tag -a "rollback-$stamp" -m "rescue: undo $target"
  done_in+=("$r")
  echo "$r: $target undone (commit $(git -C "$d" rev-parse --short HEAD), tag rollback-$stamp)"
done
