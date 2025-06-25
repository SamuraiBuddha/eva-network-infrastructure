# Windows Deployment Scripts

This directory contains scripts for deploying and configuring MAGI nodes on Windows systems.

## Scripts

### Deployment and Configuration
- `Deploy-Magi.ps1` - Main deployment script for MAGI Windows nodes
- `Configure-TerramasterMCP-Client.ps1` - Configure Windows client to connect to Terramaster MCP servers
- `Setup-CORTEX-Integration.ps1` - Integrate with CORTEX AI orchestration system

### System Management
- `Manage-Drivers.ps1` - Manage and install required drivers for Windows MAGI nodes

## Usage

### Initial Deployment
```powershell
# Deploy MAGI node
.\Deploy-Magi.ps1 -NodeName "Melchior" -NodeType "GPU"

# Configure Terramaster connection
.\Configure-TerramasterMCP-Client.ps1 -NasIP "192.168.50.10" -NasUser "samuraibuddha"
```

### CORTEX Integration
```powershell
# Set up CORTEX integration
.\Setup-CORTEX-Integration.ps1 -CortexServer "192.168.50.10"
```

### Driver Management
```powershell
# Check and install drivers
.\Manage-Drivers.ps1 -Action "Install" -DriverType "GPU"
```

## Prerequisites
- Windows 10/11 or Windows Server 2019+
- PowerShell 5.0 or higher
- Administrator privileges
- Docker Desktop (for container support)
- Network access to EVA infrastructure

## Node Types
- **GPU**: Nodes with dedicated GPU for AI workloads (Melchior, Caspar, Balthazar)
- **Storage**: NAS nodes for centralized storage (Lilith, Adam)
- **Bridge**: Nodes that bridge between different network segments
