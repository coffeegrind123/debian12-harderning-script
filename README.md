# 🛡️ Debian 12 Complete Security Hardening Suite

A comprehensive security hardening solution for Debian 12 systems, providing both **system-level** and **service-level** hardening through automated scripts.

## 📋 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Quick Start](#-quick-start)
- [Scripts Description](#-scripts-description)
- [Security Improvements](#-security-improvements)
- [Installation](#-installation)
- [Usage](#-usage)
- [Advanced Configuration](#-advanced-configuration)
- [Troubleshooting](#-troubleshooting)
- [Security Analysis](#-security-analysis)
- [Contributing](#-contributing)
- [License](#-license)

## 🎯 Overview

This project provides two complementary security hardening scripts for Debian 12:

1. **`install-fixed.sh`** - System-level hardening (kernel, firewall, applications)
2. **`systemd-hardening-script.sh`** - Service-level hardening (systemd services)

Together, they provide **enterprise-grade security** with automated deployment and comprehensive protection against common attack vectors.

## ✨ Features

### 🔧 System-Level Hardening (`install-fixed.sh`)

- **Kernel Hardening**: 40+ sysctl security parameters
- **Network Security**: nftables firewall with strict default-deny policy
- **Application Sandboxing**: AppArmor + Firejail integration
- **SSH Hardening**: Enhanced configuration with secure algorithms
- **Time Security**: OpenNTPD with secure time synchronization
- **Memory Protection**: Core dump prevention and memory hardening
- **Package Security**: HTTPS-only repositories with signature verification
- **Hardware Security**: Filesystem blacklisting and device restrictions

### 🔒 Service-Level Hardening (`systemd-hardening-script.sh`)

- **Progressive Hardening**: Template-based approach with maximum security by default
- **8 Critical Services**: SSH, Cron, Exim4, D-Bus, OpenNTPD, systemd core services
- **Isolation Features**: Filesystem, process, and network isolation
- **Resource Management**: Memory limits, task limits, and CPU controls
- **Capability Restrictions**: Minimal privilege principles
- **Syscall Filtering**: Restricted system call access
- **Memory Protection**: Write-execute prevention and ASLR enhancements

## 🚀 Quick Start

```bash
# 1. Clone or download the scripts
wget https://raw.githubusercontent.com/your-repo/install-fixed.sh
wget https://raw.githubusercontent.com/your-repo/systemd-hardening-script.sh

# 2. Make executable
chmod +x install-fixed.sh systemd-hardening-script.sh

# 3. Run system hardening (as root)
sudo ./install-fixed.sh

# 4. Run service hardening (as root)
sudo ./systemd-hardening-script.sh

# 5. Verify improvements
sudo systemd-analyze security
```

## 📜 Scripts Description

### 🔧 System Hardening Script (`install-fixed.sh`)

Based on the **debian12-hardening-script** with additional improvements and **blakkheim's security guide**.

**What it does:**
- Installs and configures comprehensive security components
- Applies kernel-level hardening parameters
- Sets up application sandboxing with AppArmor and Firejail
- Configures secure SSH, time synchronization, and networking
- Implements memory and core dump protection
- Hardens package management and repositories

**Runtime:** ~10-15 minutes (depending on network speed for package downloads)

### 🔒 Service Hardening Script (`systemd-hardening-script.sh`)

Custom-developed script implementing **template-based progressive hardening**.

**What it does:**
- Creates master security templates for systemd services
- Applies hardening to 8 critical system services
- Implements filesystem, process, and network isolation
- Sets resource limits and capability restrictions
- Provides quick-wins template for additional services
- Includes comprehensive error handling and retry logic

**Runtime:** ~2-3 minutes

## 📊 Security Improvements

### Before vs After Hardening

| Service | Before | After | Improvement |
|---------|--------|-------|-------------|
| **SSH** | 9.6 UNSAFE 😱 | 5.1 MEDIUM 😊 | **47%** |
| **Cron** | 9.6 UNSAFE 😱 | 5.1 MEDIUM 😊 | **47%** |
| **Exim4** | 9.6 UNSAFE 😱 | 5.1 MEDIUM 😊 | **47%** |
| **D-Bus** | 9.6 UNSAFE 😱 | 4.8 OK 🎉 | **50%** |
| **OpenNTPD** | 6.6 MEDIUM 😐 | 5.1 MEDIUM 😊 | **23%** |
| **systemd-journald** | 4.3 OK 🙂 | 3.3 OK 🎉 | **23%** |
| **systemd-logind** | 2.8 OK 🙂 | 2.0 OK 🎉 | **29%** |

### 🛡️ Protection Features Applied

**System Level:**
- ✅ CPU vulnerability mitigations (Spectre, Meltdown, L1TF)
- ✅ Memory protection (ASLR, init_on_alloc, SMEP/SMAP)
- ✅ Network stack hardening (ICMP, redirects, source routing)
- ✅ Filesystem protections (symlinks, hardlinks, FIFOs)
- ✅ Application isolation (AppArmor mandatory access control)

**Service Level:**
- ✅ Process visibility restrictions (`hidepid=2` equivalent)
- ✅ Filesystem write protection (`ProtectSystem=strict`)
- ✅ Network address family limitations
- ✅ System call architecture restrictions
- ✅ Memory execution prevention (`W^X` enforcement)

## 📦 Installation

### Prerequisites

- Debian 12 (Bookworm) system
- Root or sudo access
- Active internet connection
- Minimum 2GB free space (for firejail dependencies)

### Supported Environments

- ✅ Physical servers
- ✅ Virtual machines (KVM, VMware, VirtualBox)
- ✅ Cloud instances (AWS, GCP, Azure, DigitalOcean)
- ✅ Containers (with systemd support)
- ✅ Bare metal installations

### Installation Steps

1. **Download Scripts:**
   ```bash
   # Option 1: Direct download
   curl -O https://raw.githubusercontent.com/your-repo/install-fixed.sh
   curl -O https://raw.githubusercontent.com/your-repo/systemd-hardening-script.sh
   
   # Option 2: Clone repository
   git clone https://github.com/your-repo/debian12-hardening.git
   cd debian12-hardening
   ```

2. **Verify Scripts (Optional but Recommended):**
   ```bash
   # Check script integrity
   sha256sum install-fixed.sh systemd-hardening-script.sh
   
   # Review scripts before execution
   less install-fixed.sh
   less systemd-hardening-script.sh
   ```

3. **Make Executable:**
   ```bash
   chmod +x install-fixed.sh systemd-hardening-script.sh
   ```

## 🎮 Usage

### Basic Usage

```bash
# Step 1: System-level hardening (run first)
sudo ./install-fixed.sh

# Step 2: Service-level hardening (run after system hardening)
sudo ./systemd-hardening-script.sh
```

### Advanced Usage

#### System Hardening Options

The system hardening script runs automatically but you can customize behavior:

```bash
# Run with environment variables for customization
SKIP_FIREJAIL=1 sudo ./install-fixed.sh              # Skip firejail (faster)
DEBUG=1 sudo ./install-fixed.sh                      # Enable debug output  
NO_REBOOT_PROMPT=1 sudo ./install-fixed.sh          # Skip reboot prompt
```

#### Service Hardening Options

The service hardening script provides interactive prompts:

```bash
# Run interactively (recommended)
sudo ./systemd-hardening-script.sh

# Run non-interactively (for automation)
echo 'y' | sudo ./systemd-hardening-script.sh

# Skip specific services
SKIP_SERVICES="exim4,openntpd" sudo ./systemd-hardening-script.sh
```

### Post-Installation Steps

1. **Verify System Status:**
   ```bash
   # Check security scores
   sudo systemd-analyze security
   
   # Verify services are running
   sudo systemctl status ssh dbus openntpd
   
   # Check firewall status
   sudo nft list ruleset
   ```

2. **Review Logs:**
   ```bash
   # Check for any service issues
   sudo journalctl -xe --no-pager
   
   # Review specific service logs
   sudo journalctl -u ssh.service
   sudo journalctl -u dbus.service
   ```

3. **Test Functionality:**
   ```bash
   # Test SSH (from another terminal/machine)
   ssh user@your-server
   
   # Test basic system functionality
   sudo systemctl list-failed
   ```

## ⚙️ Advanced Configuration

### Template-Based Hardening

The service hardening script creates two templates:

#### Master Security Template (`/etc/systemd/system/security.conf`)
Maximum security restrictions - use as baseline:
```ini
[Service]
DynamicUser=yes
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
MemoryDenyWriteExecute=true
# ... comprehensive restrictions
```

#### Quick-Wins Template (`/etc/systemd/system/quick-wins.conf`)  
Safe restrictions for any service:
```ini
[Service]
ProtectSystem=strict
PrivateTmp=yes
ProtectHome=yes
MemoryDenyWriteExecute=yes
# ... moderate restrictions
```

### Applying Templates to Additional Services

```bash
# Apply quick-wins to any service
sudo mkdir -p /etc/systemd/system/myservice.service.d/
sudo ln -s /etc/systemd/system/quick-wins.conf /etc/systemd/system/myservice.service.d/

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart myservice.service
```

### Custom Service Hardening

Create service-specific configurations:

```bash
# Example: Hardening nginx
sudo mkdir -p /etc/systemd/system/nginx.service.d/
sudo tee /etc/systemd/system/nginx.service.d/security.conf << 'EOF'
[Service]
# Nginx-specific hardening
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/var/log/nginx /var/cache/nginx
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
MemoryMax=512M
TasksMax=200
EOF

sudo systemctl daemon-reload
sudo systemctl restart nginx.service
```

## 🔧 Troubleshooting

### Common Issues and Solutions

#### Issue: Service fails to start after hardening
```bash
# Check service status
sudo systemctl status service-name.service

# Review service logs
sudo journalctl -xeu service-name.service

# Temporarily disable hardening
sudo systemctl edit service-name.service
# Add: [Service]
#      # Comment out problematic restrictions

sudo systemctl restart service-name.service
```

#### Issue: OpenNTPD fails to start
The script includes automatic retry logic, but if issues persist:
```bash
# Manual fix with minimal restrictions
sudo tee /etc/systemd/system/openntpd.service.d/security.conf << 'EOF'
[Service]
PrivateTmp=yes
ProtectKernelModules=yes
MemoryMax=64M
EOF

sudo systemctl daemon-reload
sudo systemctl restart openntpd.service
```

#### Issue: SSH connection refused after hardening
```bash
# Check SSH service
sudo systemctl status ssh.service

# Verify SSH configuration
sudo sshd -T | grep -E "(permitroot|passwordauth|pubkeyauth)"

# Review SSH logs
sudo journalctl -u ssh.service

# Temporary fix: relax SSH hardening
sudo systemctl edit ssh.service
# Reduce restrictions if needed
```

#### Issue: System runs out of space during installation
```bash
# Check disk space
df -h

# Clean package cache
sudo apt autoclean
sudo apt autoremove

# Skip firejail installation (saves ~700MB)
SKIP_FIREJAIL=1 sudo ./install-fixed.sh
```

### Debugging systemd Restrictions

Use `systemd-analyze` to debug service restrictions:

```bash
# Analyze specific service
sudo systemd-analyze security service-name.service

# Check what syscalls are blocked
sudo systemd-analyze syscall-filter

# Test security settings without restarting
sudo systemd-analyze verify /etc/systemd/system/service.service.d/security.conf
```

### Recovery Procedures

#### Complete Reset of Service Hardening
```bash
# Remove all hardening configurations
sudo find /etc/systemd/system -name "security.conf" -path "*/service.d/*" -delete

# Reload systemd
sudo systemctl daemon-reload

# Restart affected services
sudo systemctl restart ssh dbus cron exim4 openntpd
```

#### System Recovery Mode
If system becomes unbootable:
1. Boot into recovery/rescue mode
2. Mount root filesystem
3. Remove problematic configurations:
   ```bash
   rm -rf /etc/systemd/system/*.service.d/security.conf
   ```
4. Reboot normally

## 📈 Security Analysis

### Measuring Improvements

```bash
# Overall security assessment
sudo systemd-analyze security | head -20

# Service-specific analysis  
sudo systemd-analyze security ssh.service

# Compare before/after (save baseline first)
sudo systemd-analyze security > baseline.txt
# ... after hardening ...
sudo systemd-analyze security > hardened.txt
diff baseline.txt hardened.txt
```

### Security Metrics

The scripts improve security across multiple dimensions:

| Metric | Before | After | Impact |
|--------|--------|-------|---------|
| **Kernel Attack Surface** | High | Low | CPU vuln mitigations |
| **Network Exposure** | High | Minimal | Firewall + restrictions |
| **Process Isolation** | None | Strong | Namespace isolation |
| **Memory Protection** | Basic | Advanced | W^X + ASLR + guards |
| **Filesystem Access** | Unrestricted | Controlled | Read-only + whitelisting |
| **Capability Model** | Full root | Minimal required | Principle of least privilege |

### Compliance and Standards

The hardening aligns with multiple security frameworks:

- **CIS Controls**: Implementation of CIS Critical Security Controls
- **NIST Cybersecurity Framework**: Protect, Detect, Respond capabilities  
- **STIG Guidelines**: DoD Security Technical Implementation Guides
- **PCI DSS**: Payment Card Industry security requirements
- **ISO 27001**: Information security management standards

## 🤝 Contributing

We welcome contributions! Please see our contribution guidelines:

### Reporting Issues

1. Check existing issues first
2. Provide detailed system information:
   ```bash
   # Include this information in bug reports
   uname -a
   lsb_release -a
   systemd --version
   sudo systemd-analyze security | head -5
   ```

### Submitting Changes

1. Fork the repository
2. Create a feature branch
3. Test your changes on a clean Debian 12 system
4. Submit a pull request with:
   - Clear description of changes
   - Test results
   - Impact on security posture

### Development Setup

```bash
# Set up development environment
git clone https://github.com/your-repo/debian12-hardening.git
cd debian12-hardening

# Test in container (recommended)
docker run -it --privileged jrei/systemd-debian:12
# Copy scripts and test inside container
```

## 📚 References and Credits

### Original Sources

- **debian12-hardening-script**: Original system hardening foundation
- **blakkheim's Linux Security Guide**: Advanced kernel and system hardening
- **systemd Security Documentation**: Service hardening best practices
- **CIS Debian Linux Benchmark**: Security configuration guidelines

### Technical Resources

- [systemd.exec(5) Manual](https://www.freedesktop.org/software/systemd/man/systemd.exec.html)
- [systemd Security Analysis](https://www.freedesktop.org/software/systemd/man/systemd-analyze.html)
- [Linux Kernel Security](https://kernsec.org/wiki/index.php/Kernel_Self_Protection_Project)
- [AppArmor Documentation](https://wiki.apparmor.net/)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Disclaimer

These scripts modify system configurations and security settings. While thoroughly tested, you should:

1. **Test in non-production environments first**
2. **Backup your system before applying**
3. **Review scripts before execution**
4. **Monitor system behavior after hardening**

The authors are not responsible for any system damage or security issues resulting from the use of these scripts.

---

## 🔗 Quick Links

- **[Installation Guide](#-installation)** - Get started quickly
- **[Troubleshooting](#-troubleshooting)** - Solve common issues
- **[Advanced Config](#-advanced-configuration)** - Customize hardening
- **[Security Analysis](#-security-analysis)** - Measure improvements
- **[Contributing](#-contributing)** - Help improve the project

---

**⚡ Ready to secure your Debian 12 system? Start with the [Quick Start](#-quick-start) guide!**