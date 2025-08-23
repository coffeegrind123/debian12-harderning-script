#!/bin/bash

# SystemD Security Hardening Script
# Automatically applies security hardening to systemd services
# Based on systemd.md best practices and template-based approach

set -euo pipefail

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root or with sudo"
    exit 1
fi

log "Starting SystemD Security Hardening..."

# Create master security template
create_security_template() {
    log "Creating master security template..."
    
    cat > /etc/systemd/system/security.conf << 'EOF'
[Service]
# User isolation
DynamicUser=yes

# Filesystem protection
PrivateTmp=true
PrivateDevices=true
PrivateNetwork=true
PrivateUsers=true
InaccessiblePaths=-/mnt/
ProtectSystem=strict
ProtectHome=true
ProtectHostname=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectProc=invisible
ProcSubset=pid

# Advanced restrictions
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
NoNewPrivileges=true
RemoveIPC=true

# Network restrictions
IPAddressDeny=any
RestrictAddressFamilies=none

# Memory protection
MemoryDenyWriteExecute=true

# System call filtering
SystemCallArchitectures=native
SystemCallFilter=~@cpu-emulation @debug @module @mount @obsolete @reboot @swap @raw-io @privileged @resources

# Capability restrictions
CapabilityBoundingSet=~CAP_SYS_PACCT CAP_KILL CAP_WAKE_ALARM CAP_LINUX_IMMUTABLE CAP_IPC_LOCK CAP_SYS_TTY_CONFIG CAP_SYS_BOOT CAP_SYS_CHROOT CAP_BLOCK_SUSPEND CAP_LEASE CAP_MKNOD CAP_CHOWN CAP_FSETID CAP_SETFCAP CAP_SETUID CAP_SETGID CAP_SETPCAP CAP_SYS_RAWIO CAP_SYS_PTRACE CAP_SYS_NICE CAP_SYS_RESOURCE CAP_NET_ADMIN CAP_SYS_ADMIN CAP_MAC_ADMIN CAP_MAC_OVERRIDE CAP_DAC_OVERRIDE CAP_DAC_READ_SEARCH CAP_FOWNER CAP_IPC_OWNER CAP_AUDIT_CONTROL CAP_AUDIT_READ CAP_AUDIT_WRITE CAP_BPF CAP_NET_BIND_SERVICE CAP_NET_BROADCAST CAP_NET_RAW

# File permissions
UMask=0077
EOF
    
    log "Master security template created at /etc/systemd/system/security.conf"
}

# SSH Service hardening
harden_ssh() {
    log "Hardening SSH service..."
    
    mkdir -p /etc/systemd/system/ssh.service.d/
    cat > /etc/systemd/system/ssh.service.d/security.conf << 'EOF'
[Service]
# Basic filesystem protection (SSH needs some privileges)
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectClock=yes

# Process visibility restrictions
ProtectProc=invisible
ProcSubset=pid

# Advanced restrictions
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes
NoNewPrivileges=yes
RemoveIPC=yes

# Network restrictions (SSH needs network access)
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# Allow SSH to write to its required directories
ReadWritePaths=/var/log /var/run /run

# Memory protection
MemoryDenyWriteExecute=yes

# Conservative syscall filtering
SystemCallArchitectures=native
SystemCallFilter=@system-service @network-io @file-system @signal

# File permissions
UMask=0077

# Resource limits
MemoryMax=512M
TasksMax=500
EOF
    
    log "SSH service hardening configuration created"
}

# Cron service hardening
harden_cron() {
    log "Hardening Cron service..."
    
    mkdir -p /etc/systemd/system/cron.service.d/
    cat > /etc/systemd/system/cron.service.d/security.conf << 'EOF'
[Service]
# Filesystem protection
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectClock=yes

# Process visibility
ProtectProc=invisible
ProcSubset=pid

# Advanced restrictions
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes
NoNewPrivileges=yes
RemoveIPC=yes

# Network restrictions (cron usually doesn't need network)
PrivateNetwork=yes

# Allow cron to write to necessary directories
ReadWritePaths=/var/spool/cron /var/log /run

# Memory protection
MemoryDenyWriteExecute=yes

# Syscall filtering
SystemCallArchitectures=native
SystemCallFilter=@system-service @file-system @signal

# File permissions
UMask=0077

# Resource limits
MemoryMax=256M
TasksMax=100
EOF
    
    log "Cron service hardening configuration created"
}

# Exim4 mail service hardening
harden_exim4() {
    log "Hardening Exim4 mail service..."
    
    mkdir -p /etc/systemd/system/exim4.service.d/
    cat > /etc/systemd/system/exim4.service.d/security.conf << 'EOF'
[Service]
# Filesystem protection
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectClock=yes

# Process visibility
ProtectProc=invisible
ProcSubset=pid

# Advanced restrictions
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes
NoNewPrivileges=yes
RemoveIPC=yes

# Network access for mail service
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# Allow exim to write to required directories
ReadWritePaths=/var/spool/exim4 /var/log/exim4 /var/lib/exim4 /var/mail /run

# Memory protection
MemoryDenyWriteExecute=yes

# Syscall filtering for mail service
SystemCallArchitectures=native
SystemCallFilter=@system-service @network-io @file-system @signal

# File permissions
UMask=0077

# Resource limits
MemoryMax=512M
TasksMax=200
EOF
    
    log "Exim4 mail service hardening configuration created"
}

# D-Bus service hardening
harden_dbus() {
    log "Hardening D-Bus service..."
    
    mkdir -p /etc/systemd/system/dbus.service.d/
    cat > /etc/systemd/system/dbus.service.d/security.conf << 'EOF'
[Service]
# Filesystem protection
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectClock=yes

# Process visibility
ProtectProc=invisible
ProcSubset=pid

# Advanced restrictions
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes
NoNewPrivileges=yes
RemoveIPC=yes

# D-Bus needs local socket communication
RestrictAddressFamilies=AF_UNIX

# Allow D-Bus to write to its directories
ReadWritePaths=/var/run/dbus /run/dbus

# Memory protection
MemoryDenyWriteExecute=yes

# Syscall filtering for IPC service
SystemCallArchitectures=native
SystemCallFilter=@system-service @file-system @signal @ipc

# Resource limits
MemoryMax=256M
TasksMax=200

# File permissions
UMask=0077
EOF
    
    log "D-Bus service hardening configuration created"
}

# OpenNTPD service hardening
harden_openntpd() {
    log "Hardening OpenNTPD service..."
    
    mkdir -p /etc/systemd/system/openntpd.service.d/
    cat > /etc/systemd/system/openntpd.service.d/security.conf << 'EOF'
[Service]
# Basic filesystem protection (conservative approach for NTP)
PrivateTmp=yes
ProtectSystem=yes
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes

# Advanced restrictions
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes

# Network access for NTP
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# Memory protection
MemoryDenyWriteExecute=yes

# Conservative syscall filtering
SystemCallArchitectures=native

# Resource limits
MemoryMax=64M
TasksMax=50

# File permissions
UMask=0077
EOF
    
    log "OpenNTPD service hardening configuration created"
}

# systemd-udevd service hardening
harden_udevd() {
    log "Hardening systemd-udevd service..."
    
    mkdir -p /etc/systemd/system/systemd-udevd.service.d/
    cat > /etc/systemd/system/systemd-udevd.service.d/security.conf << 'EOF'
[Service]
# Basic protections (udev needs device access)
PrivateTmp=yes
ProtectSystem=yes
ProtectKernelTunables=no
ProtectKernelModules=no
ProtectKernelLogs=yes
ProtectClock=yes

# Process restrictions
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes

# Network restrictions (udev doesn't need network)
PrivateNetwork=yes

# Memory protection
MemoryDenyWriteExecute=yes

# Conservative syscall filtering (udev needs many syscalls)
SystemCallArchitectures=native

# Resource limits
MemoryMax=256M
TasksMax=300

# File permissions
UMask=0022
EOF
    
    log "systemd-udevd service hardening configuration created"
}

# systemd-logind hardening
harden_logind() {
    log "Hardening systemd-logind service..."
    
    mkdir -p /etc/systemd/system/systemd-logind.service.d/
    cat > /etc/systemd/system/systemd-logind.service.d/security.conf << 'EOF'
[Service]
# Filesystem protection
PrivateTmp=yes
ProtectSystem=strict
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes

# Process visibility
ProtectProc=invisible
ProcSubset=pid

# Advanced restrictions
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes
RemoveIPC=yes

# Network restrictions (logind doesn't need network)
PrivateNetwork=yes

# Allow logind to write to required directories
ReadWritePaths=/run/systemd /var/lib/systemd

# Memory protection
MemoryDenyWriteExecute=yes

# Syscall filtering
SystemCallArchitectures=native
SystemCallFilter=@system-service @file-system @signal

# Resource limits
MemoryMax=128M
TasksMax=200

# File permissions
UMask=0077
EOF
    
    log "systemd-logind service hardening configuration created"
}

# systemd-journald hardening
harden_journald() {
    log "Hardening systemd-journald service..."
    
    mkdir -p /etc/systemd/system/systemd-journald.service.d/
    cat > /etc/systemd/system/systemd-journald.service.d/security.conf << 'EOF'
[Service]
# Filesystem protection
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes

# Advanced restrictions
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes
RemoveIPC=yes

# Network restrictions (journald doesn't need network)
PrivateNetwork=yes

# Allow journald to write to log directories
ReadWritePaths=/var/log/journal /run/log

# Memory protection
MemoryDenyWriteExecute=yes

# Syscall filtering
SystemCallArchitectures=native
SystemCallFilter=@system-service @file-system @signal

# Resource limits
MemoryMax=512M
TasksMax=100

# File permissions
UMask=0077
EOF
    
    log "systemd-journald service hardening configuration created"
}

# Apply hardening and restart services
apply_hardening() {
    log "Applying hardening configurations and restarting services..."
    
    # Reload systemd configuration
    systemctl daemon-reload
    
    # List of services to restart (only if they're active)
    services=(
        "ssh.service"
        "cron.service" 
        "exim4.service"
        "dbus.service"
        "openntpd.service"
        "systemd-udevd.service"
        "systemd-logind.service"
        "systemd-journald.service"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log "Restarting $service..."
            systemctl restart "$service" || warn "Failed to restart $service"
        else
            log "Service $service is not active, skipping restart"
        fi
    done
}

# Security analysis and reporting
security_analysis() {
    log "Running security analysis..."
    
    # Show before/after comparison
    echo -e "\n${BLUE}=== SECURITY ANALYSIS RESULTS ===${NC}\n"
    
    # Check if systemd-analyze is available
    if command -v systemd-analyze >/dev/null 2>&1; then
        systemd-analyze security --no-pager 2>/dev/null | head -20 || warn "Could not run security analysis"
    else
        warn "systemd-analyze not available for security analysis"
    fi
    
    echo -e "\n${GREEN}Services with hardening applied:${NC}"
    find /etc/systemd/system -name "security.conf" -path "*/service.d/*" | \
        sed 's|/etc/systemd/system/||; s|\.service\.d/security\.conf||' | \
        sort
}

# Create quick wins configuration for easy services
create_quick_wins() {
    log "Creating quick-wins security configuration..."
    
    cat > /etc/systemd/system/quick-wins.conf << 'EOF'
[Service]
# Quick security wins that rarely break services
ProtectSystem=strict
PrivateTmp=yes
ProtectHome=yes
ProtectClock=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
RestrictSUIDSGID=yes
UMask=0077
LockPersonality=yes
RestrictRealtime=yes
MemoryDenyWriteExecute=yes
SystemCallArchitectures=native
NoNewPrivileges=yes
EOF
    
    log "Quick-wins template created at /etc/systemd/system/quick-wins.conf"
    log "To apply to a service: ln -s /etc/systemd/system/quick-wins.conf /etc/systemd/system/SERVICE.service.d/"
}

# Main execution
main() {
    log "SystemD Security Hardening Script Starting..."
    log "This script will harden multiple systemd services with security restrictions"
    
    echo -e "\n${YELLOW}Services that will be hardened:${NC}"
    echo "  • SSH (sshd)"
    echo "  • Cron"
    echo "  • Exim4 (mail)"
    echo "  • D-Bus"
    echo "  • OpenNTPD"
    echo "  • systemd-udevd"
    echo "  • systemd-logind"
    echo "  • systemd-journald"
    echo ""
    
    read -p "Continue with hardening? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Hardening cancelled by user"
        exit 0
    fi
    
    # Execute hardening steps
    create_security_template
    create_quick_wins
    
    harden_ssh
    harden_cron
    harden_exim4
    harden_dbus
    harden_openntpd
    harden_udevd
    harden_logind
    harden_journald
    
    apply_hardening
    security_analysis
    
    log "SystemD security hardening completed!"
    
    echo -e "\n${GREEN}=== HARDENING COMPLETE ===${NC}"
    echo -e "${YELLOW}IMPORTANT NOTES:${NC}"
    echo "• Services have been hardened with security restrictions"
    echo "• Memory limits, syscall filtering, and isolation applied"
    echo "• If services fail, check journalctl -xeu SERVICE.service"
    echo "• Review /etc/systemd/system/SERVICE.service.d/security.conf for each service"
    echo "• Master template available at /etc/systemd/system/security.conf"
    echo "• Quick-wins template at /etc/systemd/system/quick-wins.conf"
    echo ""
    echo "Run 'systemd-analyze security' to see improved security scores"
    
    warn "Monitor system logs and services after hardening to ensure proper functionality"
}

# Execute main function
main "$@"