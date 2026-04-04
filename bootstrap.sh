#!/usr/bin/env bash
# ============================================================================
# vps-bootstrap — Identity-free VPS foundation for Ubuntu 24.04
# https://github.com/meaning-systems/vps-bootstrap
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/meaning-systems/vps-bootstrap/main/bootstrap.sh | sudo bash
#   curl -sSL https://raw.githubusercontent.com/meaning-systems/vps-bootstrap/main/bootstrap.sh | sudo bash -s -- \
#     --user neno --ssh-key "ssh-ed25519 AAAA..." --hostname mybox --timezone Europe/Rome
#
# This script is PUBLIC and contains NO secrets. It:
#   1. Hardens the system (SSH, UFW, fail2ban)
#   2. Creates a non-root sudo user
#   3. Installs runtimes (Node.js, Python, uv)
#   4. Installs AI coding agents (Claude Code, Codex, Gemini CLI, OpenCode, Hermes)
#   5. Prints next-steps for private identity/user provisioning
#
# Idempotent — safe to run multiple times.
# ============================================================================
set -euo pipefail

# -- Defaults --
USERNAME="dev"
SSH_PUBLIC_KEY=""
HOSTNAME_SET=""
TIMEZONE="UTC"
SKIP_AGENTS=false
SKIP_HARDENING=false
SSH_PORT=22
NVM_VERSION="v0.40.3"
NODE_LTS=true

# -- Colors --
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

step_num=0
step() {
    step_num=$((step_num + 1))
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}[$step_num]${NC} ${GREEN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

info()  { echo -e "  ${BLUE}ℹ${NC}  $1"; }
ok()    { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail()  { echo -e "  ${RED}✗${NC}  $1"; exit 1; }
skip()  { echo -e "  ${YELLOW}⊘${NC}  $1 (skipped)"; }

# ============================================================================
# Parse arguments
# ============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)         USERNAME="$2";       shift 2 ;;
        --ssh-key)      SSH_PUBLIC_KEY="$2"; shift 2 ;;
        --hostname)     HOSTNAME_SET="$2";   shift 2 ;;
        --timezone)     TIMEZONE="$2";       shift 2 ;;
        --ssh-port)     SSH_PORT="$2";       shift 2 ;;
        --skip-agents)  SKIP_AGENTS=true;    shift   ;;
        --skip-hardening) SKIP_HARDENING=true; shift  ;;
        --help|-h)
            echo "Usage: bootstrap.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --user NAME        Username to create (default: dev)"
            echo "  --ssh-key KEY      SSH public key for the user"
            echo "  --hostname NAME    Set system hostname"
            echo "  --timezone TZ      Set timezone (default: UTC)"
            echo "  --ssh-port PORT    SSH port (default: 22)"
            echo "  --skip-agents      Skip AI agent installation"
            echo "  --skip-hardening   Skip SSH/UFW/fail2ban hardening"
            echo "  --help             Show this help"
            exit 0
            ;;
        *) warn "Unknown option: $1"; shift ;;
    esac
done

# ============================================================================
# Preflight checks
# ============================================================================
echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}       ${BLUE}vps-bootstrap${NC} — VPS Foundation Setup              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}       Identity-free • Idempotent • Ubuntu 24.04         ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"

[[ $EUID -ne 0 ]] && fail "This script must be run as root (use sudo)"

if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    warn "This script is designed for Ubuntu. Proceeding anyway..."
fi

info "User: ${USERNAME}"
info "Timezone: ${TIMEZONE}"
info "SSH port: ${SSH_PORT}"
[[ -n "$HOSTNAME_SET" ]] && info "Hostname: ${HOSTNAME_SET}"
[[ -n "$SSH_PUBLIC_KEY" ]] && info "SSH key: provided" || warn "No SSH key provided — password auth will remain enabled"

# ============================================================================
# 1. System identity & time
# ============================================================================
step "System identity & time"

export DEBIAN_FRONTEND=noninteractive

if [[ -n "$HOSTNAME_SET" ]]; then
    hostnamectl set-hostname "$HOSTNAME_SET"
    ok "Hostname set to ${HOSTNAME_SET}"
else
    ok "Hostname: $(hostname)"
fi

timedatectl set-timezone "$TIMEZONE"
ok "Timezone set to ${TIMEZONE}"

# Ensure locale
if ! locale -a 2>/dev/null | grep -q "en_US.utf8"; then
    locale-gen en_US.UTF-8 >/dev/null 2>&1
    update-locale LANG=en_US.UTF-8 >/dev/null 2>&1
fi
ok "Locale: en_US.UTF-8"

# ============================================================================
# 2. System update
# ============================================================================
step "System update"

apt-get update -qq
apt-get dist-upgrade -y -qq
apt-get autoremove -y -qq
ok "System updated"

# ============================================================================
# 3. Essential packages
# ============================================================================
step "Essential packages"

PACKAGES=(
    # Core tools
    curl wget git jq unzip zip tar
    # Build essentials (needed for some agent deps)
    build-essential gcc g++ make
    # System tools
    htop tmux vim-tiny
    # Network tools
    net-tools dnsutils iproute2 ca-certificates gnupg
    # Security
    fail2ban ufw
    # Auto updates
    unattended-upgrades apt-listchanges
    # Python ecosystem
    python3 python3-pip python3-venv python3-dev
    # Shell
    zsh
    # Search tools
    ripgrep fd-find
    # Misc
    software-properties-common apt-transport-https
    rsyslog logrotate
)

apt-get install -y -qq "${PACKAGES[@]}"
ok "Essential packages installed"

# Symlink fd-find to fd (Ubuntu names it differently)
if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    ln -sf "$(which fdfind)" /usr/local/bin/fd
    ok "Symlinked fdfind → fd"
fi

# ============================================================================
# 4. Create user
# ============================================================================
step "Create user: ${USERNAME}"

if id "$USERNAME" &>/dev/null; then
    ok "User ${USERNAME} already exists"
else
    useradd -m -s /bin/bash -G sudo "$USERNAME"
    # Set a random password (user should use SSH keys)
    RANDOM_PASS=$(openssl rand -base64 24)
    echo "${USERNAME}:${RANDOM_PASS}" | chpasswd
    ok "User ${USERNAME} created"
    info "Temporary password set (use SSH keys instead)"
fi

# Ensure sudo group and passwordless sudo
if ! grep -q "^${USERNAME}" /etc/sudoers.d/* 2>/dev/null; then
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"
    chmod 440 "/etc/sudoers.d/${USERNAME}"
    ok "Passwordless sudo configured"
fi

USER_HOME=$(eval echo "~${USERNAME}")

# SSH key setup
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    SSH_DIR="${USER_HOME}/.ssh"
    mkdir -p "$SSH_DIR"
    if ! grep -qF "$SSH_PUBLIC_KEY" "${SSH_DIR}/authorized_keys" 2>/dev/null; then
        echo "$SSH_PUBLIC_KEY" >> "${SSH_DIR}/authorized_keys"
    fi
    chmod 700 "$SSH_DIR"
    chmod 600 "${SSH_DIR}/authorized_keys"
    chown -R "${USERNAME}:${USERNAME}" "$SSH_DIR"
    ok "SSH public key installed"
fi

# ============================================================================
# 5. SSH hardening
# ============================================================================
if [[ "$SKIP_HARDENING" == true ]]; then
    step "SSH hardening"
    skip "Hardening skipped (--skip-hardening)"
else
    step "SSH hardening"

    SSHD_CONFIG="/etc/ssh/sshd_config"

    # Backup original
    if [[ ! -f "${SSHD_CONFIG}.bootstrap-backup" ]]; then
        cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bootstrap-backup"
        ok "Original sshd_config backed up"
    fi

    # Write hardened config
    cat > /etc/ssh/sshd_config.d/99-bootstrap.conf <<SSHEOF
# vps-bootstrap hardening — $(date -Iseconds)
Port ${SSH_PORT}
PermitRootLogin no
MaxAuthTries 3
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication $([ -n "$SSH_PUBLIC_KEY" ] && echo "no" || echo "yes")
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ${USERNAME}
SSHEOF

    # Validate config before restarting
    if sshd -t 2>/dev/null; then
        systemctl restart sshd
        ok "SSH hardened (port ${SSH_PORT}, root login disabled)"
        if [[ -n "$SSH_PUBLIC_KEY" ]]; then
            ok "Password auth disabled (SSH key provided)"
        else
            warn "Password auth still enabled (no SSH key provided)"
        fi
    else
        rm -f /etc/ssh/sshd_config.d/99-bootstrap.conf
        fail "SSH config validation failed — reverted changes"
    fi

    # ========================================================================
    # 6. Firewall (UFW)
    # ========================================================================
    step "Firewall (UFW)"

    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null
    ufw allow "$SSH_PORT"/tcp comment "SSH" >/dev/null
    ufw allow 80/tcp comment "HTTP" >/dev/null
    ufw allow 443/tcp comment "HTTPS" >/dev/null
    ufw limit "$SSH_PORT"/tcp comment "SSH rate limit" >/dev/null
    ufw logging on >/dev/null
    ufw --force enable >/dev/null
    ok "UFW enabled (SSH:${SSH_PORT}, HTTP, HTTPS)"

    # ========================================================================
    # 7. Fail2ban
    # ========================================================================
    step "Fail2ban"

    cat > /etc/fail2ban/jail.local <<F2BEOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd

[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
maxretry = 3
bantime  = 7200

[recidive]
enabled  = true
bantime  = 604800
findtime = 86400
maxretry = 3
F2BEOF

    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban
    ok "Fail2ban configured (SSH jail + recidive)"
fi

# ============================================================================
# 8. Swap
# ============================================================================
step "Swap"

if swapon --show | grep -q "/swapfile"; then
    ok "Swap already active"
else
    # Size swap based on RAM
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_RAM_MB -le 2048 ]]; then
        SWAP_SIZE="2G"
    elif [[ $TOTAL_RAM_MB -le 8192 ]]; then
        SWAP_SIZE="4G"
    else
        SWAP_SIZE="2G"
    fi

    if [[ ! -f /swapfile ]]; then
        fallocate -l "$SWAP_SIZE" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null
    fi
    swapon /swapfile 2>/dev/null || true

    # Add to fstab if not there
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi

    # Tune swappiness for server
    sysctl -w vm.swappiness=10 >/dev/null 2>&1
    if ! grep -q "vm.swappiness" /etc/sysctl.d/99-bootstrap.conf 2>/dev/null; then
        echo "vm.swappiness=10" >> /etc/sysctl.d/99-bootstrap.conf
    fi

    ok "Swap configured (${SWAP_SIZE}, swappiness=10)"
fi

# ============================================================================
# 9. Unattended upgrades
# ============================================================================
step "Unattended security upgrades"

cat > /etc/apt/apt.conf.d/20auto-upgrades <<UUEOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
UUEOF

ok "Automatic security updates enabled"

# ============================================================================
# 10. Kernel/sysctl hardening
# ============================================================================
step "Kernel hardening"

cat > /etc/sysctl.d/99-bootstrap.conf <<SYSEOF
# Network hardening
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0

# Kernel hardening
kernel.randomize_va_space = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1

# Swap
vm.swappiness = 10
SYSEOF

sysctl --system >/dev/null 2>&1
ok "Sysctl hardened"

# ============================================================================
# 11. Runtimes & AI agents (as user)
# ============================================================================
if [[ "$SKIP_AGENTS" == true ]]; then
    step "AI coding agents"
    skip "Agent installation skipped (--skip-agents)"
else
    step "Runtimes: Node.js, Python, uv"

    # Install nvm + Node.js LTS for the user
    su - "$USERNAME" -c "
        # nvm
        if [[ ! -d \"\$HOME/.nvm\" ]]; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash
        fi
        export NVM_DIR=\"\$HOME/.nvm\"
        [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"

        # Node.js LTS
        if ! command -v node &>/dev/null; then
            nvm install --lts
            nvm use --lts
            nvm alias default lts/*
        fi
        echo \"Node: \$(node --version 2>/dev/null || echo 'not installed')\"
        echo \"npm: \$(npm --version 2>/dev/null || echo 'not installed')\"

        # uv (Python package manager)
        if ! command -v uv &>/dev/null; then
            curl -LsSf https://astral.sh/uv/install.sh | sh
        fi
    " 2>&1 | while IFS= read -r line; do
        # Only print key lines, not the nvm installer noise
        case "$line" in
            *"Node:"*|*"npm:"*|*"installed"*|*"Now using"*) info "$line" ;;
        esac
    done
    ok "Runtimes installed"

    step "AI coding agents"

    # Each agent is installed independently — failures don't stop others
    install_agent() {
        local name="$1"
        local cmd="$2"
        info "Installing ${name}..."
        if su - "$USERNAME" -c "
            export NVM_DIR=\"\$HOME/.nvm\"
            [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
            export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"
            ${cmd}
        " >/dev/null 2>&1; then
            ok "${name} installed"
        else
            warn "${name} failed to install (non-fatal, install manually later)"
        fi
    }

    install_agent "Claude Code"  "curl -fsSL https://claude.ai/install.sh | bash"
    install_agent "Codex"        "npm i -g @openai/codex"
    install_agent "Gemini CLI"   "npm i -g @google/gemini-cli"
    install_agent "OpenCode"     "curl -fsSL https://opencode.ai/install | bash"
    install_agent "Hermes"       "curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
fi

# ============================================================================
# 12. Oh-My-Zsh (optional, as user)
# ============================================================================
step "Shell: zsh + oh-my-zsh"

su - "$USERNAME" -c "
    if [[ ! -d \"\$HOME/.oh-my-zsh\" ]]; then
        RUNZSH=no CHSH=no sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\"
    fi
" >/dev/null 2>&1

# Change default shell to zsh
chsh -s "$(which zsh)" "$USERNAME" 2>/dev/null || true
ok "zsh + oh-my-zsh configured"

# ============================================================================
# 13. MOTD
# ============================================================================
step "MOTD"

cat > /etc/motd <<'MOTDEOF'

  ╔══════════════════════════════════════════╗
  ║  VPS bootstrapped by vps-bootstrap       ║
  ║  github.com/meaning-systems/vps-bootstrap║
  ╚══════════════════════════════════════════╝

MOTDEOF
ok "Custom MOTD set"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                  ${BLUE}Bootstrap Complete${NC}                      ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✓${NC} System hardened (SSH, UFW, fail2ban)"
echo -e "  ${GREEN}✓${NC} User ${BLUE}${USERNAME}${NC} created with sudo"
echo -e "  ${GREEN}✓${NC} Node.js + Python + uv installed"
echo -e "  ${GREEN}✓${NC} AI agents: Claude Code, Codex, Gemini CLI, OpenCode, Hermes"
echo -e "  ${GREEN}✓${NC} Zsh + oh-my-zsh configured"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "  ${CYAN}1.${NC} SSH in as the new user:"
echo -e "     ${BLUE}ssh ${USERNAME}@$(curl -s ifconfig.me 2>/dev/null || echo '<IP>') -p ${SSH_PORT}${NC}"
echo ""
echo -e "  ${CYAN}2.${NC} Apply your identity (API keys, configs):"
echo -e "     Clone your private identity repo and run apply.sh"
echo ""
echo -e "  ${CYAN}3.${NC} Provision additional users:"
echo -e "     Clone your private users repo and run provision.sh"
echo ""
echo -e "  ${YELLOW}⚠  Root login is now DISABLED. Make sure you can SSH as ${USERNAME}.${NC}"
echo ""
