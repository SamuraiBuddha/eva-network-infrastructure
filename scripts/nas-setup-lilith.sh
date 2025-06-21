#!/bin/bash

# Lilith (Terramaster F8 SSD) Setup Script
# Primary AI/Development NAS
# Intel i3 N305, 16GB DDR5, 6x4TB M.2 NVMe

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}=== Lilith NAS Setup ===${NC}"
echo -e "${PURPLE}Primary AI/Development Server${NC}"
echo

# System Configuration
HOSTNAME="lilith"
IP_ADDRESS="192.168.50.10"
DISKS=("/dev/nvme0n1" "/dev/nvme1n1" "/dev/nvme2n1" "/dev/nvme3n1" "/dev/nvme4n1" "/dev/nvme5n1")

# Update system
echo -e "${BLUE}Updating system packages...${NC}"
apt-get update && apt-get upgrade -y

# Install required packages
echo -e "${BLUE}Installing required packages...${NC}"
apt-get install -y \
    zfs-dkms zfsutils-linux \
    docker.io docker-compose \
    nfs-kernel-server \
    prometheus-node-exporter \
    smartmontools \
    htop iotop \
    git curl wget \
    python3-pip

# Configure hostname
echo -e "${BLUE}Setting hostname...${NC}"
hostnamectl set-hostname $HOSTNAME
echo "$IP_ADDRESS $HOSTNAME" >> /etc/hosts

# Create ZFS pools
echo -e "${BLUE}Creating ZFS pools...${NC}"

# Create mirror pool for fast storage (2 disks)
zpool create -f -o ashift=12 \
    -O compression=lz4 \
    -O atime=off \
    -O xattr=sa \
    -O normalization=formD \
    fast-pool mirror ${DISKS[0]} ${DISKS[1]}

# Create RAIDZ1 pool for bulk storage (4 disks)
zpool create -f -o ashift=12 \
    -O compression=lz4 \
    -O atime=off \
    -O xattr=sa \
    -O normalization=formD \
    bulk-pool raidz1 ${DISKS[2]} ${DISKS[3]} ${DISKS[4]} ${DISKS[5]}

# Create datasets
echo -e "${BLUE}Creating ZFS datasets...${NC}"

# Fast pool datasets
zfs create fast-pool/docker
zfs create fast-pool/databases
zfs create fast-pool/cache

# Bulk pool datasets  
zfs create bulk-pool/shared
zfs create bulk-pool/backups
zfs create bulk-pool/media
zfs create bulk-pool/models  # For AI models

# Set mount points
zfs set mountpoint=/docker fast-pool/docker
zfs set mountpoint=/databases fast-pool/databases
zfs set mountpoint=/cache fast-pool/cache
zfs set mountpoint=/shared bulk-pool/shared
zfs set mountpoint=/backups bulk-pool/backups
zfs set mountpoint=/media bulk-pool/media
zfs set mountpoint=/models bulk-pool/models

# Configure NFS exports
echo -e "${BLUE}Configuring NFS exports...${NC}"
cat >> /etc/exports << EOF
/shared 192.168.50.0/24(rw,sync,no_subtree_check,no_root_squash)
/models 192.168.50.0/24(ro,sync,no_subtree_check)
/backups 192.168.50.11(rw,sync,no_subtree_check)  # Adam only
EOF

exportfs -ra
systemctl enable nfs-kernel-server
systemctl start nfs-kernel-server

# Docker configuration
echo -e "${BLUE}Configuring Docker...${NC}"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
    "data-root": "/docker",
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF

systemctl restart docker

# Create EVA network infrastructure
echo -e "${BLUE}Setting up EVA infrastructure...${NC}"
mkdir -p /opt/eva/{config,data,scripts}

# Create docker-compose.yml
cat > /opt/eva/docker-compose.yml << 'EOF'
version: '3.8'

networks:
  eva-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /docker/portainer:/data
    networks:
      eva-net:
        ipv4_address: 172.20.0.10

  neo4j:
    image: neo4j:5-enterprise
    container_name: neo4j
    restart: unless-stopped
    ports:
      - "7474:7474"
      - "7687:7687"
    volumes:
      - /databases/neo4j/data:/data
      - /databases/neo4j/logs:/logs
      - /databases/neo4j/import:/import
      - /databases/neo4j/plugins:/plugins
    environment:
      - NEO4J_AUTH=neo4j/lilith-secure-password
      - NEO4J_ACCEPT_LICENSE_AGREEMENT=yes
      - NEO4J_server_memory_heap_initial__size=4G
      - NEO4J_server_memory_heap_max__size=4G
    networks:
      eva-net:
        ipv4_address: 172.20.0.11

  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    ports:
      - "6333:6333"
    volumes:
      - /databases/qdrant:/qdrant/storage
    networks:
      eva-net:
        ipv4_address: 172.20.0.12

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - /cache/redis:/data
    command: redis-server --appendonly yes
    networks:
      eva-net:
        ipv4_address: 172.20.0.13

  blockchain-validator:
    image: samuraibuddha/magi-blockchain:latest
    container_name: blockchain-validator
    restart: unless-stopped
    ports:
      - "30303:30303"  # P2P
      - "8545:8545"    # RPC
    volumes:
      - /docker/blockchain:/data
      - /opt/eva/config/validator.key:/keys/validator.key:ro
    environment:
      - NODE_NAME=lilith
      - VALIDATOR_KEY=/keys/validator.key
    networks:
      eva-net:
        ipv4_address: 172.20.0.14

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - /docker/prometheus:/prometheus
      - /opt/eva/config/prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    networks:
      eva-net:
        ipv4_address: 172.20.0.15

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - /docker/grafana:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=lilith-grafana
    networks:
      eva-net:
        ipv4_address: 172.20.0.16
EOF

# Create Prometheus configuration
cat > /opt/eva/config/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets:
        - 'lilith:9100'
        - 'adam:9100'
        - 'balthazar:9100'
        - 'caspar:9100'
  
  - job_name: 'docker'
    static_configs:
      - targets: ['172.20.0.1:9323']
EOF

# Install monitoring scripts
echo -e "${BLUE}Installing monitoring scripts...${NC}"
cat > /opt/eva/scripts/check_temps.sh << 'EOF'
#!/bin/bash
echo "=== System Temperatures ==="
sensors 2>/dev/null || echo "lm-sensors not installed"
echo
echo "=== NVMe Temperatures ==="
for disk in /dev/nvme*n1; do
    echo -n "$disk: "
    smartctl -a $disk | grep -i temp | head -1
done
EOF

chmod +x /opt/eva/scripts/check_temps.sh

# Create startup script
cat > /opt/eva/scripts/startup.sh << 'EOF'
#!/bin/bash
# EVA Network Startup Script

# Start monitoring
systemctl start prometheus-node-exporter

# Start Docker services
cd /opt/eva
docker-compose up -d

# Wait for services
sleep 10

# Check status
docker-compose ps
EOF

chmod +x /opt/eva/scripts/startup.sh

# Enable startup on boot
cat > /etc/systemd/system/eva-startup.service << EOF
[Unit]
Description=EVA Network Startup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/opt/eva/scripts/startup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable eva-startup.service

# Configure firewall
echo -e "${BLUE}Configuring firewall...${NC}"
ufw allow from 192.168.50.0/24 to any port 22
ufw allow from 192.168.50.0/24 to any port 2049  # NFS
ufw allow from 192.168.50.0/24 to any port 9000  # Portainer
ufw allow from 192.168.50.0/24 to any port 7474  # Neo4j
ufw allow from 192.168.50.0/24 to any port 6333  # Qdrant
ufw allow from 192.168.50.0/24 to any port 6379  # Redis
ufw allow 30303  # Blockchain P2P
ufw --force enable

# Final setup
echo -e "${GREEN}Lilith setup complete!${NC}"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy blockchain validator key to /opt/eva/config/validator.key"
echo "2. Start services with: cd /opt/eva && docker-compose up -d"
echo "3. Access Portainer at: https://$IP_ADDRESS:9000"
echo "4. Configure automated snapshots for ZFS pools"
echo
echo -e "${BLUE}Pool Status:${NC}"
zpool status
echo
echo -e "${BLUE}Dataset Layout:${NC}"
zfs list
