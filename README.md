# MountAllS3

A bash script that automatically mounts Amazon S3 buckets as local filesystem directories using s3fs-fuse. Mount all your S3 buckets from all AWS profiles or selectively mount from specific profiles with customizable locations.

> **Note:** This script has been developed and tested on Ubuntu. While it should work on other Linux distributions and macOS, you may need to make adjustments for different package managers or system configurations. Pull requests for compatibility improvements are welcome!

## 🚀 Features

- **Multi-Profile Support**: Mount buckets from all AWS profiles or select specific profiles
- **Custom Mount Locations**: Override the default `~/s3` mount directory
- **Smart Bucket Handling**: Automatically handles buckets with dots in names and different regions
- **Duplicate Prevention**: Detects and skips already mounted buckets
- **Easy Unmounting**: Simple command to unmount all S3 buckets at once
- **Performance Optimized**: Built-in caching and optimizations to minimize resource usage
- **Bucket Groups**: Organize buckets into logical groups (user-folders, websites, infra, etc.)
- **Smart Defaults**: Configure which groups mount automatically
- **Auto-Start Integration**: Desktop environment autostart support
- **System Integration**: Prevents unnecessary scanning by system utilities
- **Comprehensive Error Handling**: Clear error messages and troubleshooting guidance
- **Prerequisite Validation**: Automatic checks for required tools and configuration

## 📋 Prerequisites

The script automatically checks for these requirements and provides installation instructions if missing:

1. **s3fs-fuse** - FUSE-based file system for S3
2. **keyutils** - Linux session keyring support for secure credential storage
3. **AWS CLI** - Amazon Web Services command line interface
4. **AWS Credentials** - Properly configured AWS profiles with access keys

### Quick Installation

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install s3fs awscli keyutils
```

**CentOS/RHEL:**
```bash
sudo yum install s3fs-fuse awscli keyutils
```

**macOS:**
```bash
brew install s3fs awscli
# Note: keyutils not available on macOS - script will use alternative approach
```

**Configure AWS:**
```bash
aws configure
# OR for multiple profiles:
aws configure --profile myprofile
```

## 🔧 Installation

1. **Download the script:**
   ```bash
   wget https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/mountalls3.sh
   # OR
   curl -O https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/mountalls3.sh
   ```

2. **Make it executable:**
   ```bash
   chmod +x mountalls3.sh
   ```

3. **Run setup:**
   ```bash
   ./setup-mountalls3.sh
   ```

4. **Start using:**
   ```bash
   ./mountalls3.sh
   # Or if you set up symlinks: mountalls3
   ```

## 📖 Usage

For complete usage instructions, command line options, and examples:

```bash
./mountalls3.sh --help
```

## 🔄 Auto-Start Setup

Use the setup script to configure MountAllS3 to automatically start when you log in:

```bash
./setup-mountalls3.sh
```

The setup script will:
- Create desktop environment autostart entries (works with GNOME, KDE Plasma, XFCE, etc.)
- Set up symlinks to your personal bin directory for easy access
- Configure system-level performance optimizations (if run with sudo)
- Set up your bucket groups and preferences
- Allow you to enable/disable auto-start easily

This is much more user-friendly than crontab and integrates properly with your desktop environment.

### Personal Bin Directory Integration

The setup script can create symlinks in your personal bin directory (`~/bin`, `~/.local/bin`, etc.) so you can run `mountalls3` from anywhere:

```bash
# After setup with symlinks
mountalls3              # Mount default groups
mountalls3 -g websites   # Mount specific groups
mountalls3 --setup      # Access setup from anywhere
mountalls3 --unmount    # Unmount all
```

## 🧹 Directory Cleanup

MountAllS3 automatically cleans up empty unmounted directories after each run to prevent mount directory clutter. The cleanup function includes multiple safety checks to ensure only truly empty, unmounted directories are removed.

Use `./mountalls3.sh --cleanup` for manual cleanup or see `--help` for details.

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

## ⚙️ Configuration

MountAllS3 uses a configuration file at `~/.config/mountalls3/config.yaml` to organize your S3 buckets into logical groups.

### Initial Setup

Run the setup script to create your configuration:

```bash
./setup-mountalls3.sh
```

### Configuration File Structure

```yaml
# Default settings
defaults:
  mount_groups: ["user-folders"]  # Groups to mount by default
  mount_base: "~/s3"              # Default mount directory
  aws_profile: "all"              # AWS profile to use

# Bucket groups
groups:
  user-folders:
    description: "Personal user folders and data"
    buckets:
      - profile: "personal"
        bucket: "my-personal-files"
      - profile: "work"
        bucket: "user-documents"
  
  websites:
    description: "Website assets and static files"
    buckets:
      - profile: "production"
        bucket: "company-website-assets"
      - profile: "personal"
        bucket: "personal-blog-assets"
```

### Using Groups

```bash
# Mount default groups (from config)
./mountalls3.sh

# Mount specific groups
./mountalls3.sh -g user-folders,websites

# List available groups
./mountalls3.sh --list-groups

# Mount all buckets (ignore config)
./mountalls3.sh -a
```

## ⚡ Performance Optimizations

This script includes several performance optimizations to minimize resource usage when s3fs mounts are idle:

### Built-in Optimizations

- **Local Caching**: Uses `~/.cache/s3fs/` for faster file access and reduced S3 API calls
- **Optimized Mount Options**: 
  - `enable_noobj_cache`: Caches non-existent files to reduce repeated checks
  - `multireq_max=20`: Increases parallel requests for better throughput
  - `ensure_diskfree=1024`: Maintains 1GB free space for cache operations
- **Smart Region Detection**: Automatically sets optimal S3 endpoints

### System Configuration

The biggest performance issue with idle s3fs mounts comes from system utilities scanning mounted directories. The setup script handles this automatically:

```bash
sudo ./setup-mountalls3.sh
```

This prevents tools like `mlocate`/`updatedb` from traversing s3fs directories, which can cause:
- Thousands of unnecessary S3 API calls per minute
- High memory usage (multiple GBs in some cases)
- Network bandwidth consumption
- Increased AWS costs

### Monitoring Performance

Check s3fs resource usage:
```bash
# Monitor s3fs processes
ps aux | grep s3fs

# Check cache disk usage
du -sh ~/.cache/s3fs/*

# View mounted buckets
mount | grep s3fs
```

### Helpful Shell Aliases

When you have many S3 buckets mounted, `df` output can become cluttered. Add this alias to your `~/.bashrc` to automatically filter out s3fs filesystems while preserving all `df` functionality:

```bash
# Add to ~/.bashrc
alias df='command df "$@" | grep -v "^s3fs"'
```

After adding this alias, restart your terminal or run `source ~/.bashrc`. Now `df` will show a clean output without s3fs mounts, but all flags still work normally:

```bash
df              # Clean output without s3fs clutter
df -h           # Human readable, no s3fs
df -T           # Show filesystem types, no s3fs
df /home        # Check specific path, no s3fs
```

If you ever need to see s3fs mounts specifically, use:
```bash
command df | grep s3fs    # Show only s3fs mounts
mount | grep s3fs         # Better way to check s3fs mounts
```

## 🔒 Security Features

MountAllS3 uses modern security practices to protect your AWS credentials:

### **AWS STS Temporary Credentials**
- Generates 12-hour temporary credentials using AWS STS
- No long-lived AWS credentials stored on disk
- Automatic credential refresh with desktop notifications

### **Linux Session Keyring Storage**
- Credentials stored in kernel session keyring (memory-only)
- Automatically cleared when you log out
- No credential files written to disk

### **Process Substitution**
- s3fs receives credentials via anonymous pipes
- Zero disk footprint for credential passing
- Credentials never touch the filesystem

### **Lazy Refresh with Notifications**
- Credentials automatically refresh when expired
- Desktop notifications when refresh occurs
- Transparent to user workflow

This approach is significantly more secure than storing AWS credentials in plaintext files, while maintaining the convenience of automatic mounting.

## 🐛 Troubleshooting

### Common Issues

**Permission Denied:**
```bash
# Make sure you have proper AWS permissions for the buckets
aws s3 ls --profile yourprofile

# Test STS credential generation
aws sts get-session-token --profile yourprofile
```

**Mount Failures:**
```bash
# Check if keyutils is installed
keyctl show @s

# Test manual mount with debug info
# (Note: this will prompt for credentials since it bypasses our STS system)
s3fs your-bucket /path/to/mountpoint -o dbglevel=info -f
```

**STS Token Issues:**
```bash
# Check current STS tokens in keyring
keyctl show @s | grep s3fs

# Clear expired tokens manually
keyctl clear @s
```

**Bucket Not Accessible:**
- Verify your AWS credentials have access to the bucket
- Check if the bucket exists and you have the correct permissions
- Ensure your AWS profile is properly configured

### Debug Mode

For troubleshooting mount issues, the script provides debug commands in its error messages. Run them to get detailed information about what's failing.

## 🤝 Contributing

Contributions are welcome! Here are ways you can help:

1. **Report Bugs**: Open an issue with details about the problem
2. **Suggest Features**: Open an issue with your feature request
3. **Submit PRs**: Fork the repo, make changes, and submit a pull request
4. **Improve Documentation**: Help make the README or comments clearer

### Development Setup

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
chmod +x mountalls3.sh
```

## 📄 License

This project is licensed under the MIT License - see below for details.

```
MIT License

Copyright (c) 2024

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## ⭐ Support

If you find this script useful, please consider:
- Giving it a star ⭐ on GitHub
- Sharing it with others who might benefit
- Contributing improvements or bug fixes

---

**Happy mounting! 🚀**
