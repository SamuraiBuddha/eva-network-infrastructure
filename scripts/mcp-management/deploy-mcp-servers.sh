#!/bin/bash
# Deploy all MCP servers on Terramaster NAS
# Run this script on your NAS via SSH

set -e

echo "🚀 Deploying MCP Servers on Terramaster NAS..."

# Check if running on NAS
if [ ! -d "/Volume1" ]; then
    echo "❌ Error: This script should be run on the Terramaster NAS"
    exit 1
fi

# Create directories
echo "📁 Creating directories..."
mkdir -p /Volume1/docker/mcp-workspace
mkdir -p /Volume1/docker/mcp-logs
chmod 755 /Volume1/docker/mcp-workspace

# Load environment variables
if [ -f ".env" ]; then
    echo "📋 Loading environment variables..."
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "⚠️  Warning: .env file not found. Using defaults."
fi

# Stop existing containers
echo "🛑 Stopping existing MCP containers..."
docker-compose down 2>/dev/null || true

# Pull latest images
echo "📥 Pulling latest images..."
docker-compose pull

# Start services
echo "🚀 Starting MCP services..."
docker-compose up -d

# Wait for containers to start
echo "⏳ Waiting for containers to initialize..."
sleep 10

# Show status
echo "\n✅ MCP Servers deployed!"
echo "\n📊 Container Status:"
docker-compose ps

# Test basic functionality
echo "\n🧪 Testing MCP Time Server..."
if docker exec mcp-time python /app/server.py --version 2>/dev/null; then
    echo "✅ MCP Time Server is responding"
else
    echo "⚠️  MCP Time Server test failed - this is normal if the server doesn't support --version"
fi

# Create test script
cat > /Volume1/docker/test-mcp.sh << 'EOF'
#!/bin/bash
# Test MCP server communication
MCP_SERVER=${1:-mcp-time}
echo "Testing $MCP_SERVER..."
echo '{"jsonrpc": "2.0", "method": "initialize", "params": {"capabilities": {}}, "id": 1}' | \
docker exec -i $MCP_SERVER python /app/server.py 2>&1 | head -n 50
EOF

chmod +x /Volume1/docker/test-mcp.sh

echo "\n📝 Next Steps:"
echo "1. Configure your MAGI machines with SSH access"
echo "2. Update claude_desktop_config.json on each machine"
echo "3. Test with: /Volume1/docker/test-mcp.sh [container-name]"
echo "\n📊 Monitor with:"
echo "   - Logs: docker logs mcp-[service]"
echo "   - Status: docker ps"
echo "   - Portainer: http://$(hostname -I | awk '{print $1}'):9000"
echo "\n✨ MCP deployment complete!"