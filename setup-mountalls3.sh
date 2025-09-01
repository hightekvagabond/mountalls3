#!/usr/bin/bash

# =============================================================================
# MountAllS3 Setup Orchestrator
# =============================================================================
#
# DESCRIPTION:
#   Main setup script that orchestrates the modular setup system.
#   Calls specialized setup modules for different configuration aspects.
#
# FEATURES:
#   - Full interactive setup workflow
#   - Modular configuration editing
#   - Intelligent module calling
#   - Flag passing to sub-modules
#
# =============================================================================

# Load common functions
COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$COMMON_SCRIPT_DIR/common.sh" || {
    echo "❌ Error: Could not load common.sh library"
    echo "Please ensure common.sh is in the same directory as this script"
    exit 1
}

# Setup modules
SETUP_CONFIG="$COMMON_SCRIPT_DIR/setup-config.sh"
SETUP_GROUPS="$COMMON_SCRIPT_DIR/setup-groups.sh"
SETUP_SYSTEM="$COMMON_SCRIPT_DIR/setup-system.sh"

# Displays comprehensive help for the setup orchestrator
# Shows all available options and examples for modular setup
show_usage() {
    echo "MountAllS3 Interactive Setup"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "FULL SETUP:"
    echo "  (no options)                Run complete interactive setup"
    echo ""
    echo "BASIC CONFIGURATION:"
    echo "  --mount-location           Configure mount base directory"
    echo "  --profiles                 Configure AWS profiles to use"
    echo "  --defaults                 Configure default mount groups"
    echo ""
    echo "BUCKET GROUPS:"
    echo "  --groups                   Configure bucket groups"
    echo "  --assign-buckets           Assign buckets to existing groups"
    echo "  --list-buckets             List buckets for profile selection"
    echo ""
    echo "SYSTEM INTEGRATION:"
    echo "  --autostart                Configure desktop autostart"
    echo "  --symlinks                 Configure command symlinks"
    echo "  --system                   Configure system optimizations (requires sudo)"
    echo ""
    echo "UTILITIES:"
    echo "  --show-config              Display current configuration"
    echo "  --validate                 Validate current configuration"
    echo "  --reset                    Reset configuration (with confirmation)"
    echo ""
    echo "HELP:"
    echo "  --help, -h                 Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                         # Complete setup wizard"
    echo "  $0 --mount-location        # Set mount directory only"
    echo "  $0 --groups                # Configure bucket groups only"
    echo "  $0 --profiles --groups     # Configure profiles and groups"
    echo "  $0 --show-config           # Display current settings"
    echo ""
    echo "MODULAR DESIGN:"
    echo "  This setup uses specialized modules for different tasks:"
    echo "  • setup-config.sh   - Basic configuration (mount, profiles, defaults)"
    echo "  • setup-groups.sh   - Bucket group management and assignment"
    echo "  • setup-system.sh   - System integration (autostart, symlinks, optimization)"
}

# Verifies that all required setup modules exist and are accessible
# Returns error if any critical setup modules are missing
check_modules() {
    local missing_modules=()
    
    if [[ ! -f "$SETUP_CONFIG" ]]; then
        missing_modules+=("setup-config.sh")
    fi
    
    if [[ ! -f "$SETUP_GROUPS" ]]; then
        missing_modules+=("setup-groups.sh")
    fi
    
    if [[ ! -f "$SETUP_SYSTEM" ]]; then
        missing_modules+=("setup-system.sh")
    fi
    
    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        print_error "Missing setup modules:"
        for module in "${missing_modules[@]}"; do
            echo "  ❌ $module"
        done
        echo ""
        print_info "These modules are required for full functionality."
        print_info "You can create placeholder versions or implement them as needed."
        return 1
    fi
    
    return 0
}

# Orchestrates the complete setup workflow by calling all modules
# Runs basic config, groups, and optionally system integration
run_full_setup() {
    print_header "MountAllS3 Complete Setup"
    echo "This wizard will guide you through configuring MountAllS3."
    echo "We'll configure everything step by step with no manual file editing!"
    echo ""
    
    # Step 1: Basic configuration
    print_info "Step 1: Basic Configuration"
    if ! "$SETUP_CONFIG" --interactive; then
        print_error "Basic configuration failed"
        return 1
    fi
    
    # Step 2: Bucket groups
    print_info "Step 2: Bucket Groups"
    if ! "$SETUP_GROUPS" --interactive; then
        print_error "Bucket group configuration failed"
        return 1
    fi
    
    # Step 3: System integration (optional)
    echo ""
    if prompt_yes_no "Configure system integration (autostart, symlinks)?" "y"; then
        print_info "Step 3: System Integration"
        "$SETUP_SYSTEM" --interactive || print_warning "System integration had issues"
    fi
    
    print_header "Setup Complete!"
    print_success "MountAllS3 is now configured and ready to use"
    echo ""
    echo "Try these commands:"
    echo "  ./mountalls3.sh           # Mount your default groups"
    echo "  ./mountalls3.sh --help    # See all available options"
    echo "  $0 --show-config          # Review your configuration"
}

# Displays current configuration in a formatted, human-readable way
# Shows mount base, profiles, groups, and group descriptions
show_current_config() {
    print_header "Current Configuration"
    
    if ! config_file_exists; then
        print_warning "No configuration file found at: $CONFIG_FILE"
        print_info "Run '$0' to create initial configuration"
        return 1
    fi
    
    echo "Configuration file: $CONFIG_FILE"
    echo ""
    
    # Load config cache and show values
    load_config_cache
    
    echo "Mount Base: $(get_config_value "defaults.mount_base" "Not configured")"
    echo "AWS Profile: $(get_config_value "defaults.aws_profile" "Not configured")"
    echo "Default Groups: $(get_config_value "defaults.mount_groups" "Not configured")"
    echo ""
    
    echo "Available Groups:"
    local groups
    mapfile -t groups < <(get_config_groups)
    if [[ ${#groups[@]} -gt 0 ]]; then
        for group in "${groups[@]}"; do
            local desc
            desc=$(get_group_description "$group")
            echo "  • $group: ${desc:-No description}"
        done
    else
        echo "  None configured"
    fi
}

# Main orchestrator function that routes requests to appropriate modules
# Handles argument parsing and delegates to specialized setup modules
main() {
    # Parse debug flags first and get remaining arguments
    local processed_args
    parse_debug_flags processed_args "$@"
    set -- "${processed_args[@]}"
    
    debug_debug "Setup orchestrator started with args: $*"
    
    # Parse arguments
    local run_full=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_usage
                exit 0
                ;;
            --mount-location)
                run_full=false
                local debug_flags=$(get_debug_flags)
                # shellcheck disable=SC2086
                check_modules && "$SETUP_CONFIG" $debug_flags --mount-location
                exit $?
                ;;
            --profiles)
                run_full=false
                local debug_flags=$(get_debug_flags)
                # shellcheck disable=SC2086
                check_modules && "$SETUP_CONFIG" $debug_flags --profiles
                exit $?
                ;;
            --defaults)
                run_full=false
                local debug_flags=$(get_debug_flags)
                # shellcheck disable=SC2086
                check_modules && "$SETUP_CONFIG" $debug_flags --defaults
                exit $?
                ;;
            --groups)
                run_full=false
                local debug_flags=$(get_debug_flags)
                # shellcheck disable=SC2086
                check_modules && "$SETUP_GROUPS" $debug_flags --groups
                exit $?
                ;;
            --assign-buckets)
                run_full=false
                local debug_flags=$(get_debug_flags)
                # shellcheck disable=SC2086
                check_modules && "$SETUP_GROUPS" $debug_flags --assign-buckets
                exit $?
                ;;
            --list-buckets)
                run_full=false
                local debug_flags=$(get_debug_flags)
                # shellcheck disable=SC2086
                check_modules && "$SETUP_GROUPS" $debug_flags --list-buckets
                exit $?
                ;;
            --autostart)
                run_full=false
                local debug_flags=$(get_debug_flags)
                # shellcheck disable=SC2086
                check_modules && "$SETUP_SYSTEM" $debug_flags --autostart
                exit $?
                ;;
            --symlinks)
                run_full=false
                local debug_flags=$(get_debug_flags)
                # shellcheck disable=SC2086
                check_modules && "$SETUP_SYSTEM" $debug_flags --symlinks
                exit $?
                ;;
            --system)
                run_full=false
                local debug_flags=$(get_debug_flags)
                # shellcheck disable=SC2086
                check_modules && "$SETUP_SYSTEM" $debug_flags --system
                exit $?
                ;;
            --show-config)
                show_current_config
                exit $?
                ;;
            --validate)
                run_full=false
                check_modules && "$SETUP_CONFIG" --validate
                exit $?
                ;;
            --reset)
                run_full=false
                check_modules && "$SETUP_CONFIG" --reset
                exit $?
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Run full setup if no specific flags
    if [[ "$run_full" == "true" ]]; then
        if ! check_modules; then
            print_error "Cannot run full setup without all modules"
            print_info "Please create the missing setup modules or use specific flags for available functionality"
            exit 1
        fi
        run_full_setup
    fi
}

main "$@"