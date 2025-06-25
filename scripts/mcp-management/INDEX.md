# MCP Management Scripts

This directory contains scripts for managing MCP (Model Context Protocol) servers across the EVA network infrastructure.

## Scripts

### Testing and Connectivity
- `test-mcp-connection.sh` - Test MCP server connectivity
- `Test-MCPConnectivity.ps1` - Windows version for testing MCP connections

### Deployment
- `deploy-mcp-servers.sh` - Deploy MCP servers to NAS
- `deploy-mcp-terramaster.sh` - Terramaster-specific MCP deployment
- `mcp-manager.sh` - General MCP management utility

### Terramaster Client Configuration
- `Configure-TerramasterMCP-Client.ps1` - Configure Windows clients to connect to Terramaster MCP servers

## Usage

### Test Connection
```bash
# Linux/NAS
./test-mcp-connection.sh

# Windows
.\Test-MCPConnectivity.ps1
```

### Deploy MCP Servers
```bash
# Deploy to NAS
./deploy-mcp-servers.sh

# Terramaster-specific deployment
./deploy-mcp-terramaster.sh
```

### Manage MCP Services
```bash
# Start all MCPs
./mcp-manager.sh start

# Stop all MCPs
./mcp-manager.sh stop

# Check status
./mcp-manager.sh status
```

## Prerequisites
- Docker installed on target system
- SSH access to NAS (for remote deployment)
- Appropriate network permissions
- MCP orchestrator deployed (for proxy mode)
