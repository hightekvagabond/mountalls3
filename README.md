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

1. **Clone the repository:**
   ```bash
   git clone https://github.com/hightekvagabond/mountalls3.git
   cd mountalls3
   ```

2. **Start using:**
   ```bash
   ./mountalls3.sh         # First run will guide you through setup
   ```

## 📖 Usage

### Quick Start

**First time (automatically runs setup):**
```bash
./mountalls3.sh         # First run will guide you through setup
```

**Daily usage:**
```bash
./mountalls3.sh         # Mount your default bucket groups
./mountalls3.sh --unmount  # Unmount all when done
```

> **💡 Default Behavior:** If you accept all defaults during setup, the script will automatically mount all S3 buckets you have access to across all your AWS profiles. The configuration system is designed for users with many buckets who want to organize them into groups for better system performance and selective mounting.

### Main Script Options

For complete usage instructions, command line options, and examples:

```bash
./mountalls3.sh --help
```

**Common usage patterns:**
```bash
# Basic operations
./mountalls3.sh                      # Mount default groups
./mountalls3.sh --all                # Mount all buckets from all profiles
./mountalls3.sh --profile myprofile  # Mount only buckets from 'myprofile'
./mountalls3.sh --group websites     # Mount specific bucket groups

# Unmounting
./mountalls3.sh --unmount            # Unmount all S3 buckets

# Maintenance
./mountalls3.sh --cleanup            # Clean up empty directories
./mountalls3.sh --list-groups        # Show available bucket groups
```

## 🔄 Auto-Start Setup

The script can automatically start when you log in. During first-time setup, you'll be asked if you want to enable this feature. It works with all major desktop environments (GNOME, KDE, XFCE, etc.).

## 🧹 Directory Cleanup

MountAllS3 automatically cleans up empty unmounted directories after each run to prevent mount directory clutter. The cleanup function includes multiple safety checks to ensure only truly empty, unmounted directories are removed.

Use `./mountalls3.sh --cleanup` for manual cleanup or see `--help` for details.



## ⚙️ Configuration

The script creates a configuration file at `~/.config/mountalls3/config.json` to organize your S3 buckets into logical groups. The first time you run the script, it will guide you through the setup process.

### Modifying Configuration

To modify your configuration after initial setup:

```bash
./mountalls3.sh --setup
```

This allows you to:
- Configure which AWS profiles are accessible by the script
- Add new bucket groups or modify existing ones
- Add buckets to existing groups
- Change default mount settings

### Using Groups

```bash
# Mount default groups (from config)
./mountalls3.sh

# Mount specific groups
./mountalls3.sh --group user-folders

# List available groups
./mountalls3.sh --list-groups

# Mount all buckets (ignore config)
./mountalls3.sh --all
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

### System Optimization

For users with many S3 buckets or performance issues, the script offers system optimizations during setup. These are completely optional but can improve performance significantly.

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
git clone https://github.com/hightekvagabond/mountalls3.git
cd mountalls3
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

## 📚 Additional Documentation

- **[Technical Architecture](TECHNICAL_ARCHITECTURE.md)** - Detailed technical design and implementation details for developers

## ⭐ Support

If you find this script useful, please consider:
- Giving it a star ⭐ on GitHub
- Sharing it with others who might benefit
- Contributing improvements or bug fixes

---

**Happy mounting! 🚀**
