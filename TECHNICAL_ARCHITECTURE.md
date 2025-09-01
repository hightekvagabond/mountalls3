# MountAllS3 Technical Architecture

This document provides technical details about MountAllS3's design and implementation for developers and advanced users.

## 🏗️ Modular Architecture

MountAllS3 uses a sophisticated modular design with data-driven configuration:

### **Setup Modules:**
- **`setup-mountalls3.sh`** - Main orchestrator that routes to specialized modules
- **`setup-config.sh`** - Basic configuration (mount location, AWS profiles, defaults)
- **`setup-groups.sh`** - Bucket group management and bucket assignment
- **`setup-system.sh`** - System integration (autostart, symlinks, optimizations)
- **`common.sh`** - Shared library with smart flag parsing and utilities

### **Data-Driven Flag System:**
Each setup module defines its flags in a declarative data structure:

```bash
register_flag "mount-location" "configure_mount_location" "optional" "~/s3" \
    "Configure mount base directory" \
    "What would you like your mount directory to be?" \
    "S3 buckets will be mounted as subdirectories under this location..."
```

Benefits:
- **Zero code duplication** - Common flag parsing for all modules
- **Consistent UX** - Identical help format and behavior across scripts
- **Self-documenting** - Help text automatically generated from definitions
- **Type-safe** - Built-in parameter validation and handling
- **Interactive integration** - Automatic prompts for missing values

### **Usage Patterns:**
```bash
# Non-interactive (automation-friendly)
./setup-config.sh --mount-location ~/my-s3 --profiles

# Interactive (user-friendly prompts)
./setup-config.sh --mount-location

# Help (dynamically generated)
./setup-config.sh --help
```

## 🔧 Core Design Patterns

### 1. **Declarative Flag Registration**
The flag system eliminates repetitive command-line parsing code:

```bash
# Traditional approach (repetitive)
while [[ $# -gt 0 ]]; do
    case $1 in
        --mount-location)
            MOUNT_LOCATION="$2"
            shift 2
            ;;
        # ... many more cases
    esac
done

# MountAllS3 approach (declarative)
register_flag "mount-location" "configure_mount_location" "optional" "~/s3" \
    "Configure mount base directory"
```

### 2. **Separation of Concerns**
Each module has a specific responsibility:
- **Configuration** - Data structure management
- **User Interface** - Interactive prompts and validation
- **System Integration** - OS-level changes
- **Core Logic** - S3 mounting and management

### 3. **Error Recovery**
Comprehensive error handling with user-friendly messages:
- Backup creation before system changes
- Rollback capabilities for failed operations
- Clear error messages with suggested solutions

## 📊 Performance Optimizations

### **Built-in S3FS Optimizations**
```bash
# Automatic performance tuning
-o enable_noobj_cache      # Cache non-existent file checks
-o multireq_max=20         # Parallel request optimization
-o ensure_diskfree=1024    # Cache space management
-o url="${endpoint_url}"   # Region-optimized endpoints
```

### **System-Level Optimizations**
The optimization system uses log analysis to detect issues before applying fixes:

```bash
# Safe optimizations (applied by default)
- UpdateDB exclusion (prevents s3fs scanning)
- File descriptor limit increases
- Network buffer optimization

# Advanced optimizations (user consent required)
- Kernel VM parameter tuning
- I/O scheduler optimization
- Memory management tuning
```

## 🔐 Security Architecture

### **Credential Management**
- **STS Integration** - Temporary credentials with automatic refresh
- **Session Keyring** - Secure in-memory credential storage
- **No Disk Storage** - Credentials never written to files

### **Privilege Separation**
- User-level operations for mounting
- Sudo required only for system optimizations
- Clear privilege escalation boundaries

## 📁 File Structure

```
mountalls3/
├── mountalls3.sh           # Main mounting script
├── setup-mountalls3.sh     # Setup orchestrator
├── setup-config.sh         # Basic configuration
├── setup-groups.sh         # Bucket group management
├── setup-system.sh         # System integration
├── setup-system-advanced.sh # Advanced optimizations
├── common.sh              # Shared utilities
├── config-example.json    # Configuration template
└── docs/
    ├── README.md          # User documentation
    ├── TECHNICAL_ARCHITECTURE.md  # This document
    └── FUNCTION_INVENTORY.md      # Complete function catalog
```

## 🧪 Development Guidelines

### **Adding New Features**
1. Use the declarative flag system for command-line options
2. Follow the modular pattern - separate UI from logic
3. Include comprehensive error handling
4. Add function documentation following existing patterns

### **Testing**
- Syntax validation: `bash -n script.sh`
- Manual testing with various AWS configurations
- Error path testing (missing dependencies, invalid configs)

### **Code Style**
- Consistent function naming (`verb_noun` pattern)
- Clear variable scoping (`local` for function variables)
- Comprehensive comments for complex operations
- Error messages include suggested solutions

## 🔄 Data Flow

### **Initialization Flow**
1. Main script checks for existing configuration
2. If missing, launches setup wizard
3. Setup modules collect configuration data
4. Configuration written to JSON file
5. System optimizations applied (optional)

### **Mounting Flow**
1. Load configuration from JSON
2. Resolve bucket groups to specific buckets
3. Obtain AWS credentials (STS if configured)
4. Create mount directories
5. Execute s3fs with optimized parameters
6. Verify mounts and report status

### **Error Handling Flow**
1. Detect error condition
2. Log error details for debugging
3. Present user-friendly error message
4. Suggest specific remediation steps
5. Offer retry or alternative options

## 📈 Scalability Considerations

- **Large Bucket Collections** - Group-based selective mounting
- **Multiple AWS Accounts** - Profile-based organization
- **System Performance** - Intelligent optimization detection
- **Network Latency** - Region-aware endpoint selection

## 🛠️ Maintenance

- **Configuration Updates** - Non-destructive JSON merging
- **System Changes** - Backup and rollback capabilities
- **Dependency Management** - Clear error messages for missing tools
- **Log Analysis** - Automated issue detection for optimizations

This architecture enables MountAllS3 to scale from simple single-bucket use cases to complex enterprise environments while maintaining ease of use.

## 📁 Configuration File Structure

The configuration file at `~/.config/mountalls3/config.json` uses a JSON structure to organize buckets into logical groups:

```json
{
  "defaults": {
    "mount_groups": ["user-folders"],
    "mount_base": "~/s3",
    "aws_profile": "all"
  },
  "groups": {
    "user-folders": {
      "description": "Personal user folders and data",
      "buckets": [
        {"profile": "personal", "bucket": "my-personal-files"},
        {"profile": "work", "bucket": "user-documents"}
      ]
    },
    "websites": {
      "description": "Website assets and static files",
      "buckets": [
        {"profile": "production", "bucket": "company-website-assets"},
        {"profile": "personal", "bucket": "personal-blog-assets"}
      ]
    }
  }
}
```

## 🚀 Advanced Performance Optimizations

### System Configuration for Performance

The biggest performance issue with idle s3fs mounts comes from system utilities scanning mounted directories. The setup provides multiple levels of optimization:

#### Safe Optimizations (Recommended for all users)
```bash
sudo ./setup-system.sh --system
```

This applies safe optimizations with log analysis and user consent:

1. **🟢 UpdateDB Optimization (SAFE)** - Prevents `locate`/`updatedb` from scanning s3fs mounts
   - Eliminates thousands of unnecessary S3 API calls per minute
   - Reduces high memory usage (multiple GBs in some cases)
   - Prevents network bandwidth consumption and increased AWS costs

2. **🟢 File Descriptor Limits (SAFE)** - Increases limits to prevent "too many open files" errors
   - Allows more concurrent S3 connections
   - Better performance with large directory structures

3. **🟡 Network Buffer Optimization (MODERATE)** - For high-throughput workloads
   - Increases network buffer sizes for better S3 transfer speeds
   - Beneficial for large file transfers

#### Advanced Optimizations (For specific performance issues)
```bash
sudo ./setup-system-advanced.sh
```

For users experiencing specific performance problems, advanced optimizations are available:

- **🟡 Kernel VM Parameters** - Adjusts memory management for network filesystems
- **🟡 I/O Scheduler** - Optimizes SSD scheduler for s3fs cache performance  
- **🔴 Memory Management** - Advanced memory tuning for large cache workloads (8GB+ RAM)

**Each optimization:**
- ✅ Checks system logs for evidence of the specific issue it solves
- ✅ Explains what the change does and potential risks
- ✅ Asks for explicit user consent before applying
- ✅ Creates backup files before making changes
- ✅ Can be applied individually or in combination

## 🔧 Detailed Optimization Framework

### Two-Tier Optimization System

The optimization system is designed with safety and user consent as primary concerns:

1. **Analyzes system logs** to detect evidence of the specific performance issue
2. **Explains the change** in detail including benefits and risks  
3. **Asks for explicit user consent** before applying
4. **Creates backup files** before making any system changes
5. **Can be applied individually** or in combination

### Individual Optimization Details

#### Safe Optimizations

**1. UpdateDB Optimization 🟢 SAFE**
- **Function**: Adds `fuse.s3fs` to `/etc/updatedb.conf` PRUNEFS setting
- **Benefits**: Prevents `locate`/`updatedb` from scanning s3fs mounts, eliminating thousands of unnecessary S3 API calls per minute
- **Risks**: None - only prevents scanning, doesn't affect functionality
- **Log patterns**: `updatedb.*s3fs`, `locate.*s3fs.*slow`, `s3fs.*blocked`

**2. File Descriptor Limits 🟢 SAFE**
- **Function**: Increases file descriptor limits in `/etc/security/limits.conf` and `sysctl.conf`
- **Benefits**: Prevents "too many open files" errors with s3fs, allows more concurrent S3 connections
- **Settings**: Soft/hard limit: 65536 file descriptors, System-wide limit: 1,000,000
- **Risks**: None - only increases limits (never decreases)

**3. Network Buffer Optimization 🟡 MODERATE**
- **Function**: Increases network buffer sizes in `/etc/sysctl.conf`
- **Benefits**: Higher throughput for large S3 transfers, better handling of high-latency connections
- **Settings**: 16MB receive/send buffers, TCP window scaling optimizations
- **Risks**: Uses more system memory for network buffers

#### Advanced Optimizations

**4. Kernel VM Parameters 🟡 RISKY**
- **Function**: Adjusts kernel virtual memory management
- **Benefits**: Reduces memory pressure from large s3fs caches, more predictable write performance
- **Settings**: `vm.dirty_ratio = 10`, `vm.dirty_background_ratio = 5`, `vm.vfs_cache_pressure = 50`
- **Risks**: Affects system-wide memory management

**5. I/O Scheduler Optimization 🟡 MODERATE**
- **Function**: Sets deadline scheduler for SSD devices via udev rules
- **Benefits**: Better I/O performance for s3fs local caches on SSD, lower latency
- **Implementation**: Detects SSD vs HDD automatically, only applies to non-rotational storage
- **Risks**: Changes I/O scheduling system-wide for SSDs

**6. Memory Management 🔴 HIGH RISK**
- **Function**: Advanced memory management tuning for large s3fs cache workloads
- **Requirements**: 8GB+ RAM systems only
- **Settings**: `vm.swappiness = 10`, reduced dirty page timeouts
- **Risks**: Affects system-wide memory management

### Log Analysis System

Each optimization includes intelligent log analysis:

**Log Sources Checked:**
- `/var/log/syslog`, `/var/log/messages`, `/var/log/kern.log`
- `/var/log/dmesg`, `journalctl` (systemd journal, last 7 days)

**Analysis Results:**
- **Issues found**: "✅ Your logs show evidence of [issue type] that this could help resolve."
- **No issues found**: "ℹ️ No evidence of [issue type] in recent logs. This optimization [recommendation]."

### Safety Features

**Backup System:**
- All modified files backed up with timestamps
- Example: `/etc/sysctl.conf.backup.20241203_143022`
- Multiple backups preserved for rollback capability

**Individual Consent:**
- Each optimization asks for explicit user confirmation
- Default answers lean toward safer choices
- Users can skip optimizations they're not comfortable with

**Idempotent Operation:**
- Optimizations check if already applied before proceeding
- Won't duplicate settings or create conflicts
- Safe to run multiple times

### Usage Examples

```bash
# Apply safe optimizations only
sudo ./setup-system.sh --system

# Apply specific advanced optimization
sudo ./setup-system-advanced.sh --kernel-vm

# Interactive selection of all optimizations
sudo ./setup-system.sh --system          # Safe optimizations first
sudo ./setup-system-advanced.sh          # Then advanced if needed
```

### Monitoring and Troubleshooting

```bash
# Check applied optimizations
sudo sysctl vm.dirty_ratio vm.dirty_background_ratio vm.swappiness
ulimit -Hn  # Hard limit
ulimit -Sn  # Soft limit
cat /sys/block/sda/queue/scheduler  # I/O scheduler

# View backup files
ls -la /etc/*.backup.*
ls -la /etc/security/*.backup.*

# Rollback changes
sudo cp /etc/sysctl.conf.backup.20241203_143022 /etc/sysctl.conf
sudo sysctl -p
```

### Risk Assessment Summary

| Optimization | Risk Level | Reversible | System Impact | Recommended For |
|--------------|------------|------------|---------------|-----------------|
| UpdateDB | 🟢 None | Yes | Scanning only | All users |
| File Limits | 🟢 Very Low | Yes | Resource limits | All users |
| Network Buffers | 🟡 Low | Yes | Memory usage | High-throughput workloads |
| VM Parameters | 🟡 Moderate | Yes | Memory management | I/O issue diagnosis |
| I/O Scheduler | 🟡 Moderate | Yes | Storage performance | SSD systems with cache |
| Memory Management | 🔴 High | Yes | System responsiveness | Large cache workloads only |
