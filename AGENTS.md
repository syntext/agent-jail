# Repository Guidelines

## Project Structure & Module Organization
- `agent-jail`: fish launcher that builds/runs the container and selects the provider (`codex`, `claude`, `coder`).
- `Dockerfile`: image with provider CLIs and dev tools.
- `docker-compose.yml`: base compose; the launcher generates a temporary override at runtime.
- `init-firewall.sh`: optional lockdown script (currently commented-out in Dockerfile).
- `README.md`: usage, prerequisites, and troubleshooting.

## Build, Test, and Development Commands
- Build + run default (Codex): `./agent-jail`
- Open a shell in the jail: `./agent-jail --shell`
- Select provider: `./agent-jail --codex|--claude|--just-every [args...]`
- Clean up artifacts: `docker volume rm agent-jail-home && docker rmi agent-jail`
- Smoke check CLIs inside the container: `codex --help`, `claude --help`, `coder --help`

## Coding Style & Naming Conventions
- Scripts: use strict mode where applicable (`set -euo pipefail` for bash) and clear, kebab-case filenames.
- Shell style: prefer POSIX-compatible bash for scripts under `#!/bin/bash`; fish is acceptable for the launcher only.
- Indentation: 2 spaces for shell and YAML; wrap lines at ~100 chars.
- Formatting/linting: run `shfmt -w` and `shellcheck` for bash scripts (if available).

## Testing Guidelines
- No formal test suite. Add smoke tests when changing the launcher or Dockerfile:
  - Build and open shell: `./agent-jail --shell`
  - Verify mounts: `mount | grep /workspace`
  - Verify providers: `codex --version`, `claude --version`, `coder --version`
- PRs touching networking should note firewall behavior; do not enable `init-firewall.sh` by default.

## Commit & Pull Request Guidelines
- Commit style: follow Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `wip:`).
- PRs must include: purpose, summary of changes, test plan (commands run), and any screenshots/logs.
- Link related issues and call out breaking changes or new env vars.

## Security & Configuration Tips
- Secrets: export `OPENAI_API_KEY` and/or `ANTHROPIC_API_KEY` in your host shell; never commit credentials.
- Volumes: `agent-jail-home` persists `/home/jail`; remove it if you need a clean state.
- Network lockdown: use `init-firewall.sh` only when required; validate access to allowed endpoints after changes.
