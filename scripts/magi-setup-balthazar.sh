#!/bin/bash

# Balthazar (GPU Node) Setup Script
# MAGI GPU Compute Node
# Recently fixed water pump, GPU-enabled

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}=== Balthazar GPU Node Setup ===${NC}"
echo -e "${PURPLE}MAGI Distributed Compute Node${NC}"
echo

# System Configuration
HOSTNAME="balthazar"
IP_ADDRESS="192.168.50.20"
LILITH_IP="192.168.50.10"

# Update system
echo -e "${BLUE}Updating system packages...${NC}"
sudo apt-get update && sudo apt-get upgrade -y

# Install required packages
echo -e "${BLUE}Installing required packages...${NC}"
sudo apt-get install -y \
    docker.io docker-compose \
    nvidia-container-toolkit \
    nfs-common \
    prometheus-node-exporter \
    lm-sensors fancontrol \
    htop nvtop \
    git curl wget \
    python3-pip

# Configure hostname
echo -e "${BLUE}Setting hostname...${NC}"
sudo hostnamectl set-hostname $HOSTNAME
echo "$IP_ADDRESS $HOSTNAME" | sudo tee -a /etc/hosts
echo "$LILITH_IP lilith" | sudo tee -a /etc/hosts

# Configure NVIDIA Docker
echo -e "${BLUE}Configuring NVIDIA Docker runtime...${NC}"
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Configure temperature monitoring
echo -e "${BLUE}Setting up temperature monitoring...${NC}"
sudo sensors-detect --auto

# Create temperature monitoring script
mkdir -p /opt/balthazar/scripts
cat > /opt/balthazar/scripts/monitor-temps.sh << 'EOF'
#!/bin/bash
# Temperature monitoring script - critical after pump replacement!

WARN_CPU_TEMP=75
CRIT_CPU_TEMP=85
WARN_GPU_TEMP=80
CRIT_GPU_TEMP=90

while true; do
    # CPU Temperature
    CPU_TEMP=$(sensors | grep "Package id 0:" | awk '{print $4}' | sed 's/+//g' | sed 's/°C//g')
    
    # GPU Temperature
    GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo "0")
    
    # Check CPU
    if (( $(echo "$CPU_TEMP > $CRIT_CPU_TEMP" | bc -l) )); then
        echo "CRITICAL: CPU temperature is ${CPU_TEMP}°C!" | wall
        # Emergency throttle
        echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    elif (( $(echo "$CPU_TEMP > $WARN_CPU_TEMP" | bc -l) )); then
        echo "WARNING: CPU temperature is ${CPU_TEMP}°C"
    fi
    
    # Check GPU
    if [ "$GPU_TEMP" != "0" ]; then
        if (( $(echo "$GPU_TEMP > $CRIT_GPU_TEMP" | bc -l) )); then
            echo "CRITICAL: GPU temperature is ${GPU_TEMP}°C!" | wall
            # Set GPU power limit
            nvidia-smi -pl 200
        elif (( $(echo "$GPU_TEMP > $WARN_GPU_TEMP" | bc -l) )); then
            echo "WARNING: GPU temperature is ${GPU_TEMP}°C"
        fi
    fi
    
    # Log to file
    echo "$(date): CPU=${CPU_TEMP}°C GPU=${GPU_TEMP}°C" >> /var/log/balthazar-temps.log
    
    sleep 30
done
EOF

chmod +x /opt/balthazar/scripts/monitor-temps.sh

# Create systemd service for temperature monitoring
cat > /etc/systemd/system/temp-monitor.service << EOF
[Unit]
Description=Temperature Monitoring Service
After=multi-user.target

[Service]
Type=simple
ExecStart=/opt/balthazar/scripts/monitor-temps.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable temp-monitor.service
sudo systemctl start temp-monitor.service

# Mount Lilith shares
echo -e "${BLUE}Setting up NFS mounts...${NC}"
sudo mkdir -p /mnt/lilith-shared
sudo mkdir -p /mnt/lilith-models

echo "$LILITH_IP:/shared /mnt/lilith-shared nfs defaults,_netdev 0 0" | sudo tee -a /etc/fstab
echo "$LILITH_IP:/models /mnt/lilith-models nfs defaults,_netdev,ro 0 0" | sudo tee -a /etc/fstab

sudo mount -a

# Create docker-compose for GPU services
echo -e "${BLUE}Creating GPU service configuration...${NC}"
mkdir -p /opt/balthazar

cat > /opt/balthazar/docker-compose.yml << 'EOF'
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
      - /opt/balthazar/blockchain:/data
      - /opt/balthazar/validator.key:/keys/validator.key:ro
    environment:
      - NODE_NAME=balthazar
      - VALIDATOR_KEY=/keys/validator.key
      - PEERS=enode://[lilith-enode]@lilith:30303

  comfyui:
    image: samuraibuddha/comfyui-nvidia:latest
    container_name: comfyui
    restart: unless-stopped
    runtime: nvidia
    ports:
      - "8188:8188"
    volumes:
      - /opt/balthazar/comfyui:/workspace
      - /mnt/lilith-models:/models:ro
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

  ai-worker:
    image: samuraibuddha/ai-celery-worker:latest
    container_name: ai-worker
    restart: unless-stopped
    runtime: nvidia
    volumes:
      - /mnt/lilith-shared/tasks:/tasks
      - /opt/balthazar/worker:/workspace
    environment:
      - CELERY_BROKER=redis://lilith:6379
      - NVIDIA_VISIBLE_DEVICES=all
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

  gpu-monitor:
    image: samuraibuddha/gpu-prometheus-exporter:latest
    container_name: gpu-monitor
    restart: unless-stopped
    runtime: nvidia
    ports:
      - "9835:9835"
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF

# Create GPU benchmark script
cat > /opt/balthazar/scripts/gpu-benchmark.sh << 'EOF'
#!/bin/bash
# GPU Benchmark Script

echo "Running GPU benchmark..."
echo "Current GPU status:"
nvidia-smi

echo -e "\nRunning compute benchmark..."
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi

echo -e "\nTesting AI inference..."
# Add your preferred benchmark here
EOF

chmod +x /opt/balthazar/scripts/gpu-benchmark.sh

# Configure firewall
echo -e "${BLUE}Configuring firewall...${NC}"
sudo ufw allow from 192.168.50.0/24 to any port 22
sudo ufw allow from 192.168.50.0/24 to any port 8188  # ComfyUI
sudo ufw allow from 192.168.50.0/24 to any port 9835  # GPU metrics
sudo ufw allow 30303  # Blockchain P2P
sudo ufw --force enable

# Create startup script
cat > /opt/balthazar/scripts/startup.sh << 'EOF'
#!/bin/bash
# Balthazar startup script

# Check temperatures first!
echo "Checking system temperatures..."
sensors

if nvidia-smi &>/dev/null; then
    echo "GPU Status:"
    nvidia-smi
fi

# Start services
cd /opt/balthazar
docker-compose up -d

echo "Balthazar GPU node ready!"
EOF

chmod +x /opt/balthazar/scripts/startup.sh

# Final setup
echo -e "${GREEN}Balthazar setup complete!${NC}"
echo
echo -e "${YELLOW}CRITICAL REMINDERS:${NC}"
echo -e "${RED}1. MONITOR TEMPERATURES - Water pump was recently replaced!${NC}"
echo -e "${RED}2. Check /var/log/balthazar-temps.log regularly${NC}"
echo -e "${RED}3. Emergency CPU throttle activates at 85°C${NC}"
echo -e "${RED}4. Emergency GPU throttle activates at 90°C${NC}"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy validator key to /opt/balthazar/validator.key"
echo "2. Test GPU: nvidia-smi"
echo "3. Run benchmark: /opt/balthazar/scripts/gpu-benchmark.sh"
echo "4. Start services: cd /opt/balthazar && docker-compose up -d"
echo
echo -e "${BLUE}Current temperatures:${NC}"
sensors | grep -E "Core|Package|gpu"
