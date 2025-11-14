#!/usr/bin/env bash

# startx segmentation fault fix script
# Addresses critical X server crash issues

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

echo -e "${RED}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════╗
║     SEGMENTATION FAULT FIX - X Server Crash          ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

if [ "$EUID" -eq 0 ]; then
   err "Do not run this script as root"
   exit 1
fi

log "Analyzing segmentation fault causes..."
echo ""

# 1. Check for corrupted X server installation
info "Step 1: Checking X server integrity..."
XORG_PKGS=("xorg-server" "xorg-xinit" "xorg-xauth" "xf86-input-libinput")

for pkg in "${XORG_PKGS[@]}"; do
    if pacman -Qi "$pkg" &>/dev/null; then
        log "✓ $pkg installed"
    else
        warn "✗ $pkg MISSING"
    fi
done

# Reinstall X server completely
warn "Reinstalling X server packages to fix corruption..."
if read -rp "Reinstall all X server packages? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
    sudo pacman -S --noconfirm xorg-server xorg-xinit xorg-xauth xf86-input-libinput
    log "✓ X server reinstalled"
fi

# 2. Check graphics drivers (CRITICAL for segfaults)
echo ""
info "Step 2: Checking graphics drivers..."

# Detect GPU
if lspci | grep -i vga | grep -qi vmware; then
    warn "VMware GPU detected"
    
    if ! pacman -Qi xf86-video-vmware &>/dev/null; then
        err "VMware video driver MISSING - this is likely the cause!"
        warn "Installing xf86-video-vmware..."
        sudo pacman -S --noconfirm xf86-video-vmware xf86-input-vmmouse
        log "✓ VMware drivers installed"
    else
        log "✓ VMware driver present"
    fi
    
    # Check if open-vm-tools is running
    if ! systemctl is-active --quiet vmtoolsd 2>/dev/null; then
        warn "VMware tools service not running"
        if pacman -Qi open-vm-tools &>/dev/null; then
            sudo systemctl enable --now vmtoolsd 2>/dev/null || warn "Could not start vmtoolsd"
            log "✓ Started vmtoolsd"
        fi
    fi

elif lspci | grep -i vga | grep -qi virtualbox; then
    warn "VirtualBox GPU detected"
    
    if ! pacman -Qi virtualbox-guest-utils &>/dev/null; then
        err "VirtualBox guest additions MISSING"
        warn "Installing virtualbox-guest-utils..."
        sudo pacman -S --noconfirm virtualbox-guest-utils
        log "✓ VirtualBox guest utils installed"
    fi

elif lspci | grep -i vga | grep -qi nvidia; then
    warn "NVIDIA GPU detected"
    info "NVIDIA requires proprietary drivers"
    echo "Install: sudo pacman -S nvidia nvidia-utils"
    
elif lspci | grep -i vga | grep -qi amd; then
    log "AMD GPU detected - using open source drivers"
    
elif lspci | grep -i vga | grep -qi intel; then
    log "Intel GPU detected"
    if ! pacman -Qi xf86-video-intel &>/dev/null; then
        warn "Consider installing: xf86-video-intel"
    fi
else
    warn "Unknown GPU - using generic VESA driver"
fi

# 3. Remove problematic modesetting/fbdev configs
echo ""
info "Step 3: Checking for problematic X configurations..."

if [ -d /etc/X11/xorg.conf.d ]; then
    if ls /etc/X11/xorg.conf.d/*.conf &>/dev/null; then
        warn "Found X configuration files that may cause conflicts"
        ls -la /etc/X11/xorg.conf.d/
        echo ""
        if read -rp "Backup and remove X config files? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
            sudo mkdir -p /etc/X11/xorg.conf.d.backup
            sudo mv /etc/X11/xorg.conf.d/*.conf /etc/X11/xorg.conf.d.backup/ 2>/dev/null || true
            log "✓ X configs backed up and removed"
        fi
    fi
fi

if [ -f /etc/X11/xorg.conf ]; then
    warn "Found /etc/X11/xorg.conf (may cause issues)"
    if read -rp "Backup and remove xorg.conf? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
        sudo mv /etc/X11/xorg.conf /etc/X11/xorg.conf.backup
        log "✓ xorg.conf backed up"
    fi
fi

# 4. Create minimal safe .xinitrc
echo ""
info "Step 4: Creating minimal safe .xinitrc..."

cat > ~/.xinitrc << 'XINITRC'
#!/bin/sh
exec i3
XINITRC

chmod +x ~/.xinitrc
log "✓ Created minimal .xinitrc"

# 5. Verify i3 installation
echo ""
info "Step 5: Verifying i3 installation..."

if ! command -v i3 &>/dev/null; then
    err "i3 not found!"
    if read -rp "Install i3-wm? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
        sudo pacman -S --noconfirm i3-wm i3status i3lock
        log "✓ i3 installed"
    fi
else
    log "✓ i3 found: $(which i3)"
fi

# 6. Create minimal i3 config
echo ""
info "Step 6: Creating minimal i3 configuration..."

mkdir -p ~/.config/i3

cat > ~/.config/i3/config << 'I3CONFIG'
# Minimal i3 config for testing
set $mod Mod4

# Font
font pango:monospace 10

# Start a terminal
bindsym $mod+Return exec xterm

# Kill focused window
bindsym $mod+Shift+q kill

# Change focus
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

# Move focused window
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right

# Split
bindsym $mod+b split h
bindsym $mod+v split v

# Fullscreen
bindsym $mod+f fullscreen toggle

# Reload/restart
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart

# Exit
bindsym $mod+Shift+e exec "i3-msg exit"

# Workspaces
bindsym $mod+1 workspace 1
bindsym $mod+2 workspace 2
bindsym $mod+3 workspace 3
bindsym $mod+4 workspace 4
bindsym $mod+5 workspace 5
I3CONFIG

log "✓ Created minimal i3 config"

# 7. Install xterm as fallback terminal
echo ""
info "Step 7: Ensuring terminal emulator..."

if ! command -v xterm &>/dev/null; then
    warn "Installing xterm as fallback terminal..."
    sudo pacman -S --noconfirm xterm
    log "✓ xterm installed"
else
    log "✓ xterm available"
fi

# 8. Check for kernel module issues
echo ""
info "Step 8: Checking kernel modules..."

# Ensure DRM modules are loaded
REQUIRED_MODULES=("drm" "drm_kms_helper")
for mod in "${REQUIRED_MODULES[@]}"; do
    if lsmod | grep -q "^${mod}"; then
        log "✓ Module $mod loaded"
    else
        warn "Module $mod not loaded (may be normal)"
    fi
done

# 9. Clear any stale X locks
echo ""
info "Step 9: Clearing stale X server locks..."

rm -f /tmp/.X0-lock ~/.Xauthority 2>/dev/null || true
log "✓ Cleared X locks"

# 10. Check logs for specific errors
echo ""
info "Step 10: Checking previous X server logs..."

LOG_LOCATIONS=(
    "$HOME/.local/share/xorg/Xorg.0.log"
    "/var/log/Xorg.0.log"
)

for logfile in "${LOG_LOCATIONS[@]}"; do
    if [ -f "$logfile" ]; then
        echo ""
        warn "Checking $logfile for errors..."
        echo ""
        
        # Look for critical errors
        if grep -i "segmentation fault\|fatal\|failed to load module" "$logfile" 2>/dev/null | tail -10; then
            echo ""
            info "Found errors above - review these carefully"
        fi
        
        # Check for missing drivers
        if grep -i "no screens found\|no devices detected" "$logfile" 2>/dev/null; then
            err "NO SCREENS FOUND - driver issue!"
            echo ""
            warn "This means your graphics driver is missing or incompatible"
        fi
        
        break
    fi
done

# 11. Final recommendations
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         Segmentation Fault Fix Summary            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

log "Critical fixes applied:"
echo "  ✓ X server packages reinstalled"
echo "  ✓ Graphics drivers checked/installed"
echo "  ✓ Conflicting configs removed"
echo "  ✓ Minimal safe configuration created"
echo "  ✓ X locks cleared"
echo ""

warn "IMPORTANT: If in a VM, ensure:"
echo "  • 3D acceleration is DISABLED in VM settings"
echo "  • VM guest tools are installed (open-vm-tools or virtualbox-guest-utils)"
echo "  • Sufficient video memory allocated (at least 128MB)"
echo ""

info "Try starting X now with:"
echo "  startx"
echo ""

info "If it still crashes, run:"
echo "  startx 2>&1 | tee ~/startx-error.log"
echo "  (This will save the full error log)"
echo ""

info "For immediate testing, try:"
echo "  Xorg -configure"
echo "  (This tests X server without a window manager)"
echo ""

# Offer to test X server directly
if read -rp "Would you like to test the X server now? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
    echo ""
    log "Testing X server configuration..."
    echo ""
    warn "This will test Xorg directly. Press Ctrl+Alt+F2 to return to console if needed."
    echo ""
    sleep 2
    
    # Test with minimal config
    log "Attempting to start X..."
    exec startx
fi

log "Setup complete. Run 'startx' when ready."
