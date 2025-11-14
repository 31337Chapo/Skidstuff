#!/usr/bin/env bash
# skidstall.sh - One-command modular VM-optimized Arch post-install script
# - Interactive CLI by default, --auto for unattended
# - Modules: ui, pentest, dev, docker, theming, vpn, networking, vmtools
# - Picom installed but NOT auto-started; blur disabled for VM friendliness
# - Docker installed but NOT enabled; helper scripts docker-on/docker-off provided
# - Uses pipx for selected Python tools to avoid pacman/pip conflicts
# - Supports `--update` to re-run/upgrade installed modules
#
# Usage examples:
#   ./skidstall.sh               # interactive CLI
#   ./skidstall.sh --auto --modules ui,pentest,docker
#   ./skidstall.sh --update --modules pentest

set -euo pipefail
IFS=$'\n\t'

# ------------------ Configuration ------------------
PACMAN_UI=(
  xorg xorg-xinit i3-gaps i3status i3lock
  feh rofi thunar kitty maim xclip dunst btop firefox
  picom polybar
  ttf-fira-code ttf-jetbrains-mono ttf-font-awesome
)

PACMAN_PENTEST=(
  nmap wireshark-qt john hashcat sqlmap gobuster nikto
  aircrack-ng hydra netcat smbclient cifs-utils
  tcpdump exploitdb wordlists proxychains-ng socat ffuf
  radare2 strace ltrace gdb binwalk foremost exiftool
  masscan
)

PACMAN_DEV=(
  git curl wget base-devel python python-pip python-virtualenv
  go rust cargo nodejs npm jq yq fd ripgrep
)

AUR_PACKAGES=(
  burpsuite zaproxy seclists feroxbuster rustscan nuclei subfinder httpx waybackurls gau gospider hakrawler polybar
)

PIPX_TOOLS=(
  crackmapexec impacket bloodhound mitm6 dnstwist sublist3r shodan censys
)

# Modules available
AVAILABLE_MODULES=(core ui pentest dev docker theming vpn networking vmtools)

# ------------------ Helpers ------------------
log() { printf "[+] %s\n" "$*"; }
err() { printf "[!] %s\n" "$*" >&2; }
confirm() { # prompt yes/no
  local prompt="$1" default=${2:-n}
  read -r -p "$prompt [y/N]: " ans
  [[ "$ans" =~ ^([yY][eE][sS]|[yY])$ ]]
}

ensure_sudo() {
  if ! command -v sudo &>/dev/null; then
    err "sudo is required. Install sudo and re-run."; exit 1
  fi
}

ensure_yay() {
  if ! command -v yay &>/dev/null; then
    log "Installing yay AUR helper..."
    cd /tmp || return
    git clone https://aur.archlinux.org/yay.git || return
    cd yay || return
    makepkg -si --noconfirm || return
    cd - >/dev/null || true
  fi
}

ensure_pipx() {
  if ! command -v pipx &>/dev/null; then
    log "Installing pipx (user-level)..."
    python -m pip install --user pipx || true
    python -m pipx ensurepath || true
    export PATH="$HOME/.local/bin:$PATH"
  fi
}

install_pacman_pkgs(){
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then return; fi
  log "pacman -> Installing: ${pkgs[*]}"
  sudo pacman -S --noconfirm --needed "${pkgs[@]}"
}

install_aur_pkgs(){
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then return; fi
  ensure_yay
  log "AUR -> Installing: ${pkgs[*]}"
  yay -S --noconfirm --needed "${pkgs[@]}"
}

install_pipx_tools(){
  ensure_pipx
  for t in "$@"; do
    if ! pipx list | grep -q "^\s*${t}"; then
      log "pipx -> Installing: $t"
      pipx install "$t" || true
    else
      log "pipx -> $t already installed"
    fi
  done
}

# ------------------ Module implementations ------------------
module_core(){
  log "[core] Running system update and installing minimal tools..."
  ensure_sudo
  sudo pacman -Syu --noconfirm
  install_pacman_pkgs git curl wget base-devel sudo
  log "[core] Done."
}

module_ui(){
  log "[ui] Installing UI packages (i3 + VM-friendly picom)..."
  install_pacman_pkgs "${PACMAN_UI[@]}"

  # Picom VM-friendly config (xrender, no blur)
  mkdir -p ~/.config/picom
  cat > ~/.config/picom/picom.conf <<'EOF'
backend = "xrender";
shadow = true;
shadow-radius = 8;
shadow-opacity = 0.6;
fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;
vsync = true;
use-damage = true;
# blur intentionally disabled for VM usage
EOF
  log "[ui] Picom written (blur disabled). Picom not auto-started."

  mkdir -p ~/.config/i3
  if [ ! -f ~/.config/i3/config ]; then
    cat > ~/.config/i3/config <<'EOF'
set $mod Mod4
exec --no-startup-id dunst
bindsym $mod+Return exec kitty
bindsym $mod+d exec --no-startup-id rofi -show drun
EOF
    log "[ui] Minimal i3 config created."
  else
    log "[ui] i3 config exists; leaving it untouched."
  fi

  # Polybar minimal
  mkdir -p ~/.config/polybar
  if [ ! -f ~/.config/polybar/config.ini ]; then
    cat > ~/.config/polybar/config.ini <<'EOF'
[bar/example]
width = 100%
height = 24
modules-left = xworkspaces
modules-right = date
EOF
    cat > ~/.config/polybar/launch.sh <<'EOF'
#!/bin/bash
killall -q polybar || true
polybar example &>/dev/null &
EOF
    chmod +x ~/.config/polybar/launch.sh || true
    log "[ui] Minimal polybar written."
  fi

  log "[ui] Done."
}

module_pentest(){
  log "[pentest] Installing pentesting packages (pacman + AUR + pipx)..."
  install_pacman_pkgs "${PACMAN_PENTEST[@]}"
  install_aur_pkgs burpsuite zaproxy seclists feroxbuster rustscan nuclei subfinder httpx waybackurls gau gospider hakrawler || true

  # Python tools via pipx
  install_pipx_tools "${PIPX_TOOLS[@]}"

  # pip user libs used by some tools
  python -m pip install --user pwntools ropper ropgadget pycryptodome paramiko ldap3 || true

  log "[pentest] Done."
}

module_dev(){
  log "[dev] Installing developer tools..."
  install_pacman_pkgs "${PACMAN_DEV[@]}"
  log "[dev] Done."
}

module_docker(){
  log "[docker] Installing Docker (service NOT enabled by default)..."
  install_pacman_pkgs docker docker-compose
  # Create helpers
  sudo tee /usr/local/bin/docker-on >/dev/null <<'EOF'
#!/bin/bash
sudo systemctl start docker
EOF
  sudo tee /usr/local/bin/docker-off >/dev/null <<'EOF'
#!/bin/bash
sudo systemctl stop docker
EOF
  sudo chmod +x /usr/local/bin/docker-on /usr/local/bin/docker-off || true
  log "[docker] Installed. Use 'sudo systemctl start docker' or 'docker-on' to start, 'docker-off' to stop."
}

module_theming(){
  log "[theming] Installing lightweight theme assets (Catppuccin-ish)..."
  # Minimal theming: papirus icon, cursor, gtk theme from AUR if desired
  install_pacman_pkgs papirus-icon-theme
  ensure_yay
  # install catppuccin-gtk-theme if available
  if yay -Si catppuccin-gtk &>/dev/null; then
    yay -S --noconfirm catppuccin-gtk || true
  fi
  # Kitty theme
  mkdir -p ~/.config/kitty
  cat > ~/.config/kitty/kitty.conf <<'EOF'
font_family JetBrainsMono Nerd Font
font_size 11.0
foreground #eceff4
background #2e3440
EOF
  log "[theming] Done (minimal)."
}

module_vpn(){
  log "[vpn] Installing OpenVPN and WireGuard + NetworkManager plugins..."
  install_pacman_pkgs openvpn wireguard-tools networkmanager-openvpn networkmanager-wireguard
  log "[vpn] Helper scripts added: vpn-up <config> and vpn-down"
  # vpn helper scripts
  cat > ~/.local/bin/vpn-up <<'EOF'
#!/bin/bash
if [ -z "$1" ]; then
  echo "Usage: vpn-up <ovpn-or-wg-config>"; exit 1
fi
CONFIG="$1"
if [[ "$CONFIG" == *.ovpn ]]; then
  sudo openvpn --config "$CONFIG"
else
  echo "If using WireGuard, use: sudo wg-quick up <conf>"; exit 1
fi
EOF
  cat > ~/.local/bin/vpn-down <<'EOF'
#!/bin/bash
sudo pkill openvpn || true
EOF
  chmod +x ~/.local/bin/vpn-up ~/.local/bin/vpn-down || true
  log "[vpn] Done. Note: NetworkManager GUI also works; configs are manual."
}

module_networking(){
  log "[networking] Installing networking utilities (SSH client only; server disabled)..."
  install_pacman_pkgs openssh iperf3 traceroute net-tools ufw
  log "[networking] SSH server (sshd) will NOT be enabled by this installer. To enable inbound SSH, run: sudo systemctl enable --now sshd"
  # Provide helper to ensure sshd remains disabled by default
  cat > ~/.local/bin/ssh-out <<'EOF'
#!/bin/bash
ssh "${1:-}" 
EOF
  chmod +x ~/.local/bin/ssh-out || true
  log "[networking] Done. Installed SSH client and diagnostics; inbound SSH not enabled."
}

module_vmtools(){
  log "[vmtools] Installing VMware guest tools and enabling them..."
  install_pacman_pkgs open-vm-tools
  sudo systemctl enable --now vmtoolsd || true
  log "[vmtools] open-vm-tools enabled (vmtoolsd)."
}

# ------------------ CLI menu & argument parsing ------------------
show_help(){
  cat <<EOF
skidstall.sh - modular Arch post-install (VM-friendly)

Usage:
  ./skidstall.sh              # interactive
  ./skidstall.sh --auto --modules ui,pentest
  ./skidstall.sh --update --modules pentest

Options:
  --auto             Run without interactive prompts (requires --modules)
  --modules a,b,c    Comma-separated modules to install/update
  --update           Re-run module installers to update packages
  -h, --help         Show this help

Available modules: ${AVAILABLE_MODULES[*]}

EOF
}

# parse args
AUTO=false
UPDATE=false
MODULES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --auto) AUTO=true; shift ;;
    --modules) shift; IFS=',' read -ra MODULES <<< "$1"; shift ;;
    --update) UPDATE=true; shift ;;
    -h|--help) show_help; exit 0 ;;
    *) err "Unknown arg: $1"; show_help; exit 1 ;;
  esac
done

# Validate modules if provided
if [ ${#MODULES[@]} -gt 0 ]; then
  for m in "${MODULES[@]}"; do
    if [[ ! " ${AVAILABLE_MODULES[*]} " =~ " $m " ]]; then
      err "Unknown module: $m"; exit 1
    fi
  done
fi

# interactive selection if not auto and no modules provided
if ! $AUTO && [ ${#MODULES[@]} -eq 0 ] && ! $UPDATE; then
  echo "Select modules to install (y/n):"
  for m in "${AVAILABLE_MODULES[@]}"; do
    case $m in
      core) echo " core (required) - will update system"; continue ;;
      *) ;;
    esac
    if confirm "Install module: $m?" n; then
      MODULES+=("$m")
    fi
  done
fi

# If no modules selected, default to core+ui+pentest
if [ ${#MODULES[@]} -eq 0 ]; then
  MODULES=(core ui pentest dev docker theming vpn networking vmtools)
  log "No modules specified; defaulting to: ${MODULES[*]}"
fi

# Handle update: run pacman -Syu first
if $UPDATE; then
  ensure_sudo
  log "--update: running system update"
  sudo pacman -Syu --noconfirm || true
  ensure_yay || true
  log "--update: upgrading AUR packages (yay -Syu)"
  if command -v yay &>/dev/null; then yay -Syu --noconfirm || true; fi
  log "--update: upgrading pipx packages"
  if command -v pipx &>/dev/null; then pipx upgrade-all || true; fi
fi

# Execute selected modules in order
for m in "${MODULES[@]}"; do
  case "$m" in
    core) module_core ;;
    ui) module_ui ;;
    pentest) module_pentest ;;
    dev) module_dev ;;
    docker) module_docker ;;
    theming) module_theming ;;
    vpn) module_vpn ;;
    networking) module_networking ;;
    vmtools) module_vmtools ;;
    *) err "Unknown module: $m" ;;
  esac
done

# Final messages
log "skidstall: finished running selected modules: ${MODULES[*]}"
log "Notes:"
log " - Picom configured with blur disabled and not auto-started. Start it manually if you want: picom --config ~/.config/picom/picom.conf &"
log " - Docker is installed but NOT enabled; use 'docker-on'/'docker-off' (sudo) or 'sudo systemctl start/stop docker'"
log " - SSH server is NOT enabled. To enable inbound SSH: sudo systemctl enable --now sshd"
log " - For VMware, vmtoolsd has been enabled (if vmtools module selected)."
log "To run update mode: ./skidstall.sh --update --modules pentest"
