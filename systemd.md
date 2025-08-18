# SystemD Service Security Hardening Guide

## Table of Contents
1. [Introduction](#introduction)
2. [Understanding Your Security Posture](#understanding-your-security-posture)
3. [The Hardening Process](#the-hardening-process)
4. [Security Directives Reference](#security-directives-reference)
5. [Resource Management and Performance](#resource-management-and-performance)
6. [Socket Activation for Enhanced Security](#socket-activation-for-enhanced-security)
7. [Practical Examples](#practical-examples)
8. [The Security Template Strategy](#the-security-template-strategy)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)
11. [Conclusion](#conclusion)

## Introduction

SystemD provides a robust framework for securing services through built-in isolation and restriction mechanisms. While systemd ships with loose security defaults to ensure compatibility and usability out of the box, it offers extensive hardening options that can significantly reduce both the likelihood of compromise and the blast radius of potential exploits.

One of systemd's greatest strengths is that it shifts security responsibility from individual services to the system level. Rather than each service needing to reimplement security features, systemd provides a unified interface to the kernel's security capabilities, making advanced isolation techniques accessible to all services through simple configuration directives.

**Why Harden SystemD Services?**
- **Contain breaches**: A compromised service cannot easily spread to other parts of the system
- **Reduce attack surface**: Limit what resources and capabilities a service can access
- **Defense in depth**: Add multiple layers of protection beyond application-level security
- **Principle of least privilege**: Services only get the minimal permissions they actually need
- **Homelab security**: Particularly valuable for self-hosters running multiple services on single machines

**Target Audience**: This guide is especially useful for self-hosters, homelab enthusiasts, and system administrators running custom services alongside standard system utilities. While you don't need to harden every single system service, focusing on external-facing services and custom applications provides the most security benefit.

**Warning**: This is not a prescriptive guide. Every service has different requirements, and hardening will require experimentation and log review when things inevitably break. You are responsible for testing and validating these changes in your environment.

## Understanding Your Security Posture

Before hardening services, you need to understand where you currently stand. SystemD provides built-in tools for security analysis.

### System-Wide Security Analysis

To get a high-level overview of all services on your system:

```bash
sudo systemd-analyze security
```

This will show a list of all services with their current security scores. You'll likely see a lot of red - this is normal for default configurations.

### Service-Specific Analysis

For detailed analysis of a specific service:

```bash
sudo systemd-analyze security sshd.service
```

This outputs a detailed table showing:
- **✓/✗**: Whether a security measure is enabled
- **Name**: The directive name you'll use in unit files
- **Description**: Plain-language explanation of the control
- **Exposure**: Quantitative risk score (use this to prioritize changes)

The exposure score helps you focus on changes that provide the most security benefit.

## The Hardening Process

Hardening systemd services is an iterative process:

1. **Analyze**: Use `systemd-analyze security` to understand current state
2. **Modify**: Add security directives to your service configuration
3. **Test**: Reload systemd and restart the service
4. **Verify**: Ensure the service still functions correctly
5. **Repeat**: Continue until satisfied with the security posture

### Making Configuration Changes

Security directives are placed in different sections depending on your service type:
- **SystemD services**: Place directives in the `[Service]` section of unit files
- **Podman quadlets**: Place directives in the `[Container]` section of quadlet files

**File Locations:**
- SystemD services: `/etc/systemd/system/`
- Podman quadlets: `/etc/containers/systemd/`
- User services: Various locations under user directories

**Recommended approach**: Use systemd override files rather than modifying the original unit files:

```bash
# Create an override file automatically (recommended)
sudo systemctl edit myservice.service

# Use a better editor
EDITOR=nvim sudo systemctl edit myservice.service

# Or manually create the override directory and file
sudo mkdir -p /etc/systemd/system/myservice.service.d/
sudo nano /etc/systemd/system/myservice.service.d/security.conf
```

**The Golden Rule**: If a service fails to start after adding security directives, it probably needs the permissions or capabilities you just took away from it. This is your primary debugging signal.

After making changes:

```bash
sudo systemctl daemon-reload
sudo systemctl restart myservice.service
```

## Security Directives Reference

Here's a comprehensive reference of key security directives, organized by function:

### User and Process Isolation

**`DynamicUser=yes`**
- Creates a unique, temporary user for the service
- User ID is allocated dynamically and recycled when service stops
- Prevents privilege escalation through static user accounts

**`User=someuser`**
- Run service as a specific non-root user
- Alternative to DynamicUser when you need a persistent user

**`NoNewPrivileges=yes`**
- Prevents process from gaining new privileges via setuid/setgid
- Blocks escalation through filesystem capabilities

### Filesystem Protection

**`ProtectSystem=strict`**
- Makes entire filesystem hierarchy read-only except /dev, /proc, /sys
- Most restrictive option; use `ReadWritePaths=` to allow specific writes
- Options: `no`, `yes`, `full`, `strict`

**`ProtectHome=yes`**
- Makes /home, /root, and /run/user inaccessible
- Alternative: `ProtectHome=tmpfs` creates empty tmpfs if service needs a home directory

**`PrivateTmp=yes`**
- Service gets its own private /tmp and /var/tmp
- Prevents temp file attacks between services

**`ReadWritePaths=`**
- Specify paths that should remain writable when using `ProtectSystem=strict`
- Example: `ReadWritePaths=/var/log/myapp /var/lib/myapp`

**`InaccessiblePaths=`**
- Make specific paths completely inaccessible
- Example: `InaccessiblePaths=/mnt /media`

**`NoExecPaths=`**
- Remove execute permissions from specified paths
- Useful for preventing execution from data directories

### Device and Hardware Access

**`PrivateDevices=yes`**
- Restricts access to physical devices
- Only allows pseudo-devices like /dev/null, /dev/zero, /dev/random

**`ProtectClock=yes`**
- Prevents writes to system and hardware clocks
- Blocks sethostname() and setdomainname() syscalls

**`ProtectKernelModules=yes`**
- Prevents explicit kernel module loading/unloading

**`ProtectKernelLogs=yes`**
- Restricts access to kernel log buffer (dmesg)

**`ProtectKernelTunables=yes`**
- Makes /proc and /sys read-only to prevent kernel parameter changes

### Process Visibility and Control

**`ProtectProc=invisible`**
- Hides other users' processes from /proc
- Service can only see its own processes

**`ProcSubset=pid`**
- Limits /proc access to only process management files
- Hides system information not needed for process introspection

**`ProtectControlGroups=yes`**
- Makes cgroup filesystem read-only

### Network Restrictions

**`PrivateNetwork=yes`**
- Service gets its own network namespace with only loopback
- Completely isolates service from network

**`RestrictAddressFamilies=`**
- Limit allowed socket address families
- Example: `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`
- Common families: AF_INET (IPv4), AF_INET6 (IPv6), AF_UNIX (local sockets), AF_NETLINK

**`IPAddressDeny=any`**
- Block all network access (alternative to PrivateNetwork)
- Use with `IPAddressAllow=` to create allowlists

### Capability Restrictions

**`CapabilityBoundingSet=`**
- Restrict Linux capabilities available to the process
- Prefix with `~` to remove capabilities
- Example: `CapabilityBoundingSet=~CAP_SETUID CAP_SETPCAP`

**`AmbientCapabilities=`**
- Grant specific capabilities that are inherited by child processes
- Use sparingly and only when necessary

### System Call Filtering

**`SystemCallFilter=`**
- Powerful but complex: filters allowed system calls
- Use predefined groups: `@system-service`, `@network-io`, `@file-system`
- Example: `SystemCallFilter=@system-service @file-system`
- Prefix with `~` to deny: `SystemCallFilter=~@clock @cpu-emulation @debug @module @mount @obsolete @reboot @swap @raw-io @privileged @resources`

**`SystemCallArchitectures=native`**
- Restrict to native architecture syscalls only (usually x86-64)
- Prevents running 32-bit code on 64-bit systems

**`SystemCallErrorNumber=EPERM`**
- Return error code instead of killing process for denied syscalls
- Useful for debugging syscall restrictions

### Memory Protection

**`MemoryDenyWriteExecute=yes`**
- Prevents allocating memory that's both writable and executable
- Blocks many code injection attacks
- May break JIT compilers (JavaScript, Java, .NET)

### Advanced Restrictions

**`RestrictNamespaces=yes`**
- Restricts creation of new namespaces
- May interfere with containerized applications

**`RestrictSUIDSGID=yes`**
- Prevents setting setuid/setgid bits on files

**`RestrictRealtime=yes`**
- Blocks realtime scheduling
- Only needed for specialized applications (audio processing, industrial control)

**`LockPersonality=yes`**
- Prevents changing execution domain
- Blocks compatibility modes for legacy applications

**`RemoveIPC=yes`**
- Automatically removes IPC objects when service stops

**`UMask=0077`**
- Sets restrictive default file permissions (owner read/write only)

## Resource Management and Performance

Beyond security isolation, systemd provides powerful resource management capabilities that can enhance both security and system stability. These directives help ensure critical services remain functional even under resource pressure, and can limit the impact of compromised or misbehaving services.

### CPU and Process Management

**`CPUWeight=100`**
- Controls CPU scheduling priority relative to other services
- Range: 1-10000 (default: 100)
- Higher values get more CPU time when system is under load
- Example: Set critical services to 200, less important to 50

**`TasksMax=1000`**
- Limits maximum number of tasks (threads/processes) the service can create
- Prevents fork bombs and resource exhaustion attacks
- Set based on service's actual needs

**`Nice=0`**
- Traditional Unix nice value for process scheduling
- Range: -20 (highest priority) to 19 (lowest priority)
- Negative values require privileges

### Memory Management

**`MemoryMax=512M`**
- Hard limit on memory usage
- Service is killed if it exceeds this limit
- Use suffixes: K, M, G, T, P, E

**`MemoryHigh=256M`**
- Soft limit - triggers aggressive reclaim but doesn't kill
- Warning threshold before reaching MemoryMax

### I/O Management

**`IOWeight=100`**
- Controls I/O bandwidth allocation
- Range: 1-10000 (default: 100)
- Ensures critical services get I/O priority under load

### Hierarchical Resource Management

SystemD supports nested scopes for managing multiple services together:

```bash
# Create a scope for web services
sudo systemctl set-property web.slice CPUWeight=500 MemoryMax=2G

# Assign services to the slice
sudo systemctl set-property nginx.service Slice=web.slice
sudo systemctl set-property apache.service Slice=web.slice
```

This hierarchical approach ensures that:
- System-critical services always have adequate resources
- User applications can't starve system services
- Groups of related services compete fairly for resources

### Performance vs Security Balance

Resource limits complement security restrictions:
- **Prevent resource exhaustion attacks**: Limit CPU, memory, and task creation
- **Ensure service availability**: Guarantee critical services get needed resources
- **Contain blast radius**: Limit impact of compromised services on system performance

## Socket Activation for Enhanced Security

Socket activation is one of systemd's most powerful security features, allowing services to operate with much stricter network isolation while maintaining full functionality.

### How Socket Activation Works

Instead of services binding directly to network ports, systemd:
1. **Binds to the socket** on behalf of the service
2. **Starts the service** when a connection arrives
3. **Passes the connection** to the service via file descriptor
4. **Can stop the service** when idle to save resources

### Security Benefits

**Complete Network Isolation**: Services can use `PrivateNetwork=yes` while still accepting connections:

```ini
[Unit]
Description=My Web Service
Requires=myapp.socket

[Service]
ExecStart=/usr/bin/myapp
# Complete network isolation - service can't make outbound connections
PrivateNetwork=yes

[Install]
WantedBy=multi-user.target
```

## The Security Template Strategy

The most effective approach to systemd hardening is to use a template-based strategy with maximum security by default, then selectively relax restrictions as needed.

### Core Methodology

1. **Create a universal security template** with aggressive hardening
2. **Apply this template to all services** as a starting point  
3. **Create service-specific override files** that disable incompatible restrictions
4. **Document why each relaxation is necessary** for future reference

### The Master Security Template

Create `/etc/systemd/system/security.conf` with maximum hardening:

```ini
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
```

### Applying the Template

Link this template into service override directories:

```bash
# For a web service
sudo mkdir -p /etc/systemd/system/nginx.service.d/
sudo ln -s /etc/systemd/system/security.conf /etc/systemd/system/nginx.service.d/

# For multiple services
for service in nginx apache2 mysql redis; do
    sudo mkdir -p /etc/systemd/system/${service}.service.d/
    sudo ln -s /etc/systemd/system/security.conf /etc/systemd/system/${service}.service.d/
done
```

### Service-Specific Overrides

Create `unsecurity.conf` files that selectively disable incompatible restrictions:

```bash
# /etc/systemd/system/nginx.service.d/unsecurity.conf
[Service]
# Needs network access for serving web content
PrivateNetwork=no
IPAddressDeny=
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# Needs to read web content from filesystem
ReadWritePaths=/var/www /var/log/nginx

# Requires binding to port 80/443
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

# Document reasoning:
# - Network access required for HTTP/HTTPS serving
# - Filesystem access needed for web content and logs  
# - CAP_NET_BIND_SERVICE required for privileged ports
```

```bash
# /etc/systemd/system/nodejs-app.service.d/unsecurity.conf  
[Service]
# Node.js requires JIT compilation
MemoryDenyWriteExecute=no

# Needs outbound network access for API calls
PrivateNetwork=no
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# Application needs write access to data directory
ReadWritePaths=/opt/myapp/data /var/log/myapp

# Document reasoning:
# - JIT disabled due to V8 JavaScript engine requirements
# - Network access needed for external API integrations
# - Write access required for application data persistence
```

### Template Advantages

**Consistency**: All services start with the same high security baseline

**Maintainability**: Security updates only need to be made in one place

**Documentation**: Override files clearly document why each service needs specific permissions

**Auditability**: Easy to see which services have relaxed which restrictions

**Progressive Hardening**: Start with maximum security and only relax what's necessary

### Template Variations

You might create multiple templates for different service classes:

```bash
# High-security template for internet-facing services
/etc/systemd/system/security-external.conf

# Medium-security template for internal services  
/etc/systemd/system/security-internal.conf

# Basic template for system utilities
/etc/systemd/system/security-basic.conf
```

This strategy scales well and makes systemd hardening manageable across many services.

**Automatic Lifecycle Management**: Services start only when needed and can be stopped when idle, reducing attack surface.

### Socket Configuration

Create a corresponding `.socket` file:

```ini
# /etc/systemd/system/myapp.socket
[Unit]
Description=My App Socket

[Socket]
ListenStream=8080
BindIPv6Only=both

[Install]
WantedBy=sockets.target
```

Enable the socket instead of the service:
```bash
sudo systemctl enable myapp.socket
sudo systemctl start myapp.socket
```

### Socket Proxying for Legacy Services

For services that don't support socket activation natively, use `systemd-socket-proxyd`:

```ini
# /etc/systemd/system/legacy-proxy.socket
[Unit]
Description=Legacy App Proxy Socket

[Socket]
ListenStream=8080

[Install]
WantedBy=sockets.target
```

```ini
# /etc/systemd/system/legacy-proxy@.service
[Unit]
Description=Legacy App Proxy

[Service]
ExecStart=/lib/systemd/systemd-socket-proxyd 127.0.0.1:8081
PrivateNetwork=yes
```

This pattern allows you to:
- Keep the legacy service on localhost only
- Proxy external connections through systemd
- Apply security restrictions to the proxy service
- Automatically stop services when no connections exist

### Socket Activation Best Practices

**Use with Resource Limits**: Combine with `Accept=false` and connection limits:

```ini
[Socket]
ListenStream=8080
Accept=false
MaxConnections=100
MaxConnectionsPerSource=10
```

**Health Monitoring**: Socket-activated services can be monitored and restarted independently:

```ini
[Service]
Restart=always
RestartSec=5
TimeoutStartSec=30
```

**Multiple Sockets**: Services can listen on multiple ports with different security contexts:

```ini
[Unit]
Description=Multi-Port Service
Requires=app-public.socket app-admin.socket

[Service]
ExecStart=/usr/bin/myapp
PrivateNetwork=yes
```

Socket activation is particularly valuable for self-hosted services where you want maximum security without sacrificing functionality.

## Practical Examples

### Basic Hardening Template

Here's a "security.conf" template that works for many services:

```ini
[Service]
# User isolation
DynamicUser=yes

# Filesystem protection
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes

# Process visibility
ProtectProc=invisible
ProcSubset=pid

# Advanced restrictions
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
NoNewPrivileges=yes
RemoveIPC=yes

# Network restrictions (adjust as needed)
PrivateNetwork=yes
# OR: RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# Memory protection
MemoryDenyWriteExecute=yes

# Syscall filtering (conservative)
SystemCallArchitectures=native
SystemCallFilter=@system-service

# Capability restrictions
CapabilityBoundingSet=~CAP_SYS_ADMIN CAP_SETUID CAP_SETGID

# File permissions
UMask=0077
```

### Example: Hardened Web Proxy (Traefik)

```ini
[Unit]
Description=Traefik Reverse Proxy
Requires=http.socket https.socket

[Container]
ContainerName=traefik
Image=docker.io/traefik:v3
Network=traefik.network
Volume=traefik-config.volume:/etc/traefik/:Z
Volume=/var/log/traefik:/logs/:Z

[Service]
Restart=always
MemoryMax=512M
Sockets=http.socket https.socket

# Security hardening
ProtectHome=yes
ProtectClock=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
ProtectSystem=full
RestrictSUIDSGID=yes
UMask=0077
SystemCallArchitectures=native
SystemCallFilter=@system-service @mount @privileged
RestrictRealtime=yes
LockPersonality=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
MemoryDenyWriteExecute=yes
CapabilityBoundingSet=~CAP_SETUID CAP_SETPCAP

[Install]
WantedBy=default.target
```

### Example: Hardened Custom Service

```ini
[Unit]
Description=My Custom Application
After=network.target

[Service]
Type=simple
ExecStart=/opt/myapp/bin/myapp
Restart=always

# Security hardening
DynamicUser=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectProc=invisible
ProcSubset=pid

# Allow write access to application directories
ReadWritePaths=/var/lib/myapp /var/log/myapp

# Network access for web service
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# Conservative syscall filtering
SystemCallFilter=@system-service @network-io @file-system
SystemCallArchitectures=native

# Memory protection (disable if app uses JIT)
MemoryDenyWriteExecute=yes

# Capability restrictions
CapabilityBoundingSet=~CAP_SYS_ADMIN CAP_SETUID CAP_SETGID CAP_SETPCAP

# Other restrictions
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
NoNewPrivileges=yes
UMask=0077

[Install]
WantedBy=multi-user.target
```

## Troubleshooting

### Common Issues and Solutions

**Service fails to start after hardening**
- Check `journalctl -u servicename.service` for error messages
- Temporarily disable recently added directives to isolate the issue
- The service likely needs permissions you just removed

**Permission denied errors**
- Add required paths to `ReadWritePaths=`
- Check if service needs specific capabilities
- Verify `User=` directive allows access to required files

**Network connectivity issues**
- Adjust `RestrictAddressFamilies=` to include needed socket types
- Consider if `PrivateNetwork=yes` is too restrictive
- Check if service needs `AF_NETLINK` for system communication

**Application crashes or behaves unexpectedly**
- Disable `MemoryDenyWriteExecute=yes` for JIT-compiled applications
- Review `SystemCallFilter=` restrictions
- Check if `ProtectProc=` or `ProcSubset=` blocks needed system information

### Debugging SystemCall Restrictions

SystemCall filtering is powerful but can easily break services. Here's a systematic approach to debugging:

1. **Install and start auditd**:
   ```bash
   sudo systemctl enable --now auditd
   ```

2. **Reproduce the service failure**, then check for blocked syscalls:
   ```bash
   sudo ausearch -i -m SECCOMP -ts recent
   ```

3. **Look for SECCOMP violations** like:
   ```
   type=SECCOMP msg=audit(08/09/2025 14:22:10.314:08) : auid=user uid=user gid=user ses=1 subj==unconfined pid=42348 comm=ncat exe=/usr/bin/ncat sig=SIGSYS arch=x86_64 syscall=socket compat=0 ip=0x7b9e06e59477 code=kill
   ```
   Note the `syscall=socket` value.

4. **Identify the syscall group**:
   ```bash
   systemd-analyze syscall-filter | grep socket
   ```

5. **Add the syscall or group** to your `SystemCallFilter=` directive

### Common SystemCall Groups

**Essential Groups** (rarely safe to block):
- `@system-service` - Basic system service operations
- `@file-system` - File operations (open, read, write, etc.)
- `@basic-io` - Basic I/O operations

**Network Groups**:
- `@network-io` - Network socket operations
- `@signal` - Signal handling (often needed)

**Commonly Blocked Groups** (usually safe to restrict):
- `@cpu-emulation` - CPU emulation syscalls
- `@debug` - Debugging operations (ptrace, etc.)
- `@module` - Kernel module operations
- `@mount` - Filesystem mounting
- `@obsolete` - Deprecated syscalls
- `@reboot` - System reboot/shutdown
- `@swap` - Memory swapping
- `@raw-io` - Raw device I/O
- `@privileged` - Privileged operations
- `@resources` - Resource limit changes
- `@clock` - System clock changes

**Example Progressive Filtering**:
```ini
# Start permissive, then gradually restrict
SystemCallFilter=@system-service @file-system @network-io @signal

# Then add restrictions
SystemCallFilter=@system-service @file-system @network-io @signal
SystemCallFilter=~@cpu-emulation @debug @module @mount @obsolete @reboot @swap

# Finally, block dangerous groups  
SystemCallFilter=~@cpu-emulation @debug @module @mount @obsolete @reboot @swap @raw-io @privileged @resources
```

### Alternative Error Handling

Instead of killing the process, return error codes:
```ini
SystemCallFilter=~@chown:EPERM
SystemCallErrorNumber=EPERM
```

This allows debugging without service crashes.

### Using SystemD Capabilities Analysis

Check what capabilities your system supports:
```bash
systemd-analyze capabilities
```

## Best Practices

### Prioritization Strategy

1. **Start with external-facing services**: web servers, SSH, mail servers, reverse proxies
2. **Focus on custom applications**: You know their requirements better than OS utilities  
3. **Prioritize self-hosted services**: These often run with fewer security considerations than commercial software
4. **Use quantitative exposure scores**: Prioritize changes with the highest security impact from `systemd-analyze security`
5. **Apply incremental changes**: Add a few directives at a time, test thoroughly

### The Template-First Approach

**Recommended Strategy**: Start with the security template methodology:

1. **Deploy the master security template** to all services
2. **Expect most services to break** initially - this is normal and expected
3. **Create minimal unsecurity.conf overrides** to restore functionality
4. **Document every relaxation** with reasoning for future reference
5. **Regularly review and tighten** restrictions as you better understand service needs

This approach ensures you start with maximum security and only relax what's absolutely necessary, rather than trying to incrementally add restrictions.

### Quick Wins for Self-Hosters

These directives rarely break services and provide significant security benefits for homelab environments:

```ini
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
DynamicUser=yes  # For custom services
```

### Self-Hosting Specific Considerations

**Reverse Proxies** (Traefik, Nginx, Caddy):
- Critical first targets - they're internet-facing
- Often need socket activation for optimal security
- May require `CAP_NET_BIND_SERVICE` for ports 80/443

**Container Orchestrators** (Podman, Docker):
- `RestrictNamespaces=yes` typically won't work
- Focus on the containers themselves rather than the runtime
- Consider hardening quadlets individually

**Home Automation/IoT Services**:
- Often need network access for device communication
- May require specific address families (AF_BLUETOOTH, etc.)
- Good candidates for socket activation

**Media Services** (Plex, Jellyfin, etc.):
- Need filesystem access to media directories
- May require hardware device access for transcoding
- Consider `PrivateDevices=no` with specific device allowlists

**Database Services**:
- Excellent candidates for aggressive hardening
- Usually only need localhost access
- Can often use `PrivateNetwork=yes` with socket activation

### Service-Specific Considerations

**Web Services**
- Need `AF_INET`, `AF_INET6`, often `AF_UNIX`
- May require `@network-io` syscalls
- Consider socket activation to avoid `PrivateNetwork=`

**Database Services**
- Need persistent data directories in `ReadWritePaths=`
- May require specific capabilities for shared memory
- Often need `AF_UNIX` for local connections

**Backup/Sync Services**
- May need broader filesystem access
- Consider time-based restrictions vs. always-on hardening
- Evaluate if `ProtectSystem=full` is sufficient instead of `strict`

**Container Services**
- `RestrictNamespaces=yes` typically won't work
- May need additional capabilities
- Consider hardening the container runtime instead

### Managing Complex Configurations

For services requiring many permissions, consider this approach:

1. **Start with maximum hardening** using a template like the one above
2. **Create an "unsecurity.conf"** override file that relaxes specific restrictions
3. **Document why each relaxation is necessary**

Example unsecurity.conf:
```ini
[Service]
# Needs network access for API calls
PrivateNetwork=no
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# Requires JIT compilation
MemoryDenyWriteExecute=no

# Needs to read system information
ProtectProc=default
ProcSubset=all
```

### Testing and Validation

**Functional Testing**
- Test all service functionality after each hardening iteration
- Include edge cases and error conditions
- Verify logging and monitoring still work

**Security Validation**
- Use `systemd-analyze security` to track score improvements
- Run vulnerability scanners against hardened services
- Consider penetration testing for critical services

**Performance Impact**
- Monitor service performance after hardening
- Some restrictions (like syscall filtering) have minimal overhead
- Network isolation may require socket activation for performance

## Conclusion

SystemD service hardening represents a fundamental shift in how we approach system security - moving from application-by-application security implementations to system-level security as a service. This unified approach makes advanced kernel security features accessible through simple configuration directives, dramatically improving the security posture of services without requiring changes to the applications themselves.

**Key Takeaways:**

**Template-First Strategy**: Start with maximum security restrictions and selectively relax them rather than incrementally adding protections. The security.conf/unsecurity.conf pattern provides a systematic approach that scales across many services.

**Focus Your Efforts**: Prioritize external-facing services, custom applications, and self-hosted services where you have control over the configuration. Don't feel obligated to harden every system utility.

**Leverage Socket Activation**: This often-overlooked feature allows complete network isolation while maintaining full functionality, providing substantial security benefits with minimal complexity.

**Resource Management**: Use systemd's resource controls not just for performance, but as an additional security layer to prevent resource exhaustion attacks and ensure critical services remain available.

**Systematic Debugging**: When hardening breaks services, use the systematic debugging approach with auditd and systemd-analyze tools rather than guessing what permissions are needed.

**Progressive Implementation**: Start with the quick wins that rarely break services, then gradually add more restrictive measures as you gain confidence and understanding.

**Documentation is Critical**: Always document why specific restrictions were relaxed. Your future self (and your colleagues) will thank you when revisiting configurations months later.

**Remember**: Perfect is the enemy of good. A partially hardened service is infinitely more secure than an unhardened one. Apply what you can, where you can, and your systems will be significantly more resilient against both known and unknown threats.

The goal isn't to implement every possible restriction, but to implement the right restrictions for your specific use case and threat model. Even basic hardening provides substantial security benefits and helps contain the blast radius of potential compromises.

SystemD's security features represent one of the most accessible and powerful security improvements you can make to a Linux system. Don't let the complexity discourage you - start small, learn as you go, and gradually build more sophisticated configurations as your understanding grows.

---

*For the most up-to-date information, always consult the official systemd documentation: `man systemd.exec(5)` and `man systemd.service(5)`*
