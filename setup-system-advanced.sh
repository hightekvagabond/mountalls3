#!/usr/bin/bash

# =============================================================================
# MountAllS3 Advanced System Optimizations
# =============================================================================
#
# DESCRIPTION:
#   Advanced system-level optimizations for s3fs performance that carry higher
#   risk and should only be applied when experiencing specific performance issues.
#
# FEATURES:
#   - Kernel VM parameter optimization
#   - I/O scheduler optimization  
#   - Memory management optimization
#   - Log analysis and issue detection
#   - Individual user consent for each optimization
#
# USAGE:
#   sudo ./setup-system-advanced.sh [--optimization-name]
#
# =============================================================================

# Load common functions
COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$COMMON_SCRIPT_DIR/common.sh" || {
    echo "❌ Error: Could not load common.sh library"
    exit 1
}

# Script description for help system
SCRIPT_DESCRIPTION="Advanced system optimizations for s3fs performance (HIGH RISK)"

# =============================================================================
# LOG ANALYSIS FUNCTIONS (copied from setup-system.sh)
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
    
    echo "🔍 Analyzing logs for I/O performance issues..."
    
    if command -v journalctl >/dev/null 2>&1; then
        echo -n "   Checking systemd journal for I/O issues (last 2 hours)... "
        local found_issues=false
        # Use very restrictive time window and line limit to prevent hanging
        if timeout 5s journalctl --since "2 hours ago" --lines=100 >/dev/null 2>&1; then
            for pattern in "${io_patterns[@]}"; do
                if timeout 5s journalctl --since "2 hours ago" --lines=100 | grep -i "$pattern" | grep -q fuse; then
                    echo "⚠️  I/O issues found"
                    debug_debug "Found I/O issue related to fuse: $pattern"
                    return 0
                fi
            done
            echo "✅ clean"
        else
            echo "⏰ timeout (journal too large, skipping detailed check)"
        fi
    else
        echo "   systemd journal not available"
    fi
    
    return 1
}

# =============================================================================
# ADVANCED OPTIMIZATION FUNCTIONS
# =============================================================================

# Optimizes kernel VM parameters for network filesystems
# More risky: Modifies system memory management parameters
apply_optimization_kernel_vm() {
    local force_apply="${1:-false}"
    
    print_header "Kernel VM Parameters Optimization"
    echo "🟡 RISK LEVEL: RISKY - Only if experiencing I/O issues"
    echo ""
    
    # Check if already applied
    local already_applied=false
    if grep -q "# MountAllS3 VM optimizations" /etc/sysctl.conf 2>/dev/null; then
        already_applied=true
    fi
    
    # Check logs for memory/performance issues
    local logs_show_issue=false
    if check_logs_for_io_issues; then
        logs_show_issue=true
    fi
    
    # Explain the optimization
    echo "This optimization adjusts kernel virtual memory parameters for better network filesystem performance."
    echo "Changes:"
    echo "  • vm.dirty_ratio=10 (down from default ~20) - Write dirty pages sooner"
    echo "  • vm.dirty_background_ratio=5 (down from default ~10) - Start background writes earlier"
    echo "  • vm.vfs_cache_pressure=50 (down from default 100) - Keep filesystem cache longer"
    echo ""
    echo "Benefits:"
    echo "  • Reduces memory pressure from large s3fs caches"
    echo "  • Better handling of network filesystem I/O"
    echo "  • More predictable write performance"
    echo ""
    echo "📝 To undo manually:"
    echo "  sudo cp /etc/sysctl.conf.backup.* /etc/sysctl.conf"
    echo "  sudo sysctl -p  # Or edit /etc/sysctl.conf and remove MountAllS3 VM section"
    echo ""
    echo "⚠️  CAUTION: These changes affect system-wide memory management"
    echo ""
    
    if [[ "$logs_show_issue" == true ]]; then
        echo "✅ Your logs show evidence of I/O issues that this could help resolve."
    else
        echo "ℹ️  No evidence of I/O issues in recent logs."
        echo "   This optimization may not be needed unless you experience performance problems."
    fi
    echo ""
    
    if [[ "$already_applied" == true ]]; then
        print_info "✅ Kernel VM optimizations already applied"
        print_info "💡 This information is shown for reference and troubleshooting"
        return 1  # Return 1 to indicate "not newly applied"
    fi
    
    if [[ "$force_apply" != true ]]; then
        if ! prompt_yes_no "Apply kernel VM optimizations? (affects system-wide memory management)" "n"; then
            print_info "Skipped kernel VM optimizations (recommended - apply only if experiencing issues)"
            return 1  # Return 1 to indicate "not applied"
        fi
    fi
    
    # Apply the optimization
    print_step "Applying kernel VM optimizations..."
    
    # Backup current sysctl.conf
    cp /etc/sysctl.conf "/etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add VM optimizations
    cat >> /etc/sysctl.conf << 'EOF'

# MountAllS3 VM optimizations for network filesystems
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
EOF
    
    # Apply immediately
    sysctl -p >/dev/null 2>&1
    
    print_success "Kernel VM optimizations applied"
    print_info "Changes are active immediately and will persist after reboot"
    return 0  # Return 0 to indicate "successfully applied"
}

# Optimizes I/O scheduler for SSD systems with s3fs caches
# Low to moderate risk: Changes I/O scheduling for all storage devices
apply_optimization_io_scheduler() {
    local force_apply="${1:-false}"
    
    print_header "I/O Scheduler Optimization"
    echo "🟡 RISK LEVEL: MODERATE - For SSD systems"
    echo ""
    
    # Detect storage types
    local ssd_devices=()
    local hdd_devices=()
    
    for device in /sys/block/*/queue/rotational; do
        if [[ -f "$device" ]]; then
            local dev_name=$(echo "$device" | cut -d'/' -f4)
            local rotational=$(cat "$device")
            
            if [[ "$rotational" == "0" ]]; then
                ssd_devices+=("/dev/$dev_name")
            else
                hdd_devices+=("/dev/$dev_name")
            fi
        fi
    done
    
    # Only optimize if we have SSDs
    if [[ ${#ssd_devices[@]} -eq 0 ]]; then
        print_info "No SSD devices detected - I/O scheduler optimization not recommended"
        return 1  # Return 1 to indicate "not applicable"
    fi
    
    # Check current schedulers
    debug_debug "SSD devices found: ${ssd_devices[*]}"
    debug_debug "HDD devices found: ${hdd_devices[*]}"
    
    # Explain the optimization
    echo "This optimization sets the I/O scheduler to 'deadline' for SSD devices."
    echo "Detected storage devices:"
    for device in "${ssd_devices[@]}"; do
        local current_scheduler=$(cat "/sys/block/$(basename "$device")/queue/scheduler" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
        echo "  • $device (SSD): current scheduler = $current_scheduler"
    done
    
    if [[ ${#hdd_devices[@]} -gt 0 ]]; then
        echo "  • HDD devices will not be changed"
    fi
    echo ""
    echo "Benefits:"
    echo "  • Better I/O performance for s3fs local caches on SSD"
    echo "  • Lower latency for cache operations"
    echo "  • More predictable I/O behavior"
    echo ""
    echo "📝 To undo manually:"
    echo "  sudo rm /etc/udev/rules.d/60-mountalls3-scheduler.rules"
    echo "  sudo udevadm control --reload-rules"
    echo "  Reboot to reset schedulers or manually change via /sys/block/*/queue/scheduler"
    echo ""
    echo "⚠️  This affects I/O scheduling for SSD storage system-wide"
    echo ""
    
    if [[ "$force_apply" != true ]]; then
        if ! prompt_yes_no "Apply I/O scheduler optimizations for SSD devices?" "n"; then
            print_info "Skipped I/O scheduler optimizations"
            return 1  # Return 1 to indicate "not applied"
        fi
    fi
    
    # Apply the optimization
    print_step "Applying I/O scheduler optimizations..."
    
    local scheduler_rules="/etc/udev/rules.d/60-mountalls3-scheduler.rules"
    
    # Create udev rules for persistent scheduler changes
    cat > "$scheduler_rules" << 'EOF'
# MountAllS3 I/O scheduler optimization for SSD devices
# Set deadline scheduler for non-rotational (SSD) devices
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="deadline"
EOF
    
    # Apply immediately to current devices
    for device in "${ssd_devices[@]}"; do
        local block_device=$(basename "$device")
        local scheduler_path="/sys/block/$block_device/queue/scheduler"
        
        if [[ -w "$scheduler_path" ]] && grep -q "deadline" "$scheduler_path"; then
            echo "deadline" > "$scheduler_path" 2>/dev/null || true
            print_info "Set deadline scheduler for $device"
        fi
    done
    
    # Reload udev rules
    udevadm control --reload-rules 2>/dev/null || true
    
    print_success "I/O scheduler optimizations applied"
    print_info "Changes are active now and will persist after reboot"
    return 0  # Return 0 to indicate "successfully applied"
}

# Optimizes memory management for large s3fs caches
# Higher risk: Affects system-wide memory management
apply_optimization_memory_management() {
    local force_apply="${1:-false}"
    
    print_header "Memory Management Optimization for Large S3FS Caches"
    echo "🔴 RISK LEVEL: HIGH RISK - Only for large cache workloads on 8GB+ systems"
    echo ""
    
    # Check system memory
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    
    # Only recommend for systems with sufficient memory
    if [[ $total_mem_gb -lt 8 ]]; then
        print_warning "System has only ${total_mem_gb}GB RAM - memory optimizations not recommended"
        return 1  # Return 1 to indicate "not applicable"
    fi
    
    # Check if already applied
    if grep -q "# MountAllS3 memory optimizations" /etc/sysctl.conf 2>/dev/null; then
        print_info "✅ Memory management optimizations already applied - skipping"
        return 1  # Return 1 to indicate "not newly applied"
    fi
    
    # Explain the optimization
    echo "This optimization adjusts memory management for systems using large s3fs caches."
    echo "System memory: ${total_mem_gb}GB"
    echo ""
    echo "Changes:"
    echo "  • vm.swappiness=10 (down from default 60) - Reduce swapping with large caches"
    echo "  • vm.dirty_expire_centisecs=500 (down from 3000) - Faster dirty page cleanup"
    echo "  • vm.dirty_writeback_centisecs=100 (down from 500) - More frequent writeback"
    echo ""
    echo "Benefits:"
    echo "  • Better memory management with large s3fs caches"
    echo "  • Reduced risk of memory pressure"
    echo "  • More responsive system during heavy S3 operations"
    echo ""
    echo "📝 To undo manually:"
    echo "  sudo cp /etc/sysctl.conf.backup.* /etc/sysctl.conf"
    echo "  sudo sysctl -p  # Or edit /etc/sysctl.conf and remove MountAllS3 memory section"
    echo "  Default values: vm.swappiness=60, vm.dirty_expire_centisecs=3000, vm.dirty_writeback_centisecs=500"
    echo ""
    echo "⚠️  CAUTION: These changes affect system-wide memory management"
    echo "⚠️  Only recommended for systems with 8GB+ RAM and large s3fs workloads"
    echo ""
    
    if [[ "$force_apply" != true ]]; then
        if ! prompt_yes_no "Apply memory management optimizations? (only if using large s3fs caches)" "n"; then
            print_info "Skipped memory management optimizations (recommended unless you have large cache needs)"
            return 1  # Return 1 to indicate "not applied"
        fi
    fi
    
    # Apply the optimization
    print_step "Applying memory management optimizations..."
    
    # Backup if not already done
    if [[ ! -f "/etc/sysctl.conf.backup.$(date +%Y%m%d)" ]]; then
        cp /etc/sysctl.conf "/etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Add memory optimizations
    cat >> /etc/sysctl.conf << 'EOF'

# MountAllS3 memory optimizations for large s3fs caches
vm.swappiness = 10
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
EOF
    
    # Apply immediately
    sysctl -p >/dev/null 2>&1
    
    print_success "Memory management optimizations applied"
    return 0  # Return 0 to indicate "successfully applied"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

# Main function to present advanced optimizations one by one
apply_advanced_optimizations() {
    print_header "Advanced System Performance Optimizations"
    
    echo "⚠️  WARNING: These are advanced optimizations that modify system-wide settings"
    echo "⚠️  Only apply these if you are experiencing specific performance issues"
    echo ""
    echo "I'll walk you through each advanced optimization individually."
    echo "For each one, you'll see:"
    echo "  • What the optimization does"
    echo "  • Why it might help"
    echo "  • Log analysis to see if you're experiencing the issue"
    echo "  • How to undo the change"
    echo ""
    echo "You can decline any optimization and move to the next one."
    echo ""
    
    if ! prompt_yes_no "Ready to review advanced optimizations?" "y"; then
        print_info "Advanced optimization review cancelled"
        return 0
    fi
    
    local applied_any=false
    
    # Array of advanced optimization functions to execute
    local advanced_optimizations=(
        "apply_optimization_kernel_vm"
        "apply_optimization_io_scheduler"
        "apply_optimization_memory_management"
    )
    
    # Execute each advanced optimization and track if any were applied
    for optimization_func in "${advanced_optimizations[@]}"; do
        echo ""
        if "$optimization_func"; then
            applied_any=true
        fi
    done
    
    echo ""
    if [[ "$applied_any" == true ]]; then
        print_success "Advanced optimization review completed"
        print_warning "Monitor your system performance after applying these changes"
        print_info "If you experience issues, you can restore from the backup files created"
    else
        print_info "No advanced optimizations were applied"
        print_info "💡 You can run this again anytime when experiencing performance issues"
    fi
}

# Interactive setup for advanced optimizations
interactive_setup() {
    print_header "Advanced System Optimizations Setup"
    
    echo "This script provides advanced system optimizations that are:"
    echo "• More risky than basic optimizations"
    echo "• Should only be used when experiencing performance issues"
    echo "• Modify system-wide settings that affect all applications"
    echo ""
    
    if ! prompt_yes_no "Do you want to proceed with advanced optimizations?" "n"; then
        print_info "Advanced optimizations setup cancelled"
        echo ""
        print_info "💡 Consider running the basic optimizations first:"
        print_info "   sudo ./setup-system.sh --system"
        return 0
    fi
    
    apply_advanced_optimizations
}

# Flag registration for command line usage
register_flag "kernel-vm" "apply_optimization_kernel_vm" "none" "" \
    "Apply kernel VM parameter optimizations" \
    "" ""

register_flag "io-scheduler" "apply_optimization_io_scheduler" "none" "" \
    "Apply I/O scheduler optimizations" \
    "" ""

register_flag "memory" "apply_optimization_memory_management" "none" "" \
    "Apply memory management optimizations" \
    "" ""

register_flag "all-advanced" "apply_advanced_optimizations" "none" "" \
    "Apply all advanced optimizations with confirmation" \
    "" ""

# Usage information
show_usage() {
    echo "MountAllS3 Advanced System Optimizations"
    echo ""
    echo "Usage: sudo $0 [OPTIONS]"
    echo ""
    echo "ADVANCED OPTIMIZATIONS:"
    echo "  --kernel-vm                Apply kernel VM parameter optimizations (RISKY)"
    echo "  --io-scheduler             Apply I/O scheduler optimizations (MODERATE)"
    echo "  --memory                   Apply memory management optimizations (HIGH RISK)"
    echo "  --all-advanced             Apply all advanced optimizations with confirmation"
    echo "  --interactive              Run interactive advanced setup"
    echo ""
    echo "HELP:"
    echo "  --help, -h                 Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  sudo $0 --interactive      # Interactive advanced optimization setup"
    echo "  sudo $0 --kernel-vm        # Apply only kernel VM optimizations"
    echo "  sudo $0 --all-advanced     # Apply all advanced optimizations"
    echo ""
    echo "⚠️  WARNING: These optimizations modify system-wide settings and should"
    echo "    only be used when experiencing specific performance issues."
}

# Main execution
main() {
    case "${1:-}" in
        --help|-h)
            show_usage
            ;;
        *)
            # Check for root privileges for all other operations
            if [[ $EUID -ne 0 ]]; then
                print_error "Advanced optimizations require root privileges"
                print_info "Please run with sudo: sudo $0 $*"
                exit 1
            fi
            
            case "${1:-}" in
                --kernel-vm)
                    apply_optimization_kernel_vm
                    ;;
                --io-scheduler)
                    apply_optimization_io_scheduler
                    ;;
                --memory)
                    apply_optimization_memory_management
                    ;;
                --all-advanced)
                    apply_advanced_optimizations
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
            ;;
    esac
}

main "$@"
