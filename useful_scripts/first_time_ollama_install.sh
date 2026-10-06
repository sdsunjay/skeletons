#!/usr/bin/env bash
set -euo pipefail

SWAP_SIZE_GB="${SWAP_SIZE_GB:-16}"
SWAPFILE="/swapfile"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Updating Ubuntu"
apt-get update
apt-get full-upgrade -y

echo "==> Installing required packages"
apt-get install -y \
    curl \
    git \
    tmux \
    htop \
    nvme-cli \
    smartmontools \
    lm-sensors \
    zstd \
    openssh-server \
    unattended-upgrades \
    ufw

echo "==> Ubuntu Pro"
if command -v pro >/dev/null 2>&1; then
    pro status
else
    echo "Ubuntu Pro client is not installed."
    echo "Install it with:"
    echo "  apt-get install -y ubuntu-advantage-tools"
fi

echo
read -r -p "Attach this machine to Ubuntu Pro now? [y/N] " ATTACH_PRO

if [[ "${ATTACH_PRO,,}" == "y" ]]; then
    if ! command -v pro >/dev/null 2>&1; then
        apt-get install -y ubuntu-advantage-tools
    fi

    echo
    echo "Enter your Ubuntu Pro token when prompted."
    echo "The token will not be stored in this script."
    echo

    pro attach

    echo
    echo "Ubuntu Pro status:"
    pro status
fi

echo
echo "==> Configuring swap"
if ! swapon --show=NAME --noheadings | grep -qx "${SWAPFILE}"; then
    if [[ ! -f "${SWAPFILE}" ]]; then
        fallocate -l "${SWAP_SIZE_GB}G" "${SWAPFILE}"
        chmod 600 "${SWAPFILE}"
        mkswap "${SWAPFILE}"
    fi

    swapon "${SWAPFILE}"
fi

if ! grep -qE '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab; then
    echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
fi

echo "==> Configuring conservative swap behavior"
cat >/etc/sysctl.d/99-ollama.conf <<'EOF'
vm.swappiness=10
EOF

sysctl --system >/dev/null

echo "==> Enabling SSH"
systemctl enable --now ssh

echo "==> Configuring firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw --force enable

echo "==> Configuring automatic updates"
systemctl enable --now unattended-upgrades

echo "==> Installing Ollama"
if ! command -v ollama >/dev/null 2>&1; then
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollama already installed; skipping installer"
fi

echo "==> Enabling Ollama"
systemctl enable --now ollama

echo
echo "========================================"
echo " Installation complete"
echo "========================================"

echo
echo "Ubuntu Pro:"
if command -v pro >/dev/null 2>&1; then
    pro status
fi

echo
echo "Ollama:"
ollama --version || true
systemctl --no-pager --full status ollama || true

echo
echo "Memory/swap:"
free -h
swapon --show

echo
echo "Listening sockets:"
ss -lntp | grep -E ':(22|11434)\b' || true

echo
echo "Firewall:"
ufw status verbose
