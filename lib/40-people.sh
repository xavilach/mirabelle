# shellcheck shell=bash
# Accounts, identities, hosts, sites.
#   account  -> secrets/accounts/<name>               (the token, one line)
#   identity -> config/identities/<name>/gitconfig    (name, email, helper)
#               config/identities/<name>/hosts.txt    (one line per host)
#               config/identities/<name>/ca/          (certificates you trust)
#               secrets/identities/<name>/git-credentials (tokens)
#   site     -> config/sites.txt, config/projects/<name>/sites.txt
#               (plumbing/sites.txt holds what the plumbing needs; read-only here)

# --- accounts ---------------------------------------------------------------

cmd_account() {
  local sub=${1:-}; shift || true
  case "$sub" in
    add) account_add "$@" ;;
    ls)  account_ls "$@" ;;
    rm)  account_rm "$@" ;;
    *)   die "usage: mirabelle account add|ls|rm [-f] <name>" ;;
  esac
}

account_add() {
  take_force "$@"; set -- "${MB_REST[@]+"${MB_REST[@]}"}"
  local name=${1:-}; [[ -n "$name" && $# -eq 1 ]] || die "usage: mirabelle account add [-f] <name>"
  need_name account "$name"; need_docker; need_not_root
  local file="$MB_SECRETS/accounts/$name"
  if [[ -e "$file" ]]; then
    (( MB_FORCE )) || die "account '$name' already exists ($file); to log in again and replace its token: mirabelle account add -f $name"
    line replacing "the token of account '$name' (the old one is kept until the new one is saved)"
  fi
  image_exists mirabelle:latest || die "the image does not exist yet: run mirabelle build first"
  local project="account-$name" c; c=$(container_of "account-$name")
  container_exists "$c" && die "container $c exists from an earlier attempt: remove it with docker rm -f $c"

  line account "$name"
  say "Claude's login runs in a temporary container, with the firewall on."
  lock_write "$project" ""
  local -a a=(docker run -d --name "$c" --hostname "$project")
  add_base_opts a
  a+=(--label mirabelle.kind=account --label "mirabelle.project=$project"
      -e CLAUDE_CONFIG_DIR=/tmp/claude -e DISABLE_AUTOUPDATER=1
      --mount "type=bind,src=$MB_LOCAL/lock/$project,dst=/lock-run,readonly")
  add_proxy_env a
  a+=(mirabelle:latest)
  run "${a[@]}" >/dev/null || die "docker could not start $c"
  lock_apply "$c"

  say ""
  say "Claude's token login starts now. Open the address it shows in your browser,"
  say "approve, then copy the token it prints at the end."
  say ""
  run docker exec -it -u dev "$c" claude setup-token || warn "the login exited with an error"
  run docker rm -f "$c" >/dev/null
  run rm -rf "$MB_LOCAL/lock/$project"
  line removed "temporary container $c"
  (( MB_DRY )) && return 0

  local token
  read -r -s -p "Paste the token (it is not shown): " token; echo
  token=${token//[[:space:]]/}
  [[ -n "$token" ]] || die "no token given; nothing saved"
  mkdir -p "$MB_SECRETS/accounts"; chmod 700 "$MB_SECRETS" "$MB_SECRETS/accounts"
  ( umask 077; printf '%s\n' "$token" > "$file" )
  line saved "$file (readable only by you)"
  (( MB_FORCE )) && [[ -n "$(containers_using mirabelle.account "$name")" ]] &&
    say "Containers using '$name' keep the old token until: mirabelle stop, then mirabelle run ..."
  return 0
}

account_ls() {
  [[ $# -eq 0 ]] || die "usage: mirabelle account ls"
  local f found=0
  for f in "$MB_SECRETS"/accounts/*; do
    [[ -f "$f" ]] || continue
    printf '%s\n' "$(basename "$f")"; found=1
  done
  (( found )) || say "no account yet (add one: mirabelle account add <name>)"
}

account_rm() {
  take_force "$@"; set -- "${MB_REST[@]+"${MB_REST[@]}"}"
  local name=${1:-}; [[ -n "$name" && $# -eq 1 ]] || die "usage: mirabelle account rm [-f] <name>"
  local file="$MB_SECRETS/accounts/$name"
  [[ -f "$file" ]] || die "no account '$name'"
  guard_in_use "account '$name'" mirabelle.account "$name"
  confirm "Delete account '$name' ($file)?" || { say "nothing deleted"; return 0; }
  run rm -f "$file"
  line deleted "$file"
  say "Containers already running keep the token they were started with until stopped."
}

# --- identities -------------------------------------------------------------

cmd_identity() {
  local sub=${1:-}; shift || true
  case "$sub" in
    add) identity_add "$@" ;;
    ls)  identity_ls "$@" ;;
    rm)  identity_rm "$@" ;;
    *)   die "usage: mirabelle identity add|ls|rm [-f] <name>" ;;
  esac
}

identity_add() {
  local name=${1:-}; [[ -n "$name" && $# -eq 1 ]] || die "usage: mirabelle identity add <name>"
  need_name identity "$name"
  local dir="$MB_CONFIG/identities/$name" sec="$MB_SECRETS/identities/$name"
  [[ ! -e "$dir" ]] || die "identity '$name' already exists ($dir)"
  local gname gmail
  read -r -p "Git user name (for commits): " gname
  read -r -p "Git email (for commits): " gmail
  [[ -n "$gname" && -n "$gmail" ]] || die "both are needed; nothing saved"

  run mkdir -p "$dir/ca" "$sec"
  (( MB_DRY )) && return 0
  chmod 700 "$MB_SECRETS" "$MB_SECRETS/identities" "$sec"
  touch "$dir/ca/.gitkeep"
  local g="$dir/gitconfig"
  {
    say "# Git identity \"$name\" for mirabelle containers. Mounted read-only at"
    say "# /identity; used through GIT_CONFIG_GLOBAL. Tokens are not here: they are"
    say "# in secrets/identities/$name/git-credentials, mounted at /identity-secret."
  } > "$g"
  git config -f "$g" user.name "$gname"
  git config -f "$g" user.email "$gmail"
  git config -f "$g" credential.helper '!f() { test "$1" = get && git credential-store --file=/identity-secret/git-credentials get; }; f'
  git config -f "$g" init.defaultBranch main
  {
    say "# Git hosts of identity \"$name\". Written by mirabelle host add."
    say "# url host port address private|public"
  } > "$dir/hosts.txt"
  ( umask 077; : > "$sec/git-credentials" )
  line identity "$name: $gname <$gmail>"
  line wrote "$g"
  more "$dir/hosts.txt"
  more "$sec/git-credentials (empty, readable only by you)"
  next "mirabelle host add $name https://<git server>"
}

identity_ls() {
  [[ $# -eq 0 ]] || die "usage: mirabelle identity ls"
  local d found=0 n
  for d in "$MB_CONFIG"/identities/*/; do
    [[ -f "$d/gitconfig" ]] || continue
    n=$(basename "$d")
    printf '%-12s %s <%s>\n' "$n" "$(git config -f "$d/gitconfig" user.name)" "$(git config -f "$d/gitconfig" user.email)"
    found=1
  done
  (( found )) || say "no identity yet (add one: mirabelle identity add <name>)"
}

identity_rm() {
  take_force "$@"; set -- "${MB_REST[@]+"${MB_REST[@]}"}"
  local name=${1:-}; [[ -n "$name" && $# -eq 1 ]] || die "usage: mirabelle identity rm [-f] <name>"
  local dir="$MB_CONFIG/identities/$name" sec="$MB_SECRETS/identities/$name"
  [[ -d "$dir" ]] || die "no identity '$name'"
  guard_in_use "identity '$name'" mirabelle.identity "$name"
  confirm "Delete identity '$name' ($dir and its tokens)?" || { say "nothing deleted"; return 0; }
  run rm -rf "$dir" "$sec"
  line deleted "$dir"
  more "$sec"
}

# --- hosts ------------------------------------------------------------------

urlencode() {
  local s=$1 out="" c i
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    case "$c" in
      [a-zA-Z0-9._~-]) out+=$c ;;
      *) printf -v c '%%%02X' "'$c"; out+=$c ;;
    esac
  done
  printf '%s' "$out"
}

cmd_host() {
  local sub=${1:-}; shift || true
  case "$sub" in
    add) host_add "$@" ;;
    ls)  host_ls "$@" ;;
    rm)  host_rm "$@" ;;
    *)   die "usage: mirabelle host add|ls|rm [-f] <identity> [<https-url>]" ;;
  esac
}

parse_https_url() {   # sets H_HOST H_PORT H_URL
  [[ "$1" =~ ^https://([a-zA-Z0-9.-]+)(:([0-9]+))?/?$ ]] ||
    die "'$1' is not of the form https://host or https://host:port"
  H_HOST=$(tr '[:upper:]' '[:lower:]' <<<"${BASH_REMATCH[1]}")
  H_PORT=${BASH_REMATCH[3]:-443}
  H_URL="https://$H_HOST$([[ $H_PORT != 443 ]] && echo ":$H_PORT")"
}

host_add() {
  take_force "$@"; set -- "${MB_REST[@]+"${MB_REST[@]}"}"
  [[ $# -eq 2 ]] || die "usage: mirabelle host add [-f] <identity> <https-url>"
  local id=$1; parse_https_url "$2"
  local dir="$MB_CONFIG/identities/$id" sec="$MB_SECRETS/identities/$id"
  [[ -f "$dir/gitconfig" ]] || die "no identity '$id'"
  local replace=0
  if grep -q "^$H_URL " "$dir/hosts.txt" 2>/dev/null; then
    (( MB_FORCE )) || die "$H_URL is already a host of '$id'; to replace its token: mirabelle host add -f $id $H_URL"
    replace=1
    line replacing "$H_URL of '$id' (the old entry is kept until the new one is complete)"
  fi
  valid_domain "$H_HOST" || [[ "$H_HOST" =~ ^[0-9.]+$ ]] || die "'$H_HOST' is not a valid host name"

  local user token
  read -r -p "User name on $H_HOST: " user
  read -r -s -p "Token for $H_HOST (it is not shown): " token; echo
  token=${token//[[:space:]]/}
  [[ -n "$user" && -n "$token" ]] || die "both are needed; nothing saved"

  # Address: a private one means the firewall must allow exactly that pair.
  local addr where
  if [[ "$H_HOST" =~ ^[0-9.]+$ ]]; then addr=$H_HOST
  else addr=$(getent ahostsv4 "$H_HOST" 2>/dev/null | awk 'NR==1{print $1}')
  fi
  [[ -n "$addr" ]] || die "cannot find the address of $H_HOST from this PC"
  if is_private_ipv4 "$addr"; then where=private; else where=public; fi
  line host "$H_URL → $addr ($where)"

  # Certificate, checked from the PC.
  local trust=""
  if ! command -v openssl >/dev/null; then
    warn "openssl is not installed on the PC: the certificate was not checked"
  else
    local out
    out=$(openssl s_client -connect "$addr:$H_PORT" -servername "$H_HOST" -verify_return_error -verify_hostname "$H_HOST" </dev/null 2>&1) && trust=public || true
    if [[ "$trust" == public ]]; then
      line cert "publicly trusted"
    else
      local chain
      chain=$(openssl s_client -connect "$addr:$H_PORT" -servername "$H_HOST" -showcerts </dev/null 2>/dev/null |
              sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p')
      if [[ -z "$chain" ]]; then
        warn "could not read a certificate from $addr:$H_PORT; not checked"
      else
        line cert "NOT publicly trusted:"
        openssl x509 -noout -subject -issuer -enddate -fingerprint -sha256 <<<"$chain" | sed 's/^/           /'
        if confirm "Trust this certificate for identity '$id'?"; then trust=saved
        else die "not trusted; nothing saved"
        fi
      fi
    fi
  fi
  (( MB_DRY )) && return 0

  if (( replace )); then
    host_drop "$dir" "$sec"
    line removed "the old entry of $H_URL"
  fi
  if [[ "$trust" == saved ]]; then
    printf '%s\n' "$chain" > "$dir/ca/$H_HOST.crt"
    line saved "$dir/ca/$H_HOST.crt"
  fi
  printf '%s %s %s %s %s\n' "$H_URL" "$H_HOST" "$H_PORT" "$addr" "$where" >> "$dir/hosts.txt"
  ( umask 077; printf 'https://%s:%s@%s\n' "$(urlencode "$user")" "$(urlencode "$token")" "${H_URL#https://}" >> "$sec/git-credentials" )
  line wrote "$dir/hosts.txt"
  more "$sec/git-credentials"
  [[ "$where" == private ]] && more "the firewall will allow $addr:$H_PORT for containers using '$id'"
  next "running containers using '$id' get it after: mirabelle lock"
}

host_ls() {
  [[ $# -eq 1 ]] || die "usage: mirabelle host ls <identity>"
  local f="$MB_CONFIG/identities/$1/hosts.txt"
  [[ -f "$f" ]] || die "no identity '$1'"
  local url host port addr where n=0
  while read -r url host port addr where _; do
    [[ -z "${url:-}" || "$url" == \#* ]] && continue
    printf '%-40s %s %s%s\n' "$url" "$addr" "$where" "$([[ -f "$MB_CONFIG/identities/$1/ca/$host.crt" ]] && echo ', own certificate')"
    n=$((n + 1))
  done < "$f"
  (( n )) || say "no host for '$1' (add one: mirabelle host add $1 https://...)"
}

# Removes the host H_URL / H_HOST from an identity: its line, token, certificate.
host_drop() {   # host_drop <identity dir> <secrets dir>
  local dir=$1 sec=$2 tmp
  tmp=$(mktemp)
  grep -v "^$H_URL " "$dir/hosts.txt" > "$tmp" || true; cat "$tmp" > "$dir/hosts.txt"
  grep -v "@${H_URL#https://}\$" "$sec/git-credentials" > "$tmp" || true; cat "$tmp" > "$sec/git-credentials"
  rm -f "$tmp" "$dir/ca/$H_HOST.crt"
}

host_rm() {
  take_force "$@"; set -- "${MB_REST[@]+"${MB_REST[@]}"}"
  [[ $# -eq 2 ]] || die "usage: mirabelle host rm [-f] <identity> <https-url>"
  local id=$1; parse_https_url "$2"
  local dir="$MB_CONFIG/identities/$id" sec="$MB_SECRETS/identities/$id"
  grep -q "^$H_URL " "$dir/hosts.txt" 2>/dev/null || die "$H_URL is not a host of '$id'"
  guard_in_use "identity '$id'" mirabelle.identity "$id"
  confirm "Remove $H_URL from '$id' (its token and certificate too)?" || { say "nothing removed"; return 0; }
  (( MB_DRY )) && return 0
  host_drop "$dir" "$sec"
  line removed "$H_URL from $dir/hosts.txt, its token, and its certificate if any"
  next "running containers using '$id' lose its firewall entry after: mirabelle lock"
}

# --- sites ------------------------------------------------------------------

sites_file() {   # sites_file <project or "">
  if [[ -n "$1" ]]; then need_name project "$1"; printf '%s\n' "$MB_CONFIG/projects/$1/sites.txt"
  else printf '%s\n' "$MB_CONFIG/sites.txt"
  fi
}

cmd_site() {
  local sub=${1:-}; shift || true
  local domain="" project=""
  while (( $# )); do
    case "$1" in
      -n) project=${2:?-n needs a project name}; shift 2 ;;
      -*) die "site: unknown option '$1'" ;;
      *)  [[ -z "$domain" ]] || die "site: one domain at a time"; domain=$(tr '[:upper:]' '[:lower:]' <<<"$1"); shift ;;
    esac
  done
  local f; f=$(sites_file "$project")
  case "$sub" in
    add)
      [[ -n "$domain" ]] || die "usage: mirabelle site add <domain> [-n <project>]"
      valid_domain "$domain" || die "'$domain' is not a domain (example: docs.zephyrproject.org)"
      if read_sites "$f" | grep -qx "$domain"; then say "$domain is already in $f"; return 0; fi
      (( MB_DRY )) && { say "would add $domain to $f"; return 0; }
      mkdir -p "$(dirname "$f")"
      [[ -f "$f" ]] || say "# Sites for project ${project}, on top of config/sites.txt. One domain per line." > "$f"
      printf '%s\n' "$domain" >> "$f"
      line added "$domain to $f"
      next "a running container gets it after: mirabelle lock${project:+ -n $project}"
      ;;
    ls)
      [[ -z "$domain" ]] || die "usage: mirabelle site ls [-n <project>]"
      say "plumbing/sites.txt (what the plumbing needs; change it through mirabelle upgrade):"; read_sites "$MB_PLUMBING/sites.txt" | sed 's/^/  /'
      say "config/sites.txt:"; read_sites "$MB_CONFIG/sites.txt" | sed 's/^/  /'
      if [[ -n "$project" ]]; then
        say "config/projects/$project/sites.txt:"
        if [[ -f "$f" ]]; then read_sites "$f" | sed 's/^/  /'; else say "  (none)"; fi
      fi
      ;;
    rm)
      [[ -n "$domain" ]] || die "usage: mirabelle site rm <domain> [-n <project>]"
      read_sites "$f" | grep -qx "$domain" || die "$domain is not in $f"
      (( MB_DRY )) && { say "would remove $domain from $f"; return 0; }
      local tmp; tmp=$(mktemp)
      awk -v d="$domain" '{ x=$0; sub(/#.*/, "", x); gsub(/[[:space:]]/, "", x); if (tolower(x) != d) print }' "$f" > "$tmp"
      cat "$tmp" > "$f"; rm -f "$tmp"
      line removed "$domain from $f"
      next "a running container loses it after: mirabelle lock${project:+ -n $project}"
      ;;
    *) die "usage: mirabelle site add|ls|rm <domain> [-n <project>]" ;;
  esac
}
