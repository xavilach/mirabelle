#!/bin/bash
# Installs the Claude Code command-line tool into /usr/local/bin/claude.
#
# Source: the official npm package for this platform
# (@anthropic-ai/claude-code-linux-x64 or -linux-arm64), which contains the
# native binary. Node is not needed.
#
# Usage: install-claude.sh <version>
#   <version> is "stable", "latest", or an exact version such as 2.1.311.
#   An exact version is a pin. A tag is resolved at build time, so
#   `mirabelle build --fresh` picks up the newest one.
#
# The download is checked against the sha512 published by the registry.
set -euo pipefail

want=${1:?version or tag required}

case "$(dpkg --print-architecture)" in
  amd64) pkg=claude-code-linux-x64 ;;
  arm64) pkg=claude-code-linux-arm64 ;;
  *) echo "install-claude: unsupported architecture $(dpkg --print-architecture)" >&2; exit 1 ;;
esac

meta=$(curl -fsSL "https://registry.npmjs.org/@anthropic-ai/${pkg}")

pick='
import json, sys
want = sys.argv[1]
d = json.load(sys.stdin)
version = d["dist-tags"].get(want, want)
if version not in d["versions"]:
    sys.exit(f"install-claude: unknown version or tag: {want}")
dist = d["versions"][version]["dist"]
print(version, dist["tarball"], dist["integrity"])
'
read -r version tarball integrity < <(python3 -c "$pick" "$want" <<<"$meta")
[[ -n "${integrity:-}" ]] || { echo "install-claude: could not read the registry answer" >&2; exit 1; }

echo "install-claude: ${pkg} ${version} (asked: ${want})"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/pkg.tgz" "$tarball"

got="sha512-$(openssl dgst -sha512 -binary "$tmp/pkg.tgz" | base64 -w0)"
if [[ "$got" != "$integrity" ]]; then
  echo "install-claude: checksum mismatch" >&2
  echo "  expected $integrity" >&2
  echo "  got      $got" >&2
  exit 1
fi
echo "install-claude: checksum ok"

tar -xzf "$tmp/pkg.tgz" -C "$tmp" package/claude
install -m 0755 -o root -g root "$tmp/package/claude" /usr/local/bin/claude
/usr/local/bin/claude --version
