#!/usr/bin/bash

# =============================================================================
# MountAllS3 System Integration Setup
# =============================================================================

# Load common functions
COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$COMMON_SCRIPT_DIR/common.sh" || {
    echo "❌ Error: Could not load common.sh library"
    exit 1
}

# Autostart configuration
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/mountalls3.desktop"

# Configures desktop environment autostart for MountAllS3
# Creates .desktop file in ~/.config/autostart/ for automatic mounting on login
configure_autostart() {
    local enable_autostart="$1"
    
    print_header "Desktop Autostart Configuration"
    
    # Use smart configuration if not specified
    if [[ -z "$enable_autostart" ]]; then
        configure_value "enable_autostart" \
            "Desktop autostart will automatically mount your S3 buckets when you log in to your desktop environment (GNOME, KDE, XFCE, etc.)." \
            "Enable desktop autostart for MountAllS3?" \
            "y" \
            "y,n"
    else
        local enable_autostart="$enable_autostart"
    fi
    
    if [[ "$enable_autostart" == "y" ]]; then
        create_autostart_entry
    else
        remove_autostart_entry
    fi
}

# Creates desktop autostart entry file for MountAllS3
# Generates .desktop file that works with GNOME, KDE, XFCE, etc.
create_autostart_entry() {
    # Create autostart directory if it doesn't exist
    mkdir -p "$AUTOSTART_DIR" || {
        print_error "Failed to create autostart directory: $AUTOSTART_DIR"
        return 1
    }
    
    # Find the mountalls3 script location
    local mountalls3_path=""
    if [[ -f "$COMMON_SCRIPT_DIR/mountalls3.sh" ]]; then
        mountalls3_path="$COMMON_SCRIPT_DIR/mountalls3.sh"
    elif command -v mountalls3 >/dev/null 2>&1; then
        mountalls3_path="$(command -v mountalls3)"
    else
        print_error "Cannot find mountalls3 script for autostart"
        return 1
    fi
    
    # Create desktop entry
    cat > "$AUTOSTART_FILE" << EOF
[Desktop Entry]
Type=Application
Name=MountAllS3
Comment=Automatically mount S3 buckets on login
Exec=$mountalls3_path
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
EOF
    
    print_success "Created desktop autostart entry: $AUTOSTART_FILE"
    print_info "MountAllS3 will now start automatically when you log in"
}

# Removes existing desktop autostart entry if it exists
# Cleans up autostart configuration when disabled
remove_autostart_entry() {
    if [[ -f "$AUTOSTART_FILE" ]]; then
        rm -f "$AUTOSTART_FILE"
        print_success "Removed desktop autostart entry"
    else
        print_info "No autostart entry found to remove"
    fi
}

# Configures command symlink for easy terminal access
# Creates a symlink to mountalls3 in user's bin directory
configure_symlinks() {
    local bin_dir="$1"
    
    print_header "Command Symlink Configuration"
    
    # Get user's preferred bin directory
    if [[ -z "$bin_dir" ]]; then
        echo "Available personal bin directories:"
        local available_dirs=()
        
        if [[ -d "$HOME/bin" ]]; then
            available_dirs+=("$HOME/bin")
            echo "  • $HOME/bin (exists)"
        else
            echo "  • $HOME/bin (can be created)"
        fi
        
        if [[ -d "$HOME/.local/bin" ]]; then
            available_dirs+=("$HOME/.local/bin")
            echo "  • $HOME/.local/bin (exists)"
        else
            echo "  • $HOME/.local/bin (can be created)"
        fi
        
        echo ""
        
        local default_bin="$HOME/.local/bin"
        if [[ -d "$HOME/bin" ]]; then
            default_bin="$HOME/bin"
        fi
        
        echo "A symlink allows you to run 'mountalls3' from anywhere in your terminal."
        echo ""
        bin_dir=$(prompt_user "Which directory should I use for the symlink?" "$default_bin")
    fi
    
    # Ensure bin_dir is set
    if [[ -z "$bin_dir" ]]; then
        print_error "Failed to determine bin directory. bin_dir='$bin_dir'"
        return 1
    fi
    
    debug_debug "Using bin directory: $bin_dir"
    create_symlinks "$bin_dir"
}

# Creates symlink for mountalls3 command
# Handles directory creation and PATH updates as needed
create_symlinks() {
    local target_dir="$1"
    
    # Create directory if it doesn't exist
    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir" || {
            print_error "Failed to create directory: $target_dir"
            return 1
        }
        print_success "Created directory: $target_dir"
    fi
    
    # Check if directory is in PATH
    if [[ ":$PATH:" != *":$target_dir:"* ]]; then
        print_warning "Directory $target_dir is not in your PATH"
        
        local add_to_path=""
        configure_value "add_to_path" \
            "I can add this directory to your PATH by updating your ~/.bashrc file." \
            "Add $target_dir to your PATH?" \
            "y" \
            "y,n"
        
        if [[ "$add_to_path" == "y" ]]; then
            add_to_bashrc_path "$target_dir"
        fi
    fi
    
    # Create symlink for main script only
    # (setup script can be accessed via: mountalls3 --setup)
    local mountalls3_script="$COMMON_SCRIPT_DIR/mountalls3.sh"
    
    if [[ -f "$mountalls3_script" ]]; then
        ln -sf "$mountalls3_script" "$target_dir/mountalls3" || {
            print_error "Failed to create symlink for mountalls3"
            return 1
        }
        print_success "Created symlink: $target_dir/mountalls3 -> $mountalls3_script"
        print_info "💡 Access setup via: mountalls3 --setup"
    else
        print_error "Main script not found: $mountalls3_script"
        return 1
    fi
    
    print_info "You can now run 'mountalls3' from anywhere"
}

# Adds specified directory to PATH in ~/.bashrc
# Checks for existing entries to avoid duplicates
add_to_bashrc_path() {
    local dir="$1"
    local bashrc="$HOME/.bashrc"
    
    # Check if already in bashrc
    if grep -q "export PATH.*$dir" "$bashrc" 2>/dev/null; then
        print_info "Directory already in ~/.bashrc PATH"
        return 0
    fi
    
    # Add to bashrc
    echo "" >> "$bashrc"
    echo "# Added by MountAllS3 setup" >> "$bashrc"
    echo "export PATH=\"$dir:\$PATH\"" >> "$bashrc"
    
    print_success "Added $dir to ~/.bashrc PATH"
    print_info "Restart your terminal or run: source ~/.bashrc"
}

# Configures system-level performance optimizations (requires root)
# Checks for sudo privileges and prompts for optimization settings
configure_system_optimizations() {
    print_header "System Performance Optimizations"
    
    if [[ $EUID -ne 0 ]]; then
        print_warning "System optimizations require root privileges"
        print_info "Run with sudo for system-level optimizations:"
        print_info "  sudo $0 --system"
        return 1
    fi
    
    local enable_optimizations=""
    configure_value "enable_optimizations" \
        "System optimizations improve s3fs performance by excluding mount directories from system scans (updatedb/locate) and optimizing kernel parameters." \
        "Enable system performance optimizations?" \
        "y" \
        "y,n"
    
    if [[ "$enable_optimizations" == "y" ]]; then
        apply_system_optimizations
    else
        print_info "Skipped system optimizations"
    fi
}

# Applies system-level optimizations for s3fs performance
# Updates /etc/updatedb.conf to exclude s3fs from locate database
apply_system_optimizations() {
    print_step "Applying system optimizations..."
    
    # Update /etc/updatedb.conf to exclude s3fs mounts
    local updatedb_conf="/etc/updatedb.conf"
    if [[ -f "$updatedb_conf" ]]; then
        if ! grep -q "fuse.s3fs" "$updatedb_conf"; then
            # Backup original
            cp "$updatedb_conf" "$updatedb_conf.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Add fuse.s3fs to PRUNEFS
            sed -i 's/PRUNEFS="[^"]*/& fuse.s3fs/' "$updatedb_conf"
            print_success "Updated $updatedb_conf to exclude s3fs mounts from indexing"
        else
            print_info "s3fs already excluded from updatedb"
        fi
    else
        print_warning "updatedb.conf not found, skipping updatedb optimization"
    fi
    
    print_success "System optimizations applied"
}

# Main interactive setup function for system integration
# Orchestrates autostart, symlinks, and system optimization setup
interactive_setup() {
    print_header "System Integration Interactive Setup"
    
    echo "This will configure system-level integrations for MountAllS3."
    echo ""
    
    # Step 1: Autostart
    if prompt_yes_no "Configure desktop autostart?" "y"; then
        configure_autostart
    fi
    
    echo ""
    
    # Step 2: Symlink
    if prompt_yes_no "Create command symlink for easy access?" "y"; then
        configure_symlinks
    fi
    
    echo ""
    
    # Step 3: System optimizations (if running as root)
    if [[ $EUID -eq 0 ]]; then
        if prompt_yes_no "Apply system performance optimizations?" "y"; then
            configure_system_optimizations
        fi
    else
        print_info "System optimizations available with sudo privileges"
        if prompt_yes_no "Would you like instructions for system optimizations?" "n"; then
            echo ""
            print_info "To apply system optimizations, run:"
            print_info "  sudo $0 --system"
        fi
    fi
    
    print_success "System integration setup completed!"
}

# Displays help information for the system integration setup script
# Shows all available options and usage examples
show_usage() {
    echo "MountAllS3 System Integration Setup"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "INTEGRATION OPTIONS:"
    echo "  --autostart [y/n]          Configure desktop autostart"
    echo "  --symlinks [DIR]           Configure command symlink"
    echo "  --system                   Configure system optimizations (requires sudo)"
    echo "  --interactive              Run interactive system setup"
    echo ""
    echo "HELP:"
    echo "  --help, -h                 Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 --autostart y           # Enable autostart non-interactively"
    echo "  $0 --symlinks ~/.local/bin # Create symlink in specific directory"
    echo "  sudo $0 --system           # Apply system optimizations"
}

# Main function with simple argument parsing for system integration
# Routes to appropriate functions based on command line arguments
main() {
    case "${1:-}" in
        --help|-h)
            show_usage
            ;;
        --autostart)
            shift
            configure_autostart "$1"
            ;;
        --symlinks)
            shift
            configure_symlinks "$1"
            ;;
        --system)
            configure_system_optimizations
            ;;
        --interactive)
            interactive_setup
            ;;
        "")
            interactive_setup
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"