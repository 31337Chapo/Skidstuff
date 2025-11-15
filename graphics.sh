#!/usr/bin/env bash

# VMware Graphics Driver Fix for Arch Linux
# xf86-video-vmware was removed from repos - use modern alternatives

set -euo pipefail

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
║       VMware Graphics Driver Setup (Modern)           ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log "Setting up VMware graphics for Arch Linux..."
echo ""

# Verify we're in VMware
if ! lspci | grep -qi vmware; then
    warn "VMware GPU not detected. Are you running in VMware?"
    lspci | grep -i vga
    echo ""
    if ! read -rp "Continue anyway? [y/N]: " ans || ! [[ "$ans" =~ ^[yY]$ ]]; then
        exit 0
    fi
fi

log "VMware detected"
echo ""

# ============================================================
# MODERN APPROACH: Use Mesa and open-vm-tools
# ============================================================

info "The xf86-video-vmware driver was deprecated and removed from Arch repos"
info "Modern Arch Linux uses these instead:"
echo ""
echo "  1. Mesa (open source graphics) - modesetting driver"
echo "  2. open-vm-tools (VMware guest utilities)"
echo "  3. No xf86-video-vmware needed!"
echo ""

log "Installing required packages..."

# Core packages
REQUIRED=(
    "mesa"                    # Modern graphics stack
    "xf86-input-libinput"    # Input handling
    "xorg-server"            # X server
    "xorg-xinit"             # startx command
    "xorg-xauth"             # X authentication
    "open-vm-tools"          # VMware tools
    "gtkmm3"                 # GTK for vmware tools
)

MISSING=()
for pkg in "${REQUIRED[@]}"; do
    if pacman -Qi "$pkg" &>/dev/null; then
        log "✓ $pkg"
    else
        warn "✗ $pkg missing"
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    log "Installing ${#MISSING[@]} missing packages..."
    sudo pacman -S --noconfirm "${MISSING[@]}"
    log "✓ Packages installed"
else
    log "✓ All packages already installed"
fi

# ============================================================
# ENABLE AND START VMWARE TOOLS
# ============================================================

echo ""
log "Configuring VMware tools..."

# Enable vmtoolsd service
if ! systemctl is-enabled vmtoolsd &>/dev/null; then
    sudo systemctl enable vmtoolsd
    log "✓ vmtoolsd enabled"
else
    log "✓ vmtoolsd already enabled"
fi

# Start vmtoolsd service
if ! systemctl is-active --quiet vmtoolsd; then
    sudo systemctl start vmtoolsd
    log "✓ vmtoolsd started"
else
    log "✓ vmtoolsd already running"
fi

# Enable vmware-vmblock-fuse (for drag & drop)
if ! systemctl is-enabled vmware-vmblock-fuse &>/dev/null; then
    sudo systemctl enable vmware-vmblock-fuse 2>/dev/null || true
fi

# ============================================================
# REMOVE OLD VMWARE DRIVER CONFIGS (if any)
# ============================================================

echo ""
log "Removing old xf86-video-vmware configurations..."

OLD_CONFIGS=(
    "/etc/X11/xorg.conf"
    "/etc/X11/xorg.conf.d/20-vmware.conf"
    "/usr/share/X11/xorg.conf.d/40-vmware.conf"
)

for conf in "${OLD_CONFIGS[@]}"; do
    if [ -f "$conf" ]; then
        warn "Found old config: $conf"
        sudo mv "$conf" "${conf}.backup-$(date +%s)" 2>/dev/null || true
        log "✓ Backed up and removed"
    fi
done

log "✓ Old configs cleared"

# ============================================================
# CONFIGURE XORG FOR VMWARE (MODESETTING)
# ============================================================

echo ""
log "Creating optimized X configuration for VMware..."

sudo mkdir -p /etc/X11/xorg.conf.d

# Create modesetting configuration
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

log "✓ Created /etc/X11/xorg.conf.d/20-modesetting.conf"

# ============================================================
# USER CONFIGURATION
# ============================================================

echo ""
log "Setting up user environment..."

# Create minimal .xinitrc
cat > ~/.xinitrc << 'EOF'
#!/bin/sh

# VMware-optimized .xinitrc

# Disable screen blanking
xset s off
xset -dpms

# Start window manager
exec i3
EOF

chmod +x ~/.xinitrc
log "✓ Created ~/.xinitrc"

# Ensure user is in video group
if ! groups | grep -q video; then
    warn "Adding user to video group..."
    sudo usermod -aG video "$USER"
    log "✓ Added to video group (log out/in for this to take effect)"
fi

# ============================================================
# VERIFY INSTALLATION
# ============================================================

echo ""
log "Verifying installation..."

# Check kernel modules
info "Checking kernel modules..."
MODULES=("vmwgfx" "drm" "drm_kms_helper")
for mod in "${MODULES[@]}"; do
    if lsmod | grep -q "^${mod}"; then
        log "✓ Module loaded: $mod"
    else
        info "  Module not yet loaded: $mod (will load on X start)"
    fi
done

# Check vmware tools
if systemctl is-active --quiet vmtoolsd; then
    log "✓ VMware tools running"
    vmware-toolbox-cmd -v 2>/dev/null || true
else
    warn "VMware tools not running"
fi

# ============================================================
# VMWARE SETTINGS RECOMMENDATIONS
# ============================================================

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║        CRITICAL VMware Settings                    ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${NC}"
echo ""

warn "In VMware Workstation/Fusion settings, configure:"
echo ""
echo "  1. Display:"
echo "     • 3D Acceleration: DISABLED (important!)"
echo "     • Video Memory: 128 MB or higher"
echo "     • Monitor: 1920x1080 or your preferred resolution"
echo ""
echo "  2. VM Settings:"
echo "     • RAM: At least 4GB recommended"
echo "     • Processors: 2+ cores"
echo ""
echo "  3. After changing settings: RESTART the VM"
echo ""

# ============================================================
# INSTALLATION SUMMARY
# ============================================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Installation Complete!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

log "Modern VMware graphics configured:"
echo "  ✓ Mesa (modesetting driver)"
echo "  ✓ open-vm-tools"
echo "  ✓ Optimized X configuration"
echo "  ✓ User environment ready"
echo ""

info "What changed from old setup:"
echo "  • xf86-video-vmware → modesetting (Mesa)"
echo "  • Better performance with modern drivers"
echo "  • Improved compatibility"
echo ""

warn "Next steps:"
echo ""
echo "  1. DISABLE 3D acceleration in VM settings"
echo "  2. Restart the VM"
echo "  3. Log out and log back in (for group changes)"
echo "  4. From text console (Ctrl+Alt+F2), run: startx"
echo ""

info "To test without restarting:"
echo "  startx -- -logverbose 6"
echo ""

info "If X still fails, check logs:"
echo "  ~/.local/share/xorg/Xorg.0.log"
echo ""

# ============================================================
# OPTIONAL: Install window manager and tools
# ============================================================

echo ""
if ! command -v i3 &>/dev/null; then
    warn "i3 window manager not installed"
    if read -rp "Install i3 and essential tools now? [y/N]: " ans && [[ "$ans" =~ ^[yY]$ ]]; then
        log "Installing i3 and tools..."
        sudo pacman -S --noconfirm i3-wm i3status i3lock xterm
        log "✓ i3 installed"
    fi
fi

echo ""
log "Setup complete! Follow the next steps above to start X."
