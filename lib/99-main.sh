# shellcheck shell=bash
# Command dispatch and help.

usage() {
  cat <<'EOF'
mirabelle: Claude in a container, per project folder, behind a firewall.

Working in a folder (uses the folder's name, or -n <name>)
  run -a <account> -i <identity> [-p <port>] [-n <name>] [--previous]
                     start this folder's container, with its firewall
  code               open VS Code attached to the running container
  claude [-- args]   open Claude in the running container (again to reattach)
  shell              open a shell in the running container
  lock               re-apply the firewall to the running container
  stop               stop and remove the container
  ps                 list running containers
  inspect            show options, mounts, allowed sites and firewall state
  logs               show what the firewall allowed and refused

Image
  build [--fresh] [-n <project>]   build the image (or a project's extra layer)
  images                           list mirabelle's images
  prune                            delete the previous images no longer used

Accounts, identities, sites
  account add|ls|rm <name>                     Claude accounts
  identity add|ls|rm <name>                    git identities
  host add|ls|rm <identity> [<https-url>]      git hosts of an identity
  site add|ls|rm <domain> [-n <project>]       sites the firewall allows

Upgrading mirabelle
  upgrade -a <account>   start the upgrade container and open Claude in it
  status                 pending changes, what is not saved or pushed, images
  apply                  show the pending changes and, on your yes, apply them
  discard                throw the pending changes away
  rollback [<tag>]       undo the last apply (or every apply after <tag>)

Save and sync (plain git)
  home [<path-or-url>]   show or set where push and pull go
  save                   commit what is uncommitted in setup, kb, sessions
  push                   push the three repos
  pull                   pull the three repos

Every command accepts -v (show the docker and git commands) and --dry-run
(show them without running anything that changes something).
Full reference: setup/docs/REFERENCE.md
EOF
}

main() {
  take_global_flags "$@"
  set -- "${MB_ARGS[@]+"${MB_ARGS[@]}"}"
  local cmd=${1:-help}; shift || true
  case "$cmd" in
    help|-h|--help) usage; return 0 ;;
  esac
  need_not_root
  case "$cmd" in
    run)      cmd_run "$@" ;;
    lock)     cmd_lock "$@" ;;
    code)     cmd_code "$@" ;;
    claude)   cmd_claude "$@" ;;
    shell)    cmd_shell "$@" ;;
    stop)     cmd_stop "$@" ;;
    ps)       cmd_ps "$@" ;;
    inspect)  cmd_inspect "$@" ;;
    logs)     cmd_logs "$@" ;;
    build)    cmd_build "$@" ;;
    images)   cmd_images "$@" ;;
    prune)    cmd_prune "$@" ;;
    account)  cmd_account "$@" ;;
    identity) cmd_identity "$@" ;;
    host)     cmd_host "$@" ;;
    site)     cmd_site "$@" ;;
    upgrade)  cmd_upgrade "$@" ;;
    status)   cmd_status "$@" ;;
    apply)    cmd_apply "$@" ;;
    discard)  cmd_discard "$@" ;;
    rollback) cmd_rollback "$@" ;;
    home)     cmd_home "$@" ;;
    save)     cmd_save "$@" ;;
    push)     cmd_push "$@" ;;
    pull)     cmd_pull "$@" ;;
    *)        die "unknown command '$cmd' (see: mirabelle help)" ;;
  esac
}
