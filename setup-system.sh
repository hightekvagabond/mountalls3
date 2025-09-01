#!/usr/bin/bash

# =============================================================================
# MountAllS3 System Integration Setup
# =============================================================================
#
# DESCRIPTION:
#   Configures system-level integrations for MountAllS3 including desktop
#   autostart, command symlinks, and performance optimizations.
#
# FEATURES:
#   - Desktop environment autostart configuration
#   - Command symlink creation for easy access
#   - System performance optimizations (requires sudo)
#   - PATH management and shell integration
#
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

# Applies updatedb optimization to exclude s3fs mounts from locate database
# Prevents locate/updatedb from scanning s3fs mounts which causes performance issues
apply_system_optimizations_updatedb() {
    print_step "Applying updatedb optimization..."
    
    # Update /etc/updatedb.conf to exclude s3fs mounts
    local updatedb_conf="/etc/updatedb.conf"
    if [[ -f "$updatedb_conf" ]]; then
        # Check specifically if fuse.s3fs is already in the PRUNEFS line (not just anywhere in the file)
        # This regex looks for PRUNEFS="..." and checks if fuse.s3fs is within those quotes
        if ! grep -q '^[[:space:]]*PRUNEFS="[^"]*fuse\.s3fs[^"]*"' "$updatedb_conf"; then
            # Backup original
            cp "$updatedb_conf" "$updatedb_conf.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Add fuse.s3fs to PRUNEFS (regex explanation for junior developers):
            # This sed command finds PRUNEFS="..." and appends " fuse.s3fs" inside the quotes
            # The [^"]* matches everything inside quotes, & keeps the matched content, then adds our filesystem type
            sed -i 's/PRUNEFS="[^"]*/& fuse.s3fs/' "$updatedb_conf"
            print_success "Updated $updatedb_conf to exclude s3fs mounts from indexing"
        else
            print_info "fuse.s3fs already exists in PRUNEFS line"
        fi
    else
        print_warning "updatedb.conf not found, skipping updatedb optimization"
    fi
    
    print_success "updatedb optimization applied"
}

# =============================================================================
# LOG ANALYSIS FUNCTIONS
# =============================================================================

# Checks system logs for s3fs performance issues
# Returns 0 if issues found, 1 if no issues detected
check_logs_for_s3fs_issues() {
    local log_files=(
        "/var/log/syslog"
        "/var/log/messages" 
        "/var/log/kern.log"
        "/var/log/dmesg"
    )
    
    local issues_found=0
    local temp_log="/tmp/s3fs_log_check.$$"
    
    # Patterns that indicate s3fs performance issues
    local issue_patterns=(
        "s3fs.*slow"
        "s3fs.*timeout"
        "fuse.s3fs.*performance"
        "updatedb.*s3fs"
        "locate.*s3fs.*slow"
        "s3fs.*blocked"
        "s3fs.*hanging"
        "too many open files.*s3fs"
        "out of memory.*s3fs"
    )
    
    debug_debug "Checking system logs for s3fs performance issues..."
    
    # Check available log files
    for log_file in "${log_files[@]}"; do
        if [[ -r "$log_file" ]]; then
            for pattern in "${issue_patterns[@]}"; do
                if grep -i "$pattern" "$log_file" >/dev/null 2>&1; then
                    echo "Found s3fs issue pattern '$pattern' in $log_file" >> "$temp_log"
                    issues_found=1
                fi
            done
        fi
    done
    
    # Check systemd journal if available
    if command -v journalctl >/dev/null 2>&1; then
        for pattern in "${issue_patterns[@]}"; do
            if journalctl --since "7 days ago" | grep -i "$pattern" >/dev/null 2>&1; then
                echo "Found s3fs issue pattern '$pattern' in systemd journal" >> "$temp_log"
                issues_found=1
            fi
        done
    fi
    
    if [[ $issues_found -eq 1 && -f "$temp_log" ]]; then
        print_warning "Found s3fs performance issues in logs:"
        cat "$temp_log"
        rm -f "$temp_log"
        return 0
    else
        debug_debug "No s3fs performance issues found in logs"
        rm -f "$temp_log"
        return 1
    fi
}

# Checks for specific network performance issues in logs
check_logs_for_network_issues() {
    local log_files=(
        "/var/log/syslog"
        "/var/log/messages"
        "/var/log/kern.log"
    )
    
    local network_patterns=(
        "tcp.*retransmit"
        "tcp.*timeout"
        "network.*slow"
        "connection.*reset"
        "tcp.*congestion"
    )
    
    debug_debug "Checking logs for network performance issues..."
    
    for log_file in "${log_files[@]}"; do
        if [[ -r "$log_file" ]]; then
            for pattern in "${network_patterns[@]}"; do
                if grep -i "$pattern" "$log_file" | tail -20 | grep -q "$(date +%Y-%m-%d)"; then
                    debug_debug "Found recent network issue: $pattern in $log_file"
                    return 0
                fi
            done
        fi
    done
    
    return 1
}

# Checks for I/O performance issues in logs
check_logs_for_io_issues() {
    local io_patterns=(
        "blocked for more than"
        "task.*blocked"
        "hung_task"
        "io.*slow"
        "disk.*timeout"
    )
    
    debug_debug "Checking logs for I/O performance issues..."
    
    if command -v journalctl >/dev/null 2>&1; then
        for pattern in "${io_patterns[@]}"; do
            if journalctl --since "7 days ago" | grep -i "$pattern" | grep -q fuse; then
                debug_debug "Found I/O issue related to fuse: $pattern"
                return 0
            fi
        done
    fi
    
    return 1
}

# =============================================================================
# INDIVIDUAL OPTIMIZATION FUNCTIONS
# =============================================================================

# Optimizes updatedb configuration to exclude s3fs mounts
# Safe: Only modifies PRUNEFS in /etc/updatedb.conf
apply_optimization_updatedb() {
    local force_apply="${1:-false}"
    
    print_header "UpdateDB Optimization (Exclude s3fs from locate database)"
    
    # Check if already applied
    local updatedb_conf="/etc/updatedb.conf"
    if [[ -f "$updatedb_conf" ]] && grep -q '^[[:space:]]*PRUNEFS="[^"]*fuse\.s3fs[^"]*"' "$updatedb_conf"; then
        print_info "UpdateDB optimization already applied"
        return 0
    fi
    
    # Check logs for updatedb/locate issues
    local logs_show_issue=false
    if check_logs_for_s3fs_issues; then
        logs_show_issue=true
    fi
    
    # Explain the optimization
    echo "This optimization prevents the 'locate' command from scanning s3fs mount points."
    echo "Benefits:"
    echo "  • Prevents updatedb from causing high I/O on S3 buckets"
    echo "  • Reduces S3 API calls and costs"
    echo "  • Eliminates potential s3fs hangs during updatedb runs"
    echo ""
    
    if [[ "$logs_show_issue" == true ]]; then
        echo "✅ Your logs show evidence of s3fs performance issues that this could help resolve."
    else
        echo "ℹ️  No evidence of updatedb/locate issues in recent logs, but this is still a good preventive measure."
    fi
    echo ""
    
    if [[ "$force_apply" != true ]]; then
        if ! prompt_yes_no "Apply updatedb optimization now?" "y"; then
            print_info "Skipped updatedb optimization (you can run this again later if needed)"
            return 0
        fi
    fi
    
    # Apply the optimization
    apply_system_optimizations_updatedb
}

# Optimizes file descriptor limits for s3fs
# Low risk: Only increases limits, doesn't decrease them
apply_optimization_file_limits() {
    local force_apply="${1:-false}"
    
    print_header "File Descriptor Limit Optimization"
    
    # Check current limits
    local current_soft=$(ulimit -Sn)
    local current_hard=$(ulimit -Hn)
    
    # Check if already optimized
    if [[ $current_soft -ge 65536 ]]; then
        print_info "File descriptor limits already optimized (current: $current_soft)"
        return 0
    fi
    
    # Check if we've already modified limits.conf
    if grep -q "# MountAllS3 file descriptor limits" /etc/security/limits.conf 2>/dev/null; then
        print_info "File descriptor limit configuration already applied"
        print_warning "Current limit is still $current_soft - you may need to restart your session"
        return 0
    fi
    
    # Explain the optimization
    echo "This optimization increases file descriptor limits for better s3fs performance."
    echo "Changes:"
    echo "  • Soft limit: 65536 file descriptors"
    echo "  • Hard limit: 65536 file descriptors"
    echo "  • Current soft limit: $current_soft"
    echo "  • Current hard limit: $current_hard"
    echo ""
    echo "Benefits:"
    echo "  • Prevents 'too many open files' errors with s3fs"
    echo "  • Allows more concurrent S3 connections"
    echo "  • Better performance with large directory structures"
    echo ""
    echo "ℹ️  This is a safe optimization that only increases limits (never decreases them)"
    echo ""
    
    if [[ "$force_apply" != true ]]; then
        if ! prompt_yes_no "Apply file descriptor limit optimizations?" "y"; then
            print_info "Skipped file descriptor limit optimizations"
            return 0
        fi
    fi
    
    # Apply the optimization
    print_step "Applying file descriptor limit optimizations..."
    
    # Backup limits.conf
    cp /etc/security/limits.conf "/etc/security/limits.conf.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add limits
    cat >> /etc/security/limits.conf << 'EOF'

# MountAllS3 file descriptor limits for s3fs performance
* soft nofile 65536
* hard nofile 65536
EOF
    
    # Also set system-wide limit
    if grep -q "fs.file-max" /etc/sysctl.conf; then
        # Update existing
        sed -i 's/^fs\.file-max.*/fs.file-max = 1000000/' /etc/sysctl.conf
    else
        echo "fs.file-max = 1000000" >> /etc/sysctl.conf
    fi
    
    sysctl -p >/dev/null 2>&1
    
    print_success "File descriptor limit optimizations applied"
    print_info "💡 Changes take effect for new login sessions"
    print_info "   Current session limit is still $current_soft"
}

# Optimizes network buffer sizes for better S3 throughput  
# Moderate risk: Changes network buffer sizes system-wide
apply_optimization_network_buffers() {
    local force_apply="${1:-false}"
    
    print_header "Network Buffer Optimization"
    
    # Check if already applied
    if grep -q "# MountAllS3 network optimizations" /etc/sysctl.conf 2>/dev/null; then
        print_info "Network buffer optimizations already applied"
        return 0
    fi
    
    # Check logs for network issues
    local logs_show_issue=false
    if check_logs_for_network_issues; then
        logs_show_issue=true
    fi
    
    # Explain the optimization
    echo "This optimization increases network buffer sizes for better S3 throughput."
    echo "Changes:"
    echo "  • net.core.rmem_max=16777216 (16MB receive buffer)"
    echo "  • net.core.wmem_max=16777216 (16MB send buffer)" 
    echo "  • net.ipv4.tcp_rmem='4096 87380 16777216' (TCP receive window scaling)"
    echo "  • net.ipv4.tcp_wmem='4096 65536 16777216' (TCP send window scaling)"
    echo ""
    echo "Benefits:"
    echo "  • Higher throughput for large S3 transfers"
    echo "  • Better handling of high-latency connections"
    echo "  • Reduced TCP retransmissions"
    echo ""
    
    if [[ "$logs_show_issue" == true ]]; then
        echo "✅ Your logs show evidence of network issues that this could help resolve."
    else
        echo "ℹ️  No evidence of network issues in recent logs."
        echo "   This optimization provides benefits mainly for high-throughput S3 workloads."
    fi
    echo ""
    
    if [[ "$force_apply" != true ]]; then
        if ! prompt_yes_no "Apply network buffer optimizations?" "n"; then
            print_info "Skipped network buffer optimizations"
            return 0
        fi
    fi
    
    # Apply the optimization
    print_step "Applying network buffer optimizations..."
    
    # Backup if not already done
    if [[ ! -f "/etc/sysctl.conf.backup.$(date +%Y%m%d)" ]]; then
        cp /etc/sysctl.conf "/etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Add network optimizations
    cat >> /etc/sysctl.conf << 'EOF'

# MountAllS3 network optimizations for S3 throughput
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
    
    # Apply immediately
    sysctl -p >/dev/null 2>&1
    
    print_success "Network buffer optimizations applied"
}

# Applies selected system-level optimizations for s3fs performance
# Now provides individual optimization selection with safety checks
apply_system_optimizations() {
    print_header "System Performance Optimizations"
    
    echo "Available optimizations (safer options are recommended):"
    echo ""
    echo "1. 🟢 UpdateDB optimization (SAFE - recommended for all users)"
    echo "   Prevents locate/updatedb from scanning s3fs mounts"
    echo ""
    echo "2. 🟢 File descriptor limits (SAFE - recommended for all users)"
    echo "   Increases file descriptor limits to prevent 'too many open files' errors"
    echo ""
    echo "3. 🟡 Network buffer optimization (MODERATE - for high-throughput workloads)"
    echo "   Increases network buffer sizes for better S3 transfer speeds"
    echo ""
    echo "ℹ️  More advanced optimizations are available via:"
    echo "   sudo ./setup-system-advanced.sh"
    echo ""
    
    local selected_opts=""
    configure_value "selected_opts" \
        "Enter comma-separated numbers (e.g., 1,2) for optimizations to apply. Each will ask for individual confirmation." \
        "Which optimizations to apply?" \
        "1,2" \
        ""
    
    if [[ "$selected_opts" == "all" ]]; then
        selected_opts="1,2,3"
    fi
    
    local applied_any=false
    IFS=',' read -ra opt_array <<< "$selected_opts"
    for opt in "${opt_array[@]}"; do
        case "${opt// /}" in
            1) 
                apply_optimization_updatedb
                applied_any=true
                ;;
            2) 
                apply_optimization_file_limits
                applied_any=true
                ;;
            3) 
                apply_optimization_network_buffers
                applied_any=true
                ;;
            *) 
                print_warning "Unknown optimization: $opt" 
                ;;
        esac
        echo ""  # Add spacing between optimizations
    done
    
    if [[ "$applied_any" == true ]]; then
        print_success "System optimization configuration completed"
        print_info "💡 Additional optimizations can be added in the future if performance issues arise"
    else
        print_info "No optimizations were applied"
    fi
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
        if prompt_yes_no "Would you like instructions for system optimizations?" "y"; then
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