#!/usr/bin/bash

# =============================================================================
# MountAllS3 - S3 Bucket Mount Script
# =============================================================================
#
# DESCRIPTION:
#   Automatically mounts Amazon S3 buckets as local filesystem directories 
#   using s3fs-fuse with advanced security and performance features.
#
# DEPENDENCIES:
#   - s3fs-fuse: FUSE-based S3 filesystem
#   - keyutils: Linux session keyring support  
#   - AWS CLI: Amazon Web Services command line interface
#   - jq: JSON processor for configuration parsing
#   - Configured AWS profiles with appropriate S3 permissions
#
# SECURITY:
#   Uses AWS STS temporary credentials stored in Linux session keyring.
#   No AWS credentials written to disk. Auto-refresh with desktop notifications.
#
# CONFIGURATION:
#   ~/.config/mountalls3/config.yaml - User configuration with bucket groups
#   Run ./setup-mountalls3.sh for initial setup and symlink installation
#
# =============================================================================

# =============================================================================
# INITIALIZATION AND COMMON FUNCTIONS
# =============================================================================

# Source common functions and config handling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"



# =============================================================================
# USER HELP FUNCTION
# =============================================================================

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "MOUNTING OPTIONS:"
    if [[ "${config_available:-false}" == true ]]; then
        echo "  (no options)                Mount default groups from config (currently: ${mount_groups:-none})"
    else
        echo "  (no options)                Mount all buckets from all AWS profiles (default)"
    fi
    echo "  -p, --profile PROFILE       Mount all buckets from specific AWS profile only"
    echo "  -g, --group GROUP[,GROUP]   Mount specific bucket groups from config"
    echo "  -a, --all                   Mount all buckets from all profiles (ignore config)"
    echo "  -m, --mount-base PATH       Override default mount location"
    echo ""
    echo "CONFIGURATION:"
    echo "  --list-groups               List available bucket groups from config"
    echo "  --setup                     Run setup wizard to configure mountalls3"
    echo ""
    echo "UNMOUNTING OPTIONS:"
    echo "  -u, --unmount, unmount      Unmount S3 buckets (respects -p/-g flags)"
    echo ""
    echo "MAINTENANCE OPTIONS:"
    echo "  --cleanup                   Clean up empty unmounted directories"
    echo ""
    echo "DEBUG OPTIONS:"
    echo "  -v, --verbose               Enable verbose output (level 2)"
    echo "  -d, --debug                 Enable debug output (level 3)"
    echo ""
    echo "HELP:"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                          # Mount default groups from config"
    echo "  $0 -g user-folders,websites # Mount specific groups"
    echo "  $0 -p my-profile            # Mount buckets from 'my-profile' only"
    echo "  $0 -a                       # Mount all buckets (ignore config)"
    echo "  $0 -m /mnt/s3               # Mount to /mnt/s3 instead of default"
    echo "  $0 --unmount                # Unmount all S3 buckets"
    echo "  $0 -p work --unmount        # Unmount only 'work' profile buckets"
    echo "  $0 -g websites --unmount    # Unmount only 'websites' group"
    echo "  $0 --cleanup                # Clean up empty unmounted directories"
    echo "  $0 -v                       # Mount with verbose output"
    echo "  $0 -d                       # Mount with debug output"
    echo ""
    echo "SECURITY FEATURES:"
    echo "  • AWS STS temporary credentials (12-hour expiry)"
    echo "  • Session keyring storage (memory-only, cleared on logout)"
    echo "  • Process substitution (no credential files)"
    echo "  • Automatic refresh with desktop notifications"
    echo ""
    if [[ "${config_available:-false}" == true ]]; then
        echo "Configuration file: ${CONFIG_FILE:-~/.config/mountalls3/config.yaml}"
    else
        echo "No configuration file found. Run '$0 --setup' to create one."
    fi
}

# =============================================================================
# SETUP CHECK FUNCTIONS
# =============================================================================

check_setup_completed() {
    local config_file="$HOME/.config/mountalls3/config.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        return 1  # Setup not completed (no config file)
    fi
    
    return 0  # Setup completed (config file exists)
}

run_initial_setup() {
    echo "🚀 Welcome to MountAllS3!"
    echo ""
    echo "It looks like this is your first time running MountAllS3 on this system."
    echo "Let's get you set up with the initial configuration..."
    echo ""
    
    # Try to find setup script in multiple locations
    setup_script=""
    
    # First, try same directory as this script
    if [[ -f "$(dirname "$0")/setup-mountalls3.sh" ]]; then
        setup_script="$(dirname "$0")/setup-mountalls3.sh"
    # If this script is a symlink, try the original location
    elif [[ -L "$0" ]]; then
        script_dir="$(dirname "$(readlink -f "$0")")"
        if [[ -f "$script_dir/setup-mountalls3.sh" ]]; then
            setup_script="$script_dir/setup-mountalls3.sh"
        fi
    # Try common installation locations
    elif [[ -f "$HOME/bin/setup-mountalls3.sh" ]]; then
        setup_script="$HOME/bin/setup-mountalls3.sh"
    elif [[ -f "$HOME/.local/bin/setup-mountalls3.sh" ]]; then
        setup_script="$HOME/.local/bin/setup-mountalls3.sh"
    fi
    
    if [[ -n "$setup_script" ]]; then
        echo "Running setup script..."
        echo ""
        exec "$setup_script"
    else
        echo "❌ Setup script not found!"
        echo ""
        echo "Please ensure setup-mountalls3.sh is available in one of these locations:"
        echo "  - Same directory as mountalls3.sh"
        echo "  - $HOME/bin/"
        echo "  - $HOME/.local/bin/"
        echo ""
        echo "If you installed from source, the setup script should be in the same"
        echo "directory where you cloned/downloaded mountalls3.sh"
        echo ""
        echo "You can also run setup manually with:"
        echo "  ./setup-mountalls3.sh"
        exit 1
    fi
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    # Parse debug flags first and get remaining arguments
    local processed_args
    parse_debug_flags processed_args "$@"
    set -- "${processed_args[@]}"
    
    # Check for help and setup flags
    local has_setup=false
    for arg in "$@"; do
        if [[ "$arg" == "--setup" ]]; then
            has_setup=true
            break
        fi
    done
    
    for arg in "$@"; do
        if [[ "$arg" == "-h" || "$arg" == "--help" ]] && [[ "$has_setup" != "true" ]]; then
            show_usage
            exit 0
        fi
    done

    # Check for --setup flag early (before setup completion check)
    for arg in "$@"; do
        if [[ "$arg" == "--setup" ]]; then
            # Skip setup completion check if explicitly running setup
            break
        fi
    done

    # Check if setup has been completed (unless --setup flag is used)
    local skip_setup_check=false
    for arg in "$@"; do
        if [[ "$arg" == "--setup" ]]; then
            skip_setup_check=true
            break
        fi
    done
    
    if [[ "$skip_setup_check" != true ]] && ! check_setup_completed; then
        debug_info "Setup not completed, running initial setup"
        run_initial_setup
    fi
    debug_debug "Setup check completed"

    # Check prerequisites
    debug_debug "Starting prerequisite checks"
    check_prerequisites
    debug_debug "Prerequisites check completed"

    # Configuration file paths
    CONFIG_DIR="$HOME/.config/mountalls3"
    CONFIG_FILE="$CONFIG_DIR/config.yaml"

    # Default values
    mountbase="$HOME/s3"
    selected_profile=""
    mount_all_profiles=true
    use_config=false
    mount_groups=""
    config_available=false

    # Try to load configuration
    debug_debug "Looking for config file at: $CONFIG_FILE"
    if parse_config; then
        debug_verbose "Configuration file found, loading settings"
        config_available=true
        # Apply config defaults if they exist
        if [[ -n "$config_mount_base" ]]; then
            debug_debug "Using mount base from config: $config_mount_base"
            mountbase="${config_mount_base/#\~/$HOME}"
        fi
        if [[ -n "$default_groups" ]]; then
            debug_debug "Using default groups from config: $default_groups"
            mount_groups="$default_groups"
            use_config=true
            mount_all_profiles=false
        fi
        debug_debug "Configuration applied: mount_base=$mountbase, groups=$mount_groups, use_config=$use_config"
        if [[ -n "$config_aws_profile" && "$config_aws_profile" != "all" ]]; then
            selected_profile="$config_aws_profile"
            mount_all_profiles=false
        fi
    fi

    # Check prerequisites
    echo "Checking prerequisites..."
    if ! check_jq; then
        exit 1
    fi
    echo "✅ All prerequisites satisfied!"
    echo ""

    # Command line arguments are handled inline later in the function

    # Create the mount base directory if it doesn't exist
    if [ ! -d "$mountbase" ]; then
        echo "Creating mount directory: $mountbase"
        mkdir -p "$mountbase"
    fi

    echo "Mount base directory: $mountbase"
    echo ""

    # Main mounting logic based on configuration
    if [[ "$use_config" == true ]]; then
        # Mount specific groups from config
        echo "Mounting bucket groups: $mount_groups"
        
        # Collect all buckets from specified groups
        declare -A buckets_to_mount
        
        IFS=',' read -ra GROUPS <<< "$mount_groups"
        for group in "${GROUPS[@]}"; do
            group=$(echo "$group" | xargs)  # trim whitespace
            echo "Processing group: $group"
            
            # Get buckets for this group
            while IFS=':' read -r profile bucket; do
                if [[ -n "$profile" && -n "$bucket" ]]; then
                    buckets_to_mount["$profile:$bucket"]=1
                    debug_verbose "Added bucket to mount list: $bucket (profile: $profile)"
                fi
            done < <(get_group_buckets "$group")
        done
        
        if [[ ${#buckets_to_mount[@]} -eq 0 ]]; then
            echo "No buckets found in specified groups. Check your configuration."
            exit 1
        fi
        
        # Process each unique profile:bucket combination
        for profile_bucket in "${!buckets_to_mount[@]}"; do
            IFS=':' read -r profile bucket <<< "$profile_bucket"
            
            # Validate profile exists
            if ! aws configure list-profiles | grep -q "^$profile$"; then
                echo "Warning: AWS profile '$profile' not found. Skipping bucket '$bucket'."
                continue
            fi
            
            debug_info ""
            debug_info "Mounting bucket: $bucket (profile: $profile)"
            mount_single_bucket "$profile" "$bucket"
        done
        
    elif [[ "$mount_all_profiles" == false && -n "$selected_profile" ]]; then
        # Mount all buckets from specific profile
        if ! aws configure list-profiles | grep -q "^$selected_profile$"; then
            echo "Error: AWS profile '$selected_profile' not found."
            echo "Available profiles:"
            aws configure list-profiles | sed 's/^/  /'
            exit 1
        fi
        debug_info "Mounting buckets from profile: $selected_profile"
        mount_profile_buckets "$selected_profile"
        
    else
        # Mount all buckets from all profiles (original behavior)
        profiles=$(aws configure list-profiles)
        debug_info "Mounting buckets from all AWS profiles"
        
        for profile in $profiles; do
            mount_profile_buckets "$profile"
        done
    fi

    echo "==================================="
    echo "Mount operation completed!"
    echo "Mount base directory: $mountbase"
    echo "Local cache directory: ~/.cache/s3fs/"
    echo ""
    echo "To see all mounted S3 buckets, run:"
    echo "  mount | grep s3fs"
    echo ""
    echo "To monitor s3fs resource usage, run:"
    echo "  ps aux | grep s3fs"
    echo "  du -sh ~/.cache/s3fs/*"
    echo ""
    echo "To unmount all S3 buckets, run:"
    echo "  $0 --unmount"
    echo ""
    echo "PERFORMANCE TIPS:"
    echo "• To prevent system utilities from scanning s3fs mounts,"
    echo "  add 'fuse.s3fs' to PRUNEFS in /etc/updatedb.conf"
    echo "• To clean up 'df' output, add this alias to ~/.bashrc:"
    echo "  alias df='command df \"\$@\" | grep -v \"^s3fs\"'"
    echo "==================================="
    
    # Automatic cleanup of empty unmounted directories
    debug_info ""
    cleanup_unmounted_directories "$mountbase" false
}

# =============================================================================
# PREREQUISITE CHECK FUNCTIONS
# =============================================================================

check_keyctl() {
    if ! command -v keyctl >/dev/null 2>&1; then
        echo "❌ ERROR: keyctl not found. Please install keyutils package:"
        echo "  Ubuntu/Debian: sudo apt-get install keyutils"
        echo "  CentOS/RHEL:   sudo yum install keyutils"
        echo ""
        return 1
    fi
    return 0
}

check_prerequisites() {
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

    # Check if keyctl is available for session keyring support
    if ! check_keyctl; then
        exit 1
    fi

echo "✅ All prerequisites satisfied!"
echo ""
}

# =============================================================================
# AWS CREDENTIAL MANAGEMENT FUNCTIONS
# =============================================================================

store_sts_credentials() {
    local profile="$1"
    local access_key="$2"
    local secret_key="$3"
    local session_token="$4"
    local expiry="$5"
    
    # Store in session keyring with profile-specific keys
    debug_debug "Storing STS credentials for profile '$profile' in session keyring (expires: $(date -d "@$expiry" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'invalid date'))"
    keyctl add user "s3fs_access_${profile}" "$access_key" @s >/dev/null 2>&1
    keyctl add user "s3fs_secret_${profile}" "$secret_key" @s >/dev/null 2>&1
    keyctl add user "s3fs_token_${profile}" "$session_token" @s >/dev/null 2>&1
    keyctl add user "s3fs_expiry_${profile}" "$expiry" @s >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        echo "  ✓ STS credentials stored in session keyring (expires: $(date -d "@$expiry" '+%Y-%m-%d %H:%M:%S'))"
        return 0
    else
        echo "  ❌ Failed to store credentials in session keyring"
        return 1
    fi
}

get_sts_credentials() {
    local profile="$1"
    
    # Check if credentials exist and are not expired
    local expiry_key_id=$(keyctl search @s user "s3fs_expiry_${profile}" 2>/dev/null)
    if [[ -z "$expiry_key_id" ]]; then
        return 1  # No credentials found
    fi
    
    local expiry=$(keyctl print "$expiry_key_id" 2>/dev/null)
    local current_time=$(date +%s)
    
    if [[ -z "$expiry" ]] || [[ "$current_time" -ge "$expiry" ]]; then
        # Credentials expired, clean them up
        keyctl unlink $(keyctl search @s user "s3fs_access_${profile}" 2>/dev/null) @s 2>/dev/null
        keyctl unlink $(keyctl search @s user "s3fs_secret_${profile}" 2>/dev/null) @s 2>/dev/null
        keyctl unlink $(keyctl search @s user "s3fs_token_${profile}" 2>/dev/null) @s 2>/dev/null
        keyctl unlink $(keyctl search @s user "s3fs_expiry_${profile}" 2>/dev/null) @s 2>/dev/null
        return 2  # Credentials expired
    fi
    
    # Retrieve valid credentials
    local access_key_id=$(keyctl search @s user "s3fs_access_${profile}" 2>/dev/null)
    local secret_key_id=$(keyctl search @s user "s3fs_secret_${profile}" 2>/dev/null)
    local session_token_id=$(keyctl search @s user "s3fs_token_${profile}" 2>/dev/null)
    
    if [[ -n "$access_key_id" && -n "$secret_key_id" && -n "$session_token_id" ]]; then
        STS_ACCESS_KEY=$(keyctl print "$access_key_id" 2>/dev/null)
        STS_SECRET_KEY=$(keyctl print "$secret_key_id" 2>/dev/null)
        STS_SESSION_TOKEN=$(keyctl print "$session_token_id" 2>/dev/null)
        return 0  # Success
    fi
    
    return 1  # Failed to retrieve
}

generate_sts_credentials() {
    local profile="$1"
    
    echo "  🔄 Generating new STS credentials for profile: $profile"
    
    # Generate 12-hour STS token
    local sts_output
    sts_output=$(aws sts get-session-token --profile "$profile" --duration-seconds 43200 --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$sts_output" ]]; then
        echo "  ❌ Failed to generate STS credentials for profile: $profile"
        echo "     Make sure the profile has valid AWS credentials"
        return 1
    fi
    
    # Parse JSON output
    local access_key=$(echo "$sts_output" | grep -o '"AccessKeyId"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local secret_key=$(echo "$sts_output" | grep -o '"SecretAccessKey"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local session_token=$(echo "$sts_output" | grep -o '"SessionToken"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local expiration=$(echo "$sts_output" | grep -o '"Expiration"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$access_key" || -z "$secret_key" || -z "$session_token" ]]; then
        echo "  ❌ Failed to parse STS credentials"
        return 1
    fi
    
    # Convert expiration to Unix timestamp
    local expiry_timestamp=$(date -d "$expiration" +%s 2>/dev/null)
    if [[ -z "$expiry_timestamp" ]]; then
        echo "  ❌ Failed to parse expiration time"
        return 1
    fi
    
    # Store in session keyring
    store_sts_credentials "$profile" "$access_key" "$secret_key" "$session_token" "$expiry_timestamp"
    
    # Set global variables for immediate use
    STS_ACCESS_KEY="$access_key"
    STS_SECRET_KEY="$secret_key"
    STS_SESSION_TOKEN="$session_token"
    
    return 0
}

get_or_refresh_sts_credentials() {
    local profile="$1"
    
    # Try to get existing credentials from keyring
    get_sts_credentials "$profile"
    local result=$?
    
    case $result in
        0)
            # Valid credentials found
            echo "  ✓ Using cached STS credentials for profile: $profile"
            return 0
            ;;
        2)
            # Credentials expired
            echo "  ⏰ STS credentials expired for profile: $profile"
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "MountAllS3" "Refreshing expired credentials for $profile..." -t 5000
            fi
            generate_sts_credentials "$profile"
            return $?
            ;;
        1)
            # No credentials found
            echo "  🆕 No STS credentials found for profile: $profile"
            generate_sts_credentials "$profile"
            return $?
            ;;
    esac
}





# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

cleanup_unmounted_directories() {
    local mount_base="$1"
    local verbose="${2:-false}"
    
    if [[ -z "$mount_base" ]] || [[ ! -d "$mount_base" ]]; then
        echo "Mount base directory '$mount_base' does not exist. Nothing to clean up."
        return 0
    fi
    
    # Expand tilde if present
    mount_base="${mount_base/#\~/$HOME}"
    
    # Get list of currently mounted s3fs directories
    local mounted_dirs=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            # Extract mount point from mount output
            local mountpoint=$(echo "$line" | awk '{print $3}')
            mounted_dirs+=("$mountpoint")
        fi
    done < <(mount | grep "type fuse.s3fs" | grep "$mount_base")
    
    if [[ "$verbose" == true ]]; then
        echo "🧹 Cleanup: Checking for unmounted directories in $mount_base"
        if [[ ${#mounted_dirs[@]} -gt 0 ]]; then
            echo "   Currently mounted:"
            for mounted in "${mounted_dirs[@]}"; do
                echo "     • $mounted"
            done
        else
            echo "   No s3fs directories currently mounted"
        fi
    echo ""
    fi
    
    local cleaned_count=0
    local skipped_count=0
    
    # Check each directory in mount base
    for dir in "$mount_base"/*; do
        # Skip if no directories found (glob didn't match)
        [[ ! -d "$dir" ]] && continue
        
        local dir_name=$(basename "$dir")
        local is_mounted=false
        
        # Check if this directory is currently mounted
        for mounted in "${mounted_dirs[@]}"; do
            if [[ "$mounted" == "$dir" ]]; then
                is_mounted=true
                break
            fi
        done
        
        if [[ "$is_mounted" == true ]]; then
            if [[ "$verbose" == true ]]; then
                debug_verbose "   Skipping $dir_name (currently mounted)"
            fi
            ((skipped_count++))
            continue
        fi
        
        # Check if directory is truly empty
        if [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
            if [[ "$verbose" == true ]]; then
                debug_verbose "   Skipping $dir_name (contains files or directories)"
            fi
            ((skipped_count++))
            continue
        fi
        
        # Additional safety check: verify it's not a mountpoint
        if mountpoint -q "$dir" 2>/dev/null; then
            if [[ "$verbose" == true ]]; then
                debug_verbose "   Skipping $dir_name (is a mountpoint)"
            fi
            ((skipped_count++))
            continue
        fi
        
        # Safety check: ensure we're only operating within mount_base
        if [[ "$dir" != "$mount_base"/* ]]; then
            if [[ "$verbose" == true ]]; then
                debug_verbose "   Skipping $dir_name (outside mount base)"
            fi
            ((skipped_count++))
            continue
        fi
        
        # Safe to remove empty directory
        if rmdir "$dir" 2>/dev/null; then
            if [[ "$verbose" == true ]]; then
                debug_verbose "   ✓ Removed empty directory: $dir_name"
            fi
            ((cleaned_count++))
        else
            if [[ "$verbose" == true ]]; then
                debug_verbose "   ⚠️  Failed to remove $dir_name (may not be empty or permission issue)"
            fi
            ((skipped_count++))
        fi
    done
    
    if [[ "$verbose" == true ]] || [[ $cleaned_count -gt 0 ]]; then
        echo "🧹 Cleanup completed: removed $cleaned_count empty directories, skipped $skipped_count"
    fi
    
    return 0
}

# =============================================================================
# S3 MOUNTING FUNCTIONS
# =============================================================================

mount_single_bucket() {
    local profile="$1"
    local bucket="$2"
    
    # Create the mount base directory if it doesn't exist
    if [ ! -d "$mountbase" ]; then
        echo "Creating mount directory: $mountbase"
        mkdir -p "$mountbase"
    fi
    
    # Get or refresh STS credentials for this profile
    get_or_refresh_sts_credentials "$profile"
    if [[ $? -ne 0 ]]; then
        echo "  ❌ Failed to obtain STS credentials for profile '$profile'. Skipping bucket '$bucket'..."
        return 1
    fi
    
    # Check if the bucket is already mounted
    mountgrep=`mount | grep "s3fs" | grep "$bucket"`
    if [ -z "$mountgrep" ]; then
        echo "  Mounting: $bucket"
    else
        echo "  Already mounted: $bucket"
        return 0
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

    # Build the s3fs mount command with performance optimizations
    performance_opts="-o enable_noobj_cache -o notsup_compat_dir -o multireq_max=20 -o parallel_count=5 -o complement_stat"
    
    # Add local cache directory if it doesn't exist
    cache_dir="$HOME/.cache/s3fs/$bucket"
    mkdir -p "$cache_dir"
    cache_opts="-o use_cache=$cache_dir -o ensure_diskfree=1024"
    
    # Use process substitution to provide STS credentials (no disk storage!)
    cmd="/usr/bin/s3fs -o check_cache_dir_exist $option $performance_opts $cache_opts $bucket $mountbase/$bucket -o passwd_file=<(echo \"$STS_ACCESS_KEY:$STS_SECRET_KEY:$STS_SESSION_TOKEN\")"
    
    # Execute the mount command
    bash -c "$cmd"

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
}

mount_profile_buckets() {
    local profile="$1"
    
    echo "Processing profile: $profile"
    
    # Get list of buckets for this profile using AWS CLI
    echo "  Fetching bucket list..."
    local bucket_list
    bucket_list=$(aws s3 ls --profile "$profile" 2>/dev/null | awk '{print $3}')
    
    if [[ -z "$bucket_list" ]]; then
        echo "  No buckets found for profile '$profile' or access denied."
        return 1
    fi

    # Convert to array for easier processing
    local buckets=($bucket_list)
    echo "  Found ${#buckets[@]} bucket(s)"

    for bucket in "${buckets[@]}"; do
        if [[ -n "$bucket" ]]; then
            mount_single_bucket "$profile" "$bucket"
        fi
    done
    echo ""
}

unmount_buckets() {
    local target_profile="$1"
    local target_groups="$2"
    local mount_base="$3"
    local unmount_all="${4:-true}"
    
    debug_info "Starting unmount process"
    debug_debug "Parameters: profile='$target_profile', groups='$target_groups', mount_base='$mount_base', unmount_all='$unmount_all'"
    
    echo "Unmounting S3 buckets..."
    
    local unmounted_count=0
    local skipped_count=0
    
    # Get list of currently mounted s3fs filesystems
    IFS=$'\n'
    for line in $(mount | grep "type fuse.s3fs"); do
        # Parse mount line: s3fs on /path/to/mount type fuse.s3fs (options)
        local mountpoint=$(echo "$line" | awk '{print $3}')
        local bucket_name=$(basename "$mountpoint")
        
        debug_debug "Found mounted s3fs: $mountpoint (bucket: $bucket_name)"
        
        # Check if this mount is in our mount base directory
        if [[ "$mountpoint" != "$mount_base"/* ]]; then
            debug_verbose "Skipping $mountpoint (not in mount base $mount_base)"
            ((skipped_count++))
            continue
        fi
        
        local should_unmount=false
        
        if [[ "$unmount_all" == "true" ]]; then
            should_unmount=true
            debug_debug "Will unmount $bucket_name (unmount all mode)"
        else
            # Check if this bucket matches target criteria
            if [[ -n "$target_profile" ]]; then
                # For profile-specific unmounting, we need to check if this bucket
                # was mounted with the target profile (this is tricky without metadata)
                # For now, we'll unmount if profile is specified and unmount_all is false
                should_unmount=true
                debug_debug "Will unmount $bucket_name (profile mode: $target_profile)"
            elif [[ -n "$target_groups" ]]; then
                # Check if bucket is in target groups
                IFS=',' read -ra GROUPS <<< "$target_groups"
                for group in "${GROUPS[@]}"; do
                    local group_buckets=$(get_group_buckets "$group")
                    if [[ "$group_buckets" == *"$bucket_name"* ]]; then
                        should_unmount=true
                        debug_debug "Will unmount $bucket_name (found in group: $group)"
                        break
                    fi
                done
            fi
        fi
        
        if [[ "$should_unmount" == "true" ]]; then
            echo "  Unmounting: $mountpoint"
            debug_verbose "Executing: umount '$mountpoint'"
            
            if umount "$mountpoint" 2>/dev/null; then
                echo "    ✓ Successfully unmounted $bucket_name"
                ((unmounted_count++))
                
                # Remove empty mount directory
                if [[ -d "$mountpoint" ]] && [[ -z "$(ls -A "$mountpoint" 2>/dev/null)" ]]; then
                    debug_debug "Removing empty mount directory: $mountpoint"
                    rmdir "$mountpoint" 2>/dev/null || true
                fi
            else
                echo "    ⚠️  Failed to unmount $bucket_name (may not be mounted or in use)"
                ((skipped_count++))
            fi
        else
            debug_verbose "Skipping $bucket_name (doesn't match criteria)"
            ((skipped_count++))
        fi
    done
    unset IFS
    
    echo "Unmount completed: $unmounted_count unmounted, $skipped_count skipped"
    
    # Run cleanup to remove any remaining empty directories
    debug_verbose "Running cleanup after unmount"
    cleanup_unmounted_directories "$mount_base" false
}

# =============================================================================
# ARGUMENT PARSING FUNCTION
# =============================================================================

parse_arguments() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--unmount|unmount)
                # Unmount with current settings (profile/groups if specified)
                debug_info "Unmount requested with current settings"
                unmount_buckets "$selected_profile" "$mount_groups" "$mountbase" "$mount_all_profiles"
                exit 0
                ;;
            -g|--group)
                mount_groups="$2"
                use_config=true
                mount_all_profiles=false
                if [[ -z "$mount_groups" ]]; then
                    echo "Error: Group name(s) required after -g/--group"
                    show_usage
                    exit 1
                fi
                shift # past argument
                shift # past value
                ;;
            -a|--all)
                use_config=false
                mount_all_profiles=true
                mount_groups=""
                shift # past argument
                ;;
            --list-groups)
                list_groups
                exit 0
                ;;
            --cleanup)
                # Configuration file paths (needed for mount base)
                CONFIG_DIR="$HOME/.config/mountalls3"
                CONFIG_FILE="$CONFIG_DIR/config.yaml"
                
                # Default mount base
                local cleanup_mount_base="$HOME/s3"
                
                # Try to get mount base from config if it exists
                if [[ -f "$CONFIG_FILE" ]]; then
                    local config_mount_base=$(grep "mount_base:" "$CONFIG_FILE" | sed 's/.*mount_base:\s*["'\'']\?\([^"'\'']*\)["'\'']\?/\1/')
                    if [[ -n "$config_mount_base" ]]; then
                        cleanup_mount_base="${config_mount_base/#\~/$HOME}"
                    fi
                fi
                
                # Check for custom mount base in arguments
                for ((i=1; i<=$#; i++)); do
                    if [[ "${!i}" == "-m" || "${!i}" == "--mount-base" ]]; then
                        ((i++))
                        if [[ $i -le $# ]]; then
                            cleanup_mount_base="${!i}"
                            cleanup_mount_base="${cleanup_mount_base/#\~/$HOME}"
                        fi
                        break
                    fi
                done
                
                cleanup_unmounted_directories "$cleanup_mount_base" true
            exit 0
            ;;
            --setup)
                # Try to find setup script in multiple locations
                setup_script=""
                
                # First, try same directory as this script
                if [[ -f "$(dirname "$0")/setup-mountalls3.sh" ]]; then
                    setup_script="$(dirname "$0")/setup-mountalls3.sh"
                # If this script is a symlink, try the original location
                elif [[ -L "$0" ]]; then
                    script_dir="$(dirname "$(readlink -f "$0")")"
                    if [[ -f "$script_dir/setup-mountalls3.sh" ]]; then
                        setup_script="$script_dir/setup-mountalls3.sh"
                    fi
                # Try common installation locations
                elif [[ -f "$HOME/bin/setup-mountalls3.sh" ]]; then
                    setup_script="$HOME/bin/setup-mountalls3.sh"
                elif [[ -f "$HOME/.local/bin/setup-mountalls3.sh" ]]; then
                    setup_script="$HOME/.local/bin/setup-mountalls3.sh"
                fi
                
                if [[ -n "$setup_script" ]]; then
                    # Remove --setup from arguments and add debug flags
                    local setup_args=()
                    for arg in "$@"; do
                        if [[ "$arg" != "--setup" ]]; then
                            setup_args+=("$arg")
                        fi
                    done
                    
                    # Add current debug level flags
                    local debug_flags
                    debug_flags=$(get_debug_flags)
                    if [[ -n "$debug_flags" ]]; then
                        debug_debug "Passing debug flags to setup script: $debug_flags"
                        # shellcheck disable=SC2086
                        exec "$setup_script" ${debug_flags} "${setup_args[@]}"
                    else
                        exec "$setup_script" "${setup_args[@]}"
                    fi
                else
                    echo "❌ Setup script not found!"
                    echo ""
                    echo "Please ensure setup-mountalls3.sh is available in one of these locations:"
                    echo "  - Same directory as mountalls3.sh"
                    echo "  - $HOME/bin/"
                    echo "  - $HOME/.local/bin/"
                    echo ""
                    echo "If you installed from source, the setup script should be in the same"
                    echo "directory where you cloned/downloaded mountalls3.sh"
                    exit 1
                fi
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
}

# =============================================================================
# MAIN SCRIPT EXECUTION
# =============================================================================

main "$@"
