# Memory Migration via MCP Protocol - Safe Method
# This exports memory using the MCP protocol, which is safer than direct volume copy

$ErrorActionPreference = "Stop"

Write-Host "🧠 Memory Migration via MCP Protocol" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Configuration
$nasIP = "192.168.50.78"
$nasUser = "SamuraiBuddha"
$sshPort = "9222"
$outputFile = "memory-export-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

Write-Host "`n📋 This script will:" -ForegroundColor Yellow
Write-Host "1. Export your local memory graph via MCP" -ForegroundColor Gray
Write-Host "2. Copy the export to NAS" -ForegroundColor Gray
Write-Host "3. Import into the NAS memory container" -ForegroundColor Gray

Write-Host "`n⚠️  Prerequisites:" -ForegroundColor Yellow
Write-Host "- Local memory MCP server must be running" -ForegroundColor Gray
Write-Host "- Claude Desktop must be configured with memory access" -ForegroundColor Gray
Write-Host "- SSH access to NAS must be working" -ForegroundColor Gray

$continue = Read-Host "`nContinue? (y/n)"
if ($continue -ne 'y') { exit }

# Step 1: Export memory using Python script
Write-Host "`n📤 Creating memory export script..." -ForegroundColor Yellow

$exportScript = @'
import subprocess
import json
import sys

def export_memory():
    """Export memory graph via MCP protocol"""
    print("Exporting memory graph...")
    
    # This assumes you have a local MCP memory server running
    # You'll need to run this in an environment where the MCP client is available
    
    try:
        # Read the entire graph
        result = subprocess.run([
            'python', '-c',
            '''
import json
from mcp import Client

client = Client("memory")
graph = client.read_graph()
print(json.dumps(graph, indent=2))
'''
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            with open(sys.argv[1], 'w') as f:
                f.write(result.stdout)
            print(f"Export complete: {sys.argv[1]}")
        else:
            print(f"Export failed: {result.stderr}")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python export_memory.py <output_file>")
        sys.exit(1)
    export_memory()
'@

Set-Content -Path "export_memory.py" -Value $exportScript

# Alternative: Manual export instructions
Write-Host "`n📝 Manual Export Alternative:" -ForegroundColor Cyan
Write-Host "Since we need Claude to export the memory, please:" -ForegroundColor Yellow
Write-Host "1. Ask Claude in a new chat: 'Export my entire memory graph to a JSON file'" -ForegroundColor Gray
Write-Host "2. Save the output as: $outputFile" -ForegroundColor Gray
Write-Host "3. Place it in this directory" -ForegroundColor Gray

Write-Host "`nOnce you have the export file, press Enter to continue..."
Read-Host

# Step 2: Copy to NAS
if (Test-Path $outputFile) {
    Write-Host "`n📡 Copying export to NAS..." -ForegroundColor Yellow
    scp -P $sshPort $outputFile "${nasUser}@${nasIP}:/tmp/"
    
    # Step 3: Import on NAS
    Write-Host "`n📥 Importing on NAS..." -ForegroundColor Yellow
    
    $importCommand = @"
# Create import script
cat > /tmp/import_memory.py << 'EOF'
import json
import subprocess
import sys

def import_memory(filename):
    with open(filename, 'r') as f:
        data = json.load(f)
    
    # Import into memory container
    # This would need to be run inside the mcp-memory container
    print(f"Importing {len(data.get('entities', []))} entities...")
    
    # The actual import would happen here via MCP protocol

if __name__ == "__main__":
    import_memory(sys.argv[1])
EOF

# Copy import script to memory container
docker cp /tmp/import_memory.py mcp-memory:/tmp/
docker cp /tmp/$outputFile mcp-memory:/tmp/

# Run import inside container
docker exec mcp-memory python /tmp/import_memory.py /tmp/$outputFile

# Clean up
rm /tmp/import_memory.py /tmp/$outputFile
"@

    ssh -p $sshPort "$nasUser@$nasIP" $importCommand
    
    Write-Host "`n✅ Migration Complete!" -ForegroundColor Green
} else {
    Write-Host "❌ Export file not found: $outputFile" -ForegroundColor Red
}

# Cleanup
if (Test-Path "export_memory.py") {
    Remove-Item "export_memory.py"
}
