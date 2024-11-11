#!/bin/bash

# Enforce strict error handling
set -euo pipefail

# Function to prompt for user input with a default value
prompt_input() {
    local prompt="$1"
    local default="$2"
    read -rp "$prompt [$default]: " input
    echo "${input:-$default}"
}

# Get custom port, username, and password from user input
custom_port=$(prompt_input "Enter the port" "32123")
custom_user=$(prompt_input "Enter username" "user")
custom_password=$(prompt_input "Enter password" "123123")

# Update repositories and upgrade existing packages
apt update
apt upgrade -y
echo 'net.ipv4.ip_forward=1' | tee -a /etc/sysctl.conf
sysctl -p

# Install necessary packages
apt install -y wget curl ufw dante-server dnscrypt-proxy

# Enable UFW (Uncomplicated Firewall) and allow SSH and custom port
ufw --force enable
ufw allow ssh
ufw allow "$custom_port"/tcp

# Detect all non-loopback and non-primary IPs on the server
all_ips=($(hostname -I | tr ' ' '\n' | grep -v '^127\.' | grep -v "$(hostname -I | awk '{print $1}')"))

# Generate Dante server configuration
cat <<EOF > /etc/danted.conf
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $custom_port
EOF

# Add each detected IP as an external interface
for ip in "${all_ips[@]}"; do
    echo "external: $ip" >> /etc/danted.conf
done

# Add the main IP as an external interface if needed
main_ip=$(hostname -I | awk '{print $1}')
echo "external: $main_ip" >> /etc/danted.conf

# Additional static configuration
cat <<EOF >> /etc/danted.conf
method: username none
user.privileged: root
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF

# Securely add user for Dante server
useradd --shell /usr/sbin/nologin --create-home "$custom_user" || echo "User $custom_user already exists"
echo "$custom_user:$custom_password" | chpasswd

# Restart Dante, Networking, and DNScrypt server
systemctl restart danted
systemctl restart networking
systemctl restart dnscrypt-proxy

# Enable Dante server to start at boot
systemctl enable danted

# Output information about the setup
echo "Your SOCKS5 proxy server with DNScrypt configured successfully."
echo "Proxy IPs:"
for ip in "${all_ips[@]}"; do
    echo "IP: $ip Port: $custom_port"
done
echo "User: $custom_user"
echo "Password: $custom_password"
