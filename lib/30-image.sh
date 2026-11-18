# shellcheck shell=bash
# Images: build, images, prune.
#
# Names: the base image is "mirabelle", a project's extra layer is
# "mirabelle-<project>". Each has a "latest" tag and, after a rebuild, a
# "previous" tag (the image as it was before that build).
# Build records: local/images/<name>.txt and <name>.previous.txt.

# Writes the build record of an image to stdout.
image_record() {   # image_record <image:tag> <context dir>
  local image=$1 ctx=$2
  say "# Build record written by mirabelle build. Compare two with: diff <old> <new>"
  say "image:        $image"
  say "id:           $(docker image inspect -f '{{.Id}}' "$image")"
  say "built:        $(date '+%Y-%m-%d %H:%M:%S')"
  say "from:         $ctx"
  say "setup:        $(git -C "$MB_SETUP" rev-parse --short HEAD 2>/dev/null || echo unknown)$(git -C "$MB_SETUP" diff --quiet HEAD -- "$ctx" 2>/dev/null || echo ' + uncommitted changes')"
  say "claude:       $(docker run --rm --network none --entrypoint claude "$image" --version 2>/dev/null | head -1)"
  say "packages:"
  docker run --rm --network none --entrypoint dpkg-query "$image" -W -f '  ${Package} ${Version}\n'
}

cmd_build() {
  local fresh=0 project=""
  while (( $# )); do
    case "$1" in
      --fresh) fresh=1; shift ;;
      -n) project=${2:?-n needs a project name}; shift 2 ;;
      *) die "build: unknown option '$1' (usage: mirabelle build [--fresh] [-n <project>])" ;;
    esac
  done
  need_docker; need_not_root

  local repo ctx
  local -a a=(docker build)
  if [[ -n "$project" ]]; then
    need_name project "$project"
    repo="mirabelle-$project"; ctx="$MB_SETUP/projects/$project"
    [[ -f "$ctx/Dockerfile" ]] || die "no $ctx/Dockerfile (a project layer starts with: ARG BASE / FROM \${BASE})"
    image_exists mirabelle:latest || die "the base image does not exist yet: run mirabelle build first"
    a+=(--build-arg BASE=mirabelle:latest --label "mirabelle.base=$(docker image inspect -f '{{.Id}}' mirabelle:latest)")
  else
    repo=mirabelle; ctx="$MB_SETUP/image"
  fi
  # Labels change only when the definition changes, so a rebuild of an
  # unchanged definition gives the same image (and "previous" is kept).
  # SOURCE_DATE_EPOCH and --provenance=false: Docker would otherwise stamp the
  # build time into the image (and into a provenance record attached to it),
  # making every build a different image. The time used is that of the last
  # commit that changed the definition.
  local epoch; epoch=$(git -C "$MB_SETUP" log -1 --format=%ct -- "$ctx" 2>/dev/null || true)
  a+=(--build-arg "USER_UID=$(id -u)" --build-arg "USER_GID=$(id -g)"
      --build-arg "SOURCE_DATE_EPOCH=${epoch:-0}"
      --provenance=false
      --label "mirabelle.kind=image"
      --label "mirabelle.source=$(git -C "$MB_SETUP" log -1 --format=%H -- "$ctx" 2>/dev/null || echo unknown)")
  (( fresh )) && a+=(--no-cache --pull)
  a+=(-t "$repo:latest" "$ctx")

  # The current image gets a temporary name before the build, so that it is
  # not removed when "latest" moves to the new image (Docker's containerd
  # image store removes an image as soon as it has no name left).
  local old=""
  if image_exists "$repo:latest"; then
    old=$(docker image inspect -f '{{.Id}}' "$repo:latest")
    run docker tag "$repo:latest" "$repo:before-build"
  fi

  line building "$repo:latest from $ctx$( (( fresh )) && echo ', from scratch (--fresh)')"
  if ! run "${a[@]}"; then
    [[ -n "$old" ]] && run docker rmi "$repo:before-build" >/dev/null
    die "the build failed; $repo:latest is unchanged"
  fi
  (( MB_DRY )) && return 0

  local rec="$MB_LOCAL/images/$repo.txt"
  mkdir -p "$MB_LOCAL/images"
  local new; new=$(docker image inspect -f '{{.Id}}' "$repo:latest")
  if [[ -n "$old" && "$old" != "$new" ]]; then
    run docker tag "$repo:before-build" "$repo:previous"
    run docker rmi "$repo:before-build" >/dev/null
    [[ -f "$rec" ]] && run mv "$rec" "$MB_LOCAL/images/$repo.previous.txt"
    line kept "the image before this build as $repo:previous"
  elif [[ -n "$old" ]]; then
    run docker rmi "$repo:before-build" >/dev/null
    line same "nothing changed: $repo:latest is the same image as before"
  fi
  image_record "$repo:latest" "$ctx" > "$rec"

  line built "$repo:latest  $(docker image inspect -f '{{.Size}}' "$repo:latest" | awk '{printf "%.0f MB", $1/1e6}')"
  line claude "$(sed -n 's/^claude: *//p' "$rec")"
  line record "$rec"
  local prev="$MB_LOCAL/images/$repo.previous.txt"
  if [[ -n "$old" && "$old" != "$new" && -f "$prev" ]]; then
    local changes
    changes=$(diff <(sed -n '/^packages:/,$p' "$prev") <(sed -n '/^packages:/,$p' "$rec") | grep -c '^[<>]' || true)
    line changes "$changes package line(s) differ from the previous build (diff $prev $rec)"
    local oc nc
    oc=$(sed -n 's/^claude: *//p' "$prev"); nc=$(sed -n 's/^claude: *//p' "$rec")
    [[ "$oc" != "$nc" ]] && line claude "was $oc"
  fi
  [[ -z "$project" ]] && ls "$MB_SETUP/projects"/*/Dockerfile >/dev/null 2>&1 &&
    next "project layers are built on the base: rebuild them with mirabelle build -n <project>"
  next "running containers keep their old image until: mirabelle stop, then mirabelle run ..."
}

cmd_images() {
  [[ $# -eq 0 ]] || die "images takes no options"
  need_docker
  local -a rows=()
  local ref repo tag id created size claude used outdated src cur base
  while read -r ref; do
    [[ -n "$ref" ]] || continue
    repo=${ref%%:*}; tag=${ref##*:}
    id=$(docker image inspect -f '{{.Id}}' "$ref")
    size=$(docker image inspect -f '{{.Size}}' "$ref" | awk '{printf "%.0fMB", $1/1e6}')
    local recf="$MB_LOCAL/images/$repo.txt"; [[ "$tag" == previous ]] && recf="$MB_LOCAL/images/$repo.previous.txt"
    created=$( { sed -n 's/^built: *//p' "$recf" 2>/dev/null || true; } | cut -c1-16)
    claude=$( { sed -n 's/^claude: *//p' "$recf" 2>/dev/null || true; } | awk '{print $1}')
    used=$(docker ps --filter "ancestor=$id" --filter label=mirabelle.project --format '{{.Label "mirabelle.project"}}' | paste -sd, -)
    outdated=""
    if [[ "$tag" == latest ]]; then
      src=$(docker image inspect -f '{{index .Config.Labels "mirabelle.source"}}' "$ref")
      if [[ "$repo" == mirabelle ]]; then
        cur=$(git -C "$MB_SETUP" log -1 --format=%H -- image 2>/dev/null)
        { [[ "$src" != "$cur" ]] || ! git -C "$MB_SETUP" diff --quiet HEAD -- image; } && outdated="definition changed"
      else
        cur=$(git -C "$MB_SETUP" log -1 --format=%H -- "projects/${repo#mirabelle-}" 2>/dev/null)
        [[ "$src" != "$cur" ]] && outdated="definition changed"
        base=$(docker image inspect -f '{{index .Config.Labels "mirabelle.base"}}' "$ref")
        image_exists mirabelle:latest && [[ "$base" != "$(docker image inspect -f '{{.Id}}' mirabelle:latest)" ]] &&
          outdated="${outdated:+$outdated, }base rebuilt"
      fi
    fi
    rows+=("$repo"$'\t'"$tag"$'\t'"${created:--}"$'\t'"$size"$'\t'"${claude:--}"$'\t'"${used:--}"$'\t'"${outdated:-up to date}")
  done < <(docker image ls --filter label=mirabelle.kind=image --format '{{.Repository}}:{{.Tag}}' | grep -E '^mirabelle(-[a-z0-9_.-]+)?:(latest|previous)$' | sort)
  if (( ${#rows[@]} == 0 )); then say "no mirabelle image yet (build one: mirabelle build)"; return 0; fi
  { printf 'IMAGE\tTAG\tBUILT\tSIZE\tCLAUDE\tUSED BY\tSTATE\n'; printf '%s\n' "${rows[@]}"; } | table
}

cmd_prune() {
  [[ $# -eq 0 ]] || die "prune takes no options"
  need_docker
  local -a del=() keep=()
  local ref id used
  while read -r ref; do
    [[ -n "$ref" ]] || continue
    id=$(docker image inspect -f '{{.Id}}' "$ref")
    used=$(docker ps -a --filter "ancestor=$id" --format '{{.Names}}' | paste -sd, -)
    if [[ -n "$used" ]]; then keep+=("$ref (used by $used)"); else del+=("$ref"); fi
  done < <(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E '^mirabelle(-[a-z0-9_.-]+)?:previous$' | sort)
  local k
  for k in "${keep[@]}"; do line kept "$k"; done
  if (( ${#del[@]} == 0 )); then say "nothing to delete: no unused previous image"; return 0; fi
  say "These previous images and their build records will be deleted:"
  printf '  %s\n' "${del[@]}"
  confirm "Delete them?" || { say "nothing deleted"; return 0; }
  for ref in "${del[@]}"; do
    run docker rmi "$ref" >/dev/null
    run rm -f "$MB_LOCAL/images/${ref%%:*}.previous.txt"
    line deleted "$ref"
  done
}
