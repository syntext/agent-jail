# Agent Jail

- **Purpose:** Containerized sandbox that launches an AI coding agent inside a locked-down, reproducible environment mapped to your current project directory.
- **Command:** `./agent-jail`
- **Providers:** `codex` (default), `claude`, `coder` (Just Every Code fork)

**Why Use This**

- **Isolation:** Runs your provider CLI in a container with only your workspace mounted.
- **Consistency:** Ships a Dockerfile with preinstalled CLIs and tooling.
- **Convenience:** One command switches between providers with flags.

**Prerequisites**

- **Docker + docker-compose:** Required to build and run the container.
- **fish shell:** The launcher script is a fish script (`#!/usr/bin/env fish`). Install fish or run via `fish ./agent-jail ...`.
- **API keys (as needed):**
  - `OPENAI_API_KEY` for `codex`
  - `ANTHROPIC_API_KEY` for `claude`

**Install**

- Make the launcher executable: `chmod +x ./agent-jail`
- Optional: add an alias on your PATH for convenience.

**Quick Start**

- Default (Codex): `./agent-jail`
- Shell inside container: `./agent-jail --shell`
- Explicit providers:
  - Codex: `./agent-jail --codex [args...]`
  - Claude: `./agent-jail --claude [args...]`
  - Just Every (Codex CLI fork): `./agent-jail --just-every [args...]`

Any non-flag arguments are forwarded to the chosen provider CLI.

**Provider Mapping**

- `--codex` → runs `codex`
- `--claude` → runs `claude`
- `--just-every` → runs `coder`

CLIs are installed globally in the image:
- `@openai/codex` → provides `codex`
- `@anthropic-ai/claude-code` → provides `claude`
- `@just-every/code` → provides `coder`

**What the Launcher Does**

- Builds an ephemeral docker-compose override and runs service `agent`.
- Mounts your current directory to `/workspace` (read-write).
- Creates/persists a Docker volume `agent-jail-home` for `/home/node`.
- Optionally offers to sync your host `$HOME` into `agent-jail-home` the first time (one-time copy).
- Passes through environment variables:
  - `OPENAI_API_KEY`
  - `ANTHROPIC_API_KEY`
- Mounts your host `$HOME/.codex` into `/home/node/.codex` for Codex CLI config (optional; safe if absent).

**Examples**

- Open a shell to poke around: `./agent-jail --shell`
- Run Claude with a workspace flag: `./agent-jail --claude --project .`
- Pass additional args to Codex: `./agent-jail --codex --trace --verbose`

**Configuration Notes**

- The base compose file `docker-compose.yml` is present for devcontainer setup; the launcher adds an override that defines the `agent` service and image `agent-jail`.
- If you do not need the `$HOME/.codex` mount, remove or edit it in `agent-jail`.
- If you need other credentials/configs, export them before running the launcher and add them under the `environment:` section in `agent-jail` if required inside the container.

**Cleaning Up**

- Remove the persistent home volume: `docker volume rm agent-jail-home`
- Remove the built image: `docker rmi agent-jail`

**Full Clean Slate**

- Reset everything (volume + image), then rebuild on next run:
  - `docker volume rm agent-jail-home && docker rmi agent-jail`
- Optional: also clear build cache and dangling resources:
  - `docker builder prune -f && docker image prune -f && docker container prune -f && docker network prune -f`
- After this, run `./agent-jail --shell` (or a provider flag) to rebuild fresh.

**Troubleshooting**

- Provider command not found:
  - Ensure the Docker build succeeded; the image installs `codex`, `claude`, and `coder` globally.
  - Rebuild by running the launcher again (it triggers a build if needed).
- Auth or 401 errors:
  - Verify `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` are set in your host environment before running.
- Permission errors on mounts:
  - Make sure Docker Desktop (or daemon) has access to your project directory.
- fish not found:
  - Install fish (`brew install fish`, `apt-get install fish`, etc.), or run `fish ./agent-jail`.

**Project Structure**

- `agent-jail`: fish launcher script (entrypoint)
- `Dockerfile`: image with provider CLIs and dev tooling
- `docker-compose.yml`: base compose (devcontainer service); launcher adds an override for `agent`
