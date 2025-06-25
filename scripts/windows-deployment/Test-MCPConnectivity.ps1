# Test MCP Network Connectivity from Windows to Terramaster
# Run this on each Windows machine to verify network access

param(
    [string]$TerramasterHost = "terramaster.local",
    [switch]$Verbose
)

Write-Host "🔍 Testing MCP Network Connectivity" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Get local network info
Write-Host "`nLocal Network Information:" -ForegroundColor Yellow
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*"}).IPAddress
$subnet = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -eq $localIP}).PrefixLength
Write-Host "Local IP: $localIP/$subnet"

# Resolve Terramaster hostname
try {
    $terraIP = [System.Net.Dns]::GetHostAddresses($TerramasterHost) | Select-Object -First 1
    Write-Host "Terramaster IP: $terraIP" -ForegroundColor Green
    
    # Check if on same subnet
    $localNet = $localIP.Split('.')[0..2] -join '.'
    $terraNet = $terraIP.ToString().Split('.')[0..2] -join '.'
    
    if ($localNet -eq $terraNet) {
        Write-Host "✓ Same subnet - Direct access available!" -ForegroundColor Green
    } else {
        Write-Host "⚠ Different subnets - May need routing" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Cannot resolve $TerramasterHost" -ForegroundColor Red
    exit 1
}

# Test MCP service ports
Write-Host "`nTesting MCP Service Ports:" -ForegroundColor Yellow
$ports = @{
    "PostgreSQL (MCP)" = 5432
    "Redis (MCP)" = 6379
    "Neo4j Browser" = 7474
    "Neo4j Bolt" = 7687
    "InfluxDB" = 8086
    "MCP Manager" = 3100
}

$accessible = @()
$blocked = @()

foreach ($service in $ports.Keys) {
    $port = $ports[$service]
    Write-Host -NoNewline "Testing $service (port $port)... "
    
    $result = Test-NetConnection -ComputerName $TerramasterHost -Port $port -WarningAction SilentlyContinue
    
    if ($result.TcpTestSucceeded) {
        Write-Host "✓ ACCESSIBLE" -ForegroundColor Green
        $accessible += "$service:$port"
        
        if ($Verbose) {
            # Try to get service info
            switch ($port) {
                5432 {
                    # PostgreSQL version check would require psql client
                    Write-Host "  PostgreSQL is responding" -ForegroundColor Gray
                }
                6379 {
                    # Redis ping would require redis-cli
                    Write-Host "  Redis is responding" -ForegroundColor Gray
                }
                7474 {
                    # Neo4j browser
                    Write-Host "  Neo4j Browser: http://${TerramasterHost}:7474" -ForegroundColor Gray
                }
            }
        }
    } else {
        Write-Host "✗ BLOCKED/OFFLINE" -ForegroundColor Red
        $blocked += "$service:$port"
    }
}

# Network performance test
Write-Host "`nNetwork Performance Test:" -ForegroundColor Yellow
$ping = Test-Connection -ComputerName $TerramasterHost -Count 10 -Quiet
if ($ping) {
    $pingResults = Test-Connection -ComputerName $TerramasterHost -Count 10
    $avgTime = ($pingResults | Measure-Object -Property ResponseTime -Average).Average
    Write-Host "Average latency: $([math]::Round($avgTime, 2))ms" -ForegroundColor Green
    
    if ($avgTime -lt 1) {
        Write-Host "✓ Excellent - Same switch/10GbE performance" -ForegroundColor Green
    } elseif ($avgTime -lt 5) {
        Write-Host "✓ Good - Local network performance" -ForegroundColor Green
    } else {
        Write-Host "⚠ Higher latency detected" -ForegroundColor Yellow
    }
}

# Summary
Write-Host "`n📊 Summary:" -ForegroundColor Cyan
Write-Host "===========" -ForegroundColor Cyan
Write-Host "Accessible services: $($accessible.Count)" -ForegroundColor Green
if ($accessible.Count -gt 0) {
    $accessible | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }
}
Write-Host "Blocked/Offline services: $($blocked.Count)" -ForegroundColor $(if ($blocked.Count -eq 0) { "Green" } else { "Red" })
if ($blocked.Count -gt 0) {
    $blocked | ForEach-Object { Write-Host "  ✗ $_" -ForegroundColor Red }
}

# Recommendations
if ($blocked.Count -gt 0) {
    Write-Host "`n💡 Recommendations:" -ForegroundColor Yellow
    Write-Host "1. Check if MCP services are running on Terramaster:"
    Write-Host "   docker ps --filter 'name=mcp'" -ForegroundColor Cyan
    Write-Host "2. Check Terramaster firewall settings"
    Write-Host "3. Ensure ports are mapped correctly in docker-compose.yml"
    Write-Host "4. Verify no other services are using these ports"
}

# Show connection examples
Write-Host "`n🔗 Connection URLs for Testing:" -ForegroundColor Yellow
Write-Host "PostgreSQL: psql -h $TerramasterHost -p 5432 -U mcp -d mcp_db"
Write-Host "Redis: redis-cli -h $TerramasterHost -p 6379"
Write-Host "Neo4j Browser: http://${TerramasterHost}:7474"
Write-Host "InfluxDB: http://${TerramasterHost}:8086"