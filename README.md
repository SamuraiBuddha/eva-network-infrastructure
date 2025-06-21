# EVA Network Infrastructure 🌌

Complete infrastructure automation for the EVA Network - a distributed computing cluster combining Evangelion-themed NAS units (Lilith & Adam) with MAGI compute nodes (Melchior, Balthazar, Caspar).

## Overview

The EVA Network is a comprehensive infrastructure deployment that creates a unified AI development and business storage environment across 5 nodes:

- **Lilith** (Terramaster F8 SSD) - Primary AI/Development NAS
- **Adam** (Flashstor 12 Pro) - Encrypted Business Storage
- **Melchior** - WSL2 Development Workstation
- **Balthazar** - GPU Compute Node (with temperature monitoring)
- **Caspar** - Windows Bridge Node (SSH on port 9222)

## Features

- 🔧 **Automated Deployment** - Single master script orchestrates all nodes
- 💾 **Hybrid ZFS Storage** - Fast mirrors + bulk RAIDZ1 for optimal performance
- ⛓ **Blockchain Integration** - Distributed validators on each node
- 🎮 **GPU Support** - NVIDIA container runtime for AI workloads
- 🌡️ **Temperature Monitoring** - Critical for Balthazar after pump replacement
- 🔒 **Business Encryption** - ZFS native encryption for sensitive data
- 📡 **Cross-Node NFS** - Seamless file sharing across the network
- 📈 **Real-time Dashboard** - Matrix-themed monitoring interface

## Quick Start

### Prerequisites

1. All nodes on same network (192.168.50.0/24)
2. SSH key authentication configured
3. Ubuntu Server 22.04 on NAS units
4. WSL2 on Windows workstation
5. Static IP assignments ready

### Deployment

1. Clone this repository on Melchior:
```bash
git clone https://github.com/SamuraiBuddha/eva-network-infrastructure.git
cd eva-network-infrastructure
chmod +x scripts/*.sh
```

2. Run the master deployment script:
```bash
./scripts/eva-network-master-deploy.sh
```

Or use the GUI interface:
```bash
./scripts/eva-network-master-deploy.sh --gui
```

3. Access the dashboard:
```bash
firefox http://lilith:8080/eva-dashboard.html
```

## Network Architecture

```
192.168.50.0/24 Network
├── .1   - Router (managed by Tachikoma MCP)
├── .10  - Lilith (Primary NAS)
├── .11  - Adam (Business NAS)
├── .20  - Balthazar (GPU Node)
├── .21  - Caspar (Bridge Node)
└── .30  - Melchior (Workstation)
```

## Storage Layout

### Lilith (24TB raw)
- **fast-pool** (4TB mirror) - Docker, databases, cache
- **bulk-pool** (12TB RAIDZ1) - Shared storage, backups, AI models

### Adam (8TB raw)
- **business-pool** (6TB RAIDZ1 encrypted) - Accounting, clients, legal, HR

## Services

### Core Services (Lilith)
- Portainer CE - Container management
- Neo4j Enterprise - Graph database
- Qdrant - Vector database
- Redis - Cache layer
- Blockchain Validator - Consensus node
- Prometheus/Grafana - Monitoring

### Business Services (Adam)
- Samba - Windows file sharing
- Freshbooks MCP - Blockchain accounting
- Automated backups to Lilith

### GPU Services (Balthazar)
- ComfyUI - AI image generation
- Celery Worker - Distributed AI tasks
- Temperature monitoring (critical!)

### Bridge Services (Caspar)
- My Girl Friday - Outlook integration
- Windows file bridge
- Portainer agent

## Important Notes

### Security
- Adam's business data is encrypted - password required on boot
- Firewall rules restrict access to local network only
- SSH key authentication required
- SMB requires encryption (SMB3)

### Balthazar Temperature Warning
⚠️ **CRITICAL**: Water pump was recently replaced! Monitor temperatures closely:
- CPU warning: 75°C, critical: 85°C
- GPU warning: 80°C, critical: 90°C
- Automatic throttling engages at critical temps
- Check `/var/log/balthazar-temps.log` regularly

### Caspar SSH Access
SSH runs on **port 9222**, not 22! Both usernames work:
```bash
ssh -p 9222 jordan@caspar
ssh -p 9222 SamuraiBuddha@caspar
```

## Maintenance

### Daily Tasks
- Check Balthazar temperatures
- Verify backup completion on Adam
- Monitor blockchain sync status

### Weekly Tasks
- Review ZFS snapshot schedule
- Clean old Docker images
- Check GPU utilization trends
- Verify all services running

### Monthly Tasks
- Test disaster recovery
- Update all containers
- Review security logs
- ZFS scrub on all pools

## Troubleshooting

### Node Unreachable
1. Check static IP assignment
2. Verify firewall rules
3. Test with: `ping <node-ip>`
4. Check SSH service status

### Service Not Starting
1. Check Docker logs: `docker logs <container>`
2. Verify volume mounts exist
3. Check port conflicts
4. Review systemd logs: `journalctl -u <service>`

### Temperature Issues (Balthazar)
1. Check pump operation
2. Verify fan speeds
3. Review temp logs
4. Consider manual throttling

## Router Management

This infrastructure includes the Tachikoma Router MCP for automated network configuration. See [mcp-tachikoma-router](https://github.com/SamuraiBuddha/mcp-tachikoma-router) for details.

## Related Projects

- [mcp-orchestrator](https://github.com/SamuraiBuddha/mcp-orchestrator) - Tool routing
- [mcp-memory-blockchain](https://github.com/SamuraiBuddha/mcp-memory-blockchain) - Distributed memory
- [mcp-comfyui](https://github.com/SamuraiBuddha/mcp-comfyui) - AI image generation
- [my-girl-friday](https://github.com/SamuraiBuddha/my-girl-friday) - Outlook integration

## Credits

Built with ❤️ by Jordan & Claude, bringing Tony Stark-level infrastructure to life with Evangelion style.

---

*"The EVA Network - Where Angels fear to compute"* 🤖
