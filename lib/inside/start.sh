#!/bin/bash
# Runs inside a container, as "dev", right after the firewall is set:
#     docker exec -i -u dev <container> bash -s < setup/lib/inside/start.sh
# It does three things and prints each:
#   1. trusted certificates: the system's plus the identity's (if any);
#   2. links every entry of /kb/claude into Claude's config folder (/session);
#   3. runs /kb/start if it exists and is executable.
set -euo pipefail
shopt -s nullglob dotglob

# 1. certificates ------------------------------------------------------------
mkdir -p /tmp/mirabelle
cat /etc/ssl/certs/ca-certificates.crt > /tmp/mirabelle/ca.crt
n=0
for f in /identity/ca/*.crt; do
  cat "$f" >> /tmp/mirabelle/ca.crt
  n=$((n + 1))
done
printf '%-10s %s\n' certs "system certificates + $n from the identity"

# 2. kb/claude -> /session ---------------------------------------------------
linked=0; kept=(); removed=0
if [[ -d /kb/claude ]]; then
  for src in /kb/claude/*; do
    b=${src##*/}
    [[ "$b" == .gitkeep ]] && continue
    dst=/session/$b
    if [[ -L "$dst" ]]; then
      ln -sfn "$src" "$dst"; linked=$((linked + 1))
    elif [[ -e "$dst" ]]; then
      kept+=("$b")
    else
      ln -s "$src" "$dst"; linked=$((linked + 1))
    fi
  done
fi
# Links to entries that were removed from kb/claude.
for l in /session/*; do
  if [[ -L "$l" && "$(readlink "$l")" == /kb/claude/* && ! -e "$l" ]]; then
    rm "$l"; removed=$((removed + 1))
  fi
done
msg="linked kb/claude ($linked entries)"
(( removed > 0 )) && msg+=", removed $removed stale link(s)"
printf '%-10s %s\n' kb "$msg"
for b in "${kept[@]}"; do
  printf '%-10s %s\n' "" "kept /session/$b: a real file there, not replaced by kb/claude/$b"
done

# What is not worth keeping in the sessions repo: the links above, and caches.
{
  echo "# Written by mirabelle at each start. Links to kb/claude and caches."
  for src in /kb/claude/*; do b=${src##*/}; [[ "$b" == .gitkeep ]] || echo "/$b"; done
  echo "/statsig/"
  echo "/shell-snapshots/"
  echo "/ide/"
  echo "/debug/"
  echo "*.lock"
  echo "/.claude.json.backup*"
  echo "/.credentials.json"
} > /session/.gitignore

# 3. kb/start ----------------------------------------------------------------
if [[ -x /kb/start ]]; then
  printf '%-10s %s\n' kb "running kb/start"
  if /kb/start; then
    printf '%-10s %s\n' kb "kb/start finished"
  else
    printf '%-10s %s\n' kb "kb/start FAILED (exit $?); the container keeps running"
  fi
elif [[ -e /kb/start ]]; then
  printf '%-10s %s\n' kb "kb/start exists but is not executable: not run"
else
  printf '%-10s %s\n' kb "no kb/start"
fi
