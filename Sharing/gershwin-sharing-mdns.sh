#!/bin/bash
#
# gershwin-sharing-mdns - Restore mDNS service announcements after reboot
#
# This script runs at boot to restore previously announced services.
# It's called by the gershwin-sharing-mdns.service systemd unit.

STATE_FILE="/var/lib/gershwin/sharing-services-state.plist"
LOG_TAG="gershwin-sharing-mdns"

log_info() {
    logger -t "$LOG_TAG" -p user.info "$1"
    echo "[INFO] $1"
}

log_error() {
    logger -t "$LOG_TAG" -p user.err "$1"
    echo "[ERROR] $1" >&2
}

# Check if state file exists
if [ ! -f "$STATE_FILE" ]; then
    log_info "No state file found at $STATE_FILE, nothing to restore"
    exit 0
fi

log_info "Restoring mDNS service announcements from $STATE_FILE"

# Wait for network to be ready
sleep 5

# Detect mDNS backend
MDNS_BACKEND=""
if command -v dns-sd >/dev/null 2>&1; then
    MDNS_BACKEND="dns-sd"
    log_info "Using dns-sd backend"
elif command -v avahi-publish-service >/dev/null 2>&1; then
    MDNS_BACKEND="avahi"
    log_info "Using avahi backend"
else
    log_error "No mDNS backend found (dns-sd or avahi-publish-service)"
    exit 1
fi

# Parse the plist and restore services
# This is a simple approach - we'll use Python if available
if command -v python3 >/dev/null 2>&1; then
    python3 - "$STATE_FILE" "$MDNS_BACKEND" <<'PYEOF'
import sys
import os
import subprocess
import plistlib

state_file = sys.argv[1]
backend = sys.argv[2]

try:
    with open(state_file, 'rb') as f:
        state = plistlib.load(f)
    
    hostname = os.uname().nodename
    
    for service_id, service_info in state.items():
        service_type = service_info.get('type', '')
        port = service_info.get('port', 0)
        
        if not service_type or not port:
            continue
        
        print(f"Restoring {service_type} on port {port}")
        
        if backend == 'dns-sd':
            cmd = ['dns-sd', '-R', hostname, service_type, str(port)]
            subprocess.Popen(cmd, stdin=subprocess.DEVNULL, 
                           stdout=subprocess.DEVNULL, 
                           stderr=subprocess.DEVNULL)
        elif backend == 'avahi':
            cmd = ['avahi-publish-service', hostname, service_type, str(port)]
            subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        
        print(f"Started announcement for {service_type}")

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)

PYEOF
    
    if [ $? -eq 0 ]; then
        log_info "Successfully restored mDNS service announcements"
    else
        log_error "Failed to restore mDNS service announcements"
        exit 1
    fi
else
    log_error "Python3 not found, cannot parse state file"
    exit 1
fi

exit 0
