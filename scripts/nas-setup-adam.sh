#!/bin/bash

# Adam (Flashstor 12 Pro Gen1) Setup Script  
# Business Storage NAS
# Intel Celeron N5105, 32GB DDR4, 4x2TB M.2 NVMe

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}=== Adam NAS Setup ===${NC}"
echo -e "${PURPLE}Business Storage Server${NC}"
echo

# System Configuration
HOSTNAME="adam"
IP_ADDRESS="192.168.50.11"
LILITH_IP="192.168.50.10"
DISKS=("/dev/nvme0n1" "/dev/nvme1n1" "/dev/nvme2n1" "/dev/nvme3n1")

# Business encryption passwords (prompt for these in production!)
read -sp "Enter encryption password for business data: " BUSINESS_PASS
echo
read -sp "Confirm encryption password: " BUSINESS_PASS_CONFIRM
echo

if [[ "$BUSINESS_PASS" != "$BUSINESS_PASS_CONFIRM" ]]; then
    echo -e "${RED}Passwords do not match!${NC}"
    exit 1
fi

# Update system
echo -e "${BLUE}Updating system packages...${NC}"
apt-get update && apt-get upgrade -y

# Install required packages
echo -e "${BLUE}Installing required packages...${NC}"
apt-get install -y \
    zfs-dkms zfsutils-linux \
    docker.io docker-compose \
    samba samba-common-bin \
    nfs-common \
    prometheus-node-exporter \
    smartmontools \
    rsync duplicity \
    htop iotop \
    git curl wget

# Configure hostname
echo -e "${BLUE}Setting hostname...${NC}"
hostnamectl set-hostname $HOSTNAME
echo "$IP_ADDRESS $HOSTNAME" >> /etc/hosts
echo "$LILITH_IP lilith" >> /etc/hosts

# Create encrypted ZFS pool for business data
echo -e "${BLUE}Creating encrypted ZFS pool...${NC}"

# Create RAIDZ1 pool with encryption
echo "$BUSINESS_PASS" | zpool create -f -o ashift=12 \
    -O compression=lz4 \
    -O atime=off \
    -O xattr=sa \
    -O normalization=formD \
    -O encryption=aes-256-gcm \
    -O keylocation=prompt \
    -O keyformat=passphrase \
    business-pool raidz1 ${DISKS[0]} ${DISKS[1]} ${DISKS[2]} ${DISKS[3]}

# Create business datasets
echo -e "${BLUE}Creating business datasets...${NC}"
zfs create business-pool/accounting
zfs create business-pool/clients
zfs create business-pool/legal
zfs create business-pool/hr
zfs create business-pool/archive

# Set mount points
zfs set mountpoint=/business/accounting business-pool/accounting
zfs set mountpoint=/business/clients business-pool/clients
zfs set mountpoint=/business/legal business-pool/legal
zfs set mountpoint=/business/hr business-pool/hr
zfs set mountpoint=/business/archive business-pool/archive

# Configure Samba for business shares
echo -e "${BLUE}Configuring Samba shares...${NC}"

# Backup original config
cp /etc/samba/smb.conf /etc/samba/smb.conf.backup

# Create Samba configuration
cat > /etc/samba/smb.conf << EOF
[global]
    workgroup = WORKGROUP
    server string = Adam Business Storage
    security = user
    map to guest = Bad User
    log file = /var/log/samba/%m.log
    max log size = 1000
    
    # Performance tuning
    socket options = TCP_NODELAY IPTOS_LOWDELAY
    read raw = yes
    write raw = yes
    oplocks = yes
    max xmit = 65535
    dead time = 15
    getwd cache = yes
    
    # Security
    server min protocol = SMB3
    server smb encrypt = required

[Accounting]
    path = /business/accounting
    browseable = yes
    read only = no
    create mask = 0660
    directory mask = 0770
    valid users = @accounting
    force group = accounting

[Clients]
    path = /business/clients
    browseable = yes
    read only = no
    create mask = 0660
    directory mask = 0770
    valid users = @business
    force group = business

[Legal]
    path = /business/legal
    browseable = yes
    read only = no
    create mask = 0660
    directory mask = 0770
    valid users = @legal
    force group = legal

[HR]
    path = /business/hr
    browseable = no
    read only = no
    create mask = 0600
    directory mask = 0700
    valid users = @hr
    force group = hr
EOF

# Create groups and set permissions
groupadd -f accounting
groupadd -f business
groupadd -f legal
groupadd -f hr

chown -R root:accounting /business/accounting
chown -R root:business /business/clients
chown -R root:legal /business/legal
chown -R root:hr /business/hr

chmod 2770 /business/accounting
chmod 2770 /business/clients
chmod 2770 /business/legal
chmod 2700 /business/hr

# Restart Samba
systemctl enable smb nmb
systemctl restart smb nmb

# Mount Lilith's backup share
echo -e "${BLUE}Setting up backup mount...${NC}"
mkdir -p /mnt/lilith-backup
echo "$LILITH_IP:/backups /mnt/lilith-backup nfs defaults,_netdev 0 0" >> /etc/fstab
mount /mnt/lilith-backup

# Create backup scripts
echo -e "${BLUE}Creating backup scripts...${NC}"
mkdir -p /opt/adam/scripts

cat > /opt/adam/scripts/backup-business.sh << 'EOF'
#!/bin/bash
# Business data backup script

BACKUP_DIR="/mnt/lilith-backup/adam"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/adam-backup.log"

echo "[$DATE] Starting business backup" >> $LOG_FILE

# Create ZFS snapshots
for dataset in accounting clients legal hr; do
    zfs snapshot business-pool/${dataset}@backup-${DATE}
    echo "[$DATE] Created snapshot for ${dataset}" >> $LOG_FILE
done

# Sync to Lilith
for dataset in accounting clients legal hr; do
    rsync -avz --delete \
        /business/${dataset}/ \
        ${BACKUP_DIR}/${dataset}/ \
        >> $LOG_FILE 2>&1
done

# Clean old snapshots (keep last 7 days)
for dataset in accounting clients legal hr; do
    zfs list -t snapshot -o name -s creation | \
        grep "business-pool/${dataset}@backup-" | \
        head -n -7 | \
        xargs -n1 zfs destroy
done

echo "[$DATE] Backup complete" >> $LOG_FILE
EOF

chmod +x /opt/adam/scripts/backup-business.sh

# Create cron job for automated backups
echo "0 2 * * * /opt/adam/scripts/backup-business.sh" | crontab -

# Docker configuration
echo -e "${BLUE}Configuring Docker...${NC}"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
    "data-root": "/var/lib/docker",
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF

systemctl restart docker

# Create docker-compose for business services
mkdir -p /opt/adam
cat > /opt/adam/docker-compose.yml << 'EOF'
version: '3.8'

services:
  freshbooks-mcp:
    image: samuraibuddha/mcp-freshbooks-blockchain:latest
    container_name: freshbooks-mcp
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - /business/accounting/freshbooks:/data
    environment:
      - FRESHBOOKS_API_KEY=${FRESHBOOKS_API_KEY}
      - FRESHBOOKS_API_SECRET=${FRESHBOOKS_API_SECRET}
      - BLOCKCHAIN_NODE=http://lilith:8545

  backup-validator:
    image: samuraibuddha/backup-validator:latest
    container_name: backup-validator
    restart: unless-stopped
    volumes:
      - /business:/business:ro
      - /var/log:/logs
    environment:
      - SCHEDULE="0 3 * * *"  # Daily at 3 AM
EOF

# Configure firewall
echo -e "${BLUE}Configuring firewall...${NC}"
ufw allow from 192.168.50.0/24 to any port 22
ufw allow from 192.168.50.0/24 to any port 445   # SMB
ufw allow from 192.168.50.0/24 to any port 139   # NetBIOS
ufw allow from 192.168.50.0/24 to any port 8080  # Freshbooks MCP
ufw --force enable

# Create ZFS unlock script for boot
echo -e "${BLUE}Creating boot unlock script...${NC}"
cat > /usr/local/bin/unlock-business-pool.sh << 'EOF'
#!/bin/bash
echo -n "Enter business pool password: "
read -s password
echo
echo "$password" | zfs load-key business-pool
zfs mount -a
EOF

chmod +x /usr/local/bin/unlock-business-pool.sh

# Final setup
echo -e "${GREEN}Adam setup complete!${NC}"
echo
echo -e "${YELLOW}Important notes:${NC}"
echo "1. Business pool is ENCRYPTED - password required on reboot"
echo "2. Run '/usr/local/bin/unlock-business-pool.sh' after reboot"
echo "3. Add users to appropriate groups (accounting, business, legal, hr)"
echo "4. Set Samba passwords with: smbpasswd -a username"
echo "5. Configure FRESHBOOKS_API_KEY and FRESHBOOKS_API_SECRET in .env"
echo
echo -e "${BLUE}Pool Status:${NC}"
zpool status
echo
echo -e "${BLUE}Business Datasets:${NC}"
zfs list -r business-pool
