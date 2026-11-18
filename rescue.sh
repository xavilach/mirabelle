#!/bin/bash
# rescue.sh: undo the last "mirabelle apply", with plain git, without using
# mirabelle. For when mirabelle itself no longer runs.
#
# install.sh copies this file to ~/mirabelle/rescue.sh, outside setup/, so a
# broken setup cannot break it.
#
# Usage:  ~/mirabelle/rescue.sh
#
# What it does, step by step (you can type these yourself):
#   cd ~/mirabelle/setup
#   git log --author=mirabelle --grep='^apply:' --format='%h %cd %s'   # the applies
#   git stash push -u -m rescue        # only if there are uncommitted changes
#   git revert --no-edit <commit>      # undo one apply; later changes are kept
set -euo pipefail

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
setup="$here/setup"
[[ -d "$setup/.git" ]] || { echo "rescue: no git repo at $setup" >&2; exit 1; }
cd "$setup"

# Applies not undone yet (a rollback lists what it undid as "Reverts: <commit>").
undone=$(git log --format=%B | sed -n 's/^Reverts: \([0-9a-f]\{40\}\)$/\1/p')
target=""
while read -r c; do
  [[ -n "$c" ]] || continue
  grep -qx "$c" <<<"$undone" && continue
  target=$c; break
done < <(git log --format=%H --author=mirabelle --grep='^apply:')
[[ -n "$target" ]] || { echo "rescue: there is no apply to undo" >&2; exit 1; }

echo "Last apply not undone yet:"
git --no-pager log -1 --format='  %h  %cd  %s' "$target"
git --no-pager diff --stat "$target" "$target^"
read -r -p "Undo it? [y/N] " a
[[ "$a" == y || "$a" == Y || "$a" == yes ]] || { echo "nothing changed"; exit 0; }

g() { git -c user.name=rescue -c user.email=rescue@localhost "$@"; }
if [[ -n "$(git status --porcelain)" ]]; then
  g stash push -u -m "rescue $(date '+%Y-%m-%d %H:%M')"
  echo "uncommitted changes kept in: git stash list"
fi
if ! g revert --no-commit "$target"; then
  g revert --abort || true
  echo "rescue: cannot undo cleanly (files changed again since). Nothing changed." >&2
  exit 1
fi
stamp=$(date +%Y%m%d-%H%M%S)
g commit -q -m "rollback: undo 1 apply(s) (rescue.sh)" -m "Tag: rollback-$stamp" -m "Reverts: $target"
g tag -a "rollback-$stamp" -m "rescue: undo $(git rev-parse --short "$target")"
echo "done: apply $(git rev-parse --short "$target") undone (commit $(git rev-parse --short HEAD), tag rollback-$stamp)"
