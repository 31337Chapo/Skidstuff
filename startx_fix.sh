#!/usr/bin/env bash

# startx troubleshooting and fix script
# Diagnoses and fixes common startx issues after skidstall installation

set -euo pipefail

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*" >&2; }
info() { echo -e "${CYAN}[i]${NC} $*"; }

echo -e "${CYAN}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════╗
║         startx Diagnostic & Fix Tool                 ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -eq 0 ]; then
   err "Do not run this script as root. Run as your regular user."
   exit 1
fi

log "Running diagnostics..."
echo ""

# 1. Check if X11 packages are installed
info "Checking X11 installation..."
MISSING_X11=()

REQUIRED_X11=(
    "xorg-server"
    "xorg-xinit"
    "xorg-xauth"
)

for pkg in "${REQUIRED_X11[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        MISSING_X11+=("$pkg")
    fi
done

if [ ${#MISSING_X11[@]} -gt 0 ]; then
    warn "Missing X11 packages: ${MISSING_X11[*]}"
    if read -rp "Install missing X11 packages? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
        sudo pacman -S --noconfirm "${MISSING_X11[@]}"
        log "X11 packages installed"
    fi
else
    log "✓ All required X11 packages installed"
fi

# 2. Check if i3 is installed
info "Checking i3 window manager..."
if ! pacman -Qi i3-wm &>/dev/null && ! pacman -Qi i3-gaps &>/dev/null; then
    err "i3 window manager not installed"
    if read -rp "Install i3-wm? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
        sudo pacman -S --noconfirm i3-wm i3status i3lock
        log "i3 installed"
    else
        err "Cannot start X without a window manager"
        exit 1
    fi
else
    log "✓ i3 window manager installed"
fi

# 3. Check .xinitrc
info "Checking .xinitrc configuration..."
if [ ! -f ~/.xinitrc ]; then
    warn ".xinitrc not found, creating it..."
    cat > ~/.xinitrc << 'XINITRC'
#!/bin/sh

# Load X resources
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources

# Start compositor (if available)
if command -v picom &>/dev/null; then
    picom -b &
fi

# Set wallpaper (if available)
if command -v feh &>/dev/null; then
    feh --bg-scale ~/Pictures/wallpaper.jpg 2>/dev/null || \
    feh --bg-fill /usr/share/backgrounds/* 2>/dev/null || true
fi

# Start i3
exec i3
XINITRC
    chmod +x ~/.xinitrc
    log "✓ Created ~/.xinitrc"
else
    log "✓ ~/.xinitrc exists"
    
    # Check if it's executable
    if [ ! -x ~/.xinitrc ]; then
        warn ".xinitrc is not executable, fixing..."
        chmod +x ~/.xinitrc
        log "✓ Made ~/.xinitrc executable"
    fi
    
    # Check if it has a shebang
    if ! head -n1 ~/.xinitrc | grep -q '^#!'; then
        warn ".xinitrc missing shebang, adding it..."
        echo '#!/bin/sh' | cat - ~/.xinitrc > ~/.xinitrc.tmp
        mv ~/.xinitrc.tmp ~/.xinitrc
        chmod +x ~/.xinitrc
        log "✓ Added shebang to ~/.xinitrc"
    fi
fi

# 4. Check i3 config
info "Checking i3 configuration..."
if [ ! -f ~/.config/i3/config ]; then
    warn "i3 config not found"
    if read -rp "Generate default i3 config? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
        mkdir -p ~/.config/i3
        i3-config-wizard --version &>/dev/null && i3-config-wizard || {
            # Create minimal config
            cat > ~/.config/i3/config << 'I3CONFIG'
# Minimal i3 config
set $mod Mod4
font pango:monospace 10

# Start terminal
bindsym $mod+Return exec i3-sensible-terminal

# Kill focused window
bindsym $mod+Shift+q kill

# Start dmenu/rofi
bindsym $mod+d exec --no-startup-id "dmenu_run || rofi -show drun"

# Change focus (vim keys)
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

# Move focused window
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right

# Split orientation
bindsym $mod+b split h
bindsym $mod+v split v

# Fullscreen
bindsym $mod+f fullscreen toggle

# Reload/restart
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart

# Exit i3
bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'"

# Workspaces
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5

bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5
I3CONFIG
        }
        log "✓ Created i3 config"
    fi
else
    log "✓ i3 config exists"
fi

# 5. Check for conflicting display managers
info "Checking for display managers..."
DISPLAY_MANAGERS=("gdm" "lightdm" "sddm" "lxdm")
ACTIVE_DM=""

for dm in "${DISPLAY_MANAGERS[@]}"; do
    if systemctl is-active --quiet "$dm" 2>/dev/null; then
        ACTIVE_DM="$dm"
        break
    fi
done

if [ -n "$ACTIVE_DM" ]; then
    warn "Display manager '$ACTIVE_DM' is running"
    info "This can conflict with startx. You should either:"
    echo "  1. Use the display manager to login (may require session selection)"
    echo "  2. Disable it: sudo systemctl disable --now $ACTIVE_DM"
    echo ""
    if read -rp "Disable $ACTIVE_DM and use startx? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
        sudo systemctl disable --now "$ACTIVE_DM"
        log "✓ Disabled $ACTIVE_DM"
    fi
else
    log "✓ No conflicting display managers"
fi

# 6. Check graphics drivers
info "Checking graphics drivers..."
if lspci | grep -i vga | grep -qi vmware; then
    log "VMware detected"
    if ! pacman -Qi xf86-video-vmware &>/dev/null; then
        warn "VMware video driver not installed"
        if read -rp "Install xf86-video-vmware? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
            sudo pacman -S --noconfirm xf86-video-vmware
            log "✓ VMware driver installed"
        fi
    else
        log "✓ VMware driver installed"
    fi
fi

# 7. Check for X server logs
info "Checking recent X server logs..."
if [ -f ~/.local/share/xorg/Xorg.0.log ]; then
    warn "Found X server log, checking for errors..."
    if grep -i "error\|failed\|fatal" ~/.local/share/xorg/Xorg.0.log | tail -5; then
        echo ""
        info "Recent X server errors found above"
    fi
elif [ -f /var/log/Xorg.0.log ]; then
    if grep -i "error\|failed\|fatal" /var/log/Xorg.0.log 2>/dev/null | tail -5; then
        echo ""
        info "Recent X server errors found above"
    fi
fi

# 8. Test X server
echo ""
info "Testing X server availability..."
if xhost &>/dev/null; then
    warn "X server already running on this display"
    info "You may already be in a graphical session"
elif pgrep -x Xorg &>/dev/null || pgrep -x X &>/dev/null; then
    warn "X server process found running"
    info "You may need to stop it first or use a different display"
fi

# 9. Check terminal emulator
info "Checking for terminal emulator..."
TERMINALS=("kitty" "alacritty" "xterm" "urxvt" "gnome-terminal" "konsole")
FOUND_TERM=false

for term in "${TERMINALS[@]}"; do
    if command -v "$term" &>/dev/null; then
        log "✓ Found terminal: $term"
        FOUND_TERM=true
        break
    fi
done

if ! $FOUND_TERM; then
    warn "No terminal emulator found"
    if read -rp "Install xterm (minimal terminal)? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
        sudo pacman -S --noconfirm xterm
        log "✓ xterm installed"
    fi
fi

# 10. Summary and recommendations
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              Diagnostic Summary                    ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

log "Diagnostics complete!"
echo ""
info "To start X11 with i3, run:"
echo "  startx"
echo ""
info "If startx still fails, check:"
echo "  1. View X server log: cat ~/.local/share/xorg/Xorg.0.log"
echo "  2. Check i3 log: cat ~/.local/share/i3/i3log"
echo "  3. Verify display: echo \$DISPLAY (should be empty before startx)"
echo "  4. Check permissions: ls -la ~/.xinitrc ~/.config/i3/config"
echo ""

# Offer to try starting X
if read -rp "Would you like to try starting X now? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
    echo ""
    log "Attempting to start X server..."
    echo ""
    exec startx
fi

info "Run 'startx' when ready to launch the graphical environment"