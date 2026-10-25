# cclaude — Containerized Claude Code
# https://github.com/nlink-jp/cclaude
#
# Pre-installed toolchains: Go, Node.js, Python (uv)
# Customize by editing this file or extending from cclaude:latest.
#
# Every download below is pinned: the base image by its digest, each tool by
# an exact version and the SHA256 its upstream author publishes for amd64 and
# arm64. A rebuild (cclaude --build) takes only Debian's updates, whose
# signatures apt verifies. A new base or a new tool version arrives with a new
# cclaude release. To change one yourself, edit its ARG lines (version and
# both hashes, copied from the upstream's checksum file named next to it).

# The multi-arch index digest of debian:bookworm-slim (amd64 and arm64 both
# resolve through it). It pins the Debian release, not each package version.
ARG BASE_IMAGE=debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8

# ---- Downloads ----
# Each tool is fetched and checked in its own stage; the image takes only
# the unpacked files. sha256sum -c fails the build on a mismatch.
FROM ${BASE_IMAGE} AS fetch
RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Go — SHA256 from https://go.dev/dl/?mode=json
FROM fetch AS go
ARG GO_VERSION=1.27.3
ARG GO_SHA256_AMD64=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40
ARG GO_SHA256_ARM64=a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49
RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
         amd64) sha="$GO_SHA256_AMD64" ;; \
         arm64) sha="$GO_SHA256_ARM64" ;; \
         *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" \
    && echo "${sha}  /tmp/go.tar.gz" | sha256sum -c - \
    && mkdir /out \
    && tar -C /out --no-same-owner -xzf /tmp/go.tar.gz

# Node.js (official build) — SHA256 from
# https://nodejs.org/dist/v<version>/SHASUMS256.txt
# Use a supported line: https://github.com/nodejs/release#release-schedule
FROM fetch AS node
ARG NODE_VERSION=24.22.1
ARG NODE_SHA256_AMD64=eb6728e77c576a35162c122c45ccadf224d89ff00abc8dae46cc2897c6002d7c
ARG NODE_SHA256_ARM64=33c37be234ba8bee041961047b19160f4d7d0f164e8e246f78bdd10feff148b3
RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
         amd64) sha="$NODE_SHA256_AMD64"; narch=x64 ;; \
         arm64) sha="$NODE_SHA256_ARM64"; narch=arm64 ;; \
         *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/node.tar.gz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${narch}.tar.gz" \
    && echo "${sha}  /tmp/node.tar.gz" | sha256sum -c - \
    && mkdir -p /tmp/node /out \
    && tar -C /tmp/node --no-same-owner -xzf /tmp/node.tar.gz --strip-components=1 \
    && mv /tmp/node/bin /tmp/node/include /tmp/node/lib /tmp/node/share /out/

# uv — SHA256 from the release's sha256.sum
# (https://github.com/astral-sh/uv/releases)
FROM fetch AS uv
ARG UV_VERSION=0.13.5
ARG UV_SHA256_AMD64=f68d291c75783122dad58ab77def0e13f3233f358731db5d6d7e8715603b928f
ARG UV_SHA256_ARM64=4bb69cf95ed13f23713bb7bc09f241896ea0c75b7c557e615a20604b82f9c403
RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
         amd64) sha="$UV_SHA256_AMD64"; triple=x86_64-unknown-linux-gnu ;; \
         arm64) sha="$UV_SHA256_ARM64"; triple=aarch64-unknown-linux-gnu ;; \
         *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/uv.tar.gz "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${triple}.tar.gz" \
    && echo "${sha}  /tmp/uv.tar.gz" | sha256sum -c - \
    && mkdir /out \
    && tar -C /out --no-same-owner -xzf /tmp/uv.tar.gz --strip-components=1

# Claude Code (native binary) — SHA256 from
# https://downloads.claude.ai/claude-code-releases/<version>/manifest.json
# (platforms."linux-x64" / "linux-arm64" .checksum). Laid out the way the
# native installer does: the launcher is a symlink to versions/<version>.
FROM fetch AS claude
ARG CLAUDE_VERSION=2.1.310
ARG CLAUDE_SHA256_AMD64=b73676430af12f97316a798b8371f81d640f90a58bdcb8f3ce56a835bb47df56
ARG CLAUDE_SHA256_ARM64=9c64d9a7442436b65fcd7cc02c1aa0051bb5a7041e7788576ed3b5f29c447d54
RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
         amd64) sha="$CLAUDE_SHA256_AMD64"; platform=linux-x64 ;; \
         arm64) sha="$CLAUDE_SHA256_ARM64"; platform=linux-arm64 ;; \
         *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/claude "https://downloads.claude.ai/claude-code-releases/${CLAUDE_VERSION}/${platform}/claude" \
    && echo "${sha}  /tmp/claude" | sha256sum -c - \
    && mkdir -p /out/bin /out/share/claude/versions \
    && install -m 755 /tmp/claude "/out/share/claude/versions/${CLAUDE_VERSION}" \
    && ln -s "/root/.local/share/claude/versions/${CLAUDE_VERSION}" /out/bin/claude

# GitHub CLI — SHA256 from the release's gh_<version>_checksums.txt
# (https://github.com/cli/cli/releases)
FROM fetch AS gh
ARG GH_VERSION=2.103.2
ARG GH_SHA256_AMD64=62ccf747115ddc61237efffdde66a3c8f70ba249433dc64f70801089b59c59c8
ARG GH_SHA256_ARM64=4c3e99a50bd8b181a3fe9d69b25dd978bac768148d88f01507c6b4d1ef61a443
RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
         amd64) sha="$GH_SHA256_AMD64" ;; \
         arm64) sha="$GH_SHA256_ARM64" ;; \
         *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/gh.tar.gz "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.tar.gz" \
    && echo "${sha}  /tmp/gh.tar.gz" | sha256sum -c - \
    && mkdir -p /tmp/gh /out \
    && tar -C /tmp/gh --no-same-owner -xzf /tmp/gh.tar.gz --strip-components=1 \
    && mv /tmp/gh/bin /tmp/gh/share /out/

# golangci-lint — SHA256 from the release's golangci-lint-<version>-checksums.txt
# (https://github.com/golangci/golangci-lint/releases). It must be built with
# a Go at least as new as GO_VERSION to lint code for that Go.
FROM fetch AS golangci-lint
ARG GOLANGCI_LINT_VERSION=2.15.0
ARG GOLANGCI_LINT_SHA256_AMD64=9b7fe6a6bf6334b98decf8d86b11415ea7889afdabdd1959fdce23af2a9ebcea
ARG GOLANGCI_LINT_SHA256_ARM64=b4d8f17068b35ee6060cc2f69a16fb48740d706fbba81661c318649c114a6998
RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
         amd64) sha="$GOLANGCI_LINT_SHA256_AMD64" ;; \
         arm64) sha="$GOLANGCI_LINT_SHA256_ARM64" ;; \
         *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/golangci-lint.tar.gz "https://github.com/golangci/golangci-lint/releases/download/v${GOLANGCI_LINT_VERSION}/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${arch}.tar.gz" \
    && echo "${sha}  /tmp/golangci-lint.tar.gz" | sha256sum -c - \
    && mkdir /out \
    && tar -C /out --no-same-owner -xzf /tmp/golangci-lint.tar.gz --strip-components=1 \
       "golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${arch}/golangci-lint"

# ---- Image ----
FROM ${BASE_IMAGE}

# ---- System dependencies ----
# `upgrade` takes Debian's security updates for packages already in the base
# image; `install` alone leaves them at the base's versions.
RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        jq \
        make \
        openssh-client \
        openssh-server \
        ripgrep \
        socat \
        unzip \
        zip \
        zsh \
    && rm -rf /var/lib/apt/lists/*

# ---- Toolchains and tools (verified in the stages above) ----
COPY --from=go /out/go /usr/local/go
COPY --from=node /out/ /usr/local/
COPY --from=uv /out/ /root/.local/bin/
COPY --from=claude /out/ /root/.local/
COPY --from=gh /out/ /usr/local/
COPY --from=golangci-lint /out/golangci-lint /usr/local/bin/golangci-lint
ENV PATH="/root/.local/bin:/usr/local/go/bin:/root/go/bin:${PATH}"

# Fail the build if any tool does not run.
RUN go version \
    && node --version \
    && npm --version \
    && uv --version \
    && claude --version \
    && gh --version \
    && golangci-lint --version

# ---- sshd for agent forwarding ----
RUN mkdir -p /run/sshd \
    && ssh-keygen -A \
    && sed -i 's/^#\?AllowAgentForwarding.*/AllowAgentForwarding yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && mkdir -p /root/.ssh && chmod 700 /root/.ssh

# ---- npm security hardening ----
RUN printf '%s\n' \
    'engine-strict=true' \
    'ignore-scripts=true' \
    'audit=true' \
    > /root/.npmrc

# ---- Container defaults ----
# Allow any mounted git repo
RUN git config --global --add safe.directory '*'

# Skip auto-updates inside the container
ENV DISABLE_AUTOUPDATER=1

# Ensure PATH is available in SSH login shells (sshd does not inherit Dockerfile ENV)
RUN printf '%s\n' \
    'export PATH="/root/.local/bin:/usr/local/go/bin:/root/go/bin:$PATH"' \
    'export DISABLE_AUTOUPDATER=1' \
    > /root/.profile \
    && cp /root/.profile /root/.bashrc

WORKDIR /workspace
