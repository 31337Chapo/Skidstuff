#!/bin/bash
# Neon Nord Pentest i3-gaps Auto-Installer
# Run this after a fresh Arch Linux installation

set -e

# Colors for output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════╗
║               🎨fsociety amirite?🎨              ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${PURPLE}Don't run this as root! Run as your normal user.${NC}"
   exit 1
fi

# Install yay if not present
if ! command -v yay &> /dev/null; then
    echo -e "${GREEN}[*] Installing yay AUR helper...${NC}"
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
fi

# Update system
echo -e "${GREEN}[*] Updating system...${NC}"
sudo pacman -Syu --noconfirm

# Install base packages
echo -e "${GREEN}[*] Installing i3-gaps and core components...${NC}"
sudo pacman -S --noconfirm --needed \
    xorg xorg-xinit i3-gaps i3status i3lock \
    open-vm-tools gtkmm3 \
    kitty \
    picom \
    rofi \
    thunar \
    feh nitrogen \
    maim xclip \
    dunst \
    btop \
    firefox

# Install fonts
echo -e "${GREEN}[*] Installing fonts...${NC}"
sudo pacman -S --noconfirm --needed \
    ttf-font-awesome ttf-fira-code \
    ttf-jetbrains-mono-nerd

# Install polybar from AUR
echo -e "${GREEN}[*] Installing polybar...${NC}"
yay -S --noconfirm --needed polybar

# Install pentesting tools
echo -e "${GREEN}[*] Installing pentesting tools (this may take a while)...${NC}"
sudo pacman -S --noconfirm --needed \
    nmap masscan wireshark-qt \
    john hashcat sqlmap gobuster nikto \
    aircrack-ng hydra netcat openvpn \
    python-pip python-requests python-scapy \
    metasploit \
    enum4linux smbclient cifs-utils \
    dns-utils bind-tools \
    tcpdump net-tools iproute2 \
    exploitdb \
    wordlists \
    proxychains-ng \
    gnu-netcat socat \
    ffuf \
    crackmapexec \
    responder \
    impacket \
    bloodhound \
    ncat ngrep \
    radare2 ghidra \
    strace ltrace \
    gdb pwndbg \
    binwalk foremost exiftool \
    tmux screen \
    jq yq \
    curl wget git \
    vim neovim ripgrep fd lazygit \
    python-virtualenv python-poetry \
    go rust cargo \
    docker docker-compose

# Additional tools from AUR
echo -e "${GREEN}[*] Installing AUR pentesting tools...${NC}"
yay -S --noconfirm --needed \
    burpsuite \
    zaproxy \
    sublister \
    seclists \
    feroxbuster \
    rustscan \
    kerbrute \
    chisel \
    ligolo-ng \
    nuclei \
    subfinder \
    httpx \
    katana \
    waybackurls \
    gau \
    anew \
    gospider \
    hakrawler

# Python tools via pip
echo -e "${GREEN}[*] Installing Python pentesting tools...${NC}"
pip install --user \
    pipx \
    pwntools \
    ropper \
    ropgadget \
    angr \
    pycryptodome \
    paramiko \
    ldap3 \
    bloodhound \
    mitm6 \
    dnstwist \
    sublist3r \
    shodan \
    censys

# Install pipx tools
pipx install crackmapexec
pipx install impacket

# Enable VMware tools
echo -e "${GREEN}[*] Enabling VMware tools...${NC}"
sudo systemctl enable vmtoolsd
sudo systemctl start vmtoolsd

# Enable Docker
echo -e "${GREEN}[*] Enabling Docker...${NC}"
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER

# Setup Metasploit database
echo -e "${GREEN}[*] Setting up Metasploit database...${NC}"
sudo systemctl enable postgresql
sudo systemctl start postgresql
sudo -u postgres initdb -D /var/lib/postgres/data 2>/dev/null || true
msfdb init 2>/dev/null || true

# Create config directories
echo -e "${GREEN}[*] Creating config directories...${NC}"
mkdir -p ~/.config/{i3,picom,kitty,rofi,polybar,dunst}
mkdir -p ~/Pictures

# Download wallpaper
echo -e "${GREEN}[*] Downloading wallpaper...${NC}"
curl -L "https://raw.githubusercontent.com/linuxdotexe/nordic-wallpapers/master/wallpapers/nord-neon-mountains.png" \
    -o ~/Pictures/wallpaper.jpg 2>/dev/null || \
    echo "Wallpaper download failed - you can add your own to ~/Pictures/wallpaper.jpg"

# Create .xinitrc
echo -e "${GREEN}[*] Creating .xinitrc...${NC}"
cat > ~/.xinitrc << 'EOF'
#!/bin/sh
exec i3
EOF
chmod +x ~/.xinitrc

# Create i3 config
echo -e "${GREEN}[*] Creating i3 config...${NC}"
cat > ~/.config/i3/config << 'EOF'
# i3-gaps "Neon Nord Pentest" Config
set $mod Mod4

font pango:JetBrainsMono Nerd Font 10

# Neon Nord Colors
set $bg-dark     #2e3440
set $bg-medium   #3b4252
set $bg-light    #434c5e
set $fg          #eceff4
set $accent-grn  #9fef00
set $accent-cyan #88c0d0
set $accent-purp #b48ead
set $urgent      #bf616a

# Window colors
client.focused           $accent-grn    $bg-dark       $fg       $accent-cyan   $accent-grn
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

exec_always --no-startup-id picom --config ~/.config/picom/picom.conf
exec_always --no-startup-id ~/.config/polybar/launch.sh
exec_always --no-startup-id feh --bg-scale ~/Pictures/wallpaper.jpg
exec --no-startup-id dunst

bindsym $mod+d exec --no-startup-id rofi -show drun -theme ~/.config/rofi/neon-nord.rasi
bindsym $mod+Return exec kitty
bindsym $mod+Shift+q kill

# Quick launch pentesting tools
bindsym $mod+Shift+b exec firefox https://burpsuite.net
bindsym $mod+Shift+w exec kitty -e wireshark
bindsym $mod+Shift+m exec kitty -e msfconsole
bindsym $mod+Shift+n exec kitty -e sudo nmap

# Floating terminal for quick commands
bindsym $mod+grave exec kitty --class floating-term
for_window [class="floating-term"] floating enable, resize set 1200 700, move position center

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

bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split

bindsym $mod+Shift+space floating toggle
bindsym $mod+space focus mode_toggle

set $ws1 "1:recon"
set $ws2 "2:enum"
set $ws3 "3:exploit"
set $ws4 "4:post"
set $ws5 "5:notes"

bindsym $mod+1 workspace number $ws1
bindsym $mod+2 workspace number $ws2
bindsym $mod+3 workspace number $ws3
bindsym $mod+4 workspace number $ws4
bindsym $mod+5 workspace number $ws5

bindsym $mod+Shift+1 move container to workspace number $ws1
bindsym $mod+Shift+2 move container to workspace number $ws2
bindsym $mod+Shift+3 move container to workspace number $ws3
bindsym $mod+Shift+4 move container to workspace number $ws4
bindsym $mod+Shift+5 move container to workspace number $ws5

bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
bindsym Print exec --no-startup-id maim -s | xclip -selection clipboard -t image/png
bindsym $mod+Shift+x exec i3lock -c 2e3440

mode "resize" {
    bindsym h resize shrink width 10 px
    bindsym j resize grow height 10 px
    bindsym k resize shrink height 10 px
    bindsym l resize grow width 10 px
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

for_window [class="Thunar"] floating enable
for_window [class="Pavucontrol"] floating enable
for_window [title="nmtui"] floating enable

# Auto-assign applications to workspaces
assign [class="Burp"] $ws3
assign [class="Wireshark"] $ws2
assign [class="obsidian"] $ws5
assign [class="Zathura"] $ws5
EOF

# Create pentest workspace launcher
echo -e "${GREEN}[*] Creating pentest workspace automation...${NC}"
mkdir -p ~/.local/bin
cat > ~/.local/bin/pentest-workspace << 'EOFSCRIPT'
#!/bin/bash
# Automated pentest workspace setup

TARGET=$1

if [ -z "$TARGET" ]; then
    echo "Usage: pentest-workspace <target-ip-or-name>"
    exit 1
fi

# Create project directory
WORKSPACE=~/pentest/$TARGET
mkdir -p $WORKSPACE/{recon,scans,loot,screenshots,notes}
cd $WORKSPACE

# Workspace 1: Reconnaissance
i3-msg "workspace 1:recon; exec kitty -e bash -c 'rustscan -a $TARGET -- -sC -sV -oN scans/nmap-initial.txt'"

# Workspace 2: Enumeration
i3-msg "workspace 2:enum; exec kitty"

# Workspace 3: Browser with Burp
i3-msg "workspace 3:exploit; exec firefox"

# Workspace 4: Post-exploitation
i3-msg "workspace 4:post; exec kitty"

# Workspace 5: Notes (open a markdown file)
i3-msg "workspace 5:notes; exec kitty -e nvim notes/$TARGET-notes.md"

# Create initial notes template
cat > notes/$TARGET-notes.md << 'NOTES'
# Pentest Notes: $TARGET

## Target Information
- IP: $TARGET
- Date: $(date)

## Reconnaissance
- [ ] Port scan
- [ ] Service enumeration
- [ ] Web enumeration
- [ ] DNS enumeration

## Vulnerabilities Found

## Exploitation Attempts

## Post-Exploitation

## Credentials
NOTES

notify-send "Pentest Workspace" "Environment ready for $TARGET"
EOFSCRIPT
chmod +x ~/.local/bin/pentest-workspace

# Create quick pentest script launcher
cat > ~/.local/bin/quick-scan << 'EOFSCRIPT'
#!/bin/bash
# Quick scan launcher with GUI

TARGET=$(echo "" | rofi -dmenu -p "Target IP/Domain:")

if [ -z "$TARGET" ]; then
    exit 0
fi

SCAN_TYPE=$(echo -e "Quick Scan\nFull Scan\nUDP Scan\nWeb Enum\nFull Workspace" | rofi -dmenu -p "Scan Type:")

case "$SCAN_TYPE" in
    "Quick Scan")
        kitty --class floating-term -e bash -c "rustscan -a $TARGET -- -sC -sV; read -p 'Press enter to close'"
        ;;
    "Full Scan")
        kitty --class floating-term -e bash -c "sudo nmap -p- -sC -sV -A -T4 $TARGET -oN ~/pentest/$TARGET-full.txt; read -p 'Press enter to close'"
        ;;
    "UDP Scan")
        kitty --class floating-term -e bash -c "sudo nmap -sU --top-ports 100 $TARGET -oN ~/pentest/$TARGET-udp.txt; read -p 'Press enter to close'"
        ;;
    "Web Enum")
        kitty --class floating-term -e bash -c "gobuster dir -u http://$TARGET -w /usr/share/wordlists/dirb/common.txt; read -p 'Press enter to close'"
        ;;
    "Full Workspace")
        pentest-workspace $TARGET
        ;;
esac
EOFSCRIPT
chmod +x ~/.local/bin/quick-scan

# Add to PATH in i3 config
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Bind quick-scan to Super+P in i3
cat >> ~/.config/i3/config << 'EOF'

# Quick pentest launcher
bindsym $mod+p exec --no-startup-id quick-scan
EOF

# Create tmux config for pentest sessions
cat > ~/.tmux.conf << 'EOFTMUX'
# Neon Nord tmux theme
set -g default-terminal "screen-256color"
set -g status-bg "#2e3440"
set -g status-fg "#eceff4"
set -g status-left "#[fg=#9fef00,bold] #S "
set -g status-right "#[fg=#88c0d0] %H:%M #[fg=#9fef00] %d-%b-%y "
set -g window-status-current-format "#[fg=#2e3440,bg=#9fef00,bold] #I:#W "
set -g window-status-format "#[fg=#d8dee9] #I:#W "
set -g pane-border-style "fg=#434c5e"
set -g pane-active-border-style "fg=#9fef00"

# Better keybindings
set -g mouse on
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %
EOFTMUX

# Create picom config
echo -e "${GREEN}[*] Creating picom config...${NC}"
cat > ~/.config/picom/picom.conf << 'EOF'
shadow = true;
shadow-radius = 12;
shadow-opacity = 0.75;
shadow-offset-x = -12;
shadow-offset-y = -12;

fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;
fade-delta = 5;

inactive-opacity = 0.92;
frame-opacity = 0.9;
inactive-opacity-override = false;

blur-method = "dual_kawase";
blur-strength = 6;
blur-background = true;
blur-background-frame = true;
blur-background-fixed = true;

blur-background-exclude = [
    "window_type = 'dock'",
    "window_type = 'desktop'",
    "_GTK_FRAME_EXTENTS@:c"
];

corner-radius = 8;
rounded-corners-exclude = [
    "window_type = 'dock'",
    "window_type = 'desktop'"
];

backend = "glx";
vsync = true;
glx-no-stencil = true;
glx-no-rebind-pixmap = true;
use-damage = true;

wintypes:
{
    tooltip = { fade = true; shadow = true; opacity = 0.95; focus = true; };
    dock = { shadow = false; };
    dnd = { shadow = false; };
};
EOF

# Create kitty config
echo -e "${GREEN}[*] Creating kitty config...${NC}"
cat > ~/.config/kitty/kitty.conf << 'EOF'
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
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
tab_powerline_style slanted
active_tab_foreground   #2e3440
active_tab_background   #9fef00
inactive_tab_foreground #d8dee9
inactive_tab_background #3b4252

window_padding_width 10
EOF

# Create polybar config
echo -e "${GREEN}[*] Creating polybar config...${NC}"
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
radius = 0
background = ${colors.background}
foreground = ${colors.foreground}
line-size = 3
padding-left = 1
padding-right = 2
module-margin = 1
separator = |
separator-foreground = ${colors.disabled}
font-0 = JetBrainsMono Nerd Font:size=10;2
font-1 = Font Awesome 6 Free:style=Solid:size=10;2
modules-left = xworkspaces xwindow
modules-right = filesystem pulseaudio memory cpu wlan eth date
cursor-click = pointer
cursor-scroll = ns-resize
enable-ipc = true

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
interval = 25
mount-0 = /
label-mounted = %{F#9fef00}%mountpoint%%{F-} %percentage_used%%
label-unmounted = %mountpoint% not mounted
label-unmounted-foreground = ${colors.disabled}

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = "VOL "
format-volume-prefix-foreground = ${colors.primary}
format-volume = <label-volume>
label-volume = %percentage%%
label-muted = muted
label-muted-foreground = ${colors.disabled}

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

[network-base]
type = internal/network
interval = 5
format-connected = <label-connected>
format-disconnected = <label-disconnected>
label-disconnected = %{F#bf616a}%ifname% disconnected

[module/wlan]
inherit = network-base
interface-type = wireless
label-connected = %{F#9fef00}%ifname%%{F-} %essid%

[module/eth]
inherit = network-base
interface-type = wired
label-connected = %{F#9fef00}%ifname%%{F-} %local_ip%

[module/date]
type = internal/date
interval = 1
date = %H:%M
date-alt = %Y-%m-%d %H:%M:%S
label = %date%
label-foreground = ${colors.primary}

[settings]
screenchange-reload = true
pseudo-transparency = true
EOF

# Create polybar launch script
cat > ~/.config/polybar/launch.sh << 'EOF'
#!/bin/bash
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done
polybar main 2>&1 | tee -a /tmp/polybar.log & disown
EOF
chmod +x ~/.config/polybar/launch.sh

# Create rofi theme
echo -e "${GREEN}[*] Creating rofi theme...${NC}"
cat > ~/.config/rofi/neon-nord.rasi << 'EOF'
* {
    bg: #2e3440;
    bg-alt: #3b4252;
    fg: #eceff4;
    primary: #9fef00;
    secondary: #88c0d0;
    
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
    placeholder-color: @bg-alt;
}

message {
    padding: 12px;
    border: 2px 0 0;
    border-color: @bg-alt;
}

listview {
    padding: 8px 0;
    lines: 8;
    columns: 1;
    scrollbar: false;
}

element {
    padding: 8px 12px;
    spacing: 8px;
}

element normal active {
    text-color: @primary;
}

element selected normal, element selected active {
    background-color: @bg-alt;
    text-color: @primary;
}

element-icon {
    size: 1em;
    vertical-align: 0.5;
}

element-text {
    text-color: inherit;
    vertical-align: 0.5;
}
EOF

# Create dunst config
echo -e "${GREEN}[*] Creating dunst config...${NC}"
cat > ~/.config/dunst/dunstrc << 'EOF'
[global]
    font = JetBrainsMono Nerd Font 10
    markup = full
    format = "<b>%s</b>\n%b"
    sort = yes
    indicate_hidden = yes
    alignment = left
    show_age_threshold = 60
    word_wrap = yes
    ignore_newline = no
    stack_duplicates = true
    hide_duplicate_count = false
    width = 300
    height = 300
    offset = 10x30
    padding = 8
    horizontal_padding = 8
    frame_width = 2
    separator_height = 2
    separator_color = frame
    
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

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════╗
║            🎉 INSTALLATION COMPLETE! 🎉           ║
╚═══════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${GREEN}To start your new setup, run:${NC}"
echo -e "${PURPLE}    startx${NC}"
echo ""
echo -e "${GREEN}Key bindings:${NC}"
echo -e "  Super+Enter         - Open terminal"
echo -e "  Super+D             - App launcher"
echo -e "  Super+P             - Quick pentest scan launcher"
echo -e "  Super+Shift+Q       - Kill window"
echo -e "  Super+Shift+B       - Open Burp Suite"
echo -e "  Super+Shift+W       - Open Wireshark"
echo -e "  Super+Shift+M       - Open Metasploit"
echo -e "  Super+Shift+N       - Quick nmap"
echo -e "  Super+\`             - Floating terminal"
echo -e "  Super+1-5           - Switch workspaces (recon/enum/exploit/post/notes)"
echo -e "  Super+Shift+X       - Lock screen"
echo -e "  Print               - Screenshot"
echo ""
echo -e "${PURPLE}Pro Tips:${NC}"
echo -e "  • Run 'pentest-workspace <target-ip>' to auto-setup full environment"
echo -e "  • Use Super+P for quick scan menu"
echo -e "  • Workspaces auto-organize your tools (recon→enum→exploit→post→notes)"
echo -e "  • Notes are saved in ~/pentest/<target>/notes/"
echo -e "  • All scans go to ~/pentest/<target>/scans/"
echo ""
echo -e "${CYAN}Enjoy your Neon Nord Pentest setup! 🚀${NC}"
