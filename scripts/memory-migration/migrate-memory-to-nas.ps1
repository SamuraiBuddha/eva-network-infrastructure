# Memory Volume Migration Script - Local to NAS
# Run this on your MAGI machine to copy memory data to NAS

$ErrorActionPreference = "Stop"

Write-Host "🧠 Memory Volume Migration to NAS" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Configuration
$nasIP = "192.168.50.78"
$nasUser = "SamuraiBuddha"
$sshPort = "9222"

# Step 1: Create a temporary container to access the volume
Write-Host "`n📦 Creating temporary container to access memory volume..." -ForegroundColor Yellow
docker run -d --name memory-export -v claude-memory:/data alpine tail -f /dev/null

# Step 2: Export the data to a tar file
Write-Host "📤 Exporting memory data..." -ForegroundColor Yellow
docker exec memory-export tar -czf /data.tar.gz -C /data .
docker cp memory-export:/data.tar.gz ./memory-export.tar.gz

# Step 3: Clean up temporary container
Write-Host "🧹 Cleaning up temporary container..." -ForegroundColor Yellow
docker rm -f memory-export

# Step 4: Copy to NAS
Write-Host "`n📡 Copying to NAS..." -ForegroundColor Yellow
Write-Host "This will prompt for your NAS password:" -ForegroundColor Gray
scp -P $sshPort ./memory-export.tar.gz "${nasUser}@${nasIP}:/tmp/"

# Step 5: Extract on NAS
Write-Host "`n📥 Extracting on NAS..." -ForegroundColor Yellow
$extractCommand = @"
# Stop the memory container
docker stop mcp-memory

# Create backup of existing data
docker run --rm -v magi-core-mcp-nas_mcp-memory-data:/data alpine tar -czf /backup-\$(date +%Y%m%d-%H%M%S).tar.gz -C /data .

# Clear the volume
docker run --rm -v magi-core-mcp-nas_mcp-memory-data:/data alpine sh -c 'rm -rf /data/*'

# Extract new data
docker run --rm -v magi-core-mcp-nas_mcp-memory-data:/data -v /tmp:/import alpine tar -xzf /import/memory-export.tar.gz -C /data

# Restart the memory container
docker start mcp-memory

# Clean up
rm /tmp/memory-export.tar.gz
"@

ssh -p $sshPort "${nasUser}@${nasIP}" $extractCommand

# Step 6: Clean up local file
Write-Host "`n🧹 Cleaning up local export file..." -ForegroundColor Yellow
Remove-Item ./memory-export.tar.gz

Write-Host "`n✅ Migration Complete!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Test the migrated memory on NAS" -ForegroundColor Gray
Write-Host "2. Update your local Claude Desktop config to use NAS memory" -ForegroundColor Gray
Write-Host "3. Verify memory access from all MAGI machines" -ForegroundColor Gray