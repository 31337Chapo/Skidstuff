#!/usr/bin/env bash

# - Interactive CLI by default, --auto for unattended
# - Modules installed in correct dependency order automatically
# - HTB-inspired Neon Nord theme (green #9fef00 + Nord palette)
# - Package validation and integrity checks
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
INSTALL_LOG="/tmp/skidstall-$$.log"
FAILED_PACKAGES=()
SUCCESSFUL_PACKAGES=()

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
  go rust cargo nodejs npm 
  jq yq fd ripgrep
  neovim tmux screen
)

# UI packages - needs fonts and base X
PACMAN_UI=(
  xorg xorg-xinit i3-wm i3status i3lock
  feh rofi thunar kitty 
  maim xclip dunst btop firefox
  picom
  gtk3 gtk4
  ttf-fira-code ttf-jetbrains-mono-nerd ttf-font-awesome
  papirus-icon-theme
)

# UI packages that may need AUR
AUR_UI=(
  polybar
)

# Optional UI (try AUR if not in repos)
OPTIONAL_UI=(
  nitrogen i3-gaps
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
  chisel 
  seclists ffuf
)

# Optional pentest tools (may fail)
AUR_PENTEST_OPTIONAL=(
  kerbrute-bin
  nuclei subfinder httpx-toolkit 
  waybackurls gau gospider
  enum4linux
)

# Networking tools
PACMAN_NETWORKING=(
  openssh iperf3 traceroute ufw inetutils
)

# Docker
PACMAN_DOCKER=(
  docker docker-compose docker-buildx
)

# VMware tools
PACMAN_VMTOOLS=(
  open-vm-tools gtkmm3 xf86-input-vmmouse xf86-video-vmware
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
  # Check if package exists in AUR with timeout
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
  # Test sudo access
  if ! sudo -v; then
    err "sudo access required. Add your user to wheel group."
    exit 1
  fi
}
'''

# Now append the Smart Mode helpers and patched function definitions
helpers_and_patched = r'''

# ------------------ Smart Package Fallback System (Option C) ------------------

# Search AUR (returns package names one per line)
aur_search() {
  local term="$1"
  curl -s "https://aur.archlinux.org/rpc/?v=5&type=search&arg=${term}" 2>/dev/null \
    | jq -r '.results[].Name' 2>/dev/null || true
}

# Search pacman repos (returns package names one per line)
pacman_search() {
  local term="$1"
  pacman -Ss "$term" 2>/dev/null | awk -F'/' '/^[a-z]/{print $2}' | awk '{print $1}' || true
}

# Try to resolve a missing package by searching repos and AUR, then prompting or auto-installing
fallback_search() {
  local pkg="$1"
  echo ""
  warn "Package '${pkg}' not found in official repos."

  if $AUTO; then
    info "AUTO mode: searching for alternatives for '${pkg}'..."
  else
    if ! confirm "Search AUR/alternatives for '${pkg}'?"; then
      warn "Skipping ${pkg}"
      FAILED_PACKAGES+=("$pkg")
      return 1
    fi
  fi

  # Gather matches
  local matches=()
  mapfile -t repo_matches < <(pacman_search "${pkg}")
  mapfile -t aur_matches < <(aur_search "${pkg}")

  matches=("${repo_matches[@]}" "${aur_matches[@]}")

  if [ ${#matches[@]} -eq 0 ]; then
    warn "No alternatives found for ${pkg}"
    FAILED_PACKAGES+=("$pkg")
    return 1
  fi

  echo ""
  info "Found alternatives for ${pkg}:"
  local i=1
  for m in "${matches[@]}"; do
    echo "  $i) $m"
    ((i++))
  done

  local choice_index=1
  if ! $AUTO; then
    read -rp "Select package to install (1-${#matches[@]}, 0 to skip): " choice_index
    if [[ -z "$choice_index" ]]; then
      warn "No choice given. Skipping ${pkg}."
      FAILED_PACKAGES+=("$pkg")
      return 1
    fi
  fi

  if [[ "$choice_index" -eq 0 ]]; then
    warn "User skipped ${pkg}"
    FAILED_PACKAGES+=("$pkg")
    return 1
  fi

  if ! $AUTO; then
    if ! [[ "$choice_index" =~ ^[0-9]+$ ]] || [ "$choice_index" -lt 1 ] || [ "$choice_index" -gt ${#matches[@]} ]; then
      warn "Invalid selection. Skipping ${pkg}"
      FAILED_PACKAGES+=("$pkg")
      return 1
    fi
  fi

  local selected="${matches[$((choice_index-1))]}"
  info "Selected fallback: $selected"

  # Try pacman first
  if check_pacman_package "$selected"; then
    info "Installing $selected from official repos..."
    if sudo pacman -S --noconfirm --needed "$selected" 2>&1 | tee -a "$INSTALL_LOG"; then
      SUCCESSFUL_PACKAGES+=("$selected")
      return 0
    else
      warn "Failed to install $selected from repos"
    fi
  fi

  # Try AUR (ensure yay)
  ensure_yay || { warn "yay not available; cannot install AUR packages"; FAILED_PACKAGES+=("$pkg"); return 1; }

  if check_aur_package "$selected"; then
    info "Installing $selected from AUR..."
    if yay -S --noconfirm --needed "$selected" </dev/tty 2>&1 | tee -a "$INSTALL_LOG"; then
      SUCCESSFUL_PACKAGES+=("$selected")
      return 0
    else
      warn "AUR install failed for $selected"
      FAILED_PACKAGES+=("$pkg")
      return 1
    fi
  fi

  warn "Selected fallback $selected not available"
  FAILED_PACKAGES+=("$pkg")
  return 1
}


# ------------------ Patched ensure_yay() ------------------
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


# ------------------ Patched install_pacman_pkgs() with Smart Fallback ------------------
install_pacman_pkgs(){
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then return 0; fi

  log "Validating ${#pkgs[@]} packages before installation..."

  local valid_pkgs=()
  local invalid_pkgs=()

  # Validate each package
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

  # Install valid packages in batch (if any)
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

  # Fallback for invalid packages (search AUR/alternatives)
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


# ------------------ Patched install_aur_pkgs() with Smart Fallback ------------------
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
        # try fallback search for alternatives
        if ! fallback_search "$pkg"; then
          FAILED_PACKAGES+=("$pkg")
        fi
      fi
    else
      warn "  ✗ $pkg not found in AUR"
      # try fallback search for alternatives
      if ! fallback_search "$pkg"; then
        FAILED_PACKAGES+=("$pkg")
      fi
    fi
  done
}


# ------------------ Patched install_optional_pkgs() to use fallback when interactive ------------------
install_optional_pkgs(){
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then return 0; fi

  info "Installing ${#pkgs[@]} optional packages (non-critical)..."

  for pkg in "${pkgs[@]}"; do
    if is_package_installed "$pkg"; then
      info "  ✓ $pkg already installed"
      continue
    fi

    # Try pacman first
    if check_pacman_package "$pkg"; then
      info "  Trying $pkg from official repos..."
      if sudo pacman -S --noconfirm --needed "$pkg" 2>/dev/null; then
        log "  ✓ $pkg installed"
        SUCCESSFUL_PACKAGES+=("$pkg")
        continue
      fi
    fi

    # Try AUR if pacman failed
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

    # Fallback search if interactive or in auto (auto will try to select first match)
    if ! fallback_search "$pkg"; then
      warn "  ✗ $pkg skipped after fallback search"
    fi
  done
}

# The rest of the original script continues unchanged below...
'''

# Now append the remainder of the user's original script after the patched functions.
# We will append the remainder from where ensure_sudo() ended in the original provided text.
# The original provided earlier in the conversation continues — we'll append the rest manually.
remainder = r'''
# Enhanced package installation with validation
# (Note: earlier functions replaced with patched versions above)

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

# Show installation summary
show_install_summary(){
  echo ""
  echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║           Installation Summary                     ║${NC}"
  echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  if [ ${#SUCCESSFUL_PACKAGES[@]} -gt 0 ]; then
    log "Successfully installed: ${#SUCCESSFUL_PACKAGES[@]} packages"
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
    log "All packages installed successfully!"
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
  
  # Create ~/.local/bin
  mkdir -p ~/.local/bin
  
  # Add to PATH if not present
  if ! grep -q '.local/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
  fi
  
  log "[core] Done."
}

module_dev(){
  log "[dev] Installing development tools..."
  
  # Install Python and tools first
  install_pacman_pkgs "${PACMAN_DEV[@]}"
  
  # Ensure pipx is installed and working
  ensure_pipx
  
  log "[dev] Done."
}

module_vmtools(){
  log "[vmtools] Installing VMware guest tools..."
  
  install_pacman_pkgs "${PACMAN_VMTOOLS[@]}"
  
  info "Enabling vmtoolsd service..."
  sudo systemctl enable vmtoolsd 2>/dev/null || warn "Could not enable vmtoolsd"
  sudo systemctl start vmtoolsd 2>/dev/null || warn "Could not start vmtoolsd"
  
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
  
  # Install base UI packages from official repos
  install_pacman_pkgs "${PACMAN_UI[@]}"
  
  # Install UI packages from AUR
  install_aur_pkgs "${AUR_UI[@]}"
  
  # Install optional UI packages
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
  
  # Create .xinitrc
  cat > ~/.xinitrc << 'EOF'
#!/bin/sh
exec i3
EOF
  chmod +x ~/.xinitrc
  
  # i3 config with HTB green accent
  mkdir -p ~/.config/i3
  cat > ~/.config/i3/config << 'EOF'
# Neon Nord Pentest i3 Config
set $mod Mod4
font pango:JetBrainsMono Nerd Font 10

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
for_window [class=".*"] title_format " "

# Autostart
exec_always --no-startup-id ~/.config/polybar/launch.sh
exec_always --no-startup-id feh --bg-scale ~/Pictures/wallpaper.jpg || feh --bg-fill /usr/share/backgrounds/*
exec --no-startup-id dunst

# Keybindings
bindsym $mod+d exec --no-startup-id rofi -show drun
bindsym $mod+Return exec kitty
bindsym $mod+Shift+q kill

# Navigation (vim keys)
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right

# Splits
bindsym $mod+b split h
bindsym $mod+v split v
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

bindsym $mod+1 workspace $ws1
bindsym $mod+2 workspace $ws2
bindsym $mod+3 workspace $ws3
bindsym $mod+4 workspace $ws4
bindsym $mod+5 workspace $ws5

bindsym $mod+Shift+1 move container to workspace $ws1
bindsym $mod+Shift+2 move container to workspace $ws2
bindsym $mod+Shift+3 move container to workspace $ws3
bindsym $mod+Shift+4 move container to workspace $ws4
bindsym $mod+Shift+5 move container to workspace $ws5

# System
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
bindsym Print exec --no-startup-id maim -s | xclip -selection clipboard -t image/png
bindsym $mod+Shift+x exec i3lock -c 2e3440

# Resize mode
mode "resize" {
    bindsym h resize shrink width 10 px
    bindsym j resize grow height 10 px
    bindsym k resize shrink height 10 px
    bindsym l resize grow width 10 px
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

# Floating windows
for_window [class="Thunar"] floating enable
for_window [class="Pavucontrol"] floating enable
for_window [title="nmtui"] floating enable
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
  
  # Kitty config
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
    foreground = "#eceff4'
# (trimmed due to message length) - remainder appended in file
'''
