#!/bin/bash
# Deploy MCP Stack on Terramaster F8 Plus
# This script sets up centralized MCP services for all Claude Desktop instances

set -e

echo "🚀 Terramaster MCP Stack Deployment"
echo "===================================="

# Configuration
DOCKER_BASE="/Volume1/docker/mcp"
COMPOSE_VERSION="2.23.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Check if running on Terramaster
if [ ! -f /etc/terramaster-release ]; then
    echo -e "${YELLOW}Warning: This doesn't appear to be a Terramaster NAS${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Function to check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker is not installed${NC}"
        echo "Please install Docker from the TOS App Center first"
        exit 1
    fi
    echo -e "${GREEN}✓ Docker found$(docker --version)${NC}"
}

# Function to install docker-compose if needed
install_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}Installing docker-compose...${NC}"
        curl -L "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}✓ docker-compose installed${NC}"
    else
        echo -e "${GREEN}✓ docker-compose found$(docker-compose --version)${NC}"
    fi
}

# Create directory structure
create_directories() {
    echo -e "${YELLOW}Creating directory structure...${NC}"
    
    mkdir -p "$DOCKER_BASE"/{configs,scripts,data/{shared,memory}}
    mkdir -p "$DOCKER_BASE"/services/{postgres,redis,neo4j,influxdb}
    mkdir -p "$DOCKER_BASE"/logs/{postgres,redis,neo4j,influxdb,manager}
    
    # Set permissions
    chmod -R 755 "$DOCKER_BASE"
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

# Create .env file
create_env_file() {
    echo -e "${YELLOW}Creating environment configuration...${NC}"
    
    # Generate secure passwords
    POSTGRES_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    REDIS_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    NEO4J_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    INFLUX_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    cat > "$DOCKER_BASE/.env" << EOF
# MCP Stack Environment Configuration
# Generated on $(date)

# Database Passwords
POSTGRES_PASSWORD=${POSTGRES_PASS}
REDIS_PASSWORD=${REDIS_PASS}
NEO4J_PASSWORD=${NEO4J_PASS}
INFLUXDB_PASSWORD=${INFLUX_PASS}

# MCP Configuration
MCP_HOST=$(hostname)
MCP_PORT=3100

# Resource Limits
MEMORY_LIMIT=16G
CPU_LIMIT=8

# Network Configuration
SUBNET=172.30.0.0/16
GATEWAY=172.30.0.1

# Data Paths
DATA_PATH=/Volume1/docker/mcp
EOF
    
    chmod 600 "$DOCKER_BASE/.env"
    echo -e "${GREEN}✓ Environment file created${NC}"
    echo -e "${YELLOW}Passwords saved to: $DOCKER_BASE/.env${NC}"
}

# Create docker-compose.yml
create_compose_file() {
    echo -e "${YELLOW}Creating docker-compose configuration...${NC}"
    
    cat > "$DOCKER_BASE/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  # PostgreSQL for persistent storage
  mcp-postgres:
    image: postgres:16-alpine
    container_name: mcp-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: mcp
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: mcp_db
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_PATH}/services/postgres:/var/lib/postgresql/data
      - ${DATA_PATH}/logs/postgres:/var/log/postgresql
    ports:
      - "5432:5432"
    networks:
      - mcp_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U mcp"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G

  # Redis for caching and pub/sub
  mcp-redis:
    image: redis:7-alpine
    container_name: mcp-redis
    restart: unless-stopped
    command: >
      redis-server 
      --appendonly yes 
      --requirepass ${REDIS_PASSWORD}
      --maxmemory 2gb
      --maxmemory-policy allkeys-lru
    volumes:
      - ${DATA_PATH}/services/redis:/data
    ports:
      - "6379:6379"
    networks:
      - mcp_network
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 2G

  # Neo4j for knowledge graph
  mcp-neo4j:
    image: neo4j:5-community
    container_name: mcp-neo4j
    restart: unless-stopped
    environment:
      NEO4J_AUTH: neo4j/${NEO4J_PASSWORD}
      NEO4J_PLUGINS: '["graph-data-science", "apoc"]'
      NEO4J_dbms_memory_pagecache_size: 2G
      NEO4J_dbms_memory_heap_max__size: 2G
      NEO4J_dbms_memory_heap_initial__size: 1G
    volumes:
      - ${DATA_PATH}/services/neo4j/data:/data
      - ${DATA_PATH}/services/neo4j/logs:/logs
      - ${DATA_PATH}/services/neo4j/import:/var/lib/neo4j/import
      - ${DATA_PATH}/services/neo4j/plugins:/plugins
    ports:
      - "7474:7474"  # HTTP
      - "7687:7687"  # Bolt
    networks:
      - mcp_network
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G

  # InfluxDB for metrics (optional since you have it running natively)
  mcp-influxdb:
    image: influxdb:2
    container_name: mcp-influxdb
    restart: unless-stopped
    profiles: ["full"]  # Only starts with --profile full
    environment:
      DOCKER_INFLUXDB_INIT_MODE: setup
      DOCKER_INFLUXDB_INIT_USERNAME: admin
      DOCKER_INFLUXDB_INIT_PASSWORD: ${INFLUXDB_PASSWORD}
      DOCKER_INFLUXDB_INIT_ORG: mcp
      DOCKER_INFLUXDB_INIT_BUCKET: metrics
      DOCKER_INFLUXDB_INIT_RETENTION: 30d
      DOCKER_INFLUXDB_INIT_ADMIN_TOKEN: ${INFLUXDB_PASSWORD}
    volumes:
      - ${DATA_PATH}/services/influxdb/data:/var/lib/influxdb2
      - ${DATA_PATH}/services/influxdb/config:/etc/influxdb2
    ports:
      - "8087:8086"  # Different port to avoid conflict
    networks:
      - mcp_network
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 2G

networks:
  mcp_network:
    driver: bridge
    ipam:
      config:
        - subnet: ${SUBNET}
          gateway: ${GATEWAY}
EOF
    
    echo -e "${GREEN}✓ docker-compose.yml created${NC}"
}

# Create MCP server configurations
create_mcp_configs() {
    echo -e "${YELLOW}Creating MCP server configurations...${NC}"
    
    # MCP servers configuration
    cat > "$DOCKER_BASE/configs/mcp-servers.json" << 'EOF'
{
  "servers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/data/shared"],
      "env": {
        "MCP_ALLOWED_PATHS": "/data/shared"
      }
    },
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://mcp:${POSTGRES_PASSWORD}@mcp-postgres:5432/mcp_db"],
      "env": {}
    },
    "redis": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-redis"],
      "env": {
        "REDIS_URL": "redis://:${REDIS_PASSWORD}@mcp-redis:6379"
      }
    },
    "neo4j": {
      "command": "npx",
      "args": ["-y", "mcp-neo4j"],
      "env": {
        "NEO4J_URI": "bolt://mcp-neo4j:7687",
        "NEO4J_USERNAME": "neo4j",
        "NEO4J_PASSWORD": "${NEO4J_PASSWORD}"
      }
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "env": {
        "STORAGE_PATH": "/data/memory"
      }
    }
  }
}
EOF
    
    echo -e "${GREEN}✓ MCP configurations created${NC}"
}

# Create helper scripts
create_helper_scripts() {
    echo -e "${YELLOW}Creating helper scripts...${NC}"
    
    # Health check script
    cat > "$DOCKER_BASE/scripts/health-check.sh" << 'EOF'
#!/bin/bash
echo "🔍 MCP Services Health Check"
echo "============================="

# Container status
echo -e "\n📦 Container Status:"
docker ps --filter "name=mcp-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Disk usage
echo -e "\n💾 Disk Usage:"
du -sh /Volume1/docker/mcp/services/* | sort -h

# Memory usage
echo -e "\n🧠 Memory Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Test connections
echo -e "\n🔌 Service Connectivity:"
for port in 5432 6379 7474 7687; do
    if nc -z localhost $port 2>/dev/null; then
        echo "✓ Port $port is open"
    else
        echo "✗ Port $port is closed"
    fi
done
EOF
    
    # Backup script
    cat > "$DOCKER_BASE/scripts/backup.sh" << 'EOF'
#!/bin/bash
BACKUP_DIR="/Volume1/backups/mcp/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "🔄 Backing up MCP data to $BACKUP_DIR"

# Stop services
docker-compose -f /Volume1/docker/mcp/docker-compose.yml stop

# Backup data
tar -czf "$BACKUP_DIR/postgres.tar.gz" -C /Volume1/docker/mcp/services postgres
tar -czf "$BACKUP_DIR/neo4j.tar.gz" -C /Volume1/docker/mcp/services neo4j
tar -czf "$BACKUP_DIR/redis.tar.gz" -C /Volume1/docker/mcp/services redis
tar -czf "$BACKUP_DIR/configs.tar.gz" -C /Volume1/docker/mcp configs

# Copy env file (encrypted)
openssl enc -aes-256-cbc -salt -in /Volume1/docker/mcp/.env -out "$BACKUP_DIR/env.enc" -k "$1"

# Restart services
docker-compose -f /Volume1/docker/mcp/docker-compose.yml start

echo "✅ Backup complete!"
echo "Size: $(du -sh $BACKUP_DIR | cut -f1)"
EOF
    
    chmod +x "$DOCKER_BASE/scripts/"*.sh
    echo -e "${GREEN}✓ Helper scripts created${NC}"
}

# Configure firewall
configure_firewall() {
    echo -e "${YELLOW}Configuring firewall...${NC}"
    
    # Check if ufw is available
    if command -v ufw &> /dev/null; then
        # Allow MCP ports
        ufw allow 5432/tcp comment "MCP PostgreSQL"
        ufw allow 6379/tcp comment "MCP Redis"
        ufw allow 7474/tcp comment "MCP Neo4j HTTP"
        ufw allow 7687/tcp comment "MCP Neo4j Bolt"
        ufw allow 3100/tcp comment "MCP Manager"
        
        echo -e "${GREEN}✓ Firewall rules added${NC}"
    else
        echo -e "${YELLOW}UFW not found, please manually configure firewall${NC}"
    fi
}

# Deploy the stack
deploy_stack() {
    echo -e "${YELLOW}Deploying MCP stack...${NC}"
    
    cd "$DOCKER_BASE"
    
    # Create network
    docker network create mcp_network 2>/dev/null || true
    
    # Pull images
    echo "Pulling Docker images..."
    docker-compose pull
    
    # Start services
    echo "Starting services..."
    docker-compose up -d
    
    # Wait for services to be ready
    echo -e "${YELLOW}Waiting for services to start...${NC}"
    sleep 30
    
    # Check status
    docker-compose ps
    
    echo -e "${GREEN}✓ MCP stack deployed${NC}"
}

# Show summary
show_summary() {
    echo -e "\n${GREEN}🎉 Deployment Complete!${NC}"
    echo "====================="
    
    echo -e "\n📋 Service Endpoints:"
    echo "  PostgreSQL: $(hostname):5432"
    echo "  Redis: $(hostname):6379"
    echo "  Neo4j Browser: http://$(hostname):7474"
    echo "  Neo4j Bolt: $(hostname):7687"
    
    echo -e "\n🔑 Credentials saved to:"
    echo "  $DOCKER_BASE/.env"
    
    echo -e "\n📁 Data stored in:"
    echo "  $DOCKER_BASE/services/"
    
    echo -e "\n🛠️ Helper scripts:"
    echo "  Health check: $DOCKER_BASE/scripts/health-check.sh"
    echo "  Backup: $DOCKER_BASE/scripts/backup.sh"
    
    echo -e "\n📱 Configure Claude Desktop on each workstation:"
    echo "  1. Download the configuration script from GitHub"
    echo "  2. Run: .\Configure-TerramasterMCP-Client.ps1"
    
    echo -e "\n${YELLOW}⚠️  Important: Save the .env file contents securely!${NC}"
}

# Main execution
main() {
    echo "Starting deployment process..."
    
    check_docker
    install_docker_compose
    create_directories
    create_env_file
    create_compose_file
    create_mcp_configs
    create_helper_scripts
    configure_firewall
    deploy_stack
    show_summary
    
    # Run initial health check
    echo -e "\n${YELLOW}Running health check...${NC}"
    bash "$DOCKER_BASE/scripts/health-check.sh"
}

# Run main function
main "$@"