# Simple Memory Volume Migration - Direct JSON Copy
# This is the easiest method since memory is just a JSON file

$ErrorActionPreference = "Stop"

Write-Host "🧠 Simple Memory Migration to NAS" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Configuration
$nasIP = "192.168.50.78"
$nasUser = "SamuraiBuddha"
$sshPort = "9222"
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# Step 1: Export memory.json from local volume
Write-Host "`n📤 Exporting local memory.json..." -ForegroundColor Yellow
docker run --rm -v claude-memory:/data alpine cat /data/memory.json > "memory-local-backup-$timestamp.json"

Write-Host "✅ Local memory exported to: memory-local-backup-$timestamp.json" -ForegroundColor Green

# Step 2: Show some stats
$memoryData = Get-Content "memory-local-backup-$timestamp.json" | ConvertFrom-Json
$entityCount = ($memoryData.entities | Measure-Object).Count
$relationCount = ($memoryData.relations | Measure-Object).Count

Write-Host "`n📊 Memory Statistics:" -ForegroundColor Cyan
Write-Host "   Entities: $entityCount" -ForegroundColor Gray
Write-Host "   Relations: $relationCount" -ForegroundColor Gray
Write-Host "   File size: $((Get-Item "memory-local-backup-$timestamp.json").Length / 1KB) KB" -ForegroundColor Gray

# Step 3: Copy to NAS
Write-Host "`n📡 Copying to NAS..." -ForegroundColor Yellow
scp -P $sshPort "memory-local-backup-$timestamp.json" "${nasUser}@${nasIP}:/tmp/"

# Step 4: Backup existing NAS memory and import new one
Write-Host "`n🔄 Updating NAS memory..." -ForegroundColor Yellow

$updateCommand = @"
# Backup existing memory
echo 'Backing up existing NAS memory...'
docker exec mcp-memory cat /data/memory.json > /tmp/memory-nas-backup-$timestamp.json

# Import new memory
echo 'Importing new memory...'
docker cp /tmp/memory-local-backup-$timestamp.json mcp-memory:/data/memory.json

# Verify
echo 'Verifying import...'
docker exec mcp-memory ls -la /data/memory.json

# Clean up temp file
rm /tmp/memory-local-backup-$timestamp.json

echo 'Memory migration complete!'
"@

ssh -p $sshPort "$nasUser@$nasIP" $updateCommand

Write-Host "`n✅ Migration Complete!" -ForegroundColor Green
Write-Host "`n📋 Next Steps:" -ForegroundColor Yellow
Write-Host "1. Your local backup is saved as: memory-local-backup-$timestamp.json" -ForegroundColor Gray
Write-Host "2. Test memory access through your NAS MCP bridges" -ForegroundColor Gray
Write-Host "3. Update Claude Desktop config to use NAS memory instead of local" -ForegroundColor Gray
Write-Host "`n💡 To update your config, change the memory server to use SSH bridge:" -ForegroundColor Cyan
Write-Host '   "nas-memory": {' -ForegroundColor Gray
Write-Host '     "command": "C:\\mcp-bridges\\mcp-memory.bat"' -ForegroundColor Gray
Write-Host '   }' -ForegroundColor Gray
