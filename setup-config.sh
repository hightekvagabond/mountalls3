#!/usr/bin/bash

# =============================================================================
# MountAllS3 Basic Configuration Setup
# =============================================================================
#
# DESCRIPTION:
#   Configures essential MountAllS3 settings including mount base directory,
#   AWS profile selection, and default bucket groups for mounting.
#
# USAGE:
#   Part of the modular setup system - can be run standalone or via orchestrator.
#   Uses data-driven flag parsing for consistent CLI behavior.
#
# =============================================================================

# Load common functions
COMMON_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$COMMON_SCRIPT_DIR/common.sh" || {
    echo "❌ Error: Could not load common.sh library"
    exit 1
}

# Script metadata
SCRIPT_DESCRIPTION="Configure basic MountAllS3 settings"

# =============================================================================
# FLAG DEFINITIONS
# =============================================================================

# Clear any existing flag definitions
unset FLAG_DEFINITIONS FLAG_VALUES FLAG_ORDER
declare -A FLAG_DEFINITIONS FLAG_VALUES FLAG_ORDER

# Register all flags for this script
# Format: register_flag "flag" "function" "param_type" "default" "help_text" "prompt_text" "prompt_help"

register_flag "mount-location" "configure_mount_location" "optional" "~/s3" \
    "Configure mount base directory" \
    "What would you like your mount directory to be?" \
    "S3 buckets will be mounted as subdirectories under this location. Each bucket becomes a folder you can browse like any other directory."

register_flag "profiles" "configure_aws_profiles" "none" "" \
    "Configure AWS profiles" \
    "Use all available AWS profiles?" \
    "You can use all your AWS profiles or select specific ones later when creating bucket groups."

register_flag "defaults" "configure_defaults" "none" "" \
    "Configure default mount groups" \
    "" \
    ""

register_flag "validate" "validate_config_file" "none" "" \
    "Validate current configuration" \
    "" \
    ""

register_flag "reset" "reset_config" "none" "" \
    "Reset configuration (with confirmation)" \
    "" \
    ""

register_flag "interactive" "interactive_setup" "none" "" \
    "Run interactive basic setup" \
    "" \
    ""

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

# Configures the base directory where S3 buckets will be mounted
# Validates path, creates directory if needed, and updates config
configure_mount_location() {
    local specified_path="$1"
    
    print_header "Mount Location Configuration"
    
    # Set the variable if provided via flag
    local mount_base="$specified_path"
    
    # Get default value if not provided
    if [[ -z "$mount_base" ]]; then
        local default_mount
        default_mount=$(get_default_mount_base)
        mount_base="$default_mount"
    fi
    
    # Expand and validate path
    mount_base=$(expand_path "$mount_base")
    
    if validate_directory_path "$mount_base" true; then
        update_config_value "defaults.mount_base" "$mount_base"
        print_success "Mount location set to: $mount_base"
    else
        print_error "Failed to configure mount location"
        return 1
    fi
}

# Configures which AWS profiles to use for S3 access
# Discovers available profiles and sets 'all' or 'selective' mode
configure_aws_profiles() {
    print_header "AWS Profile Selection"
    
    echo "Discovering available AWS profiles..."
    local available_profiles
    mapfile -t available_profiles < <(get_aws_profiles)
    
    if [[ ${#available_profiles[@]} -eq 0 ]]; then
        print_error "No AWS profiles found. Please configure AWS CLI first."
        echo "Run: aws configure"
        return 1
    fi
    
    echo ""
    echo "Available AWS profiles: ${available_profiles[*]}"
    echo ""
    
    local use_all_profiles=""
    configure_value "use_all_profiles" \
        "You can use all your AWS profiles or select specific ones later when creating bucket groups." \
        "Use all available AWS profiles?" \
        "y" \
        "y,n"
    
    if [[ "$use_all_profiles" == "y" ]]; then
        update_config_value "defaults.aws_profile" "all"
        print_success "Configured to use all profiles: ${available_profiles[*]}"
    else
        update_config_value "defaults.aws_profile" "selective"
        print_info "Configured for selective profile use. You'll choose specific profiles when creating bucket groups."
    fi
}

# Configures which bucket groups are mounted by default
# Allows user to select from existing groups for automatic mounting
configure_defaults() {
    print_header "Default Mount Groups"
    
    if ! config_file_exists; then
        print_warning "No configuration file found. Please run full setup first."
        return 1
    fi
    
    # Get available groups
    local groups
    mapfile -t groups < <(get_config_groups)
    
    if [[ ${#groups[@]} -eq 0 ]]; then
        print_warning "No bucket groups configured. Please configure groups first."
        print_info "Run: ./setup-mountalls3.sh --groups"
        return 1
    fi
    
    echo "Select which groups should be mounted by default when you run mountalls3"
    echo "without any arguments."
    echo ""
    
    echo "Available groups:"
    for i in "${!groups[@]}"; do
        echo "  $((i+1)). ${groups[i]}"
    done
    echo ""
    
    if [[ ${#groups[@]} -eq 1 ]]; then
        if prompt_yes_no "Use '${groups[0]}' as default group?" "y"; then
            update_config_value "defaults.mount_groups" "[\"${groups[0]}\"]"
            print_success "Default group set to: ${groups[0]}"
        fi
    else
        echo "Select default groups (enter numbers separated by spaces, e.g. '1 3'):"
        local selection
        selection=$(prompt_user "Group numbers" "1")
        
        local selected_groups=()
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#groups[@]} ]]; then
                selected_groups+=("${groups[$((num-1))]}")
            fi
        done
        
        if [[ ${#selected_groups[@]} -gt 0 ]]; then
            local groups_json="["
            for i in "${!selected_groups[@]}"; do
                if [[ $i -gt 0 ]]; then
                    groups_json+=", "
                fi
                groups_json+="\"${selected_groups[i]}\""
            done
            groups_json+="]"
            
            update_config_value "defaults.mount_groups" "$groups_json"
            print_success "Default groups set to: ${selected_groups[*]}"
        else
            print_warning "No valid selection. Using first group: ${groups[0]}"
            update_config_value "defaults.mount_groups" "[\"${groups[0]}\"]"
        fi
    fi
}

# =============================================================================
# CONFIG FILE MANAGEMENT
# =============================================================================



# Creates initial configuration file with default JSON structure
# Generates proper JSON format matching the config-example.json structure
create_basic_config() {
    local default_mount
    default_mount=$(get_default_mount_base)
    
    # Expand the tilde in default mount
    default_mount="${default_mount/#\~/$HOME}"
    
    cat > "$CONFIG_FILE" << EOF
{
  "_comment": "MountAllS3 Configuration - Generated by interactive setup on $(date)",
  "defaults": {
    "mount_groups": [],
    "mount_base": "$default_mount",
    "aws_profile": "all"
  },
  "groups": {
  }
}
EOF
    
    debug_debug "Created basic JSON configuration file at: $CONFIG_FILE"
    print_success "Created basic configuration file"
}

# Resets configuration by backing up and deleting current config file
# Prompts user for confirmation before permanent deletion
reset_config() {
    print_header "Reset Configuration"
    
    if ! config_file_exists; then
        print_info "No configuration file found. Nothing to reset."
        return 0
    fi
    
    echo "This will delete your current configuration and start fresh."
    echo "Current config file: $CONFIG_FILE"
    echo ""
    
    if prompt_yes_no "Are you sure you want to reset all configuration?" "n"; then
        if backup_config; then
            rm -f "$CONFIG_FILE"
            # Clear cache
            CONFIG_CACHE_LOADED=false
            unset CONFIG_CACHE
            declare -gA CONFIG_CACHE
            print_success "Configuration reset complete"
            print_info "Run full setup to recreate configuration"
        else
            print_error "Failed to backup configuration. Reset cancelled."
            return 1
        fi
    else
        print_info "Reset cancelled"
    fi
}

# Runs interactive prompts for basic configuration setup
# Handles mount location and AWS profile configuration
interactive_setup() {
    print_header "Basic Configuration Setup"
    
    # Create basic config file first
    ensure_config_dir
    create_basic_config
    
    # Prompt for mount location
    local mount_path
    echo "S3 buckets will be mounted as subdirectories under this location."
    echo "Each bucket becomes a folder you can browse like any other directory."
    echo ""
    read -p "What would you like your mount directory to be? [~/s3]: " mount_path
    mount_path="${mount_path:-~/s3}"
    
    # Configure mount location
    configure_mount_location "$mount_path"
    
    # Prompt for AWS profiles
    echo ""
    echo "You can use all your AWS profiles or select specific ones later when creating bucket groups."
    echo ""
    read -p "Use all available AWS profiles? [y/n]: " use_all_profiles
    if [[ "$use_all_profiles" =~ ^[Yy] ]]; then
        configure_aws_profiles
    fi
    
    print_success "Basic configuration completed"
    print_info "Next: Configure bucket groups with './setup-mountalls3.sh --groups'"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function using the data-driven flag parsing system
# Delegates to appropriate configuration functions based on flags
main() {
    # Parse flags using the common system
    parse_flags "setup-config" "$@"
    
    # Execute the parsed flags
    execute_flags
}

main "$@"