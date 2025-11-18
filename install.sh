#!/bin/bash

# Arch Linux Rice Auto-Installer
# Green/Purple Cyberpunk Theme
# Simplified and tested

set -e

GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════╗
║   Arch Linux Rice Installer               ║
║   Green/Purple Cyberpunk Theme            ║
╚═══════════════════════════════════════════╝
EOF
echo -e "${NC}"

if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}Don't run as root! Run as your regular user.${NC}"
    exit 1
fi

echo -e "${GREEN}[1/10] Updating system...${NC}"
sudo pacman -Syu --noconfirm

if ! command -v yay &> /dev/null; then
    echo -e "${GREEN}[2/10] Installing yay...${NC}"
    cd /tmp
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
else
    echo -e "${GREEN}[2/10] yay already installed${NC}"
fi

echo -e "${GREEN}[3/10] Installing packages...${NC}"
sudo pacman -S --needed --noconfirm \
    i3-wm \
    polybar \
    rofi \
    picom \
    alacritty \
    thunar \
    file-roller \
    feh \
    fastfetch \
    btop \
    firefox \
    pavucontrol \
    flameshot \
    xclip \
    lxappearance \
    papirus-icon-theme \
    ttf-fira-code \
    ttf-font-awesome \
    noto-fonts \
    zsh \
    zsh-syntax-highlighting

echo -e "${GREEN}[4/10] Installing VMware tools...${NC}"
sudo pacman -S --needed --noconfirm open-vm-tools gtkmm3 || true
sudo systemctl enable vmtoolsd 2>/dev/null || true
sudo systemctl start vmtoolsd 2>/dev/null || true

echo -e "${GREEN}[5/10] Creating directories...${NC}"
mkdir -p ~/.config/{i3,polybar,alacritty,rofi,picom,fastfetch}
mkdir -p ~/Pictures/Wallpapers

echo -e "${GREEN}[6/10] Downloading wallpapers...${NC}"
cd ~/Pictures/Wallpapers
if [ ! -d "walls" ]; then
    git clone https://github.com/dharmx/walls.git
    echo -e "${PURPLE}Wallpapers downloaded successfully!${NC}"
else
    echo -e "${PURPLE}Wallpapers already exist, skipping...${NC}"
fi

# Set a random wallpaper from the collection
WALLPAPER=$(find ~/Pictures/Wallpapers/walls -type f \( -name "*.jpg" -o -name "*.png" \) | shuf -n 1)
if [ -n "$WALLPAPER" ]; then
    feh --bg-fill "$WALLPAPER"
    echo -e "${PURPLE}Set random wallpaper: $WALLPAPER${NC}"
fi
cd ~

echo -e "${GREEN}[7/10] Installing i3 config...${NC}"
cat > ~/.config/i3/config << 'EOF'
set $mod Mod4

font pango:FiraCode Nerd Font 10

exec_always --no-startup-id killall picom; picom --config ~/.config/picom/picom.conf
exec_always --no-startup-id feh --bg-fill --randomize ~/Pictures/Wallpapers/walls/* 2>/dev/null || true
exec_always --no-startup-id polybar

# Float fastfetch window
for_window [title="fastfetch"] floating enable

# Run fastfetch on startup
exec --no-startup-id alacritty --title fastfetch -e fastfetch

gaps inner 10
gaps outer 5
smart_gaps on

default_border pixel 2
default_floating_border pixel 2
hide_edge_borders smart

set $bg-color            #0d0d0d
set $inactive-bg-color   #1a1a1a
set $text-color          #e0e0e0
set $inactive-text-color #6c6c6c
set $urgent-bg-color     #ff0055
set $accent-green        #00ff88
set $accent-purple       #b84dff

client.focused          $accent-green       $accent-green      $bg-color            $accent-green
client.unfocused        $inactive-bg-color  $inactive-bg-color $inactive-text-color $inactive-bg-color
client.focused_inactive $inactive-bg-color  $inactive-bg-color $inactive-text-color $inactive-bg-color
client.urgent           $urgent-bg-color    $urgent-bg-color   $text-color          $urgent-bg-color

floating_modifier $mod

bindsym $mod+Return exec alacritty
bindsym $mod+Shift+q kill
bindsym $mod+d exec rofi -show drun
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right
bindsym $mod+b split h
bindsym $mod+v split v
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle
bindsym $mod+space focus mode_toggle

set $ws1 "1"
set $ws2 "2"
set $ws3 "3"
set $ws4 "4"
set $ws5 "5"

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

bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
bindsym $mod+Shift+e exit

mode "resize" {
    bindsym h resize shrink width 10 px
    bindsym j resize grow height 10 px
    bindsym k resize shrink height 10 px
    bindsym l resize grow width 10 px
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

bindsym Print exec flameshot gui
bindsym $mod+Shift+f exec thunar
bindsym $mod+Shift+m exec alacritty -e btop
bindsym $mod+Shift+b exec firefox
EOF

echo -e "${GREEN}[8/10] Installing other configs...${NC}"

cat > ~/.config/picom/picom.conf << 'EOF'
backend = "glx";
vsync = true;

# Remove all shadow/glow settings
shadow = false;

fading = false;

# Transparency
inactive-opacity = 1.0;
active-opacity = 1.0;
frame-opacity = 1.0;
inactive-opacity-override = false;

# Opacity rules
opacity-rule = [
  "50:class_g = 'Alacritty'",
  "90:class_g = 'Thunar'"
];

# Background blur - INCREASED strength
blur-background = true;
blur-method = "kernel";
blur-size = 16;
blur-deviation = 8.0;
blur-kern = "15x15gaussian";
blur-background-fixed = false;
blur-background-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'",
  "class_g = 'Polybar'",
  "class_g = 'i3-frame'"
];

corner-radius = 0;
detect-rounded-corners = true;
detect-client-opacity = true;
use-damage = true;
EOF

cat > ~/.config/polybar/config.ini << 'EOF'
[colors]
background = #0d0d0d
foreground = #e0e0e0
primary = #00ff88
secondary = #b84dff

[bar/main]
width = 100%
height = 28
background = ${colors.background}
foreground = ${colors.foreground}
padding = 1
module-margin = 1

font-0 = FiraCode Nerd Font:size=10;2

modules-left = i3
modules-center = date
modules-right = memory cpu

[module/i3]
type = internal/i3
label-focused = %index%
label-focused-background = ${colors.primary}
label-focused-foreground = ${colors.background}
label-focused-padding = 1
label-unfocused = %index%
label-unfocused-padding = 1

[module/date]
type = internal/date
date = %H:%M:%S
label = %date%
label-foreground = ${colors.primary}

[module/memory]
type = internal/memory
label = RAM %percentage_used%%
label-foreground = ${colors.secondary}

[module/cpu]
type = internal/cpu
label = CPU %percentage%%
label-foreground = ${colors.primary}
EOF

cat > ~/.config/alacritty/alacritty.toml << 'EOF'
[window]
opacity = 0.50
padding = { x = 10, y = 10 }
decorations = "none"

[font]
size = 11.0

[font.normal]
family = "FiraCode Nerd Font"
style = "Regular"

[colors.primary]
background = "#0d0d0d"
foreground = "#e0e0e0"

[colors.cursor]
text = "#0d0d0d"
cursor = "#00ff88"

[colors.normal]
black = "#0d0d0d"
red = "#ff0055"
green = "#00ff88"
yellow = "#ffeb3b"
blue = "#8b5cf6"
magenta = "#b84dff"
cyan = "#00e5ff"
white = "#e0e0e0"
EOF

cat > ~/.config/rofi/config.rasi << 'EOF'
configuration {
    modi: "drun";
    display-drun: "Apps";
    show-icons: true;
}

* {
    background-color: #0d0d0d;
    text-color: #e0e0e0;
    accent: #00ff88;
    accent2: #b84dff;
}

window {
    border: 2px;
    border-color: @accent;
    padding: 10px;
    width: 500px;
}

listview {
    lines: 8;
    padding: 10px 0 0;
}

element {
    padding: 8px;
}

element selected {
    background-color: @accent;
    text-color: #0d0d0d;
}

inputbar {
    children: [prompt, entry];
    padding: 5px;
}

prompt {
    text-color: @accent;
}
EOF

cat > ~/.config/fastfetch/config.jsonc << 'EOF'
{
    "logo": {
        "source": "arch",
        "color": {
            "1": "green",
            "2": "magenta"
        }
    },
    "display": {
        "color": {
            "keys": "green"
        }
    },
    "modules": [
        "title",
        "separator",
        "os",
        "kernel",
        "uptime",
        "packages",
        "shell",
        "wm",
        "terminal",
        "cpu",
        "memory",
        "break",
        "colors"
    ]
}
EOF

echo -e "${GREEN}[9/10] Setting up zsh syntax highlighting...${NC}"
# Setup zsh syntax highlighting
echo "source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ~/.zshrc 2>/dev/null || true

# Remove fastfetch from shell configs if it exists
sed -i '/fastfetch/d' ~/.bashrc 2>/dev/null || true
sed -i '/fastfetch/d' ~/.zshrc 2>/dev/null || true

echo -e "${GREEN}[10/10] Done!${NC}"
echo ""
echo -e "${PURPLE}Installation complete!${NC}"
echo ""
echo -e "Next steps:"
echo -e "1. Log out and select i3 at login screen"
echo -e "2. Random wallpaper from dharmx/walls has been set!"
echo -e "3. Press Super+Shift+r to reload i3"
echo -e "4. Run: ${GREEN}chsh -s /usr/bin/zsh${NC} to set zsh as default (restart terminal after)"
echo ""
echo -e "Keybindings:"
echo -e "  Super+Enter       - Terminal"
echo -e "  Super+d           - App launcher"
echo -e "  Super+Shift+q     - Close window"
echo -e "  Super+Shift+m     - System monitor"
echo -e "  Super+Shift+f     - File manager"
echo -e "  Super+Shift+b     - Firefox"
echo ""
echo -e "${PURPLE}Features:${NC}"
echo -e "  ✓ Transparent terminals with blur effect"
echo -e "  ✓ Fastfetch launches in floating window on startup"
echo -e "  ✓ Random wallpaper from dharmx/walls collection"
echo -e "  ✓ Zsh syntax highlighting enabled"
