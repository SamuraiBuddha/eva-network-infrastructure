#!/bin/bash

# Caspar (Bridge Node) Setup Script
# MAGI Windows Integration Node
# SSH on port 9222, username fixes required

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}=== Caspar Bridge Node Setup ===${NC}"
echo -e "${PURPLE}Windows Integration & Bridge Services${NC}"
echo

# System Configuration
HOSTNAME="caspar"
IP_ADDRESS="192.168.50.21"
LILITH_IP="192.168.50.10"
SSH_PORT="9222"

# Fix username issues
echo -e "${BLUE}Fixing username configuration...${NC}"
# Create both user accounts if they don't exist
if ! id "jordan" &>/dev/null; then
    sudo useradd -m -s /bin/bash jordan
    echo -e "${GREEN}Created user 'jordan'${NC}"
fi

if ! id "SamuraiBuddha" &>/dev/null; then
    sudo useradd -m -s /bin/bash SamuraiBuddha
    echo -e "${GREEN}Created user 'SamuraiBuddha'${NC}"
fi

# Link home directories
sudo ln -sfn /home/jordan /home/SamuraiBuddha/jordan-home
sudo ln -sfn /home/SamuraiBuddha /home/jordan/samurai-home

# Update system
echo -e "${BLUE}Updating system packages...${NC}"
sudo apt-get update && sudo apt-get upgrade -y

# Install required packages
echo -e "${BLUE}Installing required packages...${NC}"
sudo apt-get install -y \
    docker.io docker-compose \
    openssh-server \
    nfs-common \
    prometheus-node-exporter \
    python3-pip python3-venv \
    nodejs npm \
    git curl wget \
    jq

# Configure hostname
echo -e "${BLUE}Setting hostname...${NC}"
sudo hostnamectl set-hostname $HOSTNAME
echo "$IP_ADDRESS $HOSTNAME" | sudo tee -a /etc/hosts
echo "$LILITH_IP lilith" | sudo tee -a /etc/hosts

# Configure SSH on port 9222
echo -e "${BLUE}Configuring SSH on port $SSH_PORT...${NC}"
sudo sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config

# Allow both usernames
echo "AllowUsers jordan SamuraiBuddha" | sudo tee -a /etc/ssh/sshd_config

sudo systemctl restart sshd

# Mount Lilith shares
echo -e "${BLUE}Setting up NFS mounts...${NC}"
sudo mkdir -p /mnt/lilith-shared

echo "$LILITH_IP:/shared /mnt/lilith-shared nfs defaults,_netdev 0 0" | sudo tee -a /etc/fstab
sudo mount -a

# Create Windows integration directory
echo -e "${BLUE}Setting up Windows integration...${NC}"
mkdir -p /opt/caspar/{mcp,scripts,config}

# Install My Girl Friday (Outlook MCP) dependencies
echo -e "${BLUE}Installing My Girl Friday dependencies...${NC}"
cd /opt/caspar/mcp
git clone https://github.com/SamuraiBuddha/my-girl-friday.git
cd my-girl-friday
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate

# Create My Girl Friday service
cat > /etc/systemd/system/my-girl-friday.service << EOF
[Unit]
Description=My Girl Friday - Outlook MCP Service
After=network.target

[Service]
Type=simple
User=jordan
WorkingDirectory=/opt/caspar/mcp/my-girl-friday
ExecStart=/opt/caspar/mcp/my-girl-friday/venv/bin/python -m mcp_outlook_server
Restart=always
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOF

# Create Portainer bridge configuration
echo -e "${BLUE}Setting up Portainer bridge...${NC}"
cd /opt/caspar/mcp
git clone https://github.com/SamuraiBuddha/mcp-portainer-bridge.git

# Create docker-compose for bridge services
cat > /opt/caspar/docker-compose.yml << 'EOF'
version: '3.8'

services:
  blockchain-validator:
    image: samuraibuddha/magi-blockchain:latest
    container_name: blockchain-validator
    restart: unless-stopped
    ports:
      - "30303:30303"
      - "8545:8545"
    volumes:
      - /opt/caspar/blockchain:/data
      - /opt/caspar/validator.key:/keys/validator.key:ro
    environment:
      - NODE_NAME=caspar
      - VALIDATOR_KEY=/keys/validator.key
      - PEERS=enode://[lilith-enode]@lilith:30303

  portainer-agent:
    image: portainer/agent:latest
    container_name: portainer-agent
    restart: unless-stopped
    ports:
      - "9001:9001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes

  windows-bridge:
    image: samuraibuddha/windows-integration:latest
    container_name: windows-bridge
    restart: unless-stopped
    ports:
      - "8090:8090"
    volumes:
      - /opt/caspar/config:/config
      - /mnt/windows:/windows
    environment:
      - BRIDGE_MODE=caspar
      - LILITH_URL=http://lilith:9000
EOF

# Create Windows mount script
cat > /opt/caspar/scripts/mount-windows.sh << 'EOF'
#!/bin/bash
# Mount Windows drives via SMB

WINDOWS_HOST="192.168.50.100"  # Adjust to your Windows IP

echo "Mounting Windows drives..."
read -p "Windows username: " WIN_USER
read -sp "Windows password: " WIN_PASS
echo

sudo mkdir -p /mnt/windows/c
sudo mount -t cifs //$WINDOWS_HOST/C$ /mnt/windows/c \
    -o username=$WIN_USER,password=$WIN_PASS,vers=3.0,uid=1000,gid=1000

echo "Windows C: drive mounted at /mnt/windows/c"
EOF

chmod +x /opt/caspar/scripts/mount-windows.sh

# Create MCP registry update script
cat > /opt/caspar/scripts/update-mcp-registry.sh << 'EOF'
#!/bin/bash
# Update MCP orchestrator registry

echo "Updating MCP orchestrator registry..."

# Add Caspar-specific MCPs
cat > /tmp/caspar-mcps.json << EOJSON
{
  "my-girl-friday": {
    "name": "my-girl-friday",
    "description": "Outlook integration for email, calendar, and tasks",
    "keywords": ["email", "outlook", "calendar", "tasks", "microsoft", "office"],
    "tools": [
      "list_emails",
      "read_email",
      "send_email",
      "list_calendar_events",
      "create_event",
      "list_tasks",
      "create_task"
    ],
    "icon": "📧"
  },
  "windows-bridge": {
    "name": "windows-bridge",
    "description": "Windows system integration and file access",
    "keywords": ["windows", "files", "system", "integration"],
    "tools": [
      "read_windows_file",
      "write_windows_file",
      "list_windows_directory",
      "execute_powershell"
    ],
    "icon": "🪟"
  }
}
EOJSON

echo "Registry entries created for Caspar MCPs"
EOF

chmod +x /opt/caspar/scripts/update-mcp-registry.sh

# Configure firewall
echo -e "${BLUE}Configuring firewall...${NC}"
sudo ufw allow from 192.168.50.0/24 to any port $SSH_PORT
sudo ufw allow from 192.168.50.0/24 to any port 9001   # Portainer agent
sudo ufw allow from 192.168.50.0/24 to any port 8090   # Windows bridge
sudo ufw allow 30303  # Blockchain P2P
sudo ufw --force enable

# Create startup script
cat > /opt/caspar/scripts/startup.sh << 'EOF'
#!/bin/bash
# Caspar startup script

echo "Starting Caspar bridge services..."

# Start My Girl Friday
sudo systemctl start my-girl-friday

# Start Docker services
cd /opt/caspar
docker-compose up -d

# Check services
echo -e "\nService Status:"
systemctl status my-girl-friday --no-pager | head -n 5
docker-compose ps

echo -e "\nCaspar bridge node ready!"
echo "SSH access: ssh -p 9222 jordan@caspar or ssh -p 9222 SamuraiBuddha@caspar"
EOF

chmod +x /opt/caspar/scripts/startup.sh

# Fix permissions for both users
echo -e "${BLUE}Setting up permissions...${NC}"
for user in jordan SamuraiBuddha; do
    sudo usermod -aG docker $user
    sudo chown -R $user:$user /home/$user
done

# Make sure both users can access Caspar files
sudo chown -R jordan:jordan /opt/caspar
sudo chmod -R g+rw /opt/caspar
sudo usermod -aG jordan SamuraiBuddha

# Final setup
echo -e "${GREEN}Caspar setup complete!${NC}"
echo
echo -e "${YELLOW}Important notes:${NC}"
echo "1. SSH is running on port ${SSH_PORT} (not 22!)"
echo "2. Both 'jordan' and 'SamuraiBuddha' usernames work"
echo "3. My Girl Friday requires Azure app registration"
echo "4. Windows mount script at: /opt/caspar/scripts/mount-windows.sh"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy validator key to /opt/caspar/validator.key"
echo "2. Configure My Girl Friday with Azure credentials"
echo "3. Mount Windows drives if needed"
echo "4. Start services: /opt/caspar/scripts/startup.sh"
echo
echo -e "${BLUE}Bridge Status:${NC}"
echo "SSH Port: $SSH_PORT"
echo "Portainer Agent: http://$IP_ADDRESS:9001"
echo "Windows Bridge: http://$IP_ADDRESS:8090"
