#!/bin/bash

# Tunnel Setup Script for Ubuntu Servers
# This script sets up an IP-in-IP tunnel between an Iranian server (restricted internet) and an external server (free internet).
# It uses ip tunnel for creating the tunnel interface and iptables for NAT/masquerading if needed.
# The script assumes root privileges. Run with sudo if necessary.
# After setup, it tests the tunnel with ping and logs the process.

# Log file
LOG_FILE="/var/log/tunnel_setup.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to display logs
if [ "$1" == "log" ]; then
    if [ -f "$LOG_FILE" ]; then
        cat "$LOG_FILE"
    else
        echo "No log file found."
    fi
    exit 0
fi

# Ensure script runs as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

# Start logging
log "Script execution started."

# Ask user which server this is
echo "Welcome to the Tunnel Setup Script."
echo "Please specify which server you are on:"
echo "1) Iranian Server (restricted internet)"
echo "2) External Server (free internet)"
read -p "Enter 1 or 2: " SERVER_TYPE

if [ "$SERVER_TYPE" != "1" ] && [ "$SERVER_TYPE" != "2" ]; then
    echo "Invalid choice. Exiting."
    log "Invalid server type selected. Exiting."
    exit 1
fi

log "Server type selected: $SERVER_TYPE"

# Load necessary modules (ipip for IP-in-IP tunnel)
modprobe ipip
log "Loaded ipip module."

# Common variables
TUNNEL_NAME="tun0"
LOCAL_TUNNEL_IP=""
REMOTE_TUNNEL_IP=""
REMOTE_PUBLIC_IP=""
LOCAL_PUBLIC_IP=$(curl -s ifconfig.me)  # Get local public IP automatically if possible

if [ -z "$LOCAL_PUBLIC_IP" ]; then
    read -p "Could not detect local public IP. Please enter the public IP of this server: " LOCAL_PUBLIC_IP
fi

log "Local public IP: $LOCAL_PUBLIC_IP"

# Depending on server type, ask for details
if [ "$SERVER_TYPE" == "1" ]; then  # Iranian Server
    echo "You are on the Iranian Server."
    echo "This server will tunnel traffic to the external server for free internet access."
    read -p "Enter the public IP of the External Server (for tunnel remote endpoint): " REMOTE_PUBLIC_IP
    log "Remote public IP (External): $REMOTE_PUBLIC_IP"
    
    # Tunnel IPs: Iranian side gets 10.0.0.1, External gets 10.0.0.2
    LOCAL_TUNNEL_IP="10.0.0.1/24"
    REMOTE_TUNNEL_IP="10.0.0.2"
    
    # Ask for port if needed, but IP-in-IP doesn't use ports. For simplicity, no port.
    echo "No specific port needed for IP-in-IP tunnel. Proceeding."

elif [ "$SERVER_TYPE" == "2" ]; then  # External Server
    echo "You are on the External Server."
    echo "This server will receive tunneled traffic from the Iranian server."
    read -p "Enter the public IP of the Iranian Server (for tunnel remote endpoint): " REMOTE_PUBLIC_IP
    log "Remote public IP (Iranian): $REMOTE_PUBLIC_IP"
    
    # Tunnel IPs: External side gets 10.0.0.2, Iranian gets 10.0.0.1
    LOCAL_TUNNEL_IP="10.0.0.2/24"
    REMOTE_TUNNEL_IP="10.0.0.1"
    
    echo "No specific port needed for IP-in-IP tunnel. Proceeding."
fi

# Create the tunnel interface
ip tunnel del "$TUNNEL_NAME" 2>/dev/null  # Delete if exists
ip tunnel add "$TUNNEL_NAME" mode ipip remote "$REMOTE_PUBLIC_IP" local "$LOCAL_PUBLIC_IP" ttl 255
log "Created tunnel interface: $TUNNEL_NAME"

# Bring up the interface and assign IP
ip link set "$TUNNEL_NAME" up
ip addr add "$LOCAL_TUNNEL_IP" dev "$TUNNEL_NAME"
log "Assigned IP to tunnel: $LOCAL_TUNNEL_IP"

# Additional setup based on server type
if [ "$SERVER_TYPE" == "1" ]; then  # Iranian Server: Route all traffic through tunnel
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    
    # Add route: default via remote tunnel IP
    ip route add default via "$REMOTE_TUNNEL_IP" dev "$TUNNEL_NAME" table main
    log "Added default route via $REMOTE_TUNNEL_IP"
    
    # Note: For full traffic routing, you may need to adjust DNS or use iptables for masquerading if NAT is needed.
    # But for basic tunnel, this routes outgoing traffic.

elif [ "$SERVER_TYPE" == "2" ]; then  # External Server: Enable masquerading for incoming tunneled traffic
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    
    # IPTables for NAT (masquerade outgoing traffic from tunnel)
    iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE  # Assuming eth0 is the main interface; adjust if needed
    log "Set up iptables masquerade for tunnel traffic."
    
    # Save iptables rules (install iptables-persistent if not present)
    apt-get update -qq && apt-get install -y iptables-persistent -qq
    netfilter-persistent save
    log "Saved iptables rules."
fi

# Make changes persistent (basic way; for production, use systemd or crontab)
# Add to /etc/rc.local if exists, or create it
if [ ! -f /etc/rc.local ]; then
    echo "#!/bin/sh -e" > /etc/rc.local
    chmod +x /etc/rc.local
fi

# Append tunnel setup commands to rc.local
cat <<EOT >> /etc/rc.local
modprobe ipip
ip tunnel add $TUNNEL_NAME mode ipip remote $REMOTE_PUBLIC_IP local $LOCAL_PUBLIC_IP ttl 255
ip link set $TUNNEL_NAME up
ip addr add $LOCAL_TUNNEL_IP dev $TUNNEL_NAME
EOT

if [ "$SERVER_TYPE" == "1" ]; then
    echo "ip route add default via $REMOTE_TUNNEL_IP dev $TUNNEL_NAME table main" >> /etc/rc.local
elif [ "$SERVER_TYPE" == "2" ]; then
    echo "iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE" >> /etc/rc.local
fi

log "Added persistence to /etc/rc.local"

# Test the tunnel
echo "Testing the tunnel..."
if ping -c 3 "$REMOTE_TUNNEL_IP" > /dev/null 2>&1; then
    echo "Tunnel test successful! Ping to remote tunnel IP ($REMOTE_TUNNEL_IP) works."
    log "Tunnel test successful."
else
    echo "Tunnel test failed. Check logs with './script.sh log' or check firewall/IPs."
    log "Tunnel test failed."
    exit 1
fi

# Additional test: On Iranian server, test internet access via tunnel (e.g., ping google.com)
if [ "$SERVER_TYPE" == "1" ]; then
    if ping -c 3 8.8.8.8 > /dev/null 2>&1; then  # Assuming tunnel routes to free DNS
        echo "Internet access test successful! Can ping 8.8.8.8."
        log "Internet test successful."
    else
        echo "Internet access test failed. You may need to adjust DNS or routes."
        log "Internet test failed."
    fi
fi

echo "Setup complete. You can now install XUI panel and configure it to use the tunnel."
echo "To view logs: Run this script with 'log' argument, e.g., './script.sh log'"
echo "Note: For full VPN-like setup, ensure firewall allows IP-in-IP (protocol 4) and adjust as needed."
echo "This is a basic setup; test thoroughly. If IP-in-IP is filtered, consider GRE or other tunnels."

log "Script execution completed."
