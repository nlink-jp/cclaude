# cclaude — Containerized Claude Code
# https://github.com/nlink-jp/cclaude
#
# Pre-installed toolchains: Go, Node.js, Python (uv)
# Customize by editing this file or extending from cclaude:latest.

FROM debian:bookworm-slim

# ---- System dependencies ----
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        jq \
        make \
        openssh-client \
        ripgrep \
        socat \
        unzip \
        zsh \
    && rm -rf /var/lib/apt/lists/*

# ---- Go ----
ARG GO_VERSION=1.23.4
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" \
       | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"

# ---- Node.js (required by Claude Code) ----
ARG NODE_VERSION=20
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ---- Python via uv ----
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# ---- Claude Code ----
RUN npm install -g @anthropic-ai/claude-code

# ---- GitHub CLI ----
RUN ARCH="$(dpkg --print-architecture)" \
    && GH_VER="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | jq -r '.tag_name | ltrimstr("v")')" \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_${ARCH}.tar.gz" \
       | tar -xz --strip-components=1 -C /usr/local

# ---- golangci-lint ----
RUN curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh \
    | sh -s -- -b /usr/local/bin

# ---- Container defaults ----
# Allow any mounted git repo
RUN git config --global --add safe.directory '*'

# Skip auto-updates inside the container
ENV DISABLE_AUTOUPDATER=1

WORKDIR /workspace
