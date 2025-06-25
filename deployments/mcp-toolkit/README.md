# MCP Toolkit Deployment

This directory contains deployment files for the MCP (Model Context Protocol) toolkit on the EVA network infrastructure.

## Overview

The MCP toolkit provides a unified interface for various AI and system management capabilities through Docker-based deployment.

## Contents

- **Docker Configuration**: Dockerfile and docker-compose.yml for container deployment
- **Environment Setup**: Scripts for setting up the environment
- **Claude Desktop Config**: Configuration for Claude Desktop integration
- **Migration Scripts**: Tools for migrating memory and data

## Quick Start

1. Copy `.env.example` to `.env` and configure:
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

2. Run the setup script:
   ```bash
   ./setup.sh
   ```

3. Deploy with Docker Compose:
   ```bash
   docker-compose up -d
   ```

## Integration with EVA Network

This deployment is designed to work with the EVA network infrastructure, particularly on the Lilith NAS system.

---

> **Note**: This content was migrated from the `mcp-toolkit-deployment` repository as part of the infrastructure consolidation effort.
