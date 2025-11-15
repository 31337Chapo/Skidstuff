#!/usr/bin/env bash

# Theme Setup Helper - Get Archcraft-style look
# Run this after installing the UI module

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

echo -e "${CYAN}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════╗
║         Archcraft-Style Theme Setup                   ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log "Setting up Archcraft-inspired theme..."
echo ""

# 1. Download cool wallpapers
log "Downloading wallpapers..."
mkdir -p ~/Pictures/wallpapers

WALLPAPERS=(
  "https://raw.githubusercontent.com/archcraft-os/archcraft-wallpapers/main/nord/nord-01.jpg"
  "https://raw.githubusercontent.com/archcraft-os/archcraft-wallpapers/main/nord/nord-02.jpg"
  "https://raw.githubusercontent.com/archcraft-os/archcraft-wallpapers/main/nord/nord-03.jpg"
)

for wall in "${WALLPAPERS[@]}"; do
  filename=$(basename "$wall")
  if ! [ -f ~/Pictures/wallpapers/"$filename" ]; then
    info "Downloading $filename..."
    curl -fsSL "$wall" -o ~/Pictures/wallpapers/"$filename" 2>/dev/null || warn "Failed to download $filename"
  fi
done

# Use first wallpaper as default
if [ -f ~/Pictures/wallpapers/nord-01.jpg ]; then
  ln -sf ~/Pictures/wallpapers/nord-01.jpg ~/Pictures/wallpaper.jpg
  log "Set default wallpaper"
fi

# 2. Initialize pywal
if command -v wal &>/dev/null; then
  log "Initializing pywal with wallpaper..."
  wal -i ~/Pictures/wallpaper.jpg -n 2>/dev/null && log "pywal initialized" || warn "pywal init failed"
else
  warn "pywal not installed - run: sudo pacman -S python-pywal"
fi

# 3. Update polybar to use pywal colors
log "Updating polybar for pywal..."
mkdir -p ~/.config/polybar

cat > ~/.config/polybar/config.ini << 'EOF'
[colors]
background = ${xrdb:color0:#2e3440}
background-alt = ${xrdb:color1:#3b4252}
foreground = ${xrdb:color7:#eceff4}
primary = #9fef00
secondary = ${xrdb:color6:#88c0d0}
alert = ${xrdb:color1:#bf616a}
disabled = ${xrdb:color8:#4c566a}

[bar/main]
width = 100%
height = 30
background = ${colors.background}
foreground = ${colors.foreground}
line-size = 3
padding = 2
module-margin = 1
separator = |
separator-foreground = ${colors.disabled}
font-0 = JetBrainsMono Nerd Font:size=10;2
font-1 = Font Awesome 6 Free:style=Solid:size=10;2
modules-left = xworkspaces xwindow
modules-center = date
modules-right = pulseaudio memory cpu wlan eth battery
cursor-click = pointer
bottom = false

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
label = %title:0:50:...%
label-foreground = ${colors.secondary}

[module/filesystem]
type = internal/fs
mount-0 = /
label-mounted = %{F#9fef00} %{F-} %percentage_used%%
label-unmounted = %mountpoint% not mounted
label-unmounted-foreground = ${colors.disabled}

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <ramp-volume> <label-volume>
label-volume = %percentage%%
label-volume-foreground = ${colors.foreground}
label-muted =  muted
label-muted-foreground = ${colors.disabled}
ramp-volume-0 = 
ramp-volume-1 = 
ramp-volume-2 = 
ramp-volume-foreground = ${colors.primary}

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.primary}
label = %percentage_used:2%%

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.primary}
label = %percentage:2%%

[module/wlan]
type = internal/network
interface-type = wireless
interval = 3.0
format-connected = <label-connected>
label-connected =  %essid%
format-disconnected = <label-disconnected>
label-disconnected = 
label-disconnected-foreground = ${colors.disabled}

[module/eth]
type = internal/network
interface-type = wired
interval = 3.0
format-connected = <label-connected>
label-connected =  
format-disconnected = <label-disconnected>
label-disconnected = 

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
full-at = 98
format-charging = <animation-charging> <label-charging>
label-charging = %percentage%%
format-discharging = <ramp-capacity> <label-discharging>
label-discharging = %percentage%%
format-full = <label-full>
label-full =  %percentage%%
ramp-capacity-0 = 
ramp-capacity-1 = 
ramp-capacity-2 = 
ramp-capacity-3 = 
ramp-capacity-4 = 
animation-charging-0 = 
animation-charging-1 = 
animation-charging-2 = 
animation-charging-3 = 
animation-charging-4 = 
animation-charging-framerate = 750

[module/date]
type = internal/date
interval = 1
date = %a, %b %d
time = %H:%M
label =  %date%  %time%
label-foreground = ${colors.primary}

[settings]
screenchange-reload = true
pseudo-transparency = true
EOF

log "Polybar config updated with pywal support"

# 4. Create rofi theme with pywal
log "Creating rofi pywal theme..."
mkdir -p ~/.config/rofi

cat > ~/.config/rofi/config.rasi << 'EOF'
configuration {
    modi: "drun,run,window,ssh";
    show-icons: true;
    display-drun: "";
    display-run: "";
    display-window: "";
    display-ssh: "";
    icon-theme: "Papirus-Dark";
    font: "JetBrainsMono Nerd Font 10";
}

@theme "~/.cache/wal/colors-rofi-dark.rasi"
EOF

log "Rofi configured for pywal"

# 5. Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Theme Setup Complete!                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

log "Setup complete! Here's what changed:"
echo "  ✓ Downloaded Nord wallpapers"
echo "  ✓ Initialized pywal color scheme"
echo "  ✓ Updated polybar with pywal colors"
echo "  ✓ Configured rofi for pywal"
echo ""

info "Usage:"
echo "  1. Change wallpaper: wal -i ~/Pictures/wallpapers/nord-02.jpg"
echo "  2. Reload theme: wal-reload"
echo "  3. Restore theme: wal -R"
echo ""

info "Keybinds reminder:"
echo "  Mod+Return       → Terminal (Alacritty)"
echo "  Mod+Shift+Return → Kitty terminal"
echo "  Mod+d            → App launcher (Rofi)"
echo "  Mod+Shift+f      → File manager (Thunar)"
echo "  Mod+Shift+w      → Firefox"
echo ""

warn "To apply changes:"
echo "  1. Reload i3: Mod+Shift+r"
echo "  2. Or logout and run 'startx' again"
echo ""

log "Enjoy your themed setup! 🎨"
