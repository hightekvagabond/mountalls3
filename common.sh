#!/usr/bin/bash

# =============================================================================
# MountAllS3 Common Functions Library
# =============================================================================
#
# DESCRIPTION:
#   Shared functions and utilities used across all MountAllS3 scripts.
#   Source this file in other scripts to access common functionality.
#
# USAGE:
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#
# FEATURES:
#   - Color output functions
#   - Configuration file handling
#   - AWS profile discovery
#   - User interaction utilities
#   - Validation functions
#   - Error handling
#
# =============================================================================

# Prevent multiple sourcing
if [[ "${MOUNTALLS3_COMMON_LOADED:-}" == "true" ]]; then
    return 0
fi
MOUNTALLS3_COMMON_LOADED=true

# =============================================================================
# GLOBAL VARIABLES AND PATHS
# =============================================================================

# Script directories and paths
COMMON_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MOUNTALLS3_SCRIPT="$COMMON_SCRIPT_DIR/mountalls3.sh"
CONFIG_DIR="$HOME/.config/mountalls3"
CONFIG_FILE="$CONFIG_DIR/config.json"
CONFIG_EXAMPLE="$COMMON_SCRIPT_DIR/config-example.json"

# Initialize global flags
PROMPT_EOF_REACHED=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =============================================================================
# DEBUG SYSTEM
# =============================================================================

# Debug levels: 0=silent, 1=info, 2=verbose, 3=debug
DEBUG_LEVEL=${DEBUG_LEVEL:-0}

# Logs debug messages at specified levels with timestamps and icons
# Level 1=info, 2=verbose, 3=debug - only shows if DEBUG_LEVEL is high enough
debug_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    
    if [[ $DEBUG_LEVEL -ge $level ]]; then
        case $level in
            1) echo "ℹ️  [$timestamp] $message" >&2 ;;
            2) echo "🔍 [$timestamp] $message" >&2 ;;
            3) echo "🐛 [$timestamp] DEBUG: $message" >&2 ;;
            *) echo "   [$timestamp] $message" >&2 ;;
        esac
    fi
}

# Convenience wrapper functions for different debug levels
debug_info() { debug_log 1 "$1"; }
debug_verbose() { debug_log 2 "$1"; }
debug_debug() { debug_log 3 "$1"; }

# Sets the global debug level and exports it for child processes
# Level 0=silent, 1=info, 2=verbose, 3=debug
set_debug_level() {
    local level="$1"
    export DEBUG_LEVEL="$level"
    debug_debug "Debug level set to: $DEBUG_LEVEL"
}

# Parses debug-related flags from arguments and returns remaining args
# Supports -v/--verbose, -d/--debug, --debug-level N
parse_debug_flags() {
    local -n remaining_args=$1
    shift
    
    remaining_args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                set_debug_level 2
                debug_verbose "Verbose mode enabled"
                ;;
            -d|--debug)
                set_debug_level 3
                debug_debug "Debug mode enabled"
                ;;
            --debug-level)
                if [[ -n "$2" && "$2" =~ ^[0-3]$ ]]; then
                    set_debug_level "$2"
                    shift
                else
                    echo "Error: --debug-level requires a number 0-3" >&2
                    return 1
                fi
                ;;
            *)
                remaining_args+=("$1")
                ;;
        esac
        shift
    done
}

# Returns appropriate debug flags for passing to child scripts
# Converts current DEBUG_LEVEL back to command line flags
get_debug_flags() {
    case $DEBUG_LEVEL in
        0) echo "" ;;
        1) echo "--debug-level 1" ;;
        2) echo "--verbose" ;;
        3) echo "--debug" ;;
        *) echo "--debug-level $DEBUG_LEVEL" ;;
    esac
}

# Configuration cache (to avoid re-reading)
declare -A CONFIG_CACHE
CONFIG_CACHE_LOADED=false

# =============================================================================
# OUTPUT FUNCTIONS
# =============================================================================

# Prints a formatted section header with purple color and bold text
print_header() { 
    echo -e "\n${BOLD}${PURPLE}=== $1 ===${NC}" 
}

# Prints a success message with green checkmark
print_success() { 
    echo -e "${GREEN}✅ $1${NC}" 
}

# Prints a warning message with yellow warning icon
print_warning() { 
    echo -e "${YELLOW}⚠️  $1${NC}" 
}

# Prints an error message with red X icon
print_error() { 
    echo -e "${RED}❌ $1${NC}" 
}

# Prints an informational message with blue info icon
print_info() { 
    echo -e "${BLUE}ℹ️  $1${NC}" 
}

# Prints a process step message with cyan wrench icon
print_step() { 
    echo -e "${CYAN}🔧 $1${NC}" 
}

# Prints debug messages if DEBUG environment variable is true
# Note: This is separate from the main debug_log system
print_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${PURPLE}🐛 DEBUG: $1${NC}" >&2
    fi
}

# =============================================================================
# USER INTERACTION FUNCTIONS
# =============================================================================

# Prompts user for input with optional default value
# Handles whitespace trimming and default value substitution
prompt_user() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [[ -n "$default" ]]; then
        echo -n -e "${CYAN}$prompt [$default]: ${NC}" >&2
    else
        echo -n -e "${CYAN}$prompt: ${NC}" >&2
    fi
    
    if ! read -r response; then
        # EOF detected - use default if available, otherwise exit gracefully
        debug_debug "EOF detected in prompt_user"
        if [[ -n "$default" ]]; then
            debug_debug "Using default due to EOF: -----$default-----"
            echo "$default"
            return 0
        else
            debug_debug "EOF with no default - returning empty and setting EOF flag"
            # Set a global flag to indicate EOF was reached
            PROMPT_EOF_REACHED=true
            echo ""
            return 1
        fi
    fi
    debug_debug "Raw response before trimming: -----$response-----"
    
    # Trim leading and trailing whitespace
    response="${response#"${response%%[![:space:]]*}"}"
    response="${response%"${response##*[![:space:]]}"}"
    
    debug_debug "Response after trimming: -----$response-----"
    debug_debug "Default value: -----$default-----"
    debug_debug "Is response empty? $([[ -z "$response" ]] && echo "YES" || echo "NO")"
    debug_debug "Is default non-empty? $([[ -n "$default" ]] && echo "YES" || echo "NO")"
    
    if [[ -z "$response" && -n "$default" ]]; then
        debug_debug "Using default value"
        echo "$default"
    else
        debug_debug "Using user response"
        echo "$response"
    fi
}

# Prompts user for yes/no input with validation and optional default
# Returns 0 for yes, 1 for no, keeps asking until valid response
prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            response=$(prompt_user "$prompt (y/n)" "y")
        elif [[ "$default" == "n" ]]; then
            response=$(prompt_user "$prompt (y/n)" "n")
        else
            response=$(prompt_user "$prompt (y/n)" "")
        fi
        
        case "${response,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) print_warning "Please answer y or n" ;;
        esac
    done
}

# Smart interactive configuration function with multiple input types
# Supports free text, yes/no, and multiple choice with validation
# Usage: configure_value VAR_NAME "Help text" "Question" "default_value" ["option1,option2,option3"]
configure_value() {
    local var_name="$1"
    local help_text="$2"
    local question="$3"
    local default_value="$4"
    local valid_options="$5"
    
    # Get current value using variable indirection
    local current_value="${!var_name}"
    
    # If value is already set (from flags), skip interactive prompt
    if [[ -n "$current_value" ]]; then
        print_info "$var_name already set to: $current_value"
        return 0
    fi
    
    # Show help text if provided
    if [[ -n "$help_text" ]]; then
        echo "$help_text"
        echo ""
    fi
    
    # Handle different input types
    if [[ -n "$valid_options" ]]; then
        # Multiple choice or validation list
        case "$valid_options" in
            "y,n"|"yes,no")
                # Yes/No question
                if prompt_yes_no "$question" "${default_value:-n}"; then
                    declare -g "$var_name"="y"
                else
                    declare -g "$var_name"="n"
                fi
                ;;
            *,*)
                # Multiple choice list
                echo "Valid options: $valid_options"
                while true; do
                    local response
                    response=$(prompt_user "$question" "$default_value")
                    
                    # Check if response is in valid options
                    if [[ ",$valid_options," == *",$response,"* ]] || [[ -z "$response" && -n "$default_value" ]]; then
                        declare -g "$var_name"="${response:-$default_value}"
                        break
                    else
                        print_warning "Please choose from: $valid_options"
                    fi
                done
                ;;
            *)
                # Single validation pattern (future use)
                local response
                response=$(prompt_user "$question" "$default_value")
                declare -g "$var_name"="$response"
                ;;
        esac
    else
        # Free text input
        local response
        response=$(prompt_user "$question" "$default_value")
        declare -g "$var_name"="$response"
    fi
    
    print_debug "Set $var_name to: ${!var_name}"
}

# Presents numbered menu choices and returns selected option
# Validates input and keeps prompting until valid choice is made
prompt_choice() {
    local prompt="$1"
    local -a choices=("${@:2}")
    local i
    
    echo "$prompt"
    for i in "${!choices[@]}"; do
        echo "  $((i+1)). ${choices[i]}"
    done
    echo ""
    
    while true; do
        local choice
        choice=$(prompt_user "Your choice (1-${#choices[@]})" "1")
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#choices[@]} ]]; then
            echo "${choices[$((choice-1))]}"
            return 0
        else
            print_warning "Invalid choice. Please enter a number between 1 and ${#choices[@]}"
        fi
    done
}

# =============================================================================
# CONFIGURATION FILE FUNCTIONS
# =============================================================================

# Checks if the main configuration file exists
config_file_exists() {
    [[ -f "$CONFIG_FILE" ]]
}

# Updates a specific configuration value in the JSON config file
# Uses jq to safely update nested JSON values with proper type handling
update_config_value() {
    local key="$1"
    local value="$2"
    
    ensure_config_dir || return 1
    
    # Config file should exist by now
    if ! config_file_exists; then
        print_error "Config file does not exist. Please run setup first."
        return 1
    fi
    
    # Create a temp file for the updated config
    local temp_file
    temp_file=$(mktemp)
    
    # Use jq to update the value, handling different value types
    case "$key" in
        "defaults.mount_base"|"defaults.aws_profile")
            # String values
            jq --arg key "$key" --arg value "$value" \
               'setpath($key | split("."); $value)' \
               "$CONFIG_FILE" > "$temp_file"
            ;;
        "defaults.mount_groups")
            # Array values (already JSON formatted)
            if [[ "$value" =~ ^\[.*\]$ ]]; then
                # Value is already a JSON array
                jq --arg key "$key" --argjson value "$value" \
                   'setpath($key | split("."); $value)' \
                   "$CONFIG_FILE" > "$temp_file"
            else
                # Treat as string and wrap in array
                jq --arg key "$key" --arg value "$value" \
                   'setpath($key | split("."); [$value])' \
                   "$CONFIG_FILE" > "$temp_file"
            fi
            ;;
        *)
            # Generic path update for any nested key
            jq --arg key "$key" --arg value "$value" \
               'setpath($key | split("."); $value)' \
               "$CONFIG_FILE" > "$temp_file"
            ;;
    esac
    
    # Check if jq succeeded
    if [[ $? -eq 0 ]] && [[ -s "$temp_file" ]]; then
        mv "$temp_file" "$CONFIG_FILE" || {
            print_error "Failed to update configuration file"
            rm -f "$temp_file"
            return 1
        }
        
        debug_debug "Updated config key '$key' to value: $value"
        
        # Reload cache
        CONFIG_CACHE_LOADED=false
        load_config_cache
        
        return 0
    else
        print_error "Failed to update configuration key: $key"
        rm -f "$temp_file"
        return 1
    fi
}

# Creates the configuration directory if it doesn't exist
# Returns error if directory creation fails
ensure_config_dir() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        print_debug "Creating config directory: $CONFIG_DIR"
        mkdir -p "$CONFIG_DIR" || {
            print_error "Failed to create config directory: $CONFIG_DIR"
            return 1
        }
    fi
    return 0
}

# Creates a timestamped backup of the current configuration file
# Only backs up if config file exists
backup_config() {
    if config_file_exists; then
        local backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        print_debug "Backing up config to: $backup_file"
        cp "$CONFIG_FILE" "$backup_file" || {
            print_error "Failed to backup config file"
            return 1
        }
        print_info "Config backed up to: $backup_file"
    fi
    return 0
}

# Loads frequently-used config values into memory cache for performance
# Prevents repeated file reads during script execution
load_config_cache() {
    if [[ "$CONFIG_CACHE_LOADED" == "true" ]]; then
        return 0
    fi
    
    if ! config_file_exists; then
        print_debug "No config file found, cache remains empty"
        return 1
    fi
    
    print_debug "Loading configuration cache from: $CONFIG_FILE"
    
    # Parse basic configuration values
    CONFIG_CACHE["mount_base"]=$(get_config_value "defaults.mount_base")
    CONFIG_CACHE["aws_profile"]=$(get_config_value "defaults.aws_profile")
    CONFIG_CACHE["mount_groups"]=$(get_config_value "defaults.mount_groups" | tr -d '[]"' | tr ',' ' ')
    
    CONFIG_CACHE_LOADED=true
    return 0
}

# Extracts a specific value from the JSON configuration using jq
# Returns default value if key doesn't exist or file is missing
get_config_value() {
    local key="$1"
    local default="${2:-}"
    
    if ! config_file_exists; then
        echo "$default"
        return 1
    fi
    
    # Use jq to extract the value
    local value
    value=$(jq -r ".$key // empty" "$CONFIG_FILE" 2>/dev/null)
    
    if [[ -n "$value" && "$value" != "null" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Returns list of all group names defined in configuration
# Uses jq to extract group keys from JSON structure
get_config_groups() {
    if ! config_file_exists; then
        return 1
    fi
    
    # Extract group names using jq
    jq -r '.groups | keys[]' "$CONFIG_FILE" 2>/dev/null
}

# Returns the description text for a specific group
# Uses jq to extract group description from JSON configuration
get_group_description() {
    local group="$1"
    
    if ! config_file_exists; then
        return 1
    fi
    
    # Extract group description using jq
    jq -r ".groups[\"$group\"].description // empty" "$CONFIG_FILE" 2>/dev/null
}

# Returns list of buckets in a group formatted as 'profile:bucket'
# Combines static buckets with pattern-matched buckets from AWS
get_group_buckets() {
    local group="$1"
    
    if ! config_file_exists; then
        return 1
    fi
    
    local all_buckets=()
    
    # First, get static buckets from config
    local static_buckets
    mapfile -t static_buckets < <(jq -r ".groups[\"$group\"].buckets[]? | \"\(.profile):\(.bucket)\"" "$CONFIG_FILE" 2>/dev/null)
    all_buckets+=("${static_buckets[@]}")
    
    # Then, resolve pattern-based buckets
    local patterns
    mapfile -t patterns < <(jq -r ".groups[\"$group\"].patterns[]? | \"\(.profile):\(.pattern)\"" "$CONFIG_FILE" 2>/dev/null)
    
    for pattern_entry in "${patterns[@]}"; do
        if [[ -z "$pattern_entry" ]]; then
            continue
        fi
        
        IFS=':' read -r pattern_profile pattern_text <<< "$pattern_entry"
        
        # Get available profiles to check
        local profiles_to_check=()
        if [[ "$pattern_profile" == "*" ]]; then
            # Wildcard - check all profiles
            mapfile -t profiles_to_check < <(get_aws_profiles 2>/dev/null)
        else
            # Specific profile
            profiles_to_check=("$pattern_profile")
        fi
        
        # Check each profile for matching buckets
        for profile in "${profiles_to_check[@]}"; do
            if [[ -z "$profile" ]]; then
                continue
            fi
            
            # Get buckets for this profile and filter by pattern
            local profile_buckets
            mapfile -t profile_buckets < <(get_buckets_for_profile "$profile" 2>/dev/null)
            
            for bucket in "${profile_buckets[@]}"; do
                local bucket_matches=false
                
                if [[ -n "$bucket" ]]; then
                    if [[ "$pattern_text" == "*" ]]; then
                        # Wildcard matches all buckets
                        bucket_matches=true
                        debug_debug "Wildcard pattern '*' matched bucket: $bucket (profile: $profile)"
                    elif [[ "$bucket" == *"$pattern_text"* ]]; then
                        # Regular pattern matching
                        bucket_matches=true
                        debug_debug "Pattern '$pattern_text' matched bucket: $bucket (profile: $profile)"
                    fi
                fi
                
                if [[ "$bucket_matches" == true ]]; then
                    # Check if this bucket is already in our list (avoid duplicates)
                    local bucket_entry="$profile:$bucket"
                    local already_exists=false
                    
                    for existing in "${all_buckets[@]}"; do
                        if [[ "$existing" == "$bucket_entry" ]]; then
                            already_exists=true
                            break
                        fi
                    done
                    
                    if [[ "$already_exists" == false ]]; then
                        all_buckets+=("$bucket_entry")
                    fi
                fi
            done
        done
    done
    
    # Output all buckets (static + pattern-matched)
    for bucket_entry in "${all_buckets[@]}"; do
        echo "$bucket_entry"
    done
}

# Main configuration parser that extracts default values
# Sets global variables for mount_groups, mount_base, and aws_profile
parse_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "No config file found at $CONFIG_FILE"
        echo "Creating example config directory..."
        mkdir -p "$CONFIG_DIR"
        if [[ -f "$(dirname "${BASH_SOURCE[0]}")/config-example.json" ]]; then
            cp "$(dirname "${BASH_SOURCE[0]}")/config-example.json" "$CONFIG_DIR/"
            echo "Example config copied to $CONFIG_DIR/config-example.json"
            echo "Please copy and customize it to $CONFIG_FILE"
        fi
        return 1
    fi
    
    # Read default mount groups from config
    default_groups=$(jq -r '.defaults.mount_groups[]?' "$CONFIG_FILE" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    
    # Read default mount base from config  
    config_mount_base=$(jq -r '.defaults.mount_base // empty' "$CONFIG_FILE" 2>/dev/null)
    
    # Read default AWS profile from config
    config_aws_profile=$(jq -r '.defaults.aws_profile // empty' "$CONFIG_FILE" 2>/dev/null)
    
    return 0
}

# Displays formatted list of all bucket groups with descriptions and counts
# Shows first few buckets as examples for each group
list_groups() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "No configuration file found at $CONFIG_FILE"
        echo "Run 'mountalls3 --setup' to create one."
        return 1
    fi
    
    echo "Available bucket groups:"
    echo ""
    
    # Extract group names and descriptions using jq
    local groups
    mapfile -t groups < <(jq -r '.groups | keys[]' "$CONFIG_FILE" 2>/dev/null)
    
    if [[ ${#groups[@]} -eq 0 ]]; then
        echo "  No groups configured"
        return 0
    fi
    
    for group in "${groups[@]}"; do
        local description
        description=$(jq -r ".groups[\"$group\"].description // \"No description\"" "$CONFIG_FILE" 2>/dev/null)
        local bucket_count
        bucket_count=$(jq -r ".groups[\"$group\"].buckets | length" "$CONFIG_FILE" 2>/dev/null)
        local pattern_count
        pattern_count=$(jq -r ".groups[\"$group\"].patterns | length" "$CONFIG_FILE" 2>/dev/null)
        
        echo "  🗂️  $group - $description"
        echo "     📦 $bucket_count static bucket(s), 🔍 $pattern_count pattern rule(s)"
        
        # Show first few static buckets as examples
        local buckets
        mapfile -t buckets < <(jq -r ".groups[\"$group\"].buckets[0:3][]? | \"\(.profile):\(.bucket)\"" "$CONFIG_FILE" 2>/dev/null)
        
        for bucket in "${buckets[@]}"; do
            echo "       • $bucket"
        done
        
        if [[ $bucket_count -gt 3 ]]; then
            echo "       ... and $((bucket_count - 3)) more static buckets"
        fi
        
        # Show pattern rules
        if [[ $pattern_count -gt 0 ]]; then
            local patterns
            mapfile -t patterns < <(jq -r ".groups[\"$group\"].patterns[]? | \"\(.profile):\(.pattern) (\(.description))\"" "$CONFIG_FILE" 2>/dev/null)
            
            for pattern in "${patterns[@]}"; do
                echo "       🔍 $pattern"
            done
        fi
        
        echo ""
    done
}

# Validates configuration file structure and required fields
# Checks for JSON syntax and required sections
validate_config_file() {
    if ! config_file_exists; then
        print_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    local errors=0
    
    # Check basic structure
    if ! grep -q "^defaults:" "$CONFIG_FILE"; then
        print_error "Config missing 'defaults' section"
        ((errors++))
    fi
    
    if ! grep -q "^groups:" "$CONFIG_FILE"; then
        print_error "Config missing 'groups' section"
        ((errors++))
    fi
    
    # Check required defaults
    local mount_base
    mount_base=$(get_config_value "defaults.mount_base")
    if [[ -z "$mount_base" ]]; then
        print_error "Config missing defaults.mount_base"
        ((errors++))
    fi
    
    # Validate YAML syntax if yq is available
    if command -v yq >/dev/null 2>&1; then
        if ! yq eval . "$CONFIG_FILE" >/dev/null 2>&1; then
            print_error "Config file has invalid YAML syntax"
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        print_success "Configuration file is valid"
        return 0
    else
        print_error "Configuration file has $errors error(s)"
        return 1
    fi
}

# =============================================================================
# AWS FUNCTIONS
# =============================================================================

# Discovers all available AWS profiles using AWS CLI
# Returns sorted, deduplicated list including 'default' profile
get_aws_profiles() {
    local profiles=()
    
    print_debug "Discovering AWS profiles"
    
    # Check AWS CLI profiles
    if command -v aws >/dev/null 2>&1; then
        while IFS= read -r profile; do
            if [[ -n "$profile" && "$profile" != "default" ]]; then
                profiles+=("$profile")
            fi
        done < <(aws configure list-profiles 2>/dev/null | grep -v '^$')
    else
        print_warning "AWS CLI not found. Cannot discover profiles automatically."
    fi
    
    # Always include default
    profiles=("default" "${profiles[@]}")
    
    # Remove duplicates and sort
    printf '%s\n' "${profiles[@]}" | sort -u
}

# Lists all S3 buckets accessible to a specific AWS profile
# Uses AWS CLI s3 ls command and extracts bucket names
get_buckets_for_profile() {
    local profile="$1"
    local buckets=()
    
    print_debug "Getting buckets for profile: $profile"
    
    if ! command -v aws >/dev/null 2>&1; then
        print_error "AWS CLI not found"
        return 1
    fi
    
    if [[ "$profile" == "default" ]]; then
        mapfile -t buckets < <(aws s3 ls 2>/dev/null | awk '{print $3}' | sort)
    else
        mapfile -t buckets < <(aws s3 ls --profile "$profile" 2>/dev/null | awk '{print $3}' | sort)
    fi
    
    if [[ ${#buckets[@]} -eq 0 ]]; then
        print_warning "No accessible buckets found for profile '$profile'"
        return 1
    fi
    
    printf '%s\n' "${buckets[@]}"
}

# Validates that an AWS profile has working credentials
# Uses STS get-caller-identity to test profile access
validate_aws_profile() {
    local profile="$1"
    
    if [[ "$profile" == "default" ]]; then
        aws sts get-caller-identity >/dev/null 2>&1
    else
        aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1
    fi
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validates directory path exists and is writable
# Optionally creates directory if missing and create_if_missing=true
validate_directory_path() {
    local path="$1"
    local create_if_missing="${2:-false}"
    
    # Expand tilde
    path="${path/#\~/$HOME}"
    
    if [[ -d "$path" ]]; then
        if [[ -w "$path" ]]; then
            return 0
        else
            print_error "Directory not writable: $path"
            return 1
        fi
    elif [[ "$create_if_missing" == "true" ]]; then
        if mkdir -p "$path" 2>/dev/null; then
            print_success "Created directory: $path"
            return 0
        else
            print_error "Cannot create directory: $path"
            return 1
        fi
    else
        print_error "Directory does not exist: $path"
        return 1
    fi
}

# Validates group name format and length restrictions
# Allows only letters, numbers, underscores, and dashes, max 50 chars
validate_group_name() {
    local group_name="$1"
    
    # Debug: Show exactly what we received (with boundaries)
    debug_debug "validate_group_name received:"
    debug_debug "-----$1-----"
    
    if [[ -z "$group_name" ]]; then
        print_error "Group name cannot be empty"
        return 1
    fi
    
    if [[ ! "$group_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Group name can only contain letters, numbers, underscores, and dashes"
        return 1
    fi
    
    if [[ ${#group_name} -gt 50 ]]; then
        print_error "Group name too long (max 50 characters)"
        return 1
    fi
    
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Verifies that jq JSON processor is installed and available
# Required for parsing JSON configuration files
check_jq() {
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed."
        print_error "Please install jq:"
        print_error "  Ubuntu/Debian: sudo apt install jq"
        print_error "  RHEL/CentOS:   sudo yum install jq"
        print_error "  macOS:         brew install jq"
        return 1
    fi
    return 0
}

# Returns default mount base directory from example config or fallback
# Tries to read from config-example.json, defaults to ~/s3
get_default_mount_base() {
    # Try to get default from example config
    local example_default="~/s3"
    
    if [[ -f "$CONFIG_EXAMPLE" ]]; then
        local config_default
        config_default=$(grep -E "^\s*mount_base:" "$CONFIG_EXAMPLE" | head -1 | sed 's/.*mount_base:\s*["'\'']\?\([^"'\'']*\)["'\'']\?.*/\1/')
        if [[ -n "$config_default" ]]; then
            example_default="$config_default"
        fi
    fi
    
    echo "$example_default"
}

# Expands tilde (~) in path to user's home directory
expand_path() {
    local path="$1"
    echo "${path/#\~/$HOME}"
}

# Checks if a directory is currently a mount point
# Uses mountpoint command for reliable detection
is_mounted() {
    local mount_point="$1"
    mountpoint -q "$mount_point" 2>/dev/null
}

# Returns list of all currently mounted s3fs filesystems
# Parses mount output to find fuse.s3fs mount points
get_s3fs_mounts() {
    mount | grep "type fuse.s3fs" | awk '{print $3}'
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Prints error message and exits script with error code
# Used for unrecoverable errors that should stop execution
fatal_error() {
    print_error "$1"
    print_info "Exiting due to fatal error"
    exit 1
}

# Checks if required command exists and shows install hint if missing
# Returns error if command not found
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        print_error "Required command not found: $cmd"
        if [[ -n "$install_hint" ]]; then
            print_info "$install_hint"
        fi
        return 1
    fi
    return 0
}

# =============================================================================
# COMMON FLAG PARSING SYSTEM
# =============================================================================

# Flag definition structure:
# FLAG_DEFINITIONS["flag_name"]="function_name|param_type|default_value|help_text|prompt_text|prompt_help"
# 
# param_type: "none", "required", "optional", "choice:option1,option2,option3", "yesno"
# function_name: function to call when flag is encountered
# default_value: default value for the parameter
# help_text: text shown in --help output
# prompt_text: question asked in interactive mode
# prompt_help: explanatory text shown before prompt

declare -A FLAG_DEFINITIONS
declare -A FLAG_VALUES
declare -A FLAG_ORDER

# Registers a command line flag with its behavior and help information
# Part of the data-driven flag parsing system
register_flag() {
    local flag="$1"
    local function_name="$2"
    local param_type="$3"
    local default_value="$4"
    local help_text="$5"
    local prompt_text="$6"
    local prompt_help="$7"
    
    FLAG_DEFINITIONS["$flag"]="${function_name}|${param_type}|${default_value}|${help_text}|${prompt_text}|${prompt_help}"
    
    # Track order of registration for help display
    local order=${#FLAG_ORDER[@]}
    FLAG_ORDER["$flag"]=$order
}

# Parses command line arguments using registered flag definitions
# Handles help, validates parameters, and populates FLAG_VALUES array
parse_flags() {
    local script_name="$1"
    shift
    
    # Parse debug flags first and update remaining args
    local processed_args
    parse_debug_flags processed_args "$@"
    set -- "${processed_args[@]}"
    
    debug_debug "Parsing flags for $script_name with args: $*"
    
    # Handle help first
    for arg in "$@"; do
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            show_dynamic_help "$script_name"
            exit 0
        fi
    done
    
    # Parse other flags
    while [[ $# -gt 0 ]]; do
        local flag="$1"
        local flag_clean="${flag#--}"  # Remove -- prefix
        
        if [[ -n "${FLAG_DEFINITIONS[$flag_clean]:-}" ]]; then
            IFS='|' read -r function_name param_type default_value help_text prompt_text prompt_help <<< "${FLAG_DEFINITIONS[$flag_clean]}"
            
            case "$param_type" in
                "none")
                    FLAG_VALUES["$flag_clean"]="true"
                    shift
                    ;;
                "required")
                    if [[ $# -lt 2 || "$2" == --* ]]; then
                        print_error "Flag $flag requires a parameter"
                        exit 1
                    fi
                    FLAG_VALUES["$flag_clean"]="$2"
                    shift 2
                    ;;
                "optional")
                    if [[ $# -gt 1 && "$2" != --* ]]; then
                        FLAG_VALUES["$flag_clean"]="$2"
                        shift 2
                    else
                        FLAG_VALUES["$flag_clean"]="$default_value"
                        shift
                    fi
                    ;;
                "yesno")
                    if [[ $# -gt 1 && "$2" =~ ^[yn]$ ]]; then
                        FLAG_VALUES["$flag_clean"]="$2"
                        shift 2
                    else
                        FLAG_VALUES["$flag_clean"]="$default_value"
                        shift
                    fi
                    ;;
                choice:*)
                    local choices="${param_type#choice:}"
                    if [[ $# -gt 1 && "$2" != --* ]]; then
                        if [[ ",$choices," == *",$2,"* ]]; then
                            FLAG_VALUES["$flag_clean"]="$2"
                            shift 2
                        else
                            print_error "Flag $flag must be one of: $choices"
                            exit 1
                        fi
                    else
                        FLAG_VALUES["$flag_clean"]="$default_value"
                        shift
                    fi
                    ;;
            esac
        elif [[ "$flag" == "" ]]; then
            # No arguments - run interactive mode
            FLAG_VALUES["interactive"]="true"
            break
        else
            print_error "Unknown flag: $flag"
            show_dynamic_help "$script_name"
            exit 1
        fi
    done
    
    # If no flags provided, default to interactive
    if [[ ${#FLAG_VALUES[@]} -eq 0 ]]; then
        FLAG_VALUES["interactive"]="true"
    fi
}

# Executes functions associated with parsed flags in registration order
# Calls flag functions with appropriate parameters
execute_flags() {
    # Sort flags by registration order for consistent execution
    local -a sorted_flags=()
    for flag in "${!FLAG_ORDER[@]}"; do
        sorted_flags[${FLAG_ORDER[$flag]}]="$flag"
    done
    
    # Execute flag functions
    for flag in "${sorted_flags[@]}"; do
        if [[ -n "${FLAG_VALUES[$flag]:-}" && "$flag" != "interactive" ]]; then
            IFS='|' read -r function_name param_type default_value help_text prompt_text prompt_help <<< "${FLAG_DEFINITIONS[$flag]}"
            
            if [[ "$param_type" == "none" ]]; then
                "$function_name"
            else
                "$function_name" "${FLAG_VALUES[$flag]}"
            fi
        fi
    done
    
    # Run interactive mode if specified
    if [[ "${FLAG_VALUES[interactive]:-}" == "true" ]]; then
        if declare -f interactive_setup >/dev/null; then
            interactive_setup
        else
            print_error "Interactive mode not implemented"
            exit 1
        fi
    fi
}

# Generates help text dynamically from registered flag definitions
# Shows usage, options, and defaults in consistent format
show_dynamic_help() {
    local script_name="$1"
    local script_description="${SCRIPT_DESCRIPTION:-}"
    
    echo "${script_name^} - ${script_description}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    
    # Group flags by category if available
    local -A categories
    local -a sorted_flags=()
    
    # Sort flags by registration order
    for flag in "${!FLAG_ORDER[@]}"; do
        sorted_flags[${FLAG_ORDER[$flag]}]="$flag"
    done
    
    echo "OPTIONS:"
    for flag in "${sorted_flags[@]}"; do
        if [[ -n "${FLAG_DEFINITIONS[$flag]:-}" ]]; then
            IFS='|' read -r function_name param_type default_value help_text prompt_text prompt_help <<< "${FLAG_DEFINITIONS[$flag]}"
            
            local flag_display="--$flag"
            case "$param_type" in
                "required") flag_display="--$flag VALUE" ;;
                "optional") flag_display="--$flag [VALUE]" ;;
                "yesno") flag_display="--$flag [y/n]" ;;
                choice:*) 
                    local choices="${param_type#choice:}"
                    flag_display="--$flag [$choices]"
                    ;;
            esac
            
            printf "  %-25s %s\n" "$flag_display" "$help_text"
            if [[ -n "$default_value" && "$default_value" != "true" ]]; then
                printf "  %-25s %s\n" "" "(default: $default_value)"
            fi
        fi
    done
    
    echo ""
    echo "  -h, --help               Show this help message"
    echo ""
    echo "If no options are provided, interactive mode will start."
}

# Runs interactive prompts for flags that weren't set via command line
# Uses configure_value to handle different input types
run_interactive_prompts() {
    local -a sorted_flags=()
    
    # Sort flags by registration order
    for flag in "${!FLAG_ORDER[@]}"; do
        sorted_flags[${FLAG_ORDER[$flag]}]="$flag"
    done
    
    for flag in "${sorted_flags[@]}"; do
        if [[ -n "${FLAG_DEFINITIONS[$flag]:-}" && -z "${FLAG_VALUES[$flag]:-}" ]]; then
            IFS='|' read -r function_name param_type default_value help_text prompt_text prompt_help <<< "${FLAG_DEFINITIONS[$flag]}"
            
            if [[ "$param_type" != "none" && -n "$prompt_text" ]]; then
                local var_name="flag_${flag//-/_}"
                
                case "$param_type" in
                    "yesno")
                        configure_value "$var_name" "$prompt_help" "$prompt_text" "$default_value" "y,n"
                        ;;
                    choice:*)
                        local choices="${param_type#choice:}"
                        configure_value "$var_name" "$prompt_help" "$prompt_text" "$default_value" "$choices"
                        ;;
                    *)
                        configure_value "$var_name" "$prompt_help" "$prompt_text" "$default_value"
                        ;;
                esac
                
                FLAG_VALUES["$flag"]="${!var_name}"
            fi
        fi
    done
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Load configuration cache on source
load_config_cache 2>/dev/null || true

print_debug "MountAllS3 common library loaded"
