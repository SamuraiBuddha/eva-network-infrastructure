#!/bin/bash
# Test MCP server connections
# Usage: ./test-mcp-connection.sh [server-name]

SERVER=${1:-mcp-time}

echo "🧪 Testing MCP Server: $SERVER"
echo "============================="

# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^$SERVER"; then
    echo "❌ Container $SERVER not found"
    echo "Available containers:"
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep mcp-
    exit 1
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^$SERVER"; then
    echo "⚠️  Container $SERVER is not running"
    echo "Starting container..."
    docker start $SERVER
    sleep 5
fi

# Get the command from container labels
CMD=$(docker inspect $SERVER --format '{{index .Config.Labels "mcp.command"}}' 2>/dev/null)
if [ -z "$CMD" ]; then
    # Default commands based on server type
    case $SERVER in
        mcp-github|mcp-node-sandbox)
            CMD="node /app/server.js"
            ;;
        *)
            CMD="python /app/server.py"
            ;;
    esac
fi

echo "Command: $CMD"
echo ""

# Test 1: Initialize request
echo "📋 Test 1: Sending initialize request..."
RESPONSE=$(echo '{"jsonrpc": "2.0", "method": "initialize", "params": {"capabilities": {}}, "id": 1}' | \
    docker exec -i $SERVER $CMD 2>&1 | head -n 100)

if echo "$RESPONSE" | grep -q '"result"'; then
    echo "✅ Initialize successful"
    echo "Response preview:"
    echo "$RESPONSE" | head -n 20
else
    echo "❌ Initialize failed"
    echo "Error output:"
    echo "$RESPONSE"
    exit 1
fi

# Test 2: Server-specific test
echo ""
echo "📋 Test 2: Server-specific test..."

case $SERVER in
    mcp-time)
        TEST_METHOD="get_current_time"
        TEST_PARAMS='{"timezone": "UTC"}'
        ;;
    mcp-docker)
        TEST_METHOD="docker_ps"
        TEST_PARAMS='{}'
        ;;
    mcp-filesystem)
        TEST_METHOD="list_directory"
        TEST_PARAMS='{"path": "/workspace"}'
        ;;
    *)
        echo "⚠️  No specific test for $SERVER"
        exit 0
        ;;
esac

if [ ! -z "$TEST_METHOD" ]; then
    echo "Testing method: $TEST_METHOD"
    RESPONSE=$(echo "{\"jsonrpc\": \"2.0\", \"method\": \"$TEST_METHOD\", \"params\": $TEST_PARAMS, \"id\": 2}" | \
        docker exec -i $SERVER $CMD 2>&1 | head -n 100)
    
    if echo "$RESPONSE" | grep -q '"result"'; then
        echo "✅ Method call successful"
        echo "Response:"
        echo "$RESPONSE" | grep -A10 '"result"' | head -n 10
    else
        echo "⚠️  Method call failed (this may be normal)"
        echo "Response:"
        echo "$RESPONSE" | head -n 20
    fi
fi

echo ""
echo "✅ Connection test complete!"
