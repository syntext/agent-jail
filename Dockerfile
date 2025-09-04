FROM debian:trixie

ARG TZ
ENV TZ="$TZ"
ENV DEBIAN_FRONTEND=noninteractive

# Base packages and tooling
RUN apt-get update && apt-get install -y \
  bash \
  ca-certificates \
  curl \
  dnsutils \
  fzf \
  gh \
  git \
  gnupg \
  iproute2 \
  ipset \
  iptables \
  jq \
  less \
  locales \
  lsb-release \
  man-db \
  ncurses-term \
  procps \
  python3 \
  python3-pip \
  python3-venv \
  sudo \
  tmux \
  unzip \
  vim \
  wget \
  zip \
  zsh \
  gosu \
  && rm -rf /var/lib/apt/lists/*

# Locales
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && \
  locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8 \
  LC_ALL=en_US.UTF-8

# Install Docker Engine (for dind)
RUN install -m 0755 -d /etc/apt/keyrings && \
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
  chmod a+r /etc/apt/keyrings/docker.asc && \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list && \
  apt-get update && apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin \
  && rm -rf /var/lib/apt/lists/*

# Create non-root user 'node' and groups
ARG USERNAME=node
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid ${USER_GID} ${USERNAME} && \
  useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} && \
  usermod -aG sudo ${USERNAME} && \
  groupadd -f docker && usermod -aG docker ${USERNAME} && \
  passwd -d ${USERNAME} || true && \
  echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/node-sudo && chmod 0440 /etc/sudoers.d/node-sudo

# Prepare shared directories and workspace
RUN mkdir -p /workspace /home/${USERNAME}/.claude /commandhistory && \
  chown -R ${USERNAME}:${USERNAME} /workspace /home/${USERNAME} /commandhistory

# Persist bash history for convenience
ENV PROMPT_COMMAND='history -a' \
  HISTFILE=/commandhistory/.bash_history
RUN touch /commandhistory/.bash_history && chown ${USERNAME}:${USERNAME} /commandhistory/.bash_history

# Devcontainer flag
ENV DEVCONTAINER=true

WORKDIR /workspace

# Install git-delta
RUN ARCH=$(dpkg --print-architecture) && \
  wget -q "https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_${ARCH}.deb" && \
  dpkg -i "git-delta_0.18.2_${ARCH}.deb" && \
  rm -f "git-delta_0.18.2_${ARCH}.deb"

# Install SDKMAN and Java 21 (Temurin) as 'node'
USER ${USERNAME}
ENV SHELL=/bin/bash \
  TERM=xterm-256color
RUN curl -s "https://get.sdkman.io" | bash && \
  bash -lc "source $HOME/.sdkman/bin/sdkman-init.sh && sdk install java 21.0.5-tem && sdk default java 21.0.5-tem"
RUN echo "source \$HOME/.sdkman/bin/sdkman-init.sh" >> $HOME/.bashrc
ENV SDKMAN_DIR=/home/${USERNAME}/.sdkman
ENV JAVA_HOME=$SDKMAN_DIR/candidates/java/current
ENV PATH=$JAVA_HOME/bin:$PATH

# Install NVM and Node.js v24 for 'node'
ENV NVM_DIR=/home/${USERNAME}/.nvm
RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh -o /tmp/install-nvm.sh && \
  bash /tmp/install-nvm.sh && rm -f /tmp/install-nvm.sh && \
  bash -lc "source \"$NVM_DIR/nvm.sh\" && nvm install 24 && nvm alias default 24"

# Install provider CLIs globally via npm
RUN bash -lc "unset NPM_CONFIG_PREFIX; source \"$NVM_DIR/nvm.sh\" && nvm use default && npm install -g @anthropic-ai/claude-code @openai/codex @just-every/code"

# Source user env by default (conditionally)
RUN echo '[ -s "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"' >> $HOME/.bashrc || true
RUN echo 'export NVM_DIR="$HOME/.nvm"' >> $HOME/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> $HOME/.bashrc && \
    echo 'nvm use --silent default >/dev/null 2>&1 || true' >> $HOME/.bashrc && \
    echo '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"' >> $HOME/.bashrc
RUN echo 'if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi' >> $HOME/.profile

# Copy optional firewall script
USER root
COPY init-firewall.sh /usr/local/bin/
# Lockdown mode disabled by default; can be enabled later
# RUN chmod +x /usr/local/bin/init-firewall.sh && \
#   echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
#   chmod 0440 /etc/sudoers.d/node-firewall

# DIND entrypoint to start dockerd then drop to 'node'
COPY --chown=root:root <<'EOF' /usr/local/bin/dind-entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail

# Ensure runtime dirs exist
mkdir -p /var/lib/docker /var/run

# Make sure iptables allows forward (common in dind)
if command -v iptables >/dev/null 2>&1; then
  iptables -P FORWARD ACCEPT || true
fi

# Start dockerd in the background (silence to logfile)
DOCKERD_ARGS=("--host=unix:///var/run/docker.sock")
if [ -n "${DOCKERD_STORAGE_DRIVER:-}" ]; then
  DOCKERD_ARGS+=("--storage-driver=${DOCKERD_STORAGE_DRIVER}")
fi
DOCKERD_LOG=${DOCKERD_LOG:-/var/log/dockerd.log}
touch "$DOCKERD_LOG" && chmod 0644 "$DOCKERD_LOG"

dockerd "${DOCKERD_ARGS[@]}" >>"$DOCKERD_LOG" 2>&1 &
DOCKERD_PID=$!

cleanup() {
  if kill -0 "$DOCKERD_PID" >/dev/null 2>&1; then
    kill "$DOCKERD_PID" || true
    wait "$DOCKERD_PID" || true
  fi
}
trap cleanup EXIT

# Wait for docker socket
tries=0
until docker version >/dev/null 2>&1; do
  tries=$((tries+1))
  if [ "$tries" -gt 60 ]; then
    echo "Timed out waiting for dockerd" >&2
    exit 1
  fi
  sleep 1
done

# Ensure nvm + Node 24 + CLIs exist in persisted /home volume
gosu node bash -lc '
  set -e
  export NVM_DIR="$HOME/.nvm"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
  fi
  nvm install 24 >/dev/null 2>&1 || true
  nvm alias default 24 >/dev/null 2>&1 || true
  # Ensure shell init
  # Remove obsolete sourcing of $HOME/.local/bin/env if present
  if [ -f "$HOME/.bashrc" ]; then
    sed -i '/\.local\/bin\/env/d' "$HOME/.bashrc" || true
  fi
  grep -q "NVM_DIR=.*\.nvm" "$HOME/.bashrc" 2>/dev/null || {
    echo "export NVM_DIR=\"$HOME/.nvm\"" >> "$HOME/.bashrc"
    echo "[ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"" >> "$HOME/.bashrc"
    echo "nvm use --silent default >/dev/null 2>&1 || true" >> "$HOME/.bashrc"
    echo "[ -s \"$NVM_DIR/bash_completion\" ] && . \"$NVM_DIR/bash_completion\"" >> "$HOME/.bashrc"
  }
  grep -q \.bashrc "$HOME/.profile" 2>/dev/null || echo "if [ -f \"$HOME/.bashrc\" ]; then . \"$HOME/.bashrc\"; fi" >> "$HOME/.profile"
  # Ensure provider CLIs present
  if ! command -v codex >/dev/null 2>&1 || ! command -v claude >/dev/null 2>&1 || ! command -v coder >/dev/null 2>&1; then
    npm install -g @anthropic-ai/claude-code @openai/codex @just-every/code >/dev/null 2>&1 || true
  fi
'

# Run the requested command as 'node' with nvm loaded
export NVM_DIR=/home/node/.nvm
CMD=("$@")

# Default to login shell if no command supplied
if [ ${#CMD[@]} -eq 0 ]; then
  CMD=("/bin/bash" "-l")
fi

# If user asked for bash, make it a login bash so rc files load
if [ "${CMD[0]##*/}" = "bash" ]; then
  has_login=false
  for arg in "${CMD[@]:1}"; do
    if [ "$arg" = "-l" ] || [ "$arg" = "--login" ]; then has_login=true; fi
  done
  if [ "$has_login" = false ]; then
    CMD=("${CMD[0]}" "-l" "${CMD[@]:1}")
  fi
fi

# Execute the exact requested command after preparing nvm
exec gosu node bash -lc 'export NVM_DIR=/home/node/.nvm; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; nvm use --silent default >/dev/null 2>&1 || true; exec "$@"' bash "${CMD[@]}"
EOF
RUN chmod +x /usr/local/bin/dind-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/dind-entrypoint.sh"]
CMD ["bash"]
