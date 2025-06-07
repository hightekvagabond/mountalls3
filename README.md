# S3 Bucket Mount Script

A bash script that automatically mounts Amazon S3 buckets as local filesystem directories using s3fs-fuse. Mount all your S3 buckets from all AWS profiles or selectively mount from specific profiles with customizable locations.

## 🚀 Features

- **Multi-Profile Support**: Mount buckets from all AWS profiles or select specific profiles
- **Custom Mount Locations**: Override the default `~/s3` mount directory
- **Smart Bucket Handling**: Automatically handles buckets with dots in names and different regions
- **Duplicate Prevention**: Detects and skips already mounted buckets
- **Easy Unmounting**: Simple command to unmount all S3 buckets at once
- **Comprehensive Error Handling**: Clear error messages and troubleshooting guidance
- **Prerequisite Validation**: Automatic checks for required tools and configuration

## 📋 Prerequisites

The script automatically checks for these requirements and provides installation instructions if missing:

1. **s3fs-fuse** - FUSE-based file system for S3
2. **AWS CLI** - Amazon Web Services command line interface
3. **AWS Credentials** - Properly configured AWS profiles with access keys

### Quick Installation

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install s3fs awscli
```

**CentOS/RHEL:**
```bash
sudo yum install s3fs-fuse awscli
```

**macOS:**
```bash
brew install s3fs awscli
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
   wget https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/mounts3.sh
   # OR
   curl -O https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/mounts3.sh
   ```

2. **Make it executable:**
   ```bash
   chmod +x mounts3.sh
   ```

3. **Run it:**
   ```bash
   ./mounts3.sh
   ```

## 📖 Usage

### Basic Commands

```bash
# Mount all buckets from all AWS profiles (default behavior)
./mounts3.sh

# Mount buckets from a specific profile only
./mounts3.sh -p my-work-profile

# Mount to a custom location instead of ~/s3
./mounts3.sh -m /mnt/s3

# Combine profile and custom location
./mounts3.sh -p production -m /production/s3

# Unmount all S3 buckets
./mounts3.sh --unmount

# Show help
./mounts3.sh --help
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `(no options)` | Mount all buckets from all AWS profiles to `~/s3` |
| `-p, --profile PROFILE` | Mount buckets from specific AWS profile only |
| `-m, --mount-base PATH` | Override default mount location |
| `-u, --unmount, unmount` | Unmount all S3 buckets |
| `-h, --help` | Show help message |

### Examples

**Mount everything:**
```bash
./mounts3.sh
```

**Work with specific environments:**
```bash
# Mount only production buckets
./mounts3.sh -p production

# Mount development buckets to a specific location
./mounts3.sh -p development -m /dev/s3

# Mount personal buckets to home directory
./mounts3.sh -p personal -m ~/personal-s3
```

**Cleanup:**
```bash
# Unmount everything
./mounts3.sh --unmount
```

## 🔄 Automation

### Crontab (Auto-mount on reboot)

Add to your crontab to automatically mount S3 buckets on system startup:

```bash
crontab -e
```

Add this line:
```bash
@reboot /path/to/mounts3.sh > /path/to/mounts3.log 2>&1
```

### Systemd Service (Advanced)

For more robust startup handling, you can create a systemd service:

```bash
sudo nano /etc/systemd/system/s3-mount.service
```

```ini
[Unit]
Description=Mount S3 Buckets
After=network.target

[Service]
Type=oneshot
User=yourusername
ExecStart=/path/to/mounts3.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable the service:
```bash
sudo systemctl enable s3-mount.service
sudo systemctl start s3-mount.service
```

## 🔒 Security Notes

- The script creates temporary password files (`~/.aws/passwd-s3fs-PROFILE`) with 600 permissions
- AWS credentials are read from your existing `~/.aws/credentials` file
- Consider using AWS IAM roles or temporary credentials for enhanced security
- Never commit AWS credentials to version control

## 🐛 Troubleshooting

### Common Issues

**Permission Denied:**
```bash
# Make sure you have proper AWS permissions for the buckets
aws s3 ls --profile yourprofile

# Check if s3fs has proper permissions
ls -la ~/.aws/passwd-s3fs-*
```

**Mount Failures:**
```bash
# Run s3fs manually with debug info
s3fs your-bucket /path/to/mountpoint -o passwd_file=~/.aws/passwd-s3fs-profile -o dbglevel=info -f
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
chmod +x mounts3.sh
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
