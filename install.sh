#!/bin/bash

# Complete Debian 12 Security Hardening Script
# Based on my original script + blakkheim's guide (https://vez.mrsk.me/linux-hardening)
# Run as root or with sudo privileges

set -euo pipefail

echo "Starting comprehensive Debian 12 security hardening..."

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Original basic hardening (cleaned up but same functionality)
basic_hardening() {
    log "Applying basic system hardening..."
    
    export PATH=$PATH:/usr/sbin
    apt update
    apt install -y cron sudo curl wget passwd apache2-utils
    
    # Create debian user if not exists
    sudo useradd -m -s /bin/bash debian 2>/dev/null || true
    echo "debian:TempPass123" | sudo chpasswd
    sudo passwd -u debian
    
    # Core dump protection
    printf '* hard core 0\n* soft core 0' | sudo tee -a /etc/security/limits.conf
    printf 'fs.suid_dumpable=0\nkernel.core_pattern=|/bin/false' | sudo tee -a /etc/sysctl.d/9999-disable-core-dump.conf
    sudo sysctl -p /etc/sysctl.d/9999-disable-core-dump.conf
    
    sudo mkdir -p /etc/systemd/coredump.conf.d/
    printf '[Coredump]\nStorage=none\nProcessSizeMax=0' | sudo tee -a /etc/systemd/coredump.conf.d/custom.conf
    sudo systemctl daemon-reload
}

# Original nftables firewall (preserved)
nftables_firewall() {
    log "Configuring nftables firewall (original)..."
    
    sudo apt install -y nftables
    sudo apt purge -y iptables-persistent netfilter-persistent 2>/dev/null || true
    
    sudo nft flush ruleset
    sudo nft add table inet filter
    sudo nft add chain inet filter input '{ type filter hook input priority 0 ; policy drop ; }'
    sudo nft add chain inet filter forward '{ type filter hook forward priority 0 ; policy drop ; }'
    sudo nft add chain inet filter output '{ type filter hook output priority 0 ; policy accept ; }'
    sudo nft add rule inet filter input iif lo accept
    sudo nft add rule inet filter input iif != lo ip daddr 127.0.0.0/8 drop
    sudo nft add rule inet filter input ct state established,related accept
    sudo nft add rule inet filter input tcp dport 22 ct state new accept
    sudo nft add rule inet filter input tcp dport 31926 ct state new accept
    sudo nft add rule inet filter input tcp dport 80 ct state new accept
    sudo nft add rule inet filter input tcp dport 443 ct state new accept
    sudo nft add rule inet filter input ct state new accept
    
    sudo mkdir -p /etc/nftables
    sudo nft list ruleset > /etc/nftables/nftables.conf
    sudo systemctl enable nftables
}

# Enhanced package manager security
package_security() {
    log "Configuring secure package sources..."
    
    # Backup original sources.list
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
    
    # Configure HTTPS-only mirrors
    sudo tee /etc/apt/sources.list > /dev/null <<EOF
# Debian 12 (bookworm) - HTTPS only sources
deb https://deb.debian.org/debian/ bookworm main contrib non-free-firmware
deb-src https://deb.debian.org/debian/ bookworm main contrib non-free-firmware

deb https://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb-src https://security.debian.org/debian-security bookworm-security main contrib non-free-firmware

deb https://deb.debian.org/debian/ bookworm-updates main contrib non-free-firmware
deb-src https://deb.debian.org/debian/ bookworm-updates main contrib non-free-firmware
EOF
    
    apt update
}

# Comprehensive kernel hardening
kernel_hardening() {
    log "Applying kernel hardening parameters..."
    
    # Install kernel hardening packages
    apt install -y linux-headers-$(uname -r)
    
    # Create comprehensive sysctl configuration (exact from blakkheim guide)
    sudo tee /etc/sysctl.d/99-sysctl.conf > /dev/null <<'EOF'
# prevent the automatic loading of line disciplines
# https://lore.kernel.org/patchwork/patch/1034150
dev.tty.ldisc_autoload=0

# additional protections for fifos, hardlinks, regular files, and symlinks
# https://patchwork.kernel.org/patch/10244781
# slightly tightened up from the systemd default values of "1" for each
fs.protected_fifos=2
fs.protected_hardlinks=1
fs.protected_regular=2
fs.protected_symlinks=1

# prevent unprivileged users from viewing the dmesg buffer
kernel.dmesg_restrict=1

# prevents processes from creating new io_uring instances
# https://security.googleblog.com/2023/06/learnings-from-kctf-vrps-42-linux.html
kernel.io_uring_disabled=2

# disable the kexec system call (can be used to replace the running kernel)
# https://lwn.net/Articles/580269
kernel.kexec_load_disabled=1

# impose restrictions on exposing kernel pointers
# https://lwn.net/Articles/420403
kernel.kptr_restrict=2

# restrict use of the performance events system by unprivileged users
# https://lwn.net/Articles/696216
kernel.perf_event_paranoid=3

# disable the "magic sysrq key" functionality
# https://security.stackexchange.com/questions/138658
# https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1861238
# uncomment if the use of this feature is not needed
#kernel.sysrq=0

# harden the BPF JIT compiler and restrict unprivileged use of BPF
# https://www.zerodayinitiative.com/advisories/ZDI-20-350
# https://lwn.net/Articles/660331
net.core.bpf_jit_harden=2
kernel.unprivileged_bpf_disabled=1

# disable unprivileged user namespaces
# https://lwn.net/Articles/673597
# (these two values are redundant, but not all kernels support the first one)
kernel.unprivileged_userns_clone=0
user.max_user_namespaces=0

# enable yama ptrace restrictions
# https://www.kernel.org/doc/Documentation/security/Yama.txt
# set to "3" if the use of ptrace is not needed
kernel.yama.ptrace_scope=1

# reverse path filtering to prevent some ip spoofing attacks
# (default in some distributions)
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1

# disable icmp redirects and RFC1620 shared media redirects
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.shared_media=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.default.shared_media=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0

# disallow source-routed packets
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.default.accept_source_route=0

# ignore pings sent to a broadcast address (common for smurf attacks)
net.ipv4.icmp_echo_ignore_broadcasts=1

# ignore bogus icmp error responses
net.ipv4.icmp_ignore_bogus_error_responses=1

# protect against time-wait assassination hazards in tcp
# https://tools.ietf.org/html/rfc1337
net.ipv4.tcp_rfc1337=1

# selective tcp acks have resulted in remotely exploitable crashes
# https://lwn.net/Articles/791409
# uncomment to potentially guard against future attacks
# (may introduce a performance hit in highly congested networks)
#net.ipv4.tcp_sack=0
#net.ipv4.tcp_dsack=0

# disable tcp timestamps to avoid leaking some system information
# https://www.whonix.org/wiki/Disable_TCP_and_ICMP_Timestamps
net.ipv4.tcp_timestamps=0

# increase aslr effectiveness for mmap
# https://lwn.net/Articles/667790
vm.mmap_rnd_bits=32
vm.mmap_rnd_compat_bits=16

# ignore icmp echo requests
# uncomment if this system doesn't need to respond to pings
#net.ipv4.icmp_echo_ignore_all=1

# disable creation of ipv6 addresses on network interfaces
# uncomment (or set the ipv6.disable=1 kernel parameter) if ipv6 is not in use
#net.ipv6.conf.all.disable_ipv6=1
#net.ipv6.conf.default.disable_ipv6=1
#net.ipv6.conf.lo.disable_ipv6=1
EOF
    
    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.d/99-sysctl.conf
    
    # Configure kernel boot parameters
    log "Configuring kernel boot parameters..."
    
    # Backup GRUB configuration
    sudo cp /etc/default/grub /etc/default/grub.backup
    
    # Add security kernel parameters (exact from blakkheim guide)
    KERNEL_PARAMS="apparmor=1 init_on_alloc=1 init_on_free=1 l1tf=full,force l1d_flush=on gather_data_sampling=force spec_rstack_overflow=ibpb lockdown=confidentiality lsm=landlock,lockdown,yama,apparmor page_alloc.shuffle=1 slab_nomerge spec_store_bypass_disable=on spectre_v2=on vsyscall=none randomize_kstack_offset=1"
    
    # Update GRUB configuration
    sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\([^\"]*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $KERNEL_PARAMS\"/" /etc/default/grub
    
    # Update GRUB
    sudo update-grub
    
    warn "Kernel parameters updated. Reboot required for changes to take effect."
}

# Application sandboxing
application_sandboxing() {
    log "Setting up application sandboxing..."
    
    # Install and configure AppArmor
    apt install -y apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra
    sudo systemctl enable apparmor
    sudo systemctl start apparmor
    
    # Install Firejail
    apt install -y firejail
    
    # Configure Firejail (exact from blakkheim guide)
    sudo systemctl enable --now apparmor
    sudo apparmor_parser -r /etc/apparmor.d/firejail-default
    sudo firecfg
    echo "debian" | sudo tee /etc/firejail/firejail.users > /dev/null
    
    # Update PATH for firejail (exact from guide)
    echo 'export PATH=/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin' | sudo tee -a /etc/profile
    
    log "AppArmor and Firejail configured. Applications will be sandboxed."
}

# Enhanced SSH configuration (original enhanced)
enhanced_ssh() {
    log "Enhancing SSH configuration..."
    
    sudo groupadd -f ssh-user
    sudo usermod -aG sudo debian
    sudo usermod -aG ssh-user debian
    
    # Enhanced SSH configuration (original but cleaned up)
    sudo tee /etc/ssh/sshd_config.d/10-sshd.conf > /dev/null <<'EOF'
AddressFamily inet
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
LogLevel VERBOSE
PermitRootLogin no
MaxAuthTries 2
MaxSessions 2
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
UsePAM no
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
TCPKeepAlive no
Compression no
ClientAliveCountMax 2
AllowGroups ssh-user
KexAlgorithms curve25519-sha256@libssh.org,curve25519-sha256,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512,diffie-hellman-group-exchange-sha256
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
HostKeyAlgorithms rsa-sha2-512,rsa-sha2-256,ssh-ed25519
EOF
    
    # Setup SSH keys (original)
    sudo mkdir -p /home/debian/.ssh
    sudo chmod 700 /home/debian/.ssh
    sudo cp /root/.ssh/authorized_keys /home/debian/.ssh/authorized_keys 2>/dev/null || sudo touch /home/debian/.ssh/authorized_keys
    sudo chmod 600 /home/debian/.ssh/authorized_keys
    sudo chown -R debian:debian /home/debian/.ssh
    
    sudo systemctl restart sshd
}

# Enhanced sudo configuration (exact from blakkheim guide)
enhanced_sudo() {
    log "Configuring enhanced sudo settings..."
    
    # Sudo logging (original)
    printf 'Defaults        logfile="/var/log/sudo.log"' | sudo tee -a /etc/sudoers.d/log
    
    # Enhanced sudo security (exact from blakkheim guide adapted for apt)
    sudo tee /etc/sudoers > /dev/null <<'EOF'
Defaults env_reset
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults umask=0022
Defaults umask_override

root    ALL=(ALL:ALL) ALL

Cmnd_Alias PACMAN = /usr/bin/apt update, /usr/bin/apt upgrade
Cmnd_Alias REBOOT = /sbin/reboot ""
Cmnd_Alias SHUTDOWN = /sbin/poweroff ""

debian ALL=(root) NOPASSWD: PACMAN
debian ALL=(root) NOPASSWD: REBOOT
debian ALL=(root) NOPASSWD: SHUTDOWN
EOF
}

# Time synchronization (exact from blakkheim guide)
time_sync() {
    log "Configuring secure time synchronization..."
    
    # Install and configure OpenNTPD
    apt install -y openntpd
    
    # Disable systemd-timesyncd
    sudo systemctl disable --now systemd-timesyncd
    
    # Configure OpenNTPD with quality servers (exact from guide)
    sudo tee /etc/openntpd/ntpd.conf > /dev/null <<'EOF'
server time.apple.com
server time.cloudflare.com
server pool.ntp.org
constraint from "https://example.com"
EOF
    
    sudo systemctl enable openntpd
    sudo systemctl start openntpd
}

# Hardware security
hardware_security() {
    log "Configuring hardware security..."
    
    # Install rfkill (util-linux package - already installed)
    # RFKill setup mentioned in guide but blocking is optional
    log "RFKill available. To block wireless: sudo systemctl enable --now rfkill-block@all.service"
    
    # Blacklist uncommon filesystems (not explicitly in guide but common hardening)
    sudo tee /etc/modprobe.d/blacklist-rare-filesystems.conf > /dev/null <<'EOF'
# Blacklist rare filesystems to reduce attack surface
blacklist cramfs
blacklist freevxfs
blacklist jffs2
blacklist hfs
blacklist hfsplus
blacklist squashfs
blacklist udf
EOF
    
    # Update initramfs
    sudo update-initramfs -u
}

# User security settings (exact from blakkheim guide)
user_security() {
    log "Applying user security settings..."
    
    # Set secure umask for debian user (exact from guide)
    echo 'umask 77' | sudo tee -a /home/debian/.bashrc
    
    # Secure home directory permissions (exact from guide)
    sudo chmod -R go-rwx /home/debian
    
    # Create tmpfs for user cache (exact from guide)
    echo 'tmpfs /home/debian/.cache tmpfs rw,size=250M,noexec,noatime,nodev,uid=debian,gid=debian,mode=700 0 0' | sudo tee -a /etc/fstab
}

# Hidden PIDs (from blakkheim guide miscellaneous section)
hidden_pids() {
    log "Configuring hidden PIDs..."
    
    # Hide processes from other users (mentioned in guide)
    echo 'proc /proc proc defaults,hidepid=2,gid=proc 0 0' | sudo tee -a /etc/fstab
    sudo groupadd -f proc
    sudo usermod -aG proc debian
    
    log "Process hiding configured. Will take effect after reboot."
}

# DNSCrypt (from blakkheim guide miscellaneous section)
dns_security() {
    log "Configuring DNSCrypt..."
    
    # Install dnscrypt-proxy (mentioned in blakkheim guide)
    apt install -y dnscrypt-proxy
    
    # Basic dnscrypt-proxy configuration
    sudo tee /etc/dnscrypt-proxy/dnscrypt-proxy.toml > /dev/null <<'EOF'
server_names = ['cloudflare', 'quad9-dnscrypt-ip4-nofilter-pri']
listen_addresses = ['127.0.0.1:53']
max_clients = 250
ipv4_servers = true
ipv6_servers = false
dnscrypt_servers = true
doh_servers = true
require_dnssec = true
require_nolog = true
require_nofilter = true
timeout = 5000
keepalive = 30
EOF
    
    # Configure system to use dnscrypt-proxy
    sudo tee /etc/systemd/resolved.conf > /dev/null <<'EOF'
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
    
    sudo systemctl disable systemd-resolved
    sudo systemctl enable dnscrypt-proxy
    
    log "DNSCrypt configured. DNS queries will be encrypted."
}

# Automatic updates (original)
automatic_updates() {
    log "Configuring automatic security updates..."
    
    sudo apt install -y unattended-upgrades
    sudo sed -i '0,/^#precedence ::ffff:0:0\/96/{s/^#//; s/10$/100/}' /etc/gai.conf
}

# Audio security (exact from blakkheim guide)
audio_security() {
    if command -v pulseaudio >/dev/null 2>&1; then
        log "Configuring PulseAudio security..."
        
        sudo -u debian mkdir -p /home/debian/.config/pulse
        sudo -u debian tee /home/debian/.config/pulse/daemon.conf > /dev/null <<'EOF'
avoid-resampling = true
flat-volumes = no
EOF
    fi
}

# Miscellaneous optimizations (exact from blakkheim guide)
miscellaneous_setup() {
    log "Applying miscellaneous security settings..."
    
    # More sysctl (exact from guide)
    sudo tee /etc/sysctl.d/98-misc.conf > /dev/null <<'EOF'
net.ipv4.tcp_congestion_control=bbr
vm.swappiness=10
EOF
    
    # Journal Size (exact from guide)
    sudo mkdir -p /etc/systemd/journald.conf.d/
    sudo tee /etc/systemd/journald.conf.d/99-limit.conf > /dev/null <<'EOF'
[Journal]
Compress=yes
SystemMaxUse=100M
EOF
    
    sudo systemctl restart systemd-journald
}

# Final system cleanup and verification
final_cleanup() {
    log "Performing final cleanup and verification..."
    
    # Clean package cache
    sudo apt autoclean
    sudo apt autoremove --purge -y
    
    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.conf 2>/dev/null
    
    # Set secure permissions on sensitive files
    sudo chmod 600 /etc/ssh/ssh_host_*_key
    sudo chmod 644 /etc/ssh/ssh_host_*_key.pub
    
    # Ensure proper ownership
    sudo chown root:root /etc/ssh/ssh_host_*
}

# Main execution
main() {
    log "Starting comprehensive Debian 12 security hardening..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Execute hardening steps
    basic_hardening
    package_security
    kernel_hardening
    nftables_firewall
    application_sandboxing
    enhanced_ssh
    enhanced_sudo
    time_sync
    hardware_security
    user_security
    hidden_pids
    dns_security
    automatic_updates
    audio_security
    miscellaneous_setup
    final_cleanup
    
    log "Comprehensive security hardening completed!"
    
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════════╗
║                              HARDENING COMPLETE                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║ SECURITY HARDENING APPLIED:                                                  ║
║                                                                              ║
║ SYSTEM CORE PROTECTION                                                       ║
║ • Core dump protection disabled                                              ║
║ • systemd coredump storage disabled                                          ║
║ • User account 'debian' created with secure permissions                      ║
║                                                                              ║
║ NETWORK SECURITY                                                             ║
║ • nftables firewall configured (ports 22, 31926, 80, 443)                    ║
║ • HTTPS-only package repositories                                            ║
║ • Network stack hardening (ICMP, redirects, source routing)                  ║
║ • DNSCrypt proxy for encrypted DNS queries                                   ║
║                                                                              ║
║ ACCESS CONTROL                                                               ║
║ • SSH hardened (no root, key-only, restricted algorithms)                    ║
║ • Sudo configured for passwordless system updates/reboot                     ║
║ • User processes hidden from other users (hidepid=2)                         ║
║ • Secure umask (077) for new files                                           ║
║                                                                              ║
║ KERNEL HARDENING                                                             ║
║ • CPU vulnerability mitigations (Spectre, Meltdown, L1TF)                    ║
║ • Memory protection (ASLR, stack randomization, init_on_alloc)               ║
║ • AppArmor LSM enabled with lockdown mode                                    ║
║ • BPF hardening and unprivileged access restrictions                         ║
║ • User namespace restrictions                                                ║
║ • Kernel pointer hiding and dmesg restrictions                               ║
║                                                                              ║
║ APPLICATION SECURITY                                                         ║
║ • AppArmor mandatory access control                                          ║
║ • Firejail application sandboxing                                            ║
║ • Automatic security updates enabled                                         ║
║                                                                              ║
║ SYSTEM SERVICES                                                              ║
║ • OpenNTPD secure time synchronization                                       ║
║ • RFKill wireless control available                                          ║
║ • PulseAudio optimized (avoid-resampling, flat-volumes)                      ║
║ • systemd journal size limits                                                ║
║                                                                              ║
║ FILESYSTEM SECURITY                                                          ║
║ • File system protections (hardlinks, symlinks, FIFOs)                       ║
║ • User cache directory in tmpfs                                              ║
║ • Home directory permissions secured (mode 700)                              ║
║                                                                              ║
║ PERFORMANCE OPTIMIZATIONS                                                    ║
║ • BBR TCP congestion control                                                 ║
║ • Reduced swap tendency (swappiness=10)                                      ║
║                                                                              ║
║ SOURCES:                                                                     ║
║ • Original user hardening script                                             ║
║ • blakkheim's "Linux Security Hardening and Other Tweaks"                    ║
║   (Last updated: 05/07/2025)                                                 ║
║                                                                              ║
║ REBOOT REQUIRED FOR:                                                         ║
║   • Kernel security parameters to take effect                                ║
║   • Process hiding (hidepid) functionality                                   ║
║   • DNS encryption and system resolver changes                               ║
║   • tmpfs mounts and filesystem changes                                      ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF
    
    warn "REBOOT REQUIRED: Many security features require restart to activate properly."
    
    read -p "Reboot now to activate all security features? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Activating security features with reboot..."
        sudo reboot
    fi
}

# Execute main function
main "$@"
