# vps-bootstrap

Identity-free VPS foundation for Ubuntu 24.04. Hardens the system, installs runtimes, and sets up AI coding agents — without tying to any specific person or credentials.

## Quick Start

```bash
# Minimal (creates user "dev", no SSH key)
curl -sSL https://raw.githubusercontent.com/meaning-systems/vps-bootstrap/main/bootstrap.sh | sudo bash

# Full (recommended)
curl -sSL https://raw.githubusercontent.com/meaning-systems/vps-bootstrap/main/bootstrap.sh | sudo bash -s -- \
  --user neno \
  --ssh-key "ssh-ed25519 AAAA..." \
  --hostname mybox \
  --timezone Europe/Rome
```

## What It Does

| Step | What | Details |
|------|------|---------|
| 1 | System identity | Hostname, timezone, locale |
| 2 | System update | `apt dist-upgrade`, autoremove |
| 3 | Base packages | curl, git, jq, ripgrep, fd, tmux, build-essential, etc. |
| 4 | User creation | Non-root sudo user with SSH key |
| 5 | SSH hardening | Root login disabled, key-only auth, rate limiting |
| 6 | Firewall | UFW with SSH, HTTP, HTTPS |
| 7 | Fail2ban | SSH jail + recidive (repeat offender) jail |
| 8 | Swap | Auto-sized, swappiness=10 |
| 9 | Auto-updates | Unattended security upgrades |
| 10 | Kernel hardening | Sysctl anti-spoofing, ASLR, SYN flood protection |
| 11 | Runtimes | Node.js (via nvm), Python 3, uv |
| 12 | AI agents | Claude Code, Codex, Gemini CLI, OpenCode, Hermes |
| 13 | Shell | zsh + oh-my-zsh |

## Options

```
--user NAME        Username to create (default: dev)
--ssh-key KEY      SSH public key string for the user
--hostname NAME    Set system hostname
--timezone TZ      Timezone (default: UTC)
--ssh-port PORT    SSH port (default: 22)
--skip-agents      Skip AI agent installation
--skip-hardening   Skip SSH/UFW/fail2ban hardening
```

## Architecture: 3-Repo Split

This is the **public foundation** — one of three repos designed to work together:

```
┌──────────────────────────────────────────────────────────────┐
│  1. vps-bootstrap (PUBLIC)                                    │
│     Foundation: hardening, packages, runtimes, agents         │
│     curl -sSL .../bootstrap.sh | sudo bash                    │
└────────────────────────┬─────────────────────────────────────┘
                         │ then SSH in as user
                         ▼
┌──────────────────────────────────────────────────────────────┐
│  2. vps-identity (PRIVATE)                                    │
│     Your API keys, tool configs, shell preferences            │
│     git clone ... ~/.identity && ~/.identity/apply.sh         │
└──────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│  3. vps-users (PRIVATE)                                       │
│     SSH keys + GitHub auth for team members                   │
│     sudo ./provision.sh add neno                              │
│     sudo ./provision.sh add simone                            │
└──────────────────────────────────────────────────────────────┘
```

The public script installs everything. The private repos configure it for your team.

## AI Agents Installed

| Agent | Install Method | Auth needed after |
|-------|---------------|-------------------|
| [Claude Code](https://github.com/anthropics/claude-code) | Native binary | `claude login` or `ANTHROPIC_API_KEY` |
| [Codex](https://github.com/openai/codex) | npm global | `OPENAI_API_KEY` |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | npm global | `gemini auth` |
| [OpenCode](https://github.com/anomalyco/opencode) | Native binary | Provider API key |
| [Hermes](https://github.com/NousResearch/hermes-agent) | Python + uv | `hermes setup` |

None of the agents are logged in after bootstrap. Use `vps-identity` to apply API keys.

## Idempotent

Safe to run multiple times. Existing users, swap, and configs are detected and skipped.

## License

MIT
