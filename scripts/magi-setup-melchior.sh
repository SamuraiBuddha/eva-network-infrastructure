#!/bin/bash

# Melchior (Workstation) Setup Script
# Primary Development Machine
# WSL2 Ubuntu with Docker Desktop integration

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}=== Melchior Workstation Setup ===${NC}"
echo -e "${PURPLE}Primary Development Environment${NC}"
echo

# Check if running in WSL
if ! grep -q Microsoft /proc/version; then
    echo -e "${YELLOW}Warning: This script is designed for WSL2 Ubuntu${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# System Configuration
HOSTNAME="melchior"
LILITH_IP="192.168.50.10"
ADAM_IP="192.168.50.11"

# Update system
echo -e "${BLUE}Updating system packages...${NC}"
sudo apt-get update && sudo apt-get upgrade -y

# Install development tools
echo -e "${BLUE}Installing development tools...${NC}"
sudo apt-get install -y \
    build-essential \
    git curl wget \
    python3-pip python3-venv \
    nodejs npm \
    jq yq \
    htop btop \
    tmux screen \
    vim neovim \
    zsh fish \
    nfs-common \
    smbclient cifs-utils

# Install Docker (if not using Docker Desktop)
if ! command -v docker &> /dev/null; then
    echo -e "${BLUE}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
fi

# Configure WSL2 settings
echo -e "${BLUE}Configuring WSL2 settings...${NC}"
cat > ~/.wslconfig << EOF
[wsl2]
memory=24GB
processors=8
swap=8GB
localhostForwarding=true

[experimental]
sparseVhd=true
autoMemoryReclaim=gradual
EOF

# Create development directory structure
echo -e "${BLUE}Creating development directories...${NC}"
mkdir -p ~/projects/{mcp,blockchain,ai,revit}
mkdir -p ~/docker/volumes
mkdir -p ~/.config/claude

# Mount network shares
echo -e "${BLUE}Setting up network mounts...${NC}"
sudo mkdir -p /mnt/lilith-shared
sudo mkdir -p /mnt/adam-business

# Create mount script
cat > ~/bin/mount-eva-shares.sh << EOF
#!/bin/bash
# Mount EVA network shares

# Mount Lilith shared storage
sudo mount -t nfs $LILITH_IP:/shared /mnt/lilith-shared

# Mount Adam business shares (requires credentials)
read -p "Enter SMB username: " SMB_USER
read -sp "Enter SMB password: " SMB_PASS
echo

sudo mount -t cifs //$ADAM_IP/Clients /mnt/adam-business \
    -o username=\$SMB_USER,password=\$SMB_PASS,vers=3.0

echo "Shares mounted:"
df -h | grep -E "lilith|adam"
EOF

chmod +x ~/bin/mount-eva-shares.sh

# Install Python development environment
echo -e "${BLUE}Setting up Python environment...${NC}"
python3 -m pip install --user pipx
python3 -m pipx ensurepath
export PATH="$PATH:~/.local/bin"

# Install Python tools
pipx install poetry
pipx install black
pipx install ruff
pipx install mypy

# Install Node.js tools
echo -e "${BLUE}Installing Node.js tools...${NC}"
npm install -g yarn pnpm typescript ts-node

# Clone MCP projects
echo -e "${BLUE}Cloning MCP projects...${NC}"
cd ~/projects/mcp

REPOS=(
    "mcp-orchestrator"
    "mcp-comfyui"
    "mcp-portainer-bridge"
    "mcp-time-precision"
    "mcp-memory-blockchain"
    "mcp-freshbooks-blockchain"
    "my-girl-friday"
    "mcp-matrix-knowledge"
)

for repo in "${REPOS[@]}"; do
    if [ ! -d "$repo" ]; then
        git clone "https://github.com/SamuraiBuddha/$repo.git"
    fi
done

# Create Claude Desktop configuration
echo -e "${BLUE}Creating Claude Desktop configuration...${NC}"
cat > ~/.config/claude/config.json << 'EOF'
{
  "mcpServers": {
    "orchestrator": {
      "command": "python",
      "args": ["-m", "mcp_orchestrator"],
      "cwd": "/home/$USER/projects/mcp/mcp-orchestrator"
    },
    "time-precision": {
      "command": "python",
      "args": ["-m", "mcp_time_precision"],
      "cwd": "/home/$USER/projects/mcp/mcp-time-precision"
    },
    "memory-blockchain": {
      "command": "python",
      "args": ["-m", "mcp_memory_blockchain"],
      "cwd": "/home/$USER/projects/mcp/mcp-memory-blockchain",
      "env": {
        "BLOCKCHAIN_NODE": "http://lilith:8545",
        "NEO4J_URI": "bolt://lilith:7687",
        "QDRANT_URL": "http://lilith:6333"
      }
    },
    "comfyui": {
      "command": "python",
      "args": ["-m", "mcp_comfyui"],
      "cwd": "/home/$USER/projects/mcp/mcp-comfyui",
      "env": {
        "COMFYUI_URL": "http://lilith:8188"
      }
    }
  }
}
EOF

# Create sync script for code deployment
echo -e "${BLUE}Creating deployment sync script...${NC}"
cat > ~/bin/sync-to-lilith.sh << 'EOF'
#!/bin/bash
# Sync local MCP development to Lilith

PROJECT=${1:-"all"}
LILITH="lilith:/shared/mcp-development"

if [ "$PROJECT" = "all" ]; then
    echo "Syncing all MCP projects to Lilith..."
    rsync -avz --delete ~/projects/mcp/ $LILITH/
else
    echo "Syncing $PROJECT to Lilith..."
    rsync -avz --delete ~/projects/mcp/$PROJECT/ $LILITH/$PROJECT/
fi

echo "Sync complete!"
EOF

chmod +x ~/bin/sync-to-lilith.sh

# Install blockchain development tools
echo -e "${BLUE}Installing blockchain tools...${NC}"

# Install Rust (for blockchain development)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

# Create SSH config for EVA nodes
echo -e "${BLUE}Configuring SSH for EVA nodes...${NC}"
mkdir -p ~/.ssh
cat >> ~/.ssh/config << EOF

Host lilith
    HostName $LILITH_IP
    User root
    Port 22

Host adam
    HostName $ADAM_IP
    User root
    Port 22

Host balthazar
    HostName 192.168.50.20
    User jordan
    Port 22

Host caspar
    HostName 192.168.50.21
    User jordan
    Port 9222
EOF

# Create startup script
echo -e "${BLUE}Creating startup script...${NC}"
cat > ~/bin/melchior-startup.sh << 'EOF'
#!/bin/bash
# Melchior startup script

echo "Starting Melchior development environment..."

# Mount network shares
~/bin/mount-eva-shares.sh

# Start Docker (if needed)
if ! docker ps &>/dev/null; then
    echo "Starting Docker..."
    sudo service docker start
fi

# Pull latest MCP updates
echo "Updating MCP projects..."
cd ~/projects/mcp
for dir in */; do
    echo "Updating $dir"
    (cd "$dir" && git pull)
done

# Check EVA network status
echo
echo "EVA Network Status:"
for host in lilith adam balthazar caspar; do
    if ping -c 1 -W 1 $host &>/dev/null; then
        echo -e "\033[0;32m✓ $host is online\033[0m"
    else
        echo -e "\033[0;31m✗ $host is offline\033[0m"
    fi
done

echo
echo "Melchior ready for development!"
EOF

chmod +x ~/bin/melchior-startup.sh

# Final setup
echo -e "${GREEN}Melchior setup complete!${NC}"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Restart WSL2 to apply memory settings: wsl --shutdown"
echo "2. Run startup script: ~/bin/melchior-startup.sh"
echo "3. Mount EVA shares: ~/bin/mount-eva-shares.sh"
echo "4. Sync code to Lilith: ~/bin/sync-to-lilith.sh [project]"
echo "5. Configure Claude Desktop with MCP paths"
echo
echo -e "${BLUE}Development environment ready!${NC}"
