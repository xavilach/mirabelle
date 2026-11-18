# shellcheck shell=bash
# Working in a folder: run, lock, code, claude, shell, stop, ps, inspect, logs.

# Shared by `run` and `upgrade`: settings, mounts, start, firewall, start.sh.
#   start_container <kind> <project> <container> <image> <account> <identity|""> <docker args...>
# The extra docker args are the mounts and settings specific to the kind.
start_container() {
  local kind=$1 project=$2 c=$3 image=$4 account=$5 identity=$6; shift 6
  local token_file="$MB_SECRETS/accounts/$account"

  local -a a=(docker run -d --name "$c" --hostname "$project")
  add_base_opts a
  a+=(--label "mirabelle.kind=$kind" --label "mirabelle.project=$project"
      --label "mirabelle.account=$account" --label "mirabelle.identity=$identity"
      --label "mirabelle.folder=$PWD" --label "mirabelle.image=$image")
  a+=(-e CLAUDE_CODE_OAUTH_TOKEN
      -e "MIRABELLE_PROJECT=$project"
      -e CLAUDE_CONFIG_DIR=/session
      -e DISABLE_AUTOUPDATER=1
      -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
      -e SSL_CERT_FILE=/tmp/mirabelle/ca.crt
      -e GIT_SSL_CAINFO=/tmp/mirabelle/ca.crt
      -e NODE_EXTRA_CA_CERTS=/tmp/mirabelle/ca.crt
      -e REQUESTS_CA_BUNDLE=/tmp/mirabelle/ca.crt)
  add_proxy_env a
  a+=(--mount "type=bind,src=$MB_AGENT,dst=/kb/agent"
      --mount "type=bind,src=$MB_SESSIONS/$project,dst=/session"
      --mount "type=bind,src=$MB_LOCAL/lock/$project,dst=/lock-run,readonly"
      --mount "type=bind,src=$MB_LOCAL/vscode-server/$project,dst=/home/dev/.vscode-server")
  a+=("$@" "$image")

  # The token reaches docker through its environment, never on the command
  # line, so it does not show in the process list or in -v output.
  if (( MB_DRY )); then
    printf 'would run: CLAUDE_CODE_OAUTH_TOKEN=<from %s> ' "$token_file"; show_cmd "${a[@]}"
  else
    ( export CLAUDE_CODE_OAUTH_TOKEN; CLAUDE_CODE_OAUTH_TOKEN=$(<"$token_file"); query "${a[@]}" ) >/dev/null \
      || die "docker could not start $c"
  fi
  (( MB_DRY )) || line started "container $c"

  lock_apply "$c"

  if (( MB_DRY )); then
    printf 'would run: '; show_cmd docker exec -i -u dev "$c" bash -s; say "           < $MB_SETUP/lib/inside/start.sh"
  else
    query docker exec -i -u dev "$c" bash -s < "$MB_SETUP/lib/inside/start.sh"
  fi
}

# Common preparation: folders that must exist before mounting.
prepare_dirs() {   # prepare_dirs <project>
  local p=$1 d
  for d in "$MB_SESSIONS/$p" "$MB_LOCAL/vscode-server/$p"; do
    [[ -d "$d" ]] || run mkdir -p "$d"
  done
}

cmd_run() {
  local account="" identity="" name="" previous=0 force=0
  local -a ports=() libraries=()
  while (( $# )); do
    case "$1" in
      -a) account=${2:?-a needs an account}; shift 2 ;;
      -i) identity=${2:?-i needs an identity}; shift 2 ;;
      -p) ports+=("${2:?-p needs a port}"); shift 2 ;;
      -l) libraries+=("${2:?-l needs a library name}"); shift 2 ;;
      -n) name=${2:?-n needs a name}; shift 2 ;;
      --previous) previous=1; shift ;;
      -f|--force) force=1; shift ;;
      *) die "run: unknown option '$1' (usage: mirabelle run [-f] -a <account> -i <identity> [-l <library>]... [-p <port>] [-n <name>] [--previous])" ;;
    esac
  done
  [[ -n "$account" ]]  || die "run: -a <account> is required (see: mirabelle account ls)"
  [[ -n "$identity" ]] || die "run: -i <identity> is required (see: mirabelle identity ls)"
  need_docker

  local project; project=$(project_name "$name")
  [[ "$project" != upgrade ]] || die "the name 'upgrade' is reserved for the upgrade project; use -n <other name>"
  local c; c=$(container_of "$project")
  if container_exists "$c"; then
    (( force )) || die "container $c already exists (stop it first: mirabelle stop${name:+ -n $name}; or replace it: mirabelle run -f ...)"
    docker exec -u dev "$c" tmux has-session -t claude 2>/dev/null &&
      warn "a Claude session is running in $c; it ends now (its conversation is kept)"
    run docker rm -f "$c" >/dev/null
    (( MB_DRY )) || line replaced "removed the existing container $c (-f)"
  fi
  [[ -f "$MB_SECRETS/accounts/$account" ]] || die "no account '$account' (see: mirabelle account ls)"
  [[ -f "$MB_SETUP/identities/$identity/gitconfig" ]] || die "no identity '$identity' (see: mirabelle identity ls)"

  local repo=mirabelle
  image_exists "mirabelle-$project:latest" && repo="mirabelle-$project"
  local image="$repo:latest"
  (( previous )) && image="$repo:previous"
  image_exists "$image" || die "image $image does not exist (build it: mirabelle build)"

  local p l
  for p in "${ports[@]}"; do [[ "$p" =~ ^[0-9]+$ ]] || die "-p: '$p' is not a port number"; done
  for l in "${libraries[@]}"; do
    need_name library "$l"
    [[ -d "$MB_LIBRARIES/$l/.git" ]] || die "no library '$l' on this computer (see: mirabelle library ls)"
  done

  line project "$project$([[ -z "$name" ]] && echo '                  (from the folder name)')"
  line account "$account"
  line identity "$identity"
  line image "$image"
  line mounts "$PWD → /work/$project  rw"
  more "$MB_AGENT → /kb/agent  rw"
  more "$MB_SESSIONS/$project → /session  rw"
  more "identity $identity → /identity  ro"
  for l in "${libraries[@]}"; do more "$MB_LIBRARIES/$l → /kb/libraries/$l  rw"; done
  for p in "${ports[@]}"; do line port "container $p → PC localhost:$p"; done

  prepare_dirs "$project"
  lock_write "$project" "$identity"

  local -a extra=(
    --mount "type=bind,src=$PWD,dst=/work/$project"
    --mount "type=bind,src=$MB_SETUP/identities/$identity,dst=/identity,readonly"
    --mount "type=bind,src=$MB_SECRETS/identities/$identity,dst=/identity-secret,readonly"
    -e GIT_CONFIG_GLOBAL=/identity/gitconfig
    -e "MIRABELLE_LIBRARIES=${libraries[*]}"
    --label "mirabelle.libraries=${libraries[*]}"
    -w "/work/$project")
  for l in "${libraries[@]}"; do extra+=(--mount "type=bind,src=$MB_LIBRARIES/$l,dst=/kb/libraries/$l"); done
  for p in "${ports[@]}"; do extra+=(-p "127.0.0.1:$p:$p"); done

  start_container project "$project" "$c" "$image" "$account" "$identity" "${extra[@]}"
  next "mirabelle code   or   mirabelle claude"
}

# Container for the current folder or -n <name>. Sets CUR_PROJECT and CUR_C.
pick_container() {
  local name=""
  while (( $# )); do
    case "$1" in
      -n) name=${2:?-n needs a name}; shift 2 ;;
      *) die "unknown option '$1'" ;;
    esac
  done
  CUR_PROJECT=$(project_name "$name")
  CUR_C=$(container_of "$CUR_PROJECT")
}

cmd_lock() {
  pick_container "$@"; need_docker; need_running "$CUR_C"
  local identity; identity=$(label_of "$CUR_C" mirabelle.identity)
  lock_write "$CUR_PROJECT" "$identity"
  lock_apply "$CUR_C"
}

cmd_code() {
  pick_container "$@"; need_docker; need_running "$CUR_C"
  local hex uri
  hex=$(printf '{"containerName":"/%s"}' "$CUR_C" | od -An -tx1 | tr -d ' \n')
  uri="vscode-remote://attached-container+$hex/work/$CUR_PROJECT"
  if ! command -v code >/dev/null; then
    say "VS Code's 'code' command is not available here."
    say "In VS Code: Dev Containers: Attach to Running Container... → /$CUR_C, then open /work/$CUR_PROJECT"
    return 1
  fi
  run code --folder-uri "$uri"
  line opened "VS Code attached to $CUR_C at /work/$CUR_PROJECT"
}

# Claude runs in a tmux session named "claude": closing the window does not
# stop it, and running this again reattaches.
cmd_claude() {
  local -a pass=() own=()
  while (( $# )); do
    if [[ "$1" == -- ]]; then shift; pass=("$@"); break; fi
    own+=("$1"); shift
  done
  pick_container "${own[@]}"; need_docker; need_running "$CUR_C"
  local workdir="/work/$CUR_PROJECT"
  if docker exec -u dev "$CUR_C" tmux has-session -t claude 2>/dev/null; then
    line claude "reattaching to the running Claude session in $CUR_C (detach: Ctrl-b d)"
    (( ${#pass[@]} )) && warn "arguments after -- are ignored when reattaching"
    run docker exec -it -u dev "$CUR_C" sh -c 'umask 022; exec tmux attach-session -t claude'
  else
    line claude "starting Claude in $CUR_C at $workdir (detach: Ctrl-b d, reattach: mirabelle claude)"
    # umask 022: files Claude creates are not writable by others, whatever
    # Docker's own umask is.
    run docker exec -it -u dev -w "$workdir" "$CUR_C" sh -c 'umask 022; d=$1; shift; exec tmux new-session -s claude -c "$d" claude "$@"' sh "$workdir" "${pass[@]}"
  fi
}

cmd_shell() {
  pick_container "$@"; need_docker; need_running "$CUR_C"
  run docker exec -it -u dev -w "/work/$CUR_PROJECT" "$CUR_C" sh -c 'umask 022; exec bash -l'
}

cmd_stop() {
  pick_container "$@"; need_docker
  container_exists "$CUR_C" || die "there is no container $CUR_C"
  run docker rm -f "$CUR_C" >/dev/null
  [[ -d "$MB_LOCAL/lock/$CUR_PROJECT" ]] && run rm -rf "$MB_LOCAL/lock/$CUR_PROJECT"
  (( MB_DRY )) && return 0
  line stopped "container $CUR_C removed (nothing is lost: everything kept is on the PC)"
  line removed "$MB_LOCAL/lock/$CUR_PROJECT"
}

cmd_ps() {
  need_docker
  local out
  out=$(query docker ps --filter label=mirabelle.project \
    --format '{{.Label "mirabelle.project"}}\t{{.Label "mirabelle.kind"}}\t{{.Label "mirabelle.account"}}\t{{.Label "mirabelle.identity"}}\t{{.Label "mirabelle.libraries"}}\t{{.RunningFor}}\t{{.Label "mirabelle.folder"}}')
  if [[ -z "$out" ]]; then say "no mirabelle container is running"; return 0; fi
  { printf 'PROJECT\tKIND\tACCOUNT\tIDENTITY\tLIBRARIES\tSTARTED\tFOLDER\n'; printf '%s\n' "$out"; } | table
}

cmd_inspect() {
  pick_container "$@"; need_docker; need_running "$CUR_C"
  local c=$CUR_C
  line project "$CUR_PROJECT ($(label_of "$c" mirabelle.kind))"
  line folder "$(label_of "$c" mirabelle.folder)"
  line account "$(label_of "$c" mirabelle.account)"
  line identity "$(label_of "$c" mirabelle.identity)"
  line libraries "$(label_of "$c" mirabelle.libraries)"
  line image "$(label_of "$c" mirabelle.image)  ($(docker container inspect -f '{{.Image}}' "$c" | cut -c1-19))"
  line started "$(docker container inspect -f '{{.State.StartedAt}}' "$c")"
  say "mounts:"
  query docker container inspect -f '{{range .Mounts}}  {{.Source}} → {{.Destination}}  {{if .RW}}rw{{else}}ro{{end}}{{"\n"}}{{end}}' "$c" | grep -v '^$'
  local ports; ports=$(docker port "$c" 2>/dev/null || true)
  [[ -n "$ports" ]] && { say "ports:"; sed 's/^/  /' <<<"$ports"; }
  say "environment (names only):"
  query docker container inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" | sed -e 's/=.*//' | grep -v '^$' | sort | paste -sd' ' | fold -s -w 100 | sed 's/^/  /'
  local dir="$MB_LOCAL/lock/$CUR_PROJECT"
  say "allowed sites ($dir/allowed.txt):"
  grep -Ev '^\s*(#|$)' "$dir/allowed.txt" | paste -sd' ' | fold -s -w 100 | sed 's/^/  /'
  say "local network pairs: $(grep -Ev '^\s*(#|$)' "$dir/private.txt" | paste -sd, - || true)"
  say "ports: $(paste -sd, "$dir/ports.txt")"
  say "kernel rules (read with one privileged, read-only command):"
  query docker exec -u root --privileged "$c" iptables -S OUTPUT | sed 's/^/  /'
  if docker exec "$c" pgrep -u gate -x tinyproxy >/dev/null; then
    say "filter: running as user gate"
  else
    say "filter: NOT running (run: mirabelle lock)"
  fi
}

cmd_logs() {
  pick_container "$@"; need_docker; need_running "$CUR_C"
  say "What the firewall's filter allowed and refused since the container started:"
  query docker exec "$CUR_C" cat /run/mirabelle/gate/tinyproxy.log
}
