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
COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOUNTALLS3_SCRIPT="$COMMON_SCRIPT_DIR/mountalls3.sh"
CONFIG_DIR="$HOME/.config/mountalls3"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
CONFIG_EXAMPLE="$COMMON_SCRIPT_DIR/config-example.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration cache (to avoid re-reading)
declare -A CONFIG_CACHE
CONFIG_CACHE_LOADED=false

# =============================================================================
# OUTPUT FUNCTIONS
# =============================================================================

print_header() { 
    echo -e "\n${BOLD}${PURPLE}=== $1 ===${NC}" 
}

print_success() { 
    echo -e "${GREEN}✅ $1${NC}" 
}

print_warning() { 
    echo -e "${YELLOW}⚠️  $1${NC}" 
}

print_error() { 
    echo -e "${RED}❌ $1${NC}" 
}

print_info() { 
    echo -e "${BLUE}ℹ️  $1${NC}" 
}

print_step() { 
    echo -e "${CYAN}🔧 $1${NC}" 
}

print_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${PURPLE}🐛 DEBUG: $1${NC}" >&2
    fi
}

# =============================================================================
# USER INTERACTION FUNCTIONS
# =============================================================================

prompt_user() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [[ -n "$default" ]]; then
        echo -n -e "${CYAN}$prompt [$default]: ${NC}"
    else
        echo -n -e "${CYAN}$prompt: ${NC}"
    fi
    
    read -r response
    if [[ -z "$response" && -n "$default" ]]; then
        echo "$default"
    else
        echo "$response"
    fi
}

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

# Smart interactive configuration function
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

config_file_exists() {
    [[ -f "$CONFIG_FILE" ]]
}

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

get_config_value() {
    local key="$1"
    local default="${2:-}"
    
    if ! config_file_exists; then
        echo "$default"
        return 1
    fi
    
    # Simple YAML parser for basic key: value pairs
    local value
    case "$key" in
        "defaults.mount_base")
            value=$(grep -E "^\s*mount_base:" "$CONFIG_FILE" | head -1 | sed 's/.*mount_base:\s*["'\'']\?\([^"'\'']*\)["'\'']\?.*/\1/')
            ;;
        "defaults.aws_profile")
            value=$(grep -E "^\s*aws_profile:" "$CONFIG_FILE" | head -1 | sed 's/.*aws_profile:\s*["'\'']\?\([^"'\'']*\)["'\'']\?.*/\1/')
            ;;
        "defaults.mount_groups")
            value=$(grep -E "^\s*mount_groups:" "$CONFIG_FILE" | head -1 | sed 's/.*mount_groups:\s*\(.*\)/\1/')
            ;;
        *)
            # Generic key lookup
            value=$(grep -E "^\s*${key##*.}:" "$CONFIG_FILE" | head -1 | sed 's/.*:\s*["'\'']\?\([^"'\'']*\)["'\'']\?.*/\1/')
            ;;
    esac
    
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

get_config_groups() {
    if ! config_file_exists; then
        return 1
    fi
    
    # Extract group names from config file
    grep -E "^\s*[a-zA-Z0-9_-]+:" "$CONFIG_FILE" | \
        grep -v -E "^\s*(defaults|mount_base|aws_profile|mount_groups|description|buckets|profile|bucket):" | \
        sed 's/^\s*\([^:]*\):.*/\1/' | \
        sort -u
}

get_group_description() {
    local group="$1"
    
    if ! config_file_exists; then
        return 1
    fi
    
    # Find the group and extract its description
    awk "/^\s*${group}:/{flag=1; next} /^\s*[a-zA-Z0-9_-]+:/{flag=0} flag && /description:/{gsub(/.*description:\s*[\"'\'']\?/, \"\"); gsub(/[\"'\'']\s*$/, \"\"); print; exit}" "$CONFIG_FILE"
}

get_group_buckets() {
    local group="$1"
    
    if ! config_file_exists; then
        return 1
    fi
    
    # Extract buckets for a specific group
    awk "
    /^\s*${group}:/{in_group=1; next}
    /^\s*[a-zA-Z0-9_-]+:/ && in_group {in_group=0}
    in_group && /- profile:/ {profile=\$NF; gsub(/[\"'\''\"'\'']/,\"\",profile)}
    in_group && /bucket:/ {bucket=\$NF; gsub(/[\"'\''\"'\'']/,\"\",bucket); print profile\":\"bucket}
    " "$CONFIG_FILE"
}

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

validate_group_name() {
    local group_name="$1"
    
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

expand_path() {
    local path="$1"
    echo "${path/#\~/$HOME}"
}

is_mounted() {
    local mount_point="$1"
    mountpoint -q "$mount_point" 2>/dev/null
}

get_s3fs_mounts() {
    mount | grep "type fuse.s3fs" | awk '{print $3}'
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

fatal_error() {
    print_error "$1"
    print_info "Exiting due to fatal error"
    exit 1
}

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
# INITIALIZATION
# =============================================================================

# Load configuration cache on source
load_config_cache 2>/dev/null || true

print_debug "MountAllS3 common library loaded"
