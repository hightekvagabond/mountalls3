#!/usr/bin/bash

# =============================================================================
# S3 Bucket Mount Script
# =============================================================================
#
# DESCRIPTION:
#   This script automatically mounts Amazon S3 buckets as local filesystem 
#   directories using s3fs-fuse. It can mount buckets from all AWS profiles 
#   or from a specific profile, with customizable mount locations.
#
# PREREQUISITES:
#   1. s3fs-fuse installed:
#      Ubuntu/Debian: sudo apt-get install s3fs
#      CentOS/RHEL:   sudo yum install s3fs-fuse
#      macOS:         brew install s3fs
#
#   2. AWS CLI installed and configured:
#      - Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
#      - Configure: aws configure (or aws configure --profile PROFILE_NAME)
#      - Your AWS credentials should be in ~/.aws/credentials
#
#   3. Appropriate AWS S3 permissions for the buckets you want to mount
#
# FEATURES:
#   - Mount all buckets from all AWS profiles (default behavior)
#   - Mount all buckets from a specific AWS profile
#   - Unmount all mounted S3 buckets
#   - Customize mount base directory (default: ~/s3)
#   - Handles buckets with dots in names (adds use_path_request_style)
#   - Automatically detects bucket regions and sets appropriate endpoints
#   - Prevents duplicate mounts
#
# CRONTAB EXAMPLE (auto-mount on reboot):
#   @reboot gypsy /home/gypsy/mounts3/mounts3.sh > /home/gypsy/mounts3/mounts3.log 2>&1
#
# SECURITY NOTE:
#   This script creates temporary password files (~/.aws/passwd-s3fs-PROFILE)
#   with your AWS credentials. These files are set to 600 permissions for security.
#
# =============================================================================

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

echo "Checking prerequisites..."

# Check if s3fs is installed
if ! command -v s3fs >/dev/null 2>&1; then
    echo "❌ ERROR: s3fs-fuse is not installed or not in PATH"
    echo ""
    echo "Please install s3fs-fuse:"
    echo "  Ubuntu/Debian: sudo apt-get install s3fs"
    echo "  CentOS/RHEL:   sudo yum install s3fs-fuse"
    echo "  macOS:         brew install s3fs"
    echo ""
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws >/dev/null 2>&1; then
    echo "❌ ERROR: AWS CLI is not installed or not in PATH"
    echo ""
    echo "Please install AWS CLI:"
    echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    echo ""
    echo "Quick install options:"
    echo "  Ubuntu/Debian: sudo apt-get install awscli"
    echo "  macOS:         brew install awscli"
    echo "  Python:        pip install awscli"
    echo ""
    exit 1
fi

# Check if AWS credentials file exists
if [ ! -f ~/.aws/credentials ]; then
    echo "❌ ERROR: AWS credentials file not found at ~/.aws/credentials"
    echo ""
    echo "Please configure your AWS credentials:"
    echo "  aws configure"
    echo "  OR  aws configure --profile PROFILE_NAME"
    echo ""
    echo "Make sure you have:"
    echo "  - AWS Access Key ID"
    echo "  - AWS Secret Access Key"
    echo "  - Default region (e.g., us-east-1)"
    echo ""
    exit 1
fi

# Check if we have any AWS profiles configured
if ! aws configure list-profiles >/dev/null 2>&1; then
    echo "❌ ERROR: No AWS profiles found"
    echo ""
    echo "Please configure at least one AWS profile:"
    echo "  aws configure"
    echo "  OR  aws configure --profile PROFILE_NAME"
    echo ""
    exit 1
fi

echo "✅ All prerequisites satisfied!"
echo ""

# =============================================================================
# SCRIPT VARIABLES
# =============================================================================

# Default values
mountbase="$HOME/s3"
selected_profile=""
mount_all_profiles=true


# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "MOUNTING OPTIONS:"
    echo "  (no options)                Mount all buckets from all AWS profiles (default)"
    echo "  -p, --profile PROFILE       Mount all buckets from specific AWS profile only"
    echo "  -m, --mount-base PATH       Override default mount location (default: ~/s3)"
    echo ""
    echo "UNMOUNTING OPTIONS:"
    echo "  -u, --unmount, unmount      Unmount all S3 buckets"
    echo ""
    echo "HELP:"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                          # Mount all buckets from all profiles to ~/s3"
    echo "  $0 -p my-profile            # Mount buckets from 'my-profile' only"
    echo "  $0 -m /mnt/s3               # Mount to /mnt/s3 instead of ~/s3"
    echo "  $0 -p work -m /work/s3      # Mount 'work' profile buckets to /work/s3"
    echo "  $0 --unmount                # Unmount all S3 buckets"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--unmount|unmount)
            # Unmount all S3 buckets
            echo "Unmounting all S3 buckets..."
            IFS=$'\n' #to split on newline
            for line in $(mount | grep "s3fs");do
                #example line:  s3fs on /home/gypsy/s3/imaginationguild-devshare type fuse.s3fs (rw,nosuid,nodev,relatime,user_id=1000,group_id=1000)
                mountpoint="$(cut -d' ' -f3 <<<\"$line\" )"
                if [[ $line =~ "$HOME/s3"* ]] || [[ $line =~ "$mountbase"* ]]; then
                    echo "Unmounting $mountpoint"
                    umount "$mountpoint"
                fi
            done
            unset IFS #reset to default split
            # Delete unused dirs if they exist
            if [ -d "$mountbase" ]; then
                echo "Removing mount directory: $mountbase"
                rm -rf "$mountbase"
            fi
            echo "Unmount complete."
            exit 0
            ;;
        -p|--profile)
            selected_profile="$2"
            mount_all_profiles=false
            if [[ -z "$selected_profile" ]]; then
                echo "Error: Profile name required after -p/--profile"
                show_usage
                exit 1
            fi
            shift # past argument
            shift # past value
            ;;
        -m|--mount-base)
            mountbase="$2"
            if [[ -z "$mountbase" ]]; then
                echo "Error: Mount base path required after -m/--mount-base"
                show_usage
                exit 1
            fi
            # Expand tilde if present
            mountbase="${mountbase/#\~/$HOME}"
            shift # past argument  
            shift # past value
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate selected profile if specified
if [[ "$mount_all_profiles" == false ]]; then
    # Check if the specified profile exists
    if ! aws configure list-profiles | grep -q "^$selected_profile$"; then
        echo "Error: AWS profile '$selected_profile' not found."
        echo "Available profiles:"
        aws configure list-profiles | sed 's/^/  /'
        exit 1
    fi
    profiles="$selected_profile"
    echo "Mounting buckets from profile: $selected_profile"
else
    # Get a list of all profiles
    profiles=$(aws configure list-profiles)
    echo "Mounting buckets from all AWS profiles"
fi

# Create the mount base directory if it doesn't exist
if [ ! -d "$mountbase" ]; then
    echo "Creating mount directory: $mountbase"
    mkdir -p "$mountbase"
fi

echo "Mount base directory: $mountbase"
echo ""

# Iterate through the list of profiles
for profile in $profiles; do  # Iterate through profiles
    echo "Processing profile: $profile"
    
    # Extract AWS credentials from the credentials file
    # Note: This is a workaround since AWS CLI doesn't provide a direct way to query secret keys
    # TODO: Consider using AWS STS for temporary credentials for better security
    # TODO: Add integration with Bitwarden CLI to securely store and retrieve AWS profile credentials
    #       instead of relying on plaintext ~/.aws/credentials file
    access_key=`grep -A 5 -m 1 "\[$profile\]" ~/.aws/credentials | grep -m 1 aws_access_key_id | awk '{split($0,a,"[ \t]*=[ \t]*"); print a[2]}' | tr -d ' '`
    secret_key=`grep -A 5 -m 1 "\[$profile\]" ~/.aws/credentials | grep -m 1 aws_secret_access_key | awk '{split($0,a,"[ \t]*=[ \t]*"); print a[2]}' | tr -d ' '`
    
    # Validate that we found credentials
    if [[ -z "$access_key" || -z "$secret_key" ]]; then
        echo "  Warning: Could not find credentials for profile '$profile'. Skipping..."
        continue
    fi
    
    # Create the password file for s3fs mounting
    echo "$access_key:$secret_key" > ~/.aws/passwd-s3fs-$profile
    chmod 600 ~/.aws/passwd-s3fs-$profile

    # Get list of buckets for this profile
    echo "  Fetching bucket list..."
    buckets=`aws --profile $profile s3api list-buckets --query "Buckets[].Name" 2>/dev/null | sed ':a;N;$!ba;s/\n/ /g' | tr -s ' ' | sed 's/^...\(.*\)...$/\1/' | sed 's/", "/ /g'`
    
    if [[ -z "$buckets" ]]; then
        echo "  No buckets found for profile '$profile' or access denied."
        continue
    fi

    for bucket in $buckets; do
        # Check if the bucket is already mounted
        mountgrep=`mount | grep "s3fs" | grep "$bucket"`
        if [ -z "$mountgrep" ]; then
            echo "  Mounting: $bucket"
        else
            echo "  Already mounted: $bucket"
            continue
        fi

        # Create mount directory
        mkdir -p "$mountbase/$bucket"

        # If bucket name contains dots or underscores, add use_path_request_style option
        option=""
        if [[ $bucket =~ "." ]] || [[ $bucket =~ "_" ]]; then
            option=" -o use_path_request_style "
        fi

        # Determine bucket region and set appropriate endpoint
        locationinfo="$(aws s3api get-bucket-location --profile=$profile --bucket $bucket 2>/dev/null)"
        reg='\"LocationConstraint\": \"(.*?)\"'
        [[ "$locationinfo" =~ $reg ]] 
        location="${BASH_REMATCH[1]}"
        if [[ ! -z $location ]]; then
            option="$option -o url=https://s3-$location.amazonaws.com "
        fi

        # Build the s3fs mount command
        cmd="/usr/bin/s3fs -o check_cache_dir_exist $option $bucket $mountbase/$bucket -o passwd_file=~/.aws/passwd-s3fs-$profile"
        
        # Execute the mount command
        eval "$cmd"

        # Verify the mount was successful
        processing=true
        attempts=0
        max_attempts=6
        while [[ (! ("$(mountpoint "$mountbase/$bucket" 2>/dev/null)" == *"is a mountpoint"*)) && "$processing" == true && $attempts -lt $max_attempts ]]; do
            echo "    Waiting for $bucket to mount... (attempt $((attempts+1))/$max_attempts)"
            mountgrep=`mount | grep "s3fs" | grep "$bucket"`
            if [ -z "$mountgrep" ]; then
                echo "    Error: Failed to mount $bucket to $mountbase/$bucket"
                echo "    Troubleshoot with: $cmd -o dbglevel=info -f"
                processing=false
            else
                sleep 5
                ((attempts++))
            fi
        done
        
        if [[ "$processing" == true && $attempts -lt $max_attempts ]]; then
            echo "    ✓ Successfully mounted: $bucket"   
        elif [[ $attempts -ge $max_attempts ]]; then
            echo "    ✗ Timeout: $bucket did not mount within expected time"
        fi
    done
    echo ""
done

echo "==================================="
echo "Mount operation completed!"
echo "Mount base directory: $mountbase"
echo ""
echo "To see all mounted S3 buckets, run:"
echo "  mount | grep s3fs"
echo ""
echo "To unmount all S3 buckets, run:"
echo "  $0 --unmount"
echo "==================================="
