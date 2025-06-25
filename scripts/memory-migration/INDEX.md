# Memory Migration Scripts

This directory contains scripts for migrating Claude's memory from local Docker volumes to NAS-based Neo4j instances.

## Scripts

### PowerShell Scripts (Windows)
- `migrate-memory-mcp-protocol.ps1` - Uses MCP protocol for safe memory export/import
- `migrate-memory-simple.ps1` - Simple volume-based migration approach
- `migrate-memory-to-nas.ps1` - Direct migration to NAS with network path support
- `verify-memory-migration.ps1` - Verify migration success and data integrity

### Usage

1. **Before Migration**: Ensure Neo4j is running on the target NAS
2. **Choose Migration Method**:
   - MCP Protocol (recommended): `.\migrate-memory-mcp-protocol.ps1`
   - Simple Volume Copy: `.\migrate-memory-simple.ps1`
3. **Verify**: Always run `.\verify-memory-migration.ps1` after migration

### Prerequisites
- PowerShell 5.0 or higher
- Docker Desktop running
- Network access to NAS
- Neo4j container running on target
