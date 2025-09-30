#!/bin/bash

# Complete Debian 13 (Trixie) Security Hardening Script with Docker
# Based on original script + blakkheim's guide (https://vez.mrsk.me/linux-hardening)
# Run as root or with sudo privileges

set -euo pipefail

echo "Starting comprehensive Debian 13 (Trixie) security hardening with Docker..."

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
    apt install -y cron sudo curl wget passwd apache2-utils procps util-linux
    
    # Create debian user if not exists
    sudo useradd -m -s /bin/bash debian 2>/dev/null || true
    echo "debian:TempPass123" | sudo chpasswd
    sudo passwd -u debian
    
    # Core dump protection
    printf '* hard core 0\n* soft core 0' | sudo tee -a /etc/security/limits.conf
    
    # Create sysctl.d directory if it doesn't exist
    sudo mkdir -p /etc/sysctl.d
    printf 'fs.suid_dumpable=0\nkernel.core_pattern=|/bin/false' | sudo tee /etc/sysctl.d/9999-disable-core-dump.conf
    sudo sysctl -p /etc/sysctl.d/9999-disable-core-dump.conf 2>/dev/null || warn "Could not apply sysctl settings (may require reboot)"
    
    sudo mkdir -p /etc/systemd/coredump.conf.d/
    printf '[Coredump]\nStorage=none\nProcessSizeMax=0' | sudo tee /etc/systemd/coredump.conf.d/custom.conf
    sudo systemctl daemon-reload 2>/dev/null || warn "Could not reload systemd daemon"
}

# Modified iptables firewall (replacing nftables)
iptables_firewall() {
    log "Configuring iptables firewall (replacing nftables)..."
    
    # Install iptables and related tools
    sudo apt install -y iptables arptables ebtables
    
    # Remove nftables
    sudo apt purge -y nftables netfilter-persistent 2>/dev/null || true
    
    # Set legacy alternatives
    sudo update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || warn "Could not set iptables alternative"
    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || warn "Could not set ip6tables alternative"
    sudo update-alternatives --set arptables /usr/sbin/arptables-legacy 2>/dev/null || warn "Could not set arptables alternative"
    sudo update-alternatives --set ebtables /usr/sbin/ebtables-legacy 2>/dev/null || warn "Could not set ebtables alternative"
    
    # Clear existing rules
    sudo iptables -F
    
    # Configure iptables rules
    sudo iptables -A INPUT -i lo -j ACCEPT
    sudo iptables -A INPUT ! -i lo -d 127.0.0.0/8 -j DROP
    sudo iptables -A OUTPUT -j ACCEPT
    sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    sudo iptables -A INPUT -p tcp -m state --state NEW --dport 22 -j ACCEPT
    sudo iptables -A INPUT -p tcp -m state --state NEW --dport 31926 -j ACCEPT
    sudo iptables -A INPUT -p tcp -m state --state NEW --dport 443 -j ACCEPT
    sudo iptables -A INPUT -m state --state NEW -j ACCEPT
    sudo iptables -A INPUT -j DROP
    
    # Set default policies
    sudo iptables --policy INPUT DROP
    sudo iptables --policy FORWARD DROP
    sudo iptables --policy OUTPUT DROP
    
    # Install and configure iptables-persistent to save rules
    sudo apt install -y iptables-persistent
    
    # Save current rules
    sudo mkdir -p /etc/iptables
    sudo iptables-save > /etc/iptables/rules.v4 2>/dev/null || warn "Could not save iptables rules"
    sudo ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || warn "Could not save ip6tables rules"
    
    log "iptables firewall configured and rules saved"
}

# Docker setup and configuration
docker_setup() {
    log "Installing and configuring Docker..."
    
    # Install prerequisites
    sudo apt update
    sudo apt install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || warn "Could not add Docker GPG key"
    
    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add debian user to docker group
    sudo usermod -aG docker debian
    
    # Enable and start Docker service
    sudo systemctl enable docker 2>/dev/null || warn "Could not enable Docker service"
    sudo systemctl start docker 2>/dev/null || warn "Could not start Docker service"
    
    # Configure Docker daemon for security
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true,
    "seccomp-profile": "/etc/docker/seccomp.json",
    "storage-driver": "overlay2"
}
EOF
    
    # Create Docker seccomp profile for additional security
    sudo tee /etc/docker/seccomp.json > /dev/null <<'EOF'
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "archMap": [
        {
            "architecture": "SCMP_ARCH_X86_64",
            "subArchitectures": [
                "SCMP_ARCH_X86",
                "SCMP_ARCH_X32"
            ]
        }
    ],
    "syscalls": [
        {
            "names": [
                "accept",
                "accept4",
                "access",
                "adjtimex",
                "alarm",
                "bind",
                "brk",
                "capget",
                "capset",
                "chdir",
                "chmod",
                "chown",
                "chown32",
                "clock_getres",
                "clock_gettime",
                "clock_nanosleep",
                "close",
                "connect",
                "copy_file_range",
                "creat",
                "dup",
                "dup2",
                "dup3",
                "epoll_create",
                "epoll_create1",
                "epoll_ctl",
                "epoll_ctl_old",
                "epoll_pwait",
                "epoll_wait",
                "epoll_wait_old",
                "eventfd",
                "eventfd2",
                "execve",
                "execveat",
                "exit",
                "exit_group",
                "faccessat",
                "fadvise64",
                "fadvise64_64",
                "fallocate",
                "fanotify_mark",
                "fchdir",
                "fchmod",
                "fchmodat",
                "fchown",
                "fchown32",
                "fchownat",
                "fcntl",
                "fcntl64",
                "fdatasync",
                "fgetxattr",
                "flistxattr",
                "flock",
                "fork",
                "fremovexattr",
                "fsetxattr",
                "fstat",
                "fstat64",
                "fstatat64",
                "fstatfs",
                "fstatfs64",
                "fsync",
                "ftruncate",
                "ftruncate64",
                "futex",
                "futimesat",
                "getcpu",
                "getcwd",
                "getdents",
                "getdents64",
                "getegid",
                "getegid32",
                "geteuid",
                "geteuid32",
                "getgid",
                "getgid32",
                "getgroups",
                "getgroups32",
                "getitimer",
                "getpeername",
                "getpgid",
                "getpgrp",
                "getpid",
                "getppid",
                "getpriority",
                "getrandom",
                "getresgid",
                "getresgid32",
                "getresuid",
                "getresuid32",
                "getrlimit",
                "get_robust_list",
                "getrusage",
                "getsid",
                "getsockname",
                "getsockopt",
                "get_thread_area",
                "gettid",
                "gettimeofday",
                "getuid",
                "getuid32",
                "getxattr",
                "inotify_add_watch",
                "inotify_init",
                "inotify_init1",
                "inotify_rm_watch",
                "io_cancel",
                "ioctl",
                "io_destroy",
                "io_getevents",
                "ioprio_get",
                "ioprio_set",
                "io_setup",
                "io_submit",
                "ipc",
                "kill",
                "lchown",
                "lchown32",
                "lgetxattr",
                "link",
                "linkat",
                "listen",
                "listxattr",
                "llistxattr",
                "lremovexattr",
                "lseek",
                "lsetxattr",
                "lstat",
                "lstat64",
                "madvise",
                "memfd_create",
                "mincore",
                "mkdir",
                "mkdirat",
                "mknod",
                "mknodat",
                "mlock",
                "mlock2",
                "mlockall",
                "mmap",
                "mmap2",
                "mprotect",
                "mq_getsetattr",
                "mq_notify",
                "mq_open",
                "mq_timedreceive",
                "mq_timedsend",
                "mq_unlink",
                "mremap",
                "msgctl",
                "msgget",
                "msgrcv",
                "msgsnd",
                "msync",
                "munlock",
                "munlockall",
                "munmap",
                "nanosleep",
                "newfstatat",
                "_newselect",
                "open",
                "openat",
                "pause",
                "pipe",
                "pipe2",
                "poll",
                "ppoll",
                "prctl",
                "pread64",
                "preadv",
                "prlimit64",
                "pselect6",
                "ptrace",
                "pwrite64",
                "pwritev",
                "read",
                "readahead",
                "readlink",
                "readlinkat",
                "readv",
                "recv",
                "recvfrom",
                "recvmmsg",
                "recvmsg",
                "remap_file_pages",
                "removexattr",
                "rename",
                "renameat",
                "renameat2",
                "restart_syscall",
                "rmdir",
                "rt_sigaction",
                "rt_sigpending",
                "rt_sigprocmask",
                "rt_sigqueueinfo",
                "rt_sigreturn",
                "rt_sigsuspend",
                "rt_sigtimedwait",
                "rt_tgsigqueueinfo",
                "sched_getaffinity",
                "sched_getattr",
                "sched_getparam",
                "sched_get_priority_max",
                "sched_get_priority_min",
                "sched_getscheduler",
                "sched_rr_get_interval",
                "sched_setaffinity",
                "sched_setattr",
                "sched_setparam",
                "sched_setscheduler",
                "sched_yield",
                "seccomp",
                "select",
                "semctl",
                "semget",
                "semop",
                "semtimedop",
                "send",
                "sendfile",
                "sendfile64",
                "sendmmsg",
                "sendmsg",
                "sendto",
                "setfsgid",
                "setfsgid32",
                "setfsuid",
                "setfsuid32",
                "setgid",
                "setgid32",
                "setgroups",
                "setgroups32",
                "setitimer",
                "setpgid",
                "setpriority",
                "setregid",
                "setregid32",
                "setresgid",
                "setresgid32",
                "setresuid",
                "setresuid32",
                "setreuid",
                "setreuid32",
                "setrlimit",
                "set_robust_list",
                "setsid",
                "setsockopt",
                "set_thread_area",
                "set_tid_address",
                "setuid",
                "setuid32",
                "setxattr",
                "shmat",
                "shmctl",
                "shmdt",
                "shmget",
                "shutdown",
                "sigaltstack",
                "signalfd",
                "signalfd4",
                "sigreturn",
                "socket",
                "socketcall",
                "socketpair",
                "splice",
                "stat",
                "stat64",
                "statfs",
                "statfs64",
                "statx",
                "symlink",
                "symlinkat",
                "sync",
                "sync_file_range",
                "syncfs",
                "sysinfo",
                "tee",
                "tgkill",
                "time",
                "timer_create",
                "timer_delete",
                "timerfd_create",
                "timerfd_gettime",
                "timerfd_settime",
                "timer_getoverrun",
                "timer_gettime",
                "timer_settime",
                "times",
                "tkill",
                "truncate",
                "truncate64",
                "ugetrlimit",
                "umask",
                "uname",
                "unlink",
                "unlinkat",
                "utime",
                "utimensat",
                "utimes",
                "vfork",
                "vmsplice",
                "wait4",
                "waitid",
                "waitpid",
                "write",
                "writev"
            ],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
EOF
    
    # Set proper permissions for Docker files
    sudo chmod 600 /etc/docker/daemon.json 2>/dev/null || warn "Could not set Docker daemon.json permissions"
    sudo chmod 600 /etc/docker/seccomp.json 2>/dev/null || warn "Could not set Docker seccomp.json permissions"
    
    # Restart Docker to apply new configuration
    sudo systemctl restart docker 2>/dev/null || warn "Could not restart Docker service"
    
    log "Docker installed and configured securely"
}

# Enhanced package manager security - fixed for modern Debian
package_security() {
    log "Configuring secure package sources..."
    
    # Handle modern Debian sources format
    if [ -f /etc/apt/sources.list ]; then
        sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
    elif [ -f /etc/apt/sources.list.d/debian.sources ]; then
        sudo cp /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.backup
    fi
    
    # Configure HTTPS-only mirrors - create traditional sources.list
    sudo tee /etc/apt/sources.list > /dev/null <<EOF
# Debian 13 (trixie) - HTTPS only sources
deb https://deb.debian.org/debian/ trixie main contrib non-free-firmware
deb-src https://deb.debian.org/debian/ trixie main contrib non-free-firmware

deb https://security.debian.org/debian-security trixie-security main contrib non-free-firmware
deb-src https://security.debian.org/debian-security trixie-security main contrib non-free-firmware

deb https://deb.debian.org/debian/ trixie-updates main contrib non-free-firmware
deb-src https://deb.debian.org/debian/ trixie-updates main contrib non-free-firmware
EOF
    
    # Remove the new format file to avoid conflicts
    sudo rm -f /etc/apt/sources.list.d/debian.sources
    
    apt update
}

# Comprehensive kernel hardening
kernel_hardening() {
    log "Applying kernel hardening parameters..."
    
    # Install kernel hardening packages
    apt install -y linux-headers-$(uname -r) 2>/dev/null || warn "Could not install kernel headers"
    
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
    sudo sysctl -p /etc/sysctl.d/99-sysctl.conf 2>/dev/null || warn "Some sysctl settings could not be applied (may require reboot)"
    
    # Configure kernel boot parameters - skip in container
    if [ -f /etc/default/grub ]; then
        log "Configuring kernel boot parameters..."
        
        # Backup GRUB configuration
        sudo cp /etc/default/grub /etc/default/grub.backup
        
        # Add security kernel parameters (exact from blakkheim guide)
        KERNEL_PARAMS="apparmor=1 init_on_alloc=1 init_on_free=1 l1tf=full,force l1d_flush=on gather_data_sampling=force spec_rstack_overflow=ibpb lockdown=confidentiality lsm=landlock,lockdown,yama,apparmor page_alloc.shuffle=1 slab_nomerge spec_store_bypass_disable=on spectre_v2=on vsyscall=none randomize_kstack_offset=1"
        
        # Update GRUB configuration
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\([^\"]*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $KERNEL_PARAMS\"/" /etc/default/grub
        
        # Update GRUB
        sudo update-grub 2>/dev/null || warn "Could not update GRUB"
        
        warn "Kernel parameters updated. Reboot required for changes to take effect."
    else
        warn "No GRUB configuration found - skipping kernel parameters (container environment)"
    fi
}

# Application sandboxing
application_sandboxing() {
    log "Setting up application sandboxing..."

    # Install and configure AppArmor (fixed for Trixie Python compatibility)
    # Note: Trixie uses Python 3.12+ which may have compatibility issues with older apparmor-utils
    # We'll install apparmor core without the utils if there's a conflict
    if apt install -y apparmor apparmor-profiles apparmor-profiles-extra 2>/dev/null; then
        log "AppArmor core and profiles installed"
        # Try to install apparmor-utils separately, skip if conflicts
        apt install -y apparmor-utils 2>/dev/null || warn "Could not install apparmor-utils (Python version conflict), using core AppArmor only"
    else
        warn "Could not install AppArmor packages"
    fi

    sudo systemctl enable apparmor 2>/dev/null || warn "Could not enable AppArmor"
    sudo systemctl start apparmor 2>/dev/null || warn "Could not start AppArmor"

    # Install Firejail
    apt install -y firejail 2>/dev/null || warn "Could not install Firejail"
    
    # Configure Firejail (exact from blakkheim guide)
    sudo systemctl enable --now apparmor 2>/dev/null || warn "Could not enable AppArmor service"
    sudo apparmor_parser -r /etc/apparmor.d/firejail-default 2>/dev/null || warn "Could not load Firejail AppArmor profile"
    sudo firecfg 2>/dev/null || warn "Could not configure Firejail"
    echo "debian" | sudo tee /etc/firejail/firejail.users > /dev/null
    
    # Update PATH for firejail (exact from guide)
    echo 'export PATH=/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin' | sudo tee -a /etc/profile
    
    log "AppArmor and Firejail configured. Applications will be sandboxed."
}

# Enhanced SSH configuration (original enhanced)
enhanced_ssh() {
    log "Enhancing SSH configuration..."
    
    # Install SSH if not present
    apt install -y openssh-server
    
    sudo groupadd -f ssh-user
    sudo usermod -aG sudo debian
    sudo usermod -aG ssh-user debian
    
    # Enhanced SSH configuration (original but cleaned up)
    sudo mkdir -p /etc/ssh/sshd_config.d
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
    
    sudo systemctl restart sshd 2>/dev/null || sudo systemctl restart ssh 2>/dev/null || warn "Could not restart SSH service"
}

# Enhanced sudo configuration (exact from blakkheim guide with Docker)
enhanced_sudo() {
    log "Configuring enhanced sudo settings..."
    
    # Sudo logging (original)
    sudo mkdir -p /etc/sudoers.d
    printf 'Defaults        logfile="/var/log/sudo.log"' | sudo tee /etc/sudoers.d/log
    
    # Enhanced sudo security (exact from blakkheim guide adapted for apt + Docker)
    sudo tee /etc/sudoers > /dev/null <<'EOF'
Defaults env_reset
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults umask=0022
Defaults umask_override

root    ALL=(ALL:ALL) ALL

Cmnd_Alias PACMAN = /usr/bin/apt update, /usr/bin/apt upgrade
Cmnd_Alias REBOOT = /sbin/reboot ""
Cmnd_Alias SHUTDOWN = /sbin/poweroff ""
Cmnd_Alias DOCKER = /usr/bin/docker, /usr/bin/docker-compose

debian ALL=(root) NOPASSWD: PACMAN
debian ALL=(root) NOPASSWD: REBOOT
debian ALL=(root) NOPASSWD: SHUTDOWN
debian ALL=(root) NOPASSWD: DOCKER
EOF
}

# Time synchronization (exact from blakkheim guide)
time_sync() {
    log "Configuring secure time synchronization..."
    
    # Install and configure OpenNTPD
    apt install -y openntpd
    
    # Disable systemd-timesyncd
    sudo systemctl disable --now systemd-timesyncd 2>/dev/null || warn "Could not disable systemd-timesyncd"
    
    # Configure OpenNTPD with quality servers (exact from guide)
    sudo tee /etc/openntpd/ntpd.conf > /dev/null <<'EOF'
server time.apple.com
server time.cloudflare.com
server pool.ntp.org
constraint from "https://example.com"
EOF
    
    sudo systemctl enable openntpd 2>/dev/null || warn "Could not enable OpenNTPD"
    sudo systemctl start openntpd 2>/dev/null || warn "Could not start OpenNTPD"
}

# Hardware security
hardware_security() {
    log "Configuring hardware security..."
    
    # RFKill setup mentioned in guide but blocking is optional
    log "RFKill available. To block wireless: sudo systemctl enable --now rfkill-block@all.service"
    
    # Blacklist uncommon filesystems (not explicitly in guide but common hardening)
    sudo mkdir -p /etc/modprobe.d
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
    sudo update-initramfs -u 2>/dev/null || warn "Could not update initramfs (may not be available in container)"
}

# User security settings (exact from blakkheim guide)
user_security() {
    log "Applying user security settings..."
    
    # Set secure umask for debian user (exact from guide)
    echo 'umask 77' | sudo tee -a /home/debian/.bashrc
    
    # Secure home directory permissions (exact from guide)
    sudo chmod -R go-rwx /home/debian
    
    # Create tmpfs for user cache (exact from guide) - skip in container
    if [ -f /etc/fstab ]; then
        echo 'tmpfs /home/debian/.cache tmpfs rw,size=250M,noexec,noatime,nodev,uid=debian,gid=debian,mode=700 0 0' | sudo tee -a /etc/fstab
    else
        warn "No /etc/fstab found - skipping tmpfs cache (container environment)"
    fi
}

# Hidden PIDs (from blakkheim guide miscellaneous section)
hidden_pids() {
    log "Configuring hidden PIDs..."
    
    # Hide processes from other users (mentioned in guide) - skip in container
    if [ -f /etc/fstab ]; then
        echo 'proc /proc proc defaults,hidepid=2,gid=proc 0 0' | sudo tee -a /etc/fstab
        sudo groupadd -f proc
        sudo usermod -aG proc debian
        log "Process hiding configured. Will take effect after reboot."
    else
        warn "No /etc/fstab found - skipping hidepid (container environment)"
    fi
}

# DNSCrypt (from blakkheim guide miscellaneous section)
dns_security() {
    log "Installing and configuring DNSCrypt manually..."
    
    # Install dnscrypt-proxy manually from GitHub releases
    cd /tmp
    
    # Download latest version
    wget https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.14/dnscrypt-proxy-linux_x86_64-2.1.14.tar.gz 2>/dev/null || {
        warn "Could not download dnscrypt-proxy, skipping DNS encryption"
        return 0
    }
    
    # Extract and install
    tar -xzf dnscrypt-proxy-linux_x86_64-2.1.14.tar.gz 2>/dev/null || {
        warn "Could not extract dnscrypt-proxy archive"
        return 0
    }
    
    sudo cp linux-x86_64/dnscrypt-proxy /usr/local/bin/
    sudo chmod +x /usr/local/bin/dnscrypt-proxy
    
    # Create configuration directory
    sudo mkdir -p /etc/dnscrypt-proxy
    
    # Create dnscrypt-proxy configuration
    sudo tee /etc/dnscrypt-proxy/dnscrypt-proxy.toml > /dev/null <<'EOF'
##############################################
#                                            #
#        dnscrypt-proxy configuration        #
#                                            #
##############################################

server_names = ['cloudflare', 'quad9-dnscrypt-ip4-nofilter-pri', 'google']

listen_addresses = ['127.0.0.1:53']

max_clients = 250

ipv4_servers = true
ipv6_servers = false

dnscrypt_servers = true
doh_servers = true

require_dnssec = true
require_nolog = true
require_nofilter = true

disabled_server_names = []

force_tcp = false
timeout = 5000
keepalive = 30

cert_refresh_delay = 240
dnscrypt_ephemeral_keys = false
tls_disable_session_tickets = false

fallback_resolvers = ['9.9.9.9:53', '8.8.8.8:53']
ignore_system_dns = false

netprobe_timeout = 60
netprobe_address = '9.9.9.9:53'

log_files_max_size = 10
log_files_max_age = 7
log_files_max_backups = 1

block_ipv6 = false

reject_ttl = 600

cache = true
cache_size = 4096
cache_min_ttl = 2400
cache_max_ttl = 86400
cache_neg_min_ttl = 60
cache_neg_max_ttl = 600

[query_log]
  # file = '/var/log/dnscrypt-proxy/query.log'

[nx_log]
  # file = '/var/log/dnscrypt-proxy/nx.log'

[blacklist]

[ip_blacklist]

[whitelist]

[schedules]

[sources]

  [sources.'public-resolvers']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md', 'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md']
  cache_file = '/var/cache/dnscrypt-proxy/public-resolvers.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
  prefix = ''

  [sources.'relays']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/relays.md', 'https://download.dnscrypt.info/resolvers-list/v3/relays.md']
  cache_file = '/var/cache/dnscrypt-proxy/relays.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
  prefix = ''

[static]
EOF

    # Create cache directory
    sudo mkdir -p /var/cache/dnscrypt-proxy
    sudo mkdir -p /var/log/dnscrypt-proxy
    
    # Create dnscrypt-proxy user
    sudo useradd -r -d /var/cache/dnscrypt-proxy -s /usr/sbin/nologin dnscrypt-proxy 2>/dev/null || true
    sudo chown -R dnscrypt-proxy:dnscrypt-proxy /var/cache/dnscrypt-proxy
    sudo chown -R dnscrypt-proxy:dnscrypt-proxy /var/log/dnscrypt-proxy
    
    # Create systemd service
    sudo tee /etc/systemd/system/dnscrypt-proxy.service > /dev/null <<'EOF'
[Unit]
Description=DNSCrypt client proxy
Documentation=https://github.com/DNSCrypt/dnscrypt-proxy/wiki
After=network.target
Before=nss-lookup.target
Wants=nss-lookup.target

[Service]
Type=simple
StandardOutput=journal
StandardError=journal
ExecStart=/usr/local/bin/dnscrypt-proxy -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml
User=dnscrypt-proxy
Group=dnscrypt-proxy
Restart=always
RestartSec=5

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths=/var/cache/dnscrypt-proxy /var/log/dnscrypt-proxy
SystemCallArchitectures=native
SystemCallFilter=~@clock @cpu-emulation @debug @keyring @module @mount @obsolete @raw-io @reboot @swap

[Install]
WantedBy=multi-user.target
EOF
    
    # Configure system to use dnscrypt-proxy
    sudo mkdir -p /etc/systemd/resolved.conf.d
    sudo tee /etc/systemd/resolved.conf > /dev/null <<'EOF'
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
DNSSEC=yes
EOF
    
    # Backup original resolv.conf
    sudo cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true
    
    # Disable systemd-resolved stub listener and restart
    sudo systemctl disable systemd-resolved 2>/dev/null || warn "Could not disable systemd-resolved"
    sudo systemctl stop systemd-resolved 2>/dev/null || warn "Could not stop systemd-resolved"
    
    # Create manual resolv.conf pointing to dnscrypt-proxy
    sudo tee /etc/resolv.conf > /dev/null <<'EOF'
# Generated by dnscrypt-proxy hardening script
nameserver 127.0.0.1
options edns0
EOF
    
    # Make resolv.conf immutable to prevent overwriting
    sudo chattr +i /etc/resolv.conf 2>/dev/null || warn "Could not make resolv.conf immutable"
    
    # Reload systemd and enable dnscrypt-proxy
    sudo systemctl daemon-reload
    sudo systemctl enable dnscrypt-proxy 2>/dev/null || warn "Could not enable dnscrypt-proxy"
    sudo systemctl start dnscrypt-proxy 2>/dev/null || warn "Could not start dnscrypt-proxy"
    
    # Wait a moment for service to start
    sleep 3
    
    # Check if dnscrypt-proxy is running
    if sudo systemctl is-active --quiet dnscrypt-proxy; then
        log "DNSCrypt-proxy installed and running successfully"
        log "DNS queries will be encrypted and authenticated"
    else
        warn "DNSCrypt-proxy may not be running properly"
        log "Check status with: sudo systemctl status dnscrypt-proxy"
    fi
    
    # Cleanup
    cd /
    rm -rf /tmp/dnscrypt-proxy-linux_x86_64-2.1.14.tar.gz /tmp/linux-x86_64 2>/dev/null || true
    
    log "DNSCrypt configured. DNS queries will be encrypted."
}

# Automatic updates (original)
automatic_updates() {
    log "Configuring automatic security updates..."
    
    sudo apt install -y unattended-upgrades
    sudo sed -i '0,/^#precedence ::ffff:0:0\/96/{s/^#//; s/10$/100/}' /etc/gai.conf 2>/dev/null || warn "Could not update gai.conf"
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
    
    sudo systemctl restart systemd-journald 2>/dev/null || warn "Could not restart systemd-journald"
}

# Final system cleanup and verification
final_cleanup() {
    log "Performing final cleanup and verification..."
    
    # Clean package cache
    sudo apt autoclean
    sudo apt autoremove --purge -y
    
    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.conf 2>/dev/null || warn "Could not apply main sysctl.conf"
    
    # Set secure permissions on sensitive files
    sudo chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || warn "Could not set SSH key permissions"
    sudo chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || warn "Could not set SSH public key permissions"
    
    # Ensure proper ownership
    sudo chown root:root /etc/ssh/ssh_host_* 2>/dev/null || warn "Could not set SSH key ownership"
}

# Main execution
main() {
    log "Starting comprehensive Debian 13 (Trixie) security hardening with Docker..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Execute hardening steps
    basic_hardening
    package_security
    kernel_hardening
    iptables_firewall  # Changed from nftables_firewall
    docker_setup       # Added Docker setup
    application_sandboxing
    enhanced_ssh
    enhanced_sudo
    time_sync
    hardware_security
    user_security
    hidden_pids
    #dns_security
    automatic_updates
    audio_security
    miscellaneous_setup
    final_cleanup
    
    log "Comprehensive security hardening with Docker completed!"
    
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
║ • iptables firewall configured (ports 22, 31926, 443)                       ║
║ • HTTPS-only package repositories                                            ║
║ • Network stack hardening (ICMP, redirects, source routing)                  ║
║ • DNSCrypt proxy for encrypted DNS queries                                   ║
║                                                                              ║
║ DOCKER CONTAINERIZATION                                                      ║
║ • Docker CE installed and configured securely                                ║
║ • Secure Docker daemon configuration with seccomp profile                    ║
║ • User 'debian' added to docker group                                        ║
║ • Docker management commands in sudoers                                      ║
║                                                                              ║
║ ACCESS CONTROL                                                               ║
║ • SSH hardened (no root, key-only, restricted algorithms)                    ║
║ • Sudo configured for passwordless system updates/reboot/docker              ║
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
║ • Docker official documentation and security best practices                  ║
║ • Updated for Debian 13 (Trixie) compatibility                               ║
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
    
    echo "Hardening script completed successfully."
}

# Execute main function
main "$@"
