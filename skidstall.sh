#!/usr/bin/env bash

# - Interactive CLI by default, --auto for unattended
# - Modules installed in correct dependency order automatically
# - HTB-inspired Neon Nord theme (green #9fef00 + Nord palette)
# - Package validation and integrity checks
# - UPDATED: Modern VMware graphics driver support (no xf86-video-vmware)
# - Dave0x21 i3-theme-template integration
#
# Usage examples:
#   ./skidstall.sh               # interactive CLI
#   ./skidstall.sh --auto --modules ui,pentest,lazyvim
#   ./skidstall.sh --update --modules pentest

set -euo pipefail
IFS=$'\n\t'

# Colors for output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Installation tracking
INSTALL_LOG="/tmp/skidstall-$.log"
FAILED_PACKAGES=()
SUCCESSFUL_PACKAGES=()
DEFERRED_PACKAGES=()

# Auto mode flag
AUTO=false

# ------------------ Banner ------------------
show_banner(){
  echo -e "${CYAN}"
  cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║   🎨 NEON NORD PENTEST - Skidstall Installer 🎨          ║
║   HackTheBox Green (#9fef00) + Nord Dark                 ║
║   Modular • VM-Optimized • Dependency-Resolved           ║
╚═══════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
}

# ------------------ Configuration ------------------
# Core dependencies - must be installed first
PACMAN_CORE=(
  base-devel git curl wget sudo
)

# Dev tools - needed before pentest (provides Python, pipx, etc)
PACMAN_DEV=(
  python python-pip python-setuptools python-wheel
  python-virtualenv python-pipx
  go rust nodejs npm 
  jq yq fd ripgrep
  neovim tmux screen
)

# UI packages - needs fonts and base X
PACMAN_UI=(
  mesa xorg-server xorg-xinit xorg-xrandr xorg-xsetroot xorg-xauth
  xf86-input-libinput
  i3-wm i3status i3lock
  feh rofi thunar kitty
  maim xclip dunst btop firefox
  picom
  gtk3 gtk4
  ttf-fira-code ttf-jetbrains-mono-nerd otf-font-awesome
  papirus-icon-theme
  python-pywal imagemagick
  xfce4-terminal lxappearance
  lsd ranger
)

# UI packages that may need AUR
AUR_UI=(
  polybar
)

# Optional UI (try AUR if not in repos)
OPTIONAL_UI=(
  nitrogen
  yazi
)

# Pentest tools - depends on python being installed
PACMAN_PENTEST=(
  nmap masscan wireshark-qt 
  john hashcat sqlmap gobuster nikto
  aircrack-ng hydra openbsd-netcat openvpn 
  smbclient cifs-utils
  bind tcpdump net-tools iproute2
  exploitdb proxychains-ng socat
  radare2 strace ltrace gdb 
  binwalk foremost exiftool
  metasploit
)

# Pentest packages that moved to AUR
AUR_PENTEST=(
  burpsuite feroxbuster rustscan 
  chisel-bin
  seclists ffuf
)

# Optional pentest tools (may fail)
AUR_PENTEST_OPTIONAL=(
  kerbrute-bin
  nuclei subfinder httpx 
  waybackurls gau gospider
  enum4linux
)

# Networking tools
PACMAN_NETWORKING=(
  openssh iperf3 traceroute inetutils
)

# Docker
PACMAN_DOCKER=(
  docker docker-compose docker-buildx
)

# VMware tools - UPDATED: No xf86-video-vmware (deprecated)
# Modern Arch uses Mesa modesetting driver
PACMAN_VMTOOLS=(
  mesa open-vm-tools gtkmm3 xf86-input-libinput
)

# VPN tools
PACMAN_VPN=(
  openvpn wireguard-tools 
  networkmanager networkmanager-openvpn
)

# Optional AUR (may fail, non-critical)
AUR_OPTIONAL=(
  zaproxy ligolo-ng katana hakrawler
)

# Python tools via pipx (installed AFTER pipx is available)
PIPX_TOOLS=(
  impacket bloodhound mitm6 dnstwist
)

# Python tools via pip --user (installed AFTER python-pip)
PIP_USER_TOOLS=(
  pwntools ropper ropgadget 
  pycryptodome paramiko requests scapy
)

# Module execution order - CRITICAL FOR DEPENDENCIES
MODULE_EXECUTION_ORDER=(
  core      # System update, base-devel, git
  dev       # Python, pip, pipx, compilers
  vmtools   # VMware tools (can run early)
  networking # Network utilities
  ui        # X server, i3, fonts (needs base-devel for AUR)
  pentest   # Pentest tools (needs python, pip)
  lazyvim   # Neovim config (needs neovim from dev)
  exploits  # Exploit templates (needs directories)
  workflow  # Workspace automation
  theming   # Final theme polish
  docker    # Docker (independent)
  vpn       # VPN tools (independent)
)

# User-selectable modules (same as execution order)
AVAILABLE_MODULES=("${MODULE_EXECUTION_ORDER[@]}")

# ------------------ Helpers ------------------
log() { echo -e "${GREEN}[+]${NC} $*" | tee -a "$INSTALL_LOG"; }
warn() { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$INSTALL_LOG"; }
err() { echo -e "${RED}[✗]${NC} $*" | tee -a "$INSTALL_LOG" >&2; }
info() { echo -e "${CYAN}[i]${NC} $*" | tee -a "$INSTALL_LOG"; }

confirm() {
  local prompt="$1"
  read -r -p "$prompt [y/N]: " ans
  [[ "$ans" =~ ^([yY][eE][sS]|[yY])$ ]]
}

# Package availability check with timeout
check_pacman_package() {
  local pkg="$1"
  timeout 5 pacman -Si "$pkg" &>/dev/null
}

check_aur_package() {
  local pkg="$1"
  timeout 10 curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg=${pkg}" 2>/dev/null | grep -q '"resultcount":1'
}

is_package_installed() {
  local pkg="$1"
  pacman -Qi "$pkg" &>/dev/null || yay -Qi "$pkg" &>/dev/null 2>&1
}

ensure_sudo() {
  if ! command -v sudo &>/dev/null; then
    err "sudo is required. Install it first."
    exit 1
  fi
  if ! sudo -v; then
    err "sudo access required. Add your user to wheel group."
    exit 1
  fi
}

# ------------------ Smart Package Fallback System ------------------

aur_search() {
  local term="$1"
  curl -s "https://aur.archlinux.org/rpc/?v=5&type=search&arg=${term}" 2>/dev/null \
    | jq -r '.results[].Name' 2>/dev/null || true
}

pacman_search() {
  local term="$1"
  pacman -Ss "$term" 2>/dev/null | awk -F'/' '/^[a-z]/{print $2}' | awk '{print $1}' || true
}

fallback_search() {
  local pkg="$1"
  
  if $AUTO; then
    warn "Package '${pkg}' not found - deferring for post-install review"
    DEFERRED_PACKAGES+=("$pkg")
    return 1
  fi
  
  echo ""
  warn "Package '${pkg}' not found in official repos."
  
  if ! confirm "Search AUR/alternatives for '${pkg}' now?"; then
    info "Deferring ${pkg} for later"
    DEFERRED_PACKAGES+=("$pkg")
    return 1
  fi

  local matches=()
  mapfile -t repo_matches < <(pacman_search "${pkg}")
  mapfile -t aur_matches < <(aur_search "${pkg}")
  matches=("${repo_matches[@]}" "${aur_matches[@]}")

  if [ ${#matches[@]} -eq 0 ]; then
    warn "No alternatives found for ${pkg}"
    DEFERRED_PACKAGES+=("$pkg")
    return 1
  fi

  echo ""
  info "Found ${#matches[@]} alternatives for ${pkg}:"
  
  local i=1
  for m in "${matches[@]}"; do
    echo "  $i) $m"
    ((i++))
  done
  
  read -rp "Select package to install (1-${#matches[@]}, 0 to skip): " choice_index
  
  if [[ -z "$choice_index" ]] || [[ "$choice_index" -eq 0 ]]; then
    info "Deferring ${pkg} for later"
    DEFERRED_PACKAGES+=("$pkg")
    return 1
  fi
  
  if ! [[ "$choice_index" =~ ^[0-9]+$ ]] || [ "$choice_index" -lt 1 ] || [ "$choice_index" -gt ${#matches[@]} ]; then
    warn "Invalid selection. Deferring ${pkg}"
    DEFERRED_PACKAGES+=("$pkg")
    return 1
  fi
  
  local selected="${matches[$((choice_index-1))]}"
  info "Selected fallback: $selected"

  if check_pacman_package "$selected"; then
    info "Installing $selected from official repos..."
    if sudo pacman -S --noconfirm --needed "$selected" 2>&1 | tee -a "$INSTALL_LOG"; then
      SUCCESSFUL_PACKAGES+=("$selected")
      return 0
    else
      warn "Failed to install $selected from repos"
    fi
  fi

  ensure_yay || { warn "yay not available; cannot install AUR packages"; DEFERRED_PACKAGES+=("$pkg"); return 1; }

  if check_aur_package "$selected"; then
    info "Installing $selected from AUR..."
    if yay -S --noconfirm --needed "$selected" </dev/tty 2>&1 | tee -a "$INSTALL_LOG"; then
      SUCCESSFUL_PACKAGES+=("$selected")
      return 0
    else
      warn "AUR install failed for $selected"
      DEFERRED_PACKAGES+=("$pkg")
      return 1
    fi
  fi

  warn "Selected fallback $selected not available"
  DEFERRED_PACKAGES+=("$pkg")
  return 1
}

# ------------------ Yay Installation ------------------
ensure_yay() {
  if command -v yay &>/dev/null; then
    return 0
  fi

  log "Installing yay AUR helper..."
  sudo -v || { err "sudo is required to build yay"; return 1; }

  local tmpdir="/tmp/yay-install-$$"
  mkdir -p "$tmpdir"
  cd "$tmpdir" || return 1

  info "Cloning yay repository..."
  if ! git clone --depth=1 https://aur.archlinux.org/yay.git 2>&1 | tee -a "$INSTALL_LOG"; then
    err "Failed to clone yay repository"
    cd - >/dev/null
    return 1
  fi

  cd yay || return 1
  info "Building yay..."
  if ! makepkg -si --noconfirm </dev/tty 2>&1 | tee -a "$INSTALL_LOG"; then
    err "Failed to build yay"
    cd - >/dev/null
    return 1
  fi

  cd - >/dev/null || true
  rm -rf "$tmpdir"
  log "yay installed successfully"
}

# ------------------ Pipx Installation ------------------
ensure_pipx() {
  if command -v pipx &>/dev/null; then
    return 0
  fi

  if ! command -v python &>/dev/null; then
    err "Python not installed. Install dev module first."
    return 1
  fi

  log "Configuring pipx..."
  if python -m pipx ensurepath 2>&1 | tee -a "$INSTALL_LOG"; then
    export PATH="$HOME/.local/bin:$PATH"
    log "pipx configured"
    return 0
  else
    err "Failed to configure pipx"
    return 1
  fi
}

# ------------------ Package Installation Functions ------------------

install_pacman_pkgs(){
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then return 0; fi

  log "Validating ${#pkgs[@]} packages before installation..."

  local valid_pkgs=()
  local invalid_pkgs=()

  for pkg in "${pkgs[@]}"; do
    if is_package_installed "$pkg"; then
      info "  ✓ $pkg (already installed)"
      SUCCESSFUL_PACKAGES+=("$pkg")
    elif check_pacman_package "$pkg"; then
      valid_pkgs+=("$pkg")
      info "  ✓ $pkg (available in repos)"
    else
      invalid_pkgs+=("$pkg")
      warn "  ✗ $pkg (not in repos or timeout)"
    fi
  done

  if [ ${#valid_pkgs[@]} -gt 0 ]; then
    log "Installing ${#valid_pkgs[@]} validated packages..."
    if sudo pacman -S --noconfirm --needed "${valid_pkgs[@]}" 2>&1 | tee -a "$INSTALL_LOG"; then
      SUCCESSFUL_PACKAGES+=("${valid_pkgs[@]}")
      log "Successfully installed ${#valid_pkgs[@]} packages"
    else
      warn "Some packages failed during installation"
      for pkg in "${valid_pkgs[@]}"; do
        if ! is_package_installed "$pkg"; then
          warn "  ✗ $pkg failed during install"
          invalid_pkgs+=("$pkg")
        fi
      done
    fi
  fi

  if [ ${#invalid_pkgs[@]} -gt 0 ]; then
    for miss in "${invalid_pkgs[@]}"; do
      warn "Attempting fallback search for: $miss"
      if ! fallback_search "$miss"; then
        warn "Fallback failed for $miss"
      fi
    done
  fi

  return 0
}

install_aur_pkgs(){
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then return 0; fi

  ensure_yay || return 1

  log "Installing ${#pkgs[@]} packages from AUR..."

  for pkg in "${pkgs[@]}"; do
    if is_package_installed "$pkg"; then
      info "  ✓ $pkg already installed (skipping)"
      SUCCESSFUL_PACKAGES+=("$pkg")
      continue
    fi

    info "  Checking $pkg availability in AUR..."
    if check_aur_package "$pkg"; then
      info "  Installing $pkg from AUR (this may take several minutes)..."
      if yay -S --noconfirm --needed "$pkg" </dev/tty 2>&1 | tee -a "$INSTALL_LOG"; then
        if is_package_installed "$pkg"; then
          log "  ✓ $pkg installed successfully"
          SUCCESSFUL_PACKAGES+=("$pkg")
        else
          warn "  ✗ $pkg installation reported success but package not found"
          FAILED_PACKAGES+=("$pkg")
        fi
      else
        warn "  ✗ Failed to install $pkg from AUR (error)"
        if ! fallback_search "$pkg"; then
          FAILED_PACKAGES+=("$pkg")
        fi
      fi
    else
      warn "  ✗ $pkg not found in AUR"
      if ! fallback_search "$pkg"; then
        FAILED_PACKAGES+=("$pkg")
      fi
    fi
  done
}

install_optional_pkgs(){
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then return 0; fi

  info "Installing ${#pkgs[@]} optional packages (non-critical)..."

  for pkg in "${pkgs[@]}"; do
    if is_package_installed "$pkg"; then
      info "  ✓ $pkg already installed"
      continue
    fi

    if check_pacman_package "$pkg"; then
      info "  Trying $pkg from official repos..."
      if sudo pacman -S --noconfirm --needed "$pkg" 2>/dev/null; then
        log "  ✓ $pkg installed"
        SUCCESSFUL_PACKAGES+=("$pkg")
        continue
      fi
    fi

    if command -v yay &>/dev/null; then
      info "  Trying $pkg from AUR..."
      if yay -S --noconfirm --needed "$pkg" 2>/dev/null; then
        log "  ✓ $pkg installed from AUR"
        SUCCESSFUL_PACKAGES+=("$pkg")
        continue
      else
        warn "  ✗ $pkg unavailable from AUR (optional, trying fallback)"
      fi
    else
      warn "  ✗ $pkg skipped (yay not available)"
    fi

    if ! fallback_search "$pkg"; then
      warn "  ✗ $pkg skipped after fallback search"
    fi
  done
}

install_pipx_tools(){
  local tools=("$@")
  if [ ${#tools[@]} -eq 0 ]; then return 0; fi
  
  ensure_pipx || return 1
  
  for tool in "${tools[@]}"; do
    if pipx list 2>/dev/null | grep -q "package $tool"; then
      info "  ✓ $tool already installed via pipx"
      SUCCESSFUL_PACKAGES+=("pipx:$tool")
      continue
    fi
    
    log "  Installing $tool via pipx..."
    if timeout 300 pipx install "$tool" 2>&1 | tee -a "$INSTALL_LOG"; then
      log "  ✓ $tool installed"
      SUCCESSFUL_PACKAGES+=("pipx:$tool")
    else
      warn "  ✗ Failed to install $tool via pipx"
      FAILED_PACKAGES+=("pipx:$tool")
    fi
  done
}

install_pip_user_tools(){
  local tools=("$@")
  if [ ${#tools[@]} -eq 0 ]; then return 0; fi
  
  log "Installing ${#tools[@]} Python packages via pip --user..."
  
  for tool in "${tools[@]}"; do
    info "  Installing $tool..."
    if timeout 180 python -m pip install --user "$tool" 2>&1 | tee -a "$INSTALL_LOG"; then
      log "  ✓ $tool installed"
      SUCCESSFUL_PACKAGES+=("pip:$tool")
    else
      warn "  ✗ Failed: $tool"
      FAILED_PACKAGES+=("pip:$tool")
    fi
  done
}

handle_deferred_packages(){
  if [ ${#DEFERRED_PACKAGES[@]} -eq 0 ]; then
    return 0
  fi
  
  echo ""
  echo -e "${YELLOW}╔════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║      Deferred Package Resolution                  ║${NC}"
  echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  warn "The following ${#DEFERRED_PACKAGES[@]} packages were not found and need your attention:"
  for pkg in "${DEFERRED_PACKAGES[@]}"; do
    echo "  - $pkg"
  done
  echo ""
  
  if $AUTO; then
    info "AUTO mode: Skipping deferred package resolution"
    info "Run the script interactively to resolve these packages"
    return 0
  fi
  
  if ! confirm "Would you like to search for alternatives now?"; then
    info "You can manually install these packages later with:"
    info "  pacman -S <package> or yay -S <package>"
    return 0
  fi
  
  for pkg in "${DEFERRED_PACKAGES[@]}"; do
    echo ""
    log "Searching alternatives for: $pkg"
    
    local matches=()
    mapfile -t repo_matches < <(pacman_search "${pkg}")
    mapfile -t aur_matches < <(aur_search "${pkg}")
    matches=("${repo_matches[@]}" "${aur_matches[@]}")
    
    if [ ${#matches[@]} -eq 0 ]; then
      warn "No alternatives found for ${pkg}"
      FAILED_PACKAGES+=("$pkg")
      continue
    fi
    
    info "Found ${#matches[@]} alternatives:"
    local i=1
    for m in "${matches[@]}"; do
      echo "  $i) $m"
      ((i++))
    done
    
    read -rp "Select package (1-${#matches[@]}, 0 to skip): " choice
    
    if [[ -z "$choice" ]] || [[ "$choice" -eq 0 ]]; then
      warn "Skipped ${pkg}"
      FAILED_PACKAGES+=("$pkg")
      continue
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#matches[@]} ]; then
      warn "Invalid selection for ${pkg}"
      FAILED_PACKAGES+=("$pkg")
      continue
    fi
    
    local selected="${matches[$((choice-1))]}"
    info "Installing $selected..."
    
    if check_pacman_package "$selected"; then
      if sudo pacman -S --noconfirm --needed "$selected" 2>&1 | tee -a "$INSTALL_LOG"; then
        log "✓ $selected installed"
        SUCCESSFUL_PACKAGES+=("$selected")
        continue
      fi
    fi
    
    if command -v yay &>/dev/null && check_aur_package "$selected"; then
      if yay -S --noconfirm --needed "$selected" </dev/tty 2>&1 | tee -a "$INSTALL_LOG"; then
        log "✓ $selected installed from AUR"
        SUCCESSFUL_PACKAGES+=("$selected")
        continue
      fi
    fi
    
    warn "Failed to install $selected"
    FAILED_PACKAGES+=("$pkg")
  done
  
  DEFERRED_PACKAGES=()
}

show_install_summary(){
  echo ""
  echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║           Installation Summary                     ║${NC}"
  echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  if [ ${#SUCCESSFUL_PACKAGES[@]} -gt 0 ]; then
    log "Successfully installed: ${#SUCCESSFUL_PACKAGES[@]} packages"
  fi
  
  if [ ${#DEFERRED_PACKAGES[@]} -gt 0 ]; then
    warn "Deferred packages: ${#DEFERRED_PACKAGES[@]}"
    echo "The following packages were deferred:"
    for pkg in "${DEFERRED_PACKAGES[@]}"; do
      echo "  - $pkg"
    done
    echo ""
  fi
  
  if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    warn "Failed packages: ${#FAILED_PACKAGES[@]}"
    echo ""
    echo "The following packages failed to install:"
    for pkg in "${FAILED_PACKAGES[@]}"; do
      echo "  - $pkg"
    done
    echo ""
    warn "Some functionality may be limited"
  else
    if [ ${#DEFERRED_PACKAGES[@]} -eq 0 ]; then
      log "All packages installed successfully!"
    fi
  fi
  
  info "Full log available at: $INSTALL_LOG"
}

# ------------------ Module Implementations ------------------

module_core(){
  log "[core] System update and base packages..."
  ensure_sudo
  
  info "Updating package databases..."
  sudo pacman -Sy --noconfirm 2>&1 | tee -a "$INSTALL_LOG"
  
  info "Upgrading system..."
  sudo pacman -Syu --noconfirm 2>&1 | tee -a "$INSTALL_LOG"
  
  info "Installing core packages..."
  install_pacman_pkgs "${PACMAN_CORE[@]}"
  
  mkdir -p ~/.local/bin
  
  if ! grep -q '.local/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
  fi
  
  log "[core] Done."
}

module_dev(){
  log "[dev] Installing development tools..."
  
  install_pacman_pkgs "${PACMAN_DEV[@]}"
  ensure_pipx
  
  log "[dev] Done."
}

module_vmtools(){
  log "[vmtools] Installing VMware guest tools (modern drivers)..."
  
  if lspci | grep -qi vmware; then
    info "VMware detected - using modern Mesa modesetting driver"
  else
    warn "VMware not detected, but installing tools anyway"
  fi
  
  install_pacman_pkgs "${PACMAN_VMTOOLS[@]}"
  
  info "Enabling vmtoolsd service..."
  sudo systemctl enable vmtoolsd 2>/dev/null || warn "Could not enable vmtoolsd"
  sudo systemctl start vmtoolsd 2>/dev/null || warn "Could not start vmtoolsd"
  
  if [ -f /etc/X11/xorg.conf ]; then
    warn "Found old xorg.conf - backing it up"
    sudo mv /etc/X11/xorg.conf /etc/X11/xorg.conf.backup-$(date +%s) 2>/dev/null || true
  fi
  
  sudo mkdir -p /etc/X11/xorg.conf.d
  sudo tee /etc/X11/xorg.conf.d/20-modesetting.conf > /dev/null << 'EOF'
Section "Device"
    Identifier "VMware SVGA"
    Driver "modesetting"
    Option "AccelMethod" "glamor"
EndSection

Section "ServerFlags"
    Option "AutoAddGPU" "off"
EndSection
EOF
  
  log "Created modern X configuration for VMware"
  
  if ! groups | grep -q video; then
    info "Adding user to video group..."
    sudo usermod -aG video "$USER" || warn "Failed to add to video group"
  fi
  
  echo ""
  warn "IMPORTANT VMware Settings:"
  echo "  • 3D Acceleration: MUST BE DISABLED in VM settings"
  echo "  • Video Memory: Set to 128MB or higher"
  echo "  • After changing settings: Restart the VM"
  echo ""
  
  log "[vmtools] Done."
}

module_networking(){
  log "[networking] Installing network utilities..."
  
  install_pacman_pkgs "${PACMAN_NETWORKING[@]}"
  
  info "SSH server NOT enabled by default (security)"
  info "To enable: sudo systemctl enable --now sshd"
  
  log "[networking] Done."
}

module_ui(){
  log "[ui] Installing UI with HTB Neon Nord theme..."
  
  install_pacman_pkgs "${PACMAN_UI[@]}"
  install_aur_pkgs "${AUR_UI[@]}"
  install_optional_pkgs "${OPTIONAL_UI[@]}"
  
  # Download HTB-style wallpaper
  info "Downloading Nord wallpaper..."
  mkdir -p ~/Pictures
  if timeout 30 curl -fsSL "https://raw.githubusercontent.com/linuxdotexe/nordic-wallpapers/master/wallpapers/nord-neon-mountains.png" \
       -o ~/Pictures/wallpaper.jpg 2>/dev/null; then
    log "Wallpaper downloaded"
  else
    warn "Wallpaper download failed (will use feh default)"
  fi
  
  # Install Dave0x21 i3-theme-template
  info "Installing i3-theme-template..."
  local theme_dir="$HOME/.config/i3-theme-template"
  
  if [ ! -d "$theme_dir" ]; then
    if git clone https://github.com/Dave0x21/i3-theme-template.git "$theme_dir" 2>&1 | tee -a "$INSTALL_LOG"; then
      log "i3-theme-template cloned successfully"
      
      # Make the install script executable and run it
      if [ -f "$theme_dir/install.sh" ]; then
        chmod +x "$theme_dir/install.sh"
        info "Running i3-theme-template installer..."
        cd "$theme_dir" || warn "Could not cd to theme directory"
        
        # Run installer non-interactively if in AUTO mode
        if $AUTO; then
          ./install.sh --auto 2>&1 | tee -a "$INSTALL_LOG" || warn "Theme installer failed (non-critical)"
        else
          ./install.sh 2>&1 | tee -a "$INSTALL_LOG" || warn "Theme installer failed (non-critical)"
        fi
        
        cd - >/dev/null || true
        log "i3-theme-template installed"
      else
        warn "Theme install script not found - manual setup required"
      fi
    else
      warn "Failed to clone i3-theme-template (non-critical)"
    fi
  else
    info "i3-theme-template already installed"
  fi
  
  # Create .xinitrc with startx fix
  cat > ~/.xinitrc << 'EOF'
#!/bin/sh

# Disable screen blanking
xset s off
xset -dpms

# Load pywal colors if available
if command -v wal >/dev/null 2>&1; then
    (cat ~/.cache/wal/sequences 2>/dev/null &)
    wal -R 2>/dev/null || wal -i ~/Pictures/wallpaper.jpg 2>/dev/null || true
fi

exec i3
EOF
  chmod +x ~/.xinitrc
  
  # i3 config with HTB green accent (Dave0x21 theme compatible)
  mkdir -p ~/.config/i3
  cat > ~/.config/i3/config << 'EOF'
# Neon Nord Pentest i3 Config
# NOTE: Press Mod+Shift+/ to show keybinding cheatsheet
set $mod Mod4
font pango:JetBrainsMono Nerd Font 10

# Source pywal colors (if available)
set_from_resource $fg i3wm.color7 #eceff4
set_from_resource $bg i3wm.color2 #9fef00

# HTB Neon Nord Colors
set $bg-dark     #2e3440
set $bg-medium   #3b4252
set $bg-light    #434c5e
set $fg          #eceff4
set $htb-green   #9fef00
set $accent-cyan #88c0d0
set $accent-purp #b48ead
set $urgent      #bf616a

# Window colors (HTB green borders on focused)
client.focused           $htb-green     $bg-dark       $fg       $accent-cyan   $htb-green
client.focused_inactive  $bg-light      $bg-dark       $fg       $bg-light      $bg-light
client.unfocused         $bg-medium     $bg-dark       $fg       $bg-medium     $bg-medium
client.urgent            $urgent        $urgent        $fg       $urgent        $urgent

gaps inner 10
gaps outer 5
smart_gaps on

for_window [class=".*"] border pixel 2
default_border pixel 2
default_floating_border pixel 2

# Autostart
exec_always --no-startup-id ~/.config/polybar/launch.sh
exec_always --no-startup-id feh --bg-scale ~/Pictures/wallpaper.jpg || feh --bg-fill /usr/share/backgrounds/*
exec --no-startup-id dunst
exec_always --no-startup-id picom --config ~/.config/picom/picom.conf

# Keybindings - FIXED: use lowercase 'shift' to avoid escape codes
bindsym $mod+d exec --no-startup-id rofi -show drun -theme ~/.config/rofi/neon-nord.rasi
bindsym $mod+Return exec kitty
bindsym $mod+Shift+q kill
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart

# Navigation (vim keys)
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

# Arrow keys alternative
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

# Move windows (vim keys)
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right

# Arrow keys alternative
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

# Splits
bindsym $mod+bar split h
bindsym $mod+minus split v
bindsym $mod+f fullscreen toggle

# Layouts
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split

# Float
bindsym $mod+Shift+space floating toggle
bindsym $mod+space focus mode_toggle

# Workspaces (pentest workflow)
set $ws1 "1:recon"
set $ws2 "2:enum"
set $ws3 "3:exploit"
set $ws4 "4:post"
set $ws5 "5:notes"
set $ws6 "6"
set $ws7 "7"
set $ws8 "8"
set $ws9 "9"
set $ws10 "10"

# Switch to workspace
bindsym $mod+1 workspace number $ws1
bindsym $mod+2 workspace number $ws2
bindsym $mod+3 workspace number $ws3
bindsym $mod+4 workspace number $ws4
bindsym $mod+5 workspace number $ws5
bindsym $mod+6 workspace number $ws6
bindsym $mod+7 workspace number $ws7
bindsym $mod+8 workspace number $ws8
bindsym $mod+9 workspace number $ws9
bindsym $mod+0 workspace number $ws10

# Move container to workspace
bindsym $mod+Shift+1 move container to workspace number $ws1
bindsym $mod+Shift+2 move container to workspace number $ws2
bindsym $mod+Shift+3 move container to workspace number $ws3
bindsym $mod+Shift+4 move container to workspace number $ws4
bindsym $mod+Shift+5 move container to workspace number $ws5
bindsym $mod+Shift+6 move container to workspace number $ws6
bindsym $mod+Shift+7 move container to workspace number $ws7
bindsym $mod+Shift+8 move container to workspace number $ws8
bindsym $mod+Shift+9 move container to workspace number $ws9
bindsym $mod+Shift+0 move container to workspace number $ws10

# System shortcuts
bindsym Print exec --no-startup-id maim -s | xclip -selection clipboard -t image/png
bindsym $mod+Shift+x exec i3lock -c 2e3440
bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'Exit i3?' -B 'Yes, exit i3' 'i3-msg exit'"

# Application shortcuts
bindsym $mod+Shift+f exec thunar
bindsym $mod+Shift+w exec firefox
bindsym $mod+Shift+slash exec --no-startup-id ~/.local/bin/i3-keybinds

# Resize mode
mode "resize" {
    bindsym h resize shrink width 10 px or 10 ppt
    bindsym j resize grow height 10 px or 10 ppt
    bindsym k resize shrink height 10 px or 10 ppt
    bindsym l resize grow width 10 px or 10 ppt

    bindsym Left resize shrink width 10 px or 10 ppt
    bindsym Down resize grow height 10 px or 10 ppt
    bindsym Up resize shrink height 10 px or 10 ppt
    bindsym Right resize grow width 10 px or 10 ppt

    bindsym Return mode "default"
    bindsym Escape mode "default"
    bindsym $mod+r mode "default"
}
bindsym $mod+r mode "resize"

# Floating windows
for_window [class="Thunar"] floating enable
for_window [class="Pavucontrol"] floating enable
for_window [title="nmtui"] floating enable
for_window [class="Lxappearance"] floating enable
for_window [class="floating-term"] floating enable, resize set 1200 700, move position center

# Auto-assign to workspaces
assign [class="Burp"] $ws3
assign [class="Wireshark"] $ws2
EOF
  
  # Picom config
  mkdir -p ~/.config/picom
  cat > ~/.config/picom/picom.conf << 'EOF'
# VM-friendly picom config
backend = "xrender";
vsync = true;
use-damage = true;

shadow = true;
shadow-radius = 12;
shadow-opacity = 0.6;
shadow-offset-x = -8;
shadow-offset-y = -8;

fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;

inactive-opacity = 0.92;
frame-opacity = 0.9;

corner-radius = 8;
rounded-corners-exclude = [
    "window_type = 'dock'",
    "window_type = 'desktop'"
];

wintypes:
{
    tooltip = { fade = true; shadow = true; opacity = 0.95; };
    dock = { shadow = false; };
};
EOF
  
  # Polybar config
  mkdir -p ~/.config/polybar
  cat > ~/.config/polybar/config.ini << 'EOF'
[colors]
background = #2e3440
background-alt = #3b4252
foreground = #eceff4
primary = #9fef00
secondary = #88c0d0
alert = #bf616a
disabled = #4c566a

[bar/main]
width = 100%
height = 28
background = ${colors.background}
foreground = ${colors.foreground}
line-size = 3
padding = 1
module-margin = 1
separator = |
separator-foreground = ${colors.disabled}
font-0 = JetBrainsMono Nerd Font:size=10;2
font-1 = Font Awesome 6 Free:style=Solid:size=10;2
modules-left = xworkspaces xwindow
modules-right = filesystem memory cpu date
cursor-click = pointer

[module/xworkspaces]
type = internal/xworkspaces
label-active = %name%
label-active-background = ${colors.background-alt}
label-active-underline= ${colors.primary}
label-active-padding = 1
label-occupied = %name%
label-occupied-padding = 1
label-urgent = %name%
label-urgent-background = ${colors.alert}
label-urgent-padding = 1
label-empty = %name%
label-empty-foreground = ${colors.disabled}
label-empty-padding = 1

[module/xwindow]
type = internal/xwindow
label = %title:0:60:...%

[module/filesystem]
type = internal/fs
mount-0 = /
label-mounted = %{F#9fef00}%mountpoint%%{F-} %percentage_used%%

[module/memory]
type = internal/memory
interval = 2
format-prefix = "RAM "
format-prefix-foreground = ${colors.primary}
label = %percentage_used:2%%

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = "CPU "
format-prefix-foreground = ${colors.primary}
label = %percentage:2%%

[module/date]
type = internal/date
interval = 1
date = %H:%M
date-alt = %Y-%m-%d %H:%M:%S
label = %date%
label-foreground = ${colors.primary}
EOF
  
  cat > ~/.config/polybar/launch.sh << 'EOF'
#!/bin/bash
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.5; done
polybar main 2>&1 | tee -a /tmp/polybar.log & disown
EOF
  chmod +x ~/.config/polybar/launch.sh
  
  # Kitty config (primary terminal)
  mkdir -p ~/.config/kitty
  cat > ~/.config/kitty/kitty.conf << 'EOF'
# HTB Neon Nord Kitty Theme
font_family      JetBrainsMono Nerd Font
font_size 11.0
cursor_shape block
cursor_blink_interval 0

background_opacity 0.92
background_blur 20

foreground            #eceff4
background            #2e3440
selection_foreground  #2e3440
selection_background  #9fef00

color0   #3b4252
color8   #4c566a
color1   #bf616a
color9   #bf616a
color2   #9fef00
color10  #9fef00
color3   #ebcb8b
color11  #ebcb8b
color4   #81a1c1
color12  #81a1c1
color5   #b48ead
color13  #b48ead
color6   #88c0d0
color14  #8fbcbb
color7   #e5e9f0
color15  #eceff4

tab_bar_style powerline
active_tab_foreground   #2e3440
active_tab_background   #9fef00
inactive_tab_foreground #d8dee9
inactive_tab_background #3b4252

window_padding_width 10
EOF
  
  # Rofi theme
  mkdir -p ~/.config/rofi
  cat > ~/.config/rofi/config.rasi << 'EOF'
configuration {
    modi: "drun,run,window";
    show-icons: true;
    display-drun: "Apps";
    display-run: "Run";
    display-window: "Windows";
}

@theme "neon-nord"
EOF
  
  cat > ~/.config/rofi/neon-nord.rasi << 'EOF'
* {
    bg: #2e3440;
    bg-alt: #3b4252;
    fg: #eceff4;
    primary: #9fef00;
    
    background-color: @bg;
    text-color: @fg;
    margin: 0;
    padding: 0;
    spacing: 0;
}

window {
    width: 600px;
    border: 2px;
    border-color: @primary;
    border-radius: 8px;
}

inputbar {
    padding: 12px;
    spacing: 12px;
    children: [prompt, entry];
}

prompt {
    text-color: @primary;
}

entry {
    placeholder: "Search...";
}

listview {
    padding: 8px 0;
    lines: 8;
}

element {
    padding: 8px 12px;
    spacing: 8px;
}

element selected {
    background-color: @bg-alt;
    text-color: @primary;
}

element-icon {
    size: 1em;
}
EOF
  
  # Dunst config
  mkdir -p ~/.config/dunst
  cat > ~/.config/dunst/dunstrc << 'EOF'
[global]
    font = JetBrainsMono Nerd Font 10
    markup = full
    format = "<b>%s</b>\n%b"
    alignment = left
    show_age_threshold = 60
    word_wrap = yes
    width = 300
    height = 300
    offset = 10x30
    padding = 8
    horizontal_padding = 8
    frame_width = 2
    
[urgency_low]
    background = "#2e3440"
    foreground = "#eceff4"
    frame_color = "#88c0d0"
    timeout = 5

[urgency_normal]
    background = "#2e3440"
    foreground = "#eceff4"
    frame_color = "#9fef00"
    timeout = 10

[urgency_critical]
    background = "#bf616a"
    foreground = "#eceff4"
    frame_color = "#bf616a"
    timeout = 0
EOF
  
  # Initialize pywal with wallpaper
  info "Initializing pywal color scheme..."
  if [ -f ~/Pictures/wallpaper.jpg ]; then
    wal -i ~/Pictures/wallpaper.jpg -n 2>/dev/null || warn "pywal initialization failed (will work after reboot)"
  fi
  
  # Create pywal reload script
  cat > ~/.local/bin/wal-reload << 'EOF'
#!/bin/bash
# Reload pywal colors and update everything

if [ -z "$1" ]; then
    # Use current wallpaper
    wal -R
else
    # Use specified wallpaper
    wal -i "$1"
fi

# Reload i3
i3-msg reload

# Restart polybar
~/.config/polybar/launch.sh

# Reload dunst
killall dunst; dunst &
EOF
  chmod +x ~/.local/bin/wal-reload
  
  log "[ui] Done. Run 'startx' to launch i3."
  echo ""
  info "Pywal commands:"
  echo "  wal -i ~/path/to/image.jpg  # Set new wallpaper & generate colors"
  echo "  wal-reload                   # Reload current theme"
  echo "  wal -R                       # Restore previous theme"
  echo ""
  info "i3-theme-template installed in ~/.config/i3-theme-template"
  echo "  See README for theme customization options"
  echo ""
  
  # Create keybinding cheatsheet (Omarchy-style)
  info "Creating keybinding cheatsheet..."
  cat > ~/.local/bin/i3-keybinds << 'EOF'
#!/bin/bash
# HTB Neon Nord i3 Keybinding Cheatsheet

rofi -dmenu -i -p "i3 Keybindings" -theme ~/.config/rofi/neon-nord.rasi << 'BINDINGS'
╔═══════════════════════════════════════════════════════════╗
║              HTB NEON NORD i3 KEYBINDINGS                ║
╚═══════════════════════════════════════════════════════════╝

┌─ ESSENTIALS ─────────────────────────────────────────────┐
│ Mod+Enter         Terminal (Kitty)                       │
│ Mod+d             Application Launcher (Rofi)            │
│ Mod+Shift+q       Kill Window                            │
│ Mod+Shift+c       Reload i3 Config                       │
│ Mod+Shift+r       Restart i3                             │
│ Mod+Shift+e       Exit i3                                │
└──────────────────────────────────────────────────────────┘

┌─ NAVIGATION (VIM-STYLE) ─────────────────────────────────┐
│ Mod+h/j/k/l       Focus Left/Down/Up/Right              │
│ Mod+Shift+h/j/k/l Move Window Left/Down/Up/Right        │
│ Mod+Arrows        Focus (Arrow Keys)                     │
│ Mod+Shift+Arrows  Move Window (Arrow Keys)              │
└──────────────────────────────────────────────────────────┘

┌─ WORKSPACES ─────────────────────────────────────────────┐
│ Mod+1-5           Switch to Workspace 1-5                │
│   1:recon         Reconnaissance                         │
│   2:enum          Enumeration                            │
│   3:exploit       Exploitation                           │
│   4:post          Post-Exploitation                      │
│   5:notes         Notes & Documentation                  │
│ Mod+Shift+1-5     Move Window to Workspace              │
└──────────────────────────────────────────────────────────┘

┌─ WINDOW MANAGEMENT ──────────────────────────────────────┐
│ Mod+f             Fullscreen Toggle                      │
│ Mod+space         Toggle Tiling/Floating Focus          │
│ Mod+Shift+space   Toggle Window Floating                │
│ Mod+s             Stacking Layout                        │
│ Mod+w             Tabbed Layout                          │
│ Mod+e             Toggle Split Layout                    │
│ Mod+bar (|)       Split Horizontal                       │
│ Mod+minus (-)     Split Vertical                         │
│ Mod+r             Resize Mode (h/j/k/l or arrows)       │
└──────────────────────────────────────────────────────────┘

┌─ APPLICATIONS ───────────────────────────────────────────┐
│ Mod+Shift+w       Firefox                                │
│ Mod+Shift+f       Thunar File Manager                    │
│ Print             Screenshot (Selection)                 │
│ Mod+Shift+x       Lock Screen                            │
└──────────────────────────────────────────────────────────┘

┌─ TIPS ───────────────────────────────────────────────────┐
│ • Mod key is Super/Windows key (Mod4)                    │
│ • All keybindings use lowercase 'shift' for reliability  │
│ • Use 'htb-init <machine>' to create HTB workspaces      │
│ • Use 'lsd' or 'll' for beautiful file listings w/ icons │
│ • Use 'ranger' or 'yazi' for file browsing w/ previews   │
│ • Check ~/.config/i3/config for full customization       │
└──────────────────────────────────────────────────────────┘
BINDINGS
EOF
  chmod +x ~/.local/bin/i3-keybinds
  
  log "Keybinding cheatsheet created. Run 'i3-keybinds' anytime!"
}


module_pentest(){
  log "[pentest] Installing penetration testing tools..."
  
  install_pacman_pkgs "${PACMAN_PENTEST[@]}"
  install_aur_pkgs "${AUR_PENTEST[@]}"
  install_optional_pkgs "${AUR_PENTEST_OPTIONAL[@]}"
  install_pipx_tools "${PIPX_TOOLS[@]}"
  install_pip_user_tools "${PIP_USER_TOOLS[@]}"
  
  if groups | grep -qv wireshark; then
    info "Adding user to wireshark group..."
    sudo usermod -aG wireshark "$USER" || warn "Failed to add to wireshark group"
  fi
  
  log "[pentest] Done."
}

module_lazyvim(){
  log "[lazyvim] Setting up LazyVim configuration..."
  
  if [ ! -d ~/.config/nvim ]; then
    info "Installing LazyVim..."
    git clone https://github.com/LazyVim/starter ~/.config/nvim
    rm -rf ~/.config/nvim/.git
    log "LazyVim installed"
  else
    warn "Neovim config already exists, skipping"
  fi
  
  log "[lazyvim] Done. Run 'nvim' to complete setup."
}

module_exploits(){
  log "[exploits] Setting up exploit templates..."
  
  mkdir -p ~/exploits/{web,privesc,network,custom}
  
  cat > ~/exploits/README.md << 'EOF'
# Exploit Templates

Organize your exploits by category:
- web/ - Web application exploits
- privesc/ - Privilege escalation scripts
- network/ - Network-based exploits
- custom/ - Custom scripts and tools
EOF
  
  log "[exploits] Done."
}

module_workflow(){
  log "[workflow] Setting up workspace automation..."
  
  mkdir -p ~/htb/{active,retired,labs}
  mkdir -p ~/.local/bin
  
  cat > ~/.local/bin/htb-init << 'EOF'
#!/bin/bash
# Initialize new HTB machine workspace

if [ -z "$1" ]; then
    echo "Usage: htb-init <machine-name>"
    exit 1
fi

MACHINE="$1"
WORKSPACE="$HOME/htb/active/$MACHINE"

if [ -d "$WORKSPACE" ]; then
    echo "Workspace already exists: $WORKSPACE"
    exit 1
fi

mkdir -p "$WORKSPACE"/{recon,enum,exploit,loot,notes}

cat > "$WORKSPACE/notes/README.md" << NOTES
# $MACHINE

## Target Information
- IP: 
- OS: 
- Difficulty: 

## Enumeration
- Ports: 
- Services: 

## Exploitation
- Vector: 
- CVE: 

## Privilege Escalation
- Method: 

## Flags
- User: 
- Root: 
NOTES

echo "Workspace created: $WORKSPACE"
cd "$WORKSPACE"
EOF
  chmod +x ~/.local/bin/htb-init
  
  log "[workflow] Done. Use 'htb-init <machine>' to create workspaces."
}

module_theming(){
  log "[theming] Applying final theme customizations..."
  
  mkdir -p ~/.config/gtk-3.0
  cat > ~/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Sans 10
gtk-cursor-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
EOF
  
  if ! grep -q "HTB Neon Nord" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'EOF'

# HTB Neon Nord Bash Theme
PS1='\[\033[0;32m\]┌──(\[\033[1;32m\]\u\[\033[0;32m\]@\[\033[1;32m\]\h\[\033[0;32m\])-[\[\033[1;36m\]\w\[\033[0;32m\]]\n\[\033[0;32m\]└─\[\033[1;32m\]\$\[\033[0m\] '

# Aliases - lsd for beautiful file listings with icons
alias ls='lsd'
alias ll='lsd -lah --color=auto'
alias la='lsd -a'
alias lt='lsd --tree --depth=2'
alias grep='grep --color=auto'
alias nmap-quick='nmap -sC -sV -oN nmap-initial'
alias nmap-full='nmap -p- -sC -sV -oN nmap-full'
alias serve='python -m http.server'
alias myip='ip -4 addr show tun0 2>/dev/null | grep -oP "(?<=inet\s)\d+(\.\d+){3}" || ip -4 addr show eth0 | grep -oP "(?<=inet\s)\d+(\.\d+){3}"'

# Enable color support
export LS_COLORS="$(vivid generate nord)"
EOF
  fi
  
  log "[theming] Done."
}

module_docker(){
  log "[docker] Installing Docker..."
  
  install_pacman_pkgs "${PACMAN_DOCKER[@]}"
  
  info "Adding user to docker group..."
  sudo usermod -aG docker "$USER" || warn "Failed to add to docker group"
  
  info "Enabling Docker service..."
  sudo systemctl enable docker 2>/dev/null || warn "Could not enable docker"
  sudo systemctl start docker 2>/dev/null || warn "Could not start docker"
  
  log "[docker] Done. Log out and back in for group changes."
}

module_vpn(){
  log "[vpn] Installing VPN tools..."
  
  install_pacman_pkgs "${PACMAN_VPN[@]}"
  
  mkdir -p ~/vpn
  
  log "[vpn] Done. Place .ovpn files in ~/vpn/"
}

# ------------------ Main Script Logic ------------------

parse_args(){
  SELECTED_MODULES=()
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      --auto)
        AUTO=true
        shift
        ;;
      --modules)
        IFS=',' read -ra SELECTED_MODULES <<< "$2"
        shift 2
        ;;
      --help|-h)
        show_banner
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --auto              Run in automatic mode (no prompts)"
        echo "  --modules <list>    Comma-separated list of modules"
        echo "  --help, -h          Show this help"
        echo ""
        echo "Available modules:"
        for mod in "${AVAILABLE_MODULES[@]}"; do
          echo "  - $mod"
        done
        exit 0
        ;;
      *)
        err "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
  done
}

interactive_module_selection(){
  echo ""
  info "Select modules to install:"
  echo ""
  
  local i=1
  for mod in "${AVAILABLE_MODULES[@]}"; do
    echo "  $i) $mod"
    ((i++))
  done
  echo "  0) All modules"
  echo ""
  
  read -rp "Enter module numbers (space-separated, or 0 for all): " selection
  
  if [[ "$selection" == "0" ]]; then
    SELECTED_MODULES=("${AVAILABLE_MODULES[@]}")
  else
    for num in $selection; do
      if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -gt 0 ] && [ "$num" -le ${#AVAILABLE_MODULES[@]} ]; then
        SELECTED_MODULES+=("${AVAILABLE_MODULES[$((num-1))]}")
      fi
    done
  fi
  
  if [ ${#SELECTED_MODULES[@]} -eq 0 ]; then
    err "No valid modules selected"
    exit 1
  fi
  
  echo ""
  info "Selected modules: ${SELECTED_MODULES[*]}"
  echo ""
  
  if ! $AUTO; then
    if ! confirm "Proceed with installation?"; then
      info "Installation cancelled"
      exit 0
    fi
  fi
}

run_modules(){
  for mod in "${SELECTED_MODULES[@]}"; do
    echo ""
    log "========================================"
    log "Running module: $mod"
    log "========================================"
    echo ""
    
    case $mod in
      core) module_core ;;
      dev) module_dev ;;
      vmtools) module_vmtools ;;
      networking) module_networking ;;
      ui) module_ui ;;
      pentest) module_pentest ;;
      lazyvim) module_lazyvim ;;
      exploits) module_exploits ;;
      workflow) module_workflow ;;
      theming) module_theming ;;
      docker) module_docker ;;
      vpn) module_vpn ;;
      *)
        warn "Unknown module: $mod"
        ;;
    esac
  done
}

check_fresh_install(){
  local uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
  local uptime_hours=$((uptime_seconds / 3600))
  
  if [ $uptime_hours -lt 1 ] && [ ! -f /var/lib/skidstall-ran ]; then
    warn "⚠️  FRESH INSTALLATION DETECTED"
    echo ""
    echo -e "${YELLOW}This appears to be a fresh Arch installation.${NC}"
    echo -e "${YELLOW}Running a full system upgrade immediately after archinstall${NC}"
    echo -e "${YELLOW}can sometimes cause boot issues.${NC}"
    echo ""
    echo -e "${CYAN}RECOMMENDED WORKFLOW:${NC}"
    echo "  1. Run 'sudo pacman -Syu' manually first"
    echo "  2. Reboot to ensure system is stable"
    echo "  3. Then run this script"
    echo ""
    
    if ! $AUTO; then
      if ! confirm "Continue anyway? (Not recommended)"; then
        info "Installation cancelled. Run the script after a manual system update."
        exit 0
      fi
      warn "Proceeding at your own risk..."
    else
      err "AUTO mode blocked on fresh install for safety"
      info "Run manually with system update first, then use --auto"
      exit 1
    fi
  fi
  
  sudo touch /var/lib/skidstall-ran 2>/dev/null || true
}

main(){
  show_banner
  parse_args "$@"
  
  check_fresh_install
  
  if [ ${#SELECTED_MODULES[@]} -eq 0 ]; then
    interactive_module_selection
  fi
  
  local ordered_modules=()
  for exec_mod in "${MODULE_EXECUTION_ORDER[@]}"; do
    for sel_mod in "${SELECTED_MODULES[@]}"; do
      if [[ "$exec_mod" == "$sel_mod" ]]; then
        ordered_modules+=("$exec_mod")
      fi
    done
  done
  
  SELECTED_MODULES=("${ordered_modules[@]}")
  
  info "Installation order: ${SELECTED_MODULES[*]}"
  echo ""
  
  run_modules
  handle_deferred_packages
  show_install_summary
  
  echo ""
  log "Installation complete!"
  echo ""
  info "Next steps:"
  echo "  1. DISABLE 3D acceleration in VMware settings"
  echo "  2. Restart the VM"
  echo "  3. Log out and back in for group changes to take effect"
  echo "  4. Run 'startx' from text console (Ctrl+Alt+F2) to launch i3"
  echo "  5. Press Mod+Shift+/ to view keybinding cheatsheet"
  echo "  6. Use 'htb-init <machine>' to create HTB workspaces"
  echo "  7. Customize themes via ~/.config/i3-theme-template"
  echo ""
}

main "$@"
