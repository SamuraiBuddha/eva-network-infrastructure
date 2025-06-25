# Configure Claude Desktop to use Terramaster MCP Services
# Run this on each Windows workstation after MCP deployment on NAS

param(
    [Parameter(Mandatory=$false)]
    [string]$TerramasterHost = "terramaster.local",
    
    [Parameter(Mandatory=$false)]
    [int]$MCPPort = 3100,
    
    [Parameter(Mandatory=$false)]
    [string]$SSHUser = "admin",
    
    [Parameter(Mandatory=$false)]
    [switch]$UseProxy,
    
    [Parameter(Mandatory=$false)]
    [switch]$TestConnection
)

$ErrorActionPreference = "Stop"

# Claude Desktop config path
$claudeConfigPath = "$env:APPDATA\Claude\claude_desktop_config.json"
$claudeConfigDir = Split-Path $claudeConfigPath -Parent

function Test-TerramasterConnection {
    Write-Host "Testing connection to Terramaster NAS..." -ForegroundColor Yellow
    
    # Test ping
    if (Test-Connection -ComputerName $TerramasterHost -Count 2 -Quiet) {
        Write-Host "✓ Ping successful" -ForegroundColor Green
    } else {
        Write-Error "Cannot ping $TerramasterHost"
        return $false
    }
    
    # Test SSH
    try {
        $sshTest = ssh $SSHUser@$TerramasterHost "echo 'SSH OK'"
        if ($sshTest -eq "SSH OK") {
            Write-Host "✓ SSH connection successful" -ForegroundColor Green
        }
    } catch {
        Write-Error "SSH connection failed. Make sure SSH keys are configured."
        return $false
    }
    
    # Test Docker
    try {
        $dockerTest = ssh $SSHUser@$TerramasterHost "docker ps --format 'table {{.Names}}' | grep mcp-"
        if ($dockerTest) {
            Write-Host "✓ MCP containers found:" -ForegroundColor Green
            Write-Host $dockerTest
        } else {
            Write-Warning "No MCP containers found on Terramaster"
        }
    } catch {
        Write-Error "Cannot query Docker containers"
        return $false
    }
    
    # Test ports
    $ports = @{
        "PostgreSQL" = 5432
        "Redis" = 6379
        "Neo4j HTTP" = 7474
        "Neo4j Bolt" = 7687
        "InfluxDB" = 8086
        "MCP Manager" = 3100
    }
    
    Write-Host "`nTesting service ports:" -ForegroundColor Yellow
    foreach ($service in $ports.Keys) {
        $port = $ports[$service]
        $tcpTest = Test-NetConnection -ComputerName $TerramasterHost -Port $port -WarningAction SilentlyContinue
        if ($tcpTest.TcpTestSucceeded) {
            Write-Host "✓ $service (port $port) is accessible" -ForegroundColor Green
        } else {
            Write-Host "✗ $service (port $port) is not accessible" -ForegroundColor Red
        }
    }
    
    return $true
}

function Setup-SSHKeys {
    Write-Host "`nSetting up SSH keys for passwordless access..." -ForegroundColor Yellow
    
    $sshDir = "$env:USERPROFILE\.ssh"
    $keyPath = "$sshDir\id_rsa_mcp"
    
    # Create .ssh directory if it doesn't exist
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }
    
    # Generate SSH key if it doesn't exist
    if (-not (Test-Path $keyPath)) {
        Write-Host "Generating SSH key..."
        ssh-keygen -t rsa -b 4096 -f $keyPath -N '""' -C "mcp@$env:COMPUTERNAME"
    }
    
    # Copy public key to Terramaster
    Write-Host "Copying public key to Terramaster (you'll need to enter password once)..."
    $pubKey = Get-Content "$keyPath.pub"
    
    # Use ssh-copy-id if available, otherwise manual method
    try {
        ssh-copy-id -i $keyPath "$SSHUser@$TerramasterHost"
    } catch {
        # Manual method
        $cmd = "mkdir -p ~/.ssh && echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        ssh "$SSHUser@$TerramasterHost" $cmd
    }
    
    # Create SSH config entry
    $sshConfig = @"

Host terramaster-mcp
    HostName $TerramasterHost
    User $SSHUser
    IdentityFile $keyPath
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
"@
    
    Add-Content -Path "$sshDir\config" -Value $sshConfig
    
    Write-Host "✓ SSH keys configured" -ForegroundColor Green
}

function Install-MCPProxy {
    Write-Host "`nInstalling MCP Proxy..." -ForegroundColor Yellow
    
    # Check if Node.js is installed
    try {
        $nodeVersion = node --version
        Write-Host "Node.js $nodeVersion found" -ForegroundColor Green
    } catch {
        Write-Error "Node.js not found. Please install Node.js first."
        return
    }
    
    # Install MCP Proxy globally
    Write-Host "Installing @modelcontextprotocol/proxy..."
    npm install -g @modelcontextprotocol/proxy
    
    # Create proxy configuration
    $proxyConfig = @{
        upstream = "http://${TerramasterHost}:${MCPPort}"
        cache = $true
        timeout = 30000
        retries = 3
        healthCheck = @{
            enabled = $true
            interval = 30000
            timeout = 5000
        }
    } | ConvertTo-Json -Depth 10
    
    $proxyConfigPath = "$env:APPDATA\Claude\mcp-proxy.json"
    $proxyConfig | Set-Content $proxyConfigPath
    
    # Create startup script
    $startupScript = @"
@echo off
echo Starting MCP Proxy...
mcp-proxy --config "$proxyConfigPath" --port 3101
"@
    
    $startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\mcp-proxy.bat"
    $startupScript | Set-Content $startupPath
    
    Write-Host "✓ MCP Proxy installed and configured" -ForegroundColor Green
    Write-Host "  Proxy will start automatically on login" -ForegroundColor Cyan
}

function Configure-ClaudeDesktop {
    param(
        [bool]$UseProxy
    )
    
    Write-Host "`nConfiguring Claude Desktop..." -ForegroundColor Yellow
    
    # Create config directory if it doesn't exist
    if (-not (Test-Path $claudeConfigDir)) {
        New-Item -ItemType Directory -Path $claudeConfigDir -Force | Out-Null
    }
    
    if ($UseProxy) {
        # Proxy configuration (simpler)
        $config = @{
            mcpServers = @{
                proxy = @{
                    command = "mcp-proxy"
                    args = @("--upstream", "http://${TerramasterHost}:${MCPPort}")
                }
            }
        }
    } else {
        # Direct SSH configuration
        $config = @{
            mcpServers = @{
                filesystem = @{
                    command = "ssh"
                    args = @(
                        "terramaster-mcp",
                        "docker exec mcp-manager npx -y @modelcontextprotocol/server-filesystem /data/shared"
                    )
                }
                postgres = @{
                    command = "ssh"
                    args = @(
                        "terramaster-mcp",
                        "docker exec mcp-manager npx -y @modelcontextprotocol/server-postgres postgresql://mcp:password@localhost:5432/mcp_db"
                    )
                }
                redis = @{
                    command = "ssh"
                    args = @(
                        "terramaster-mcp",
                        "docker exec mcp-manager npx -y @modelcontextprotocol/server-redis"
                    )
                    env = @{
                        REDIS_URL = "redis://:password@localhost:6379"
                    }
                }
                memory = @{
                    command = "ssh"
                    args = @(
                        "terramaster-mcp",
                        "docker exec mcp-manager npx -y @modelcontextprotocol/server-memory"
                    )
                }
                neo4j = @{
                    command = "ssh"
                    args = @(
                        "terramaster-mcp",
                        "docker exec mcp-manager npx -y mcp-neo4j"
                    )
                    env = @{
                        NEO4J_URI = "bolt://${TerramasterHost}:7687"
                        NEO4J_USERNAME = "neo4j"
                        NEO4J_PASSWORD = "your-password"
                    }
                }
                github = @{
                    command = "ssh"
                    args = @(
                        "terramaster-mcp",
                        "docker exec mcp-manager npx -y @modelcontextprotocol/server-github"
                    )
                    env = @{
                        GITHUB_TOKEN = "your-github-token"
                    }
                }
            }
        }
    }
    
    # Backup existing config
    if (Test-Path $claudeConfigPath) {
        $backupPath = "${claudeConfigPath}.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $claudeConfigPath $backupPath
        Write-Host "Backed up existing config to: $backupPath" -ForegroundColor Cyan
    }
    
    # Write new config
    $config | ConvertTo-Json -Depth 10 | Set-Content $claudeConfigPath
    Write-Host "✓ Claude Desktop configured" -ForegroundColor Green
}

function Show-Instructions {
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "SETUP COMPLETE!" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Cyan
    
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "1. Update passwords in Claude config file:"
    Write-Host "   $claudeConfigPath" -ForegroundColor Cyan
    
    Write-Host "`n2. Restart Claude Desktop to load new configuration"
    
    if ($UseProxy) {
        Write-Host "`n3. Start MCP Proxy manually (or reboot for auto-start):"
        Write-Host "   mcp-proxy --config `"$env:APPDATA\Claude\mcp-proxy.json`" --port 3101" -ForegroundColor Cyan
    }
    
    Write-Host "`n4. Test MCP connections in Claude by typing:"
    Write-Host "   'Show me my available MCP tools'" -ForegroundColor Cyan
    
    Write-Host "`nTerramaster MCP Services:" -ForegroundColor Yellow
    Write-Host "  PostgreSQL: ${TerramasterHost}:5432"
    Write-Host "  Redis: ${TerramasterHost}:6379"
    Write-Host "  Neo4j: http://${TerramasterHost}:7474"
    Write-Host "  InfluxDB: http://${TerramasterHost}:8086"
    Write-Host "  MCP Manager: http://${TerramasterHost}:3100"
    
    Write-Host "`nShared across all machines:" -ForegroundColor Green
    Write-Host "  ✓ Memory (knowledge graph)"
    Write-Host "  ✓ File storage"
    Write-Host "  ✓ Database state"
    Write-Host "  ✓ Tool configurations"
}

# Main execution
Write-Host "Terramaster MCP Client Configuration" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Test connection if requested
if ($TestConnection) {
    if (-not (Test-TerramasterConnection)) {
        Write-Error "Connection test failed. Please check Terramaster configuration."
        exit 1
    }
    Write-Host "`nConnection test passed!" -ForegroundColor Green
    exit 0
}

# Setup process
Write-Host "`nThis will configure Claude Desktop to use MCP services on $TerramasterHost" -ForegroundColor Yellow
$confirm = Read-Host "Continue? (Y/N)"
if ($confirm -ne "Y") {
    Write-Host "Setup cancelled" -ForegroundColor Red
    exit 0
}

# Setup SSH keys
Setup-SSHKeys

# Test connection
if (-not (Test-TerramasterConnection)) {
    Write-Error "Cannot connect to Terramaster. Please check:"
    Write-Error "  1. Terramaster is accessible at $TerramasterHost"
    Write-Error "  2. MCP services are running"
    Write-Error "  3. Firewall allows required ports"
    exit 1
}

# Install proxy if requested
if ($UseProxy) {
    Install-MCPProxy
}

# Configure Claude Desktop
Configure-ClaudeDesktop -UseProxy $UseProxy

# Show completion instructions
Show-Instructions

Write-Host "`nSetup complete!" -ForegroundColor Green