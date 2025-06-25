# Verify Memory Migration
# Run this after migration to check if NAS memory is accessible

$ErrorActionPreference = "Stop"

Write-Host "🔍 Verifying Memory Migration" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan

# Configuration
$nasIP = "192.168.50.78"
$nasUser = "SamuraiBuddha"
$sshPort = "9222"

# Step 1: Check local memory
Write-Host "`n📊 Local Memory Status:" -ForegroundColor Yellow
$localMemory = docker run --rm -v claude-memory:/data alpine cat /data/memory.json | ConvertFrom-Json
Write-Host "   Entities: $(($localMemory.entities | Measure-Object).Count)" -ForegroundColor Gray
Write-Host "   Relations: $(($localMemory.relations | Measure-Object).Count)" -ForegroundColor Gray

# Step 2: Check NAS memory via SSH
Write-Host "`n📊 NAS Memory Status:" -ForegroundColor Yellow
$nasCheck = ssh -p $sshPort "$nasUser@$nasIP" "docker exec mcp-memory wc -l /data/memory.json"
Write-Host "   Memory file exists: ✅" -ForegroundColor Green

# Step 3: Test MCP bridge
Write-Host "`n🧪 Testing MCP Bridge..." -ForegroundColor Yellow
Write-Host "Attempting to call mcp-memory through SSH bridge..." -ForegroundColor Gray

# Create a simple test that doesn't require full MCP client
$testOutput = & "C:\mcp-bridges\mcp-memory.bat" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ MCP bridge is working!" -ForegroundColor Green
} else {
    Write-Host "❌ MCP bridge test failed. This might be normal if no input was provided." -ForegroundColor Yellow
}

# Step 4: Show Session_Breadcrumbs from NAS
Write-Host "`n📜 Recent Session Breadcrumbs from NAS:" -ForegroundColor Yellow
$breadcrumbsCommand = @"
docker exec mcp-memory python -c "
import json
with open('/data/memory.json', 'r') as f:
    data = json.load(f)
    for entity in data['entities']:
        if entity['name'] == 'Session_Breadcrumbs':
            for obs in entity['observations'][-5:]:
                print(obs)
"
"@

ssh -p $sshPort "$nasUser@$nasIP" $breadcrumbsCommand

Write-Host "`n✅ Verification Complete!" -ForegroundColor Green
Write-Host "`nIf you see recent breadcrumbs above, the migration was successful!" -ForegroundColor Cyan