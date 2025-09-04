FROM node:24-bookworm
ARG TZ
ENV TZ="$TZ"
# Install basic development tools and iptables/ipset
RUN apt update && apt install -y less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  zip \
  curl \
  python3 \
  python3-pip \
  python3-venv \
  ca-certificates \
  lsb-release \
  tmux \
  ncurses-term \
  locales \
  vim

RUN locale-gen en_US.UTF-8

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share
ARG USERNAME=node
# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory
# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true
# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude
WORKDIR /workspace
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_0.18.2_${ARCH}.deb" && \
  rm "git-delta_0.18.2_${ARCH}.deb"
# Set empty password for node user
RUN passwd -d node
# Add node user to sudoers with NOPASSWD
RUN echo "node ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/node-sudo && \
  chmod 0440 /etc/sudoers.d/node-sudo
# Set up non-root user
USER node
# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin
# Set the default shell to zsh rather than sh
ENV SHELL=/bin/bash
ENV TERM=xterm-256color
# Install SDKMAN and Java 21 Temurin
#RUN curl -s "https://get.sdkman.io" | bash && \
#  bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && sdk install java 21.0.5-tem && sdk default java 21.0.5-tem"
# Add SDKMAN and Java to PATH
ENV SDKMAN_DIR=/home/node/.sdkman
ENV PATH=$SDKMAN_DIR/candidates/java/current/bin:$PATH
ENV JAVA_HOME=$SDKMAN_DIR/candidates/java/current
# Install UV for certain MCP's
#RUN curl -LsSf https://astral.sh/uv/install.sh | sh
# Default powerline10k theme
#RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v1.2.0/zsh-in-docker.sh)" -- \
#  -p git \
#  -p fzf \
#  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
#  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
#  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
#  -a "source \$HOME/.sdkman/bin/sdkman-init.sh" \
#  -x
# Install Claude
RUN npm install -g @anthropic-ai/claude-code
# Install Codex CLI
RUN npm install -g @openai/codex
# Install Just Every Code fork of Codex CLI
RUN npm install -g @just-every/code
RUN echo ". \$HOME/.local/bin/env" >> $HOME/.bashrc && . $HOME/.bashrc
# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
# Lockdown mode
#RUN chmod +x /usr/local/bin/init-firewall.sh && \
#  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
#  chmod 0440 /etc/sudoers.d/node-firewall
USER node
