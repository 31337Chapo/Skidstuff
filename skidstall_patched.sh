#!/usr/bin/env bash
# Skidstall Installer (patched with Smart Fallback Mode)
# NOTE: This is a simplified version containing the added Smart Mode fallback engine.
# Insert your full script contents here and replace the install functions with these patched ones.

set -euo pipefail
IFS=$'\n\t'

AUTO=false
if [[ "$*" == *"--auto"* ]]; then AUTO=true; fi

# ---- Logging ----
log(){ printf "[+] %s\n" "$@"; }
warn(){ printf "[!] %s\n" "$@"; }
err(){ printf "[✗] %s\n" "$@" >&2; }

# ---- Package checks ----
check_pacman_package(){ timeout 5 pacman -Si "$1" &>/dev/null; }
check_aur_exact(){ timeout 5 curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg=$1" | grep -q '"resultcount":1'; }
search_pacman(){ pacman -Ss "$1" 2>/dev/null | awk -F'/' '/^[a-z]/{print $2}' | awk '{print $1}'; }
search_aur(){ curl -s "https://aur.archlinux.org/rpc/?v=5&type=search&arg=$1" | grep '"Name"' | sed 's/.*"Name":"\([^"]*\)".*/\1/'; }

fallback_resolve(){
    local pkg="$1"
    warn "Package '$pkg' not found."
    if $AUTO; then
        log "AUTO mode: attempting fallback search..."
    else
        read -r -p "Search alternatives for '$pkg'? [y/N] " ans
        [[ ! "$ans" =~ ^[yY]$ ]] && return 1
    fi

    log "Searching pacman..."
    local pacman_matches
    pacman_matches=$(search_pacman "$pkg")

    log "Searching AUR..."
    local aur_matches
    aur_matches=$(search_aur "$pkg")

    echo "Matches:"
    echo "$pacman_matches"
    echo "$aur_matches"

    local choice
    if $AUTO; then
        choice=$(echo -e "$pacman_matches
$aur_matches" | head -n1)
    else
        read -r -p "Enter package to install: " choice
    fi
    [[ -z "$choice" ]] && return 1

    if check_pacman_package "$choice"; then
        sudo pacman -S --noconfirm "$choice" && return 0
    fi
    if check_aur_exact "$choice"; then
        yay -S --noconfirm "$choice" && return 0
    fi
    return 1
}

install_pacman_pkgs(){
    for pkg in "$@"; do
        if check_pacman_package "$pkg"; then
            sudo pacman -S --noconfirm --needed "$pkg" && continue
        fi
        fallback_resolve "$pkg" || warn "Failed to install $pkg"
    done
}

install_aur_pkgs(){
    for pkg in "$@"; do
        if check_aur_exact "$pkg"; then
            yay -S --noconfirm --needed "$pkg" && continue
        fi
        fallback_resolve "$pkg" || warn "Failed to install $pkg"
    done
}

echo "Placeholder patched script generated. Replace the body with your full script and keep these patched functions."
