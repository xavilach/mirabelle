# mirabelle base image.
#
# Everything a project container runs comes from here: the operating system,
# the build tools, Claude Code, and the two programs the firewall uses
# (iptables and tinyproxy). The firewall's *rules* are not in the image: they
# are generated on the PC and applied by setup/lock/apply.sh.
#
# Changed only through the upgrade project (`mirabelle upgrade`), then
# `mirabelle apply` and `mirabelle build`.

# Pinned: Ubuntu 24.04 LTS, by digest, so every build starts from the exact
# same system. Update the digest deliberately, in the upgrade project.
FROM ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8

# Your user and group ids on the PC, passed by `mirabelle build`, so files
# created in the container belong to you.
ARG USER_UID=1000
ARG USER_GID=1000

# Claude Code version: "stable", "latest", or an exact version such as
# "2.1.311". An exact version is a pin: every build installs the same one.
# A tag is resolved when the image is built; `mirabelle build --fresh`
# resolves it again.
ARG CLAUDE_CODE_VERSION=stable

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# Extra certificates to trust while building (for example a company proxy that
# inspects TLS). Drop .crt files in image/extra-ca/. Empty by default.
COPY extra-ca/ /usr/local/share/ca-certificates/mirabelle-extra/

# Tools. To pin a tool, write its exact version: gcc-12=12.2.0-14
# `mirabelle build` writes every installed version to the build record.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl openssl git tmux less nano procps \
      build-essential cmake ninja-build pkg-config \
      python3 python3-venv \
      iptables tinyproxy \
 && update-ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/tinyproxy/tinyproxy.conf

# Two users:
#   dev  - you and Claude. Everything you run is this user.
#   gate - only the firewall's filter runs as this user. Only it may go out.
# (Ubuntu's image ships a user "ubuntu" with id 1000; it is removed so that
# "dev" can take your ids.)
RUN userdel --remove ubuntu 2>/dev/null || true \
 && groupadd --gid "${USER_GID}" dev \
 && useradd --uid "${USER_UID}" --gid dev --create-home --shell /bin/bash dev \
 && useradd --system --no-create-home --shell /usr/sbin/nologin gate \
 && echo 'umask 022   # mirabelle: new files not writable by others' >> /etc/bash.bashrc

# Claude Code, root-owned so that it cannot be modified from inside the
# container. See install-claude.sh.
COPY install-claude.sh /usr/local/lib/mirabelle/install-claude.sh
RUN bash /usr/local/lib/mirabelle/install-claude.sh "${CLAUDE_CODE_VERSION}"

USER dev
WORKDIR /home/dev

# Read by VS Code when it attaches: work as "dev", and install the Claude Code
# extension inside the container (never in VS Code on the PC).
LABEL devcontainer.metadata='[{"remoteUser":"dev","customizations":{"vscode":{"extensions":["anthropic.claude-code"]}}}]'

CMD ["sleep", "infinity"]
