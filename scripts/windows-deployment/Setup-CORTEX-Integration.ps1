# CORTEX Integration Setup for Windows 11 Workstations
# Configures Docker, WSL2, and CORTEX components after OS deployment

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Melchior", "Balthazar", "Caspar")]
    [string]$Machine = (hostname),
    
    [Parameter(Mandatory=$false)]
    [string]$CortexRepo = "https://github.com/SamuraiBuddha/CORTEX-AI-Orchestrator-v2.git",
    
    [Parameter(Mandatory=$false)]
    [string]$DockerNetwork = "cortex_network",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipDocker,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipWSL
)

$ErrorActionPreference = "Stop"

# Machine-specific CORTEX roles
$MachineRoles = @{
    Melchior = @{
        Role = "Visual Computing & CAD Pipeline"
        DockerMemory = "32GB"
        DockerCPUs = "12"
        GPUSupport = $true
        Services = @("n8n", "neo4j", "grafana", "flowise")
    }
    Balthazar = @{
        Role = "AI Model Host & Inference"
        DockerMemory = "64GB"
        DockerCPUs = "16"
        GPUSupport = $true
        Services = @("n8n", "qdrant", "ollama", "open-webui")
    }
    Caspar = @{
        Role = "Code Generation & Data Processing"
        DockerMemory = "64GB"
        DockerCPUs = "20"
        GPUSupport = $true
        Services = @("n8n", "postgres", "redis", "prometheus")
    }
}

function Install-WSL2 {
    Write-Host "Installing WSL2..." -ForegroundColor Green
    
    # Enable WSL
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    
    # Enable Virtual Machine Platform
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    
    # Download and install WSL2 kernel
    Write-Host "Downloading WSL2 kernel update..."
    $wslUpdateUrl = "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"
    $wslUpdatePath = "$env:TEMP\wsl_update_x64.msi"
    
    Invoke-WebRequest -Uri $wslUpdateUrl -OutFile $wslUpdatePath
    Start-Process msiexec.exe -ArgumentList "/i", $wslUpdatePath, "/quiet" -Wait
    
    # Set WSL2 as default
    wsl --set-default-version 2
    
    # Install Ubuntu for development tools
    Write-Host "Installing Ubuntu 22.04..."
    wsl --install -d Ubuntu-22.04
}

function Install-DockerDesktop {
    Write-Host "Installing Docker Desktop..." -ForegroundColor Green
    
    $dockerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
    $dockerPath = "$env:TEMP\DockerDesktopInstaller.exe"
    
    # Download Docker Desktop
    Write-Host "Downloading Docker Desktop..."
    Invoke-WebRequest -Uri $dockerUrl -OutFile $dockerPath
    
    # Install Docker Desktop
    Start-Process -FilePath $dockerPath -ArgumentList "install", "--quiet", "--accept-license" -Wait
    
    # Wait for Docker to start
    Write-Host "Waiting for Docker to start..."
    $timeout = 300 # 5 minutes
    $timer = [Diagnostics.Stopwatch]::StartNew()
    
    while ($timer.Elapsed.TotalSeconds -lt $timeout) {
        try {
            docker version | Out-Null
            Write-Host "Docker is running!" -ForegroundColor Green
            break
        }
        catch {
            Start-Sleep -Seconds 5
        }
    }
}

function Configure-Docker {
    param(
        [string]$MachineName
    )
    
    Write-Host "Configuring Docker for $MachineName..." -ForegroundColor Green
    
    $config = $MachineRoles[$MachineName]
    
    # Create Docker daemon configuration
    $daemonConfig = @{
        "builder" = @{
            "gc" = @{
                "enabled" = $true
                "defaultKeepStorage" = "20GB"
            }
        }
        "experimental" = $true
        "features" = @{
            "buildkit" = $true
        }
    }
    
    # Add GPU support if available
    if ($config.GPUSupport) {
        $daemonConfig["default-runtime"] = "nvidia"
        $daemonConfig["runtimes"] = @{
            "nvidia" = @{
                "path" = "nvidia-container-runtime"
                "runtimeArgs" = @()
            }
        }
    }
    
    # Set resource limits based on machine role
    $settingsPath = "$env:USERPROFILE\.docker\daemon.json"
    $daemonConfig | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
    
    # Configure WSL2 backend resources
    $wslConfig = @"
[wsl2]
memory=$($config.DockerMemory)
processors=$($config.DockerCPUs)
swap=8GB
localhostForwarding=true

[experimental]
sparseVhd=true
"@
    
    $wslConfig | Set-Content "$env:USERPROFILE\.wslconfig"
    
    # Restart Docker
    Restart-Service *docker*
}

function Install-CORTEXStack {
    param(
        [string]$MachineName
    )
    
    Write-Host "Installing CORTEX stack for $MachineName..." -ForegroundColor Green
    
    # Clone CORTEX repository
    $cortexPath = "C:\CORTEX"
    if (-not (Test-Path $cortexPath)) {
        Write-Host "Cloning CORTEX repository..."
        git clone $CortexRepo $cortexPath
    }
    
    Set-Location $cortexPath
    
    # Copy environment template
    Copy-Item ".env.example" ".env"
    
    # Update .env with machine-specific settings
    $envContent = Get-Content ".env"
    $envContent = $envContent -replace "MACHINE_ID=.*", "MACHINE_ID=$MachineName"
    $envContent = $envContent -replace "MACHINE_ROLE=.*", "MACHINE_ROLE=$($MachineRoles[$MachineName].Role)"
    $envContent | Set-Content ".env"
    
    # Create necessary directories
    $directories = @(
        "data/shared",
        "data/postgres",
        "data/neo4j",
        "data/qdrant",
        "data/redis",
        "monitoring/grafana/dashboards",
        "monitoring/loki",
        "workflows/imports",
        "workflows/exports",
        "agents/models",
        "agents/configs"
    )
    
    foreach ($dir in $directories) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    
    # Start only the services specific to this machine
    $services = $MachineRoles[$MachineName].Services
    Write-Host "Starting services: $($services -join ', ')"
    
    # Create custom docker-compose override
    $override = @"
version: '3.8'
services:
"@
    
    # Add only the services for this machine
    $allServices = @("postgres", "n8n", "redis", "qdrant", "neo4j", "prometheus", "grafana", "loki", "flowise", "open-webui", "ollama")
    foreach ($service in $allServices) {
        if ($service -notin $services) {
            $override += @"

  $service:
    deploy:
      replicas: 0
"@
        }
    }
    
    $override | Set-Content "docker-compose.override.yml"
    
    # Pull images
    Write-Host "Pulling Docker images..."
    docker-compose pull
    
    # Start services
    Write-Host "Starting CORTEX services..."
    docker-compose up -d
}

function Configure-Networking {
    Write-Host "Configuring network for CORTEX..." -ForegroundColor Green
    
    # Create Docker network for CORTEX
    docker network create --driver bridge --subnet=172.20.0.0/16 $DockerNetwork
    
    # Configure Windows Firewall rules
    $rules = @(
        @{Name="CORTEX-n8n"; Port=5678; Protocol="TCP"},
        @{Name="CORTEX-Neo4j-Bolt"; Port=7687; Protocol="TCP"},
        @{Name="CORTEX-Neo4j-HTTP"; Port=7474; Protocol="TCP"},
        @{Name="CORTEX-Grafana"; Port=3000; Protocol="TCP"},
        @{Name="CORTEX-Prometheus"; Port=9090; Protocol="TCP"},
        @{Name="CORTEX-Qdrant"; Port=6333; Protocol="TCP"},
        @{Name="CORTEX-Redis"; Port=6379; Protocol="TCP"},
        @{Name="CORTEX-Postgres"; Port=5432; Protocol="TCP"},
        @{Name="CORTEX-InfluxDB"; Port=8086; Protocol="TCP"}
    )
    
    foreach ($rule in $rules) {
        New-NetFirewallRule -DisplayName $rule.Name `
                           -Direction Inbound `
                           -Protocol $rule.Protocol `
                           -LocalPort $rule.Port `
                           -Action Allow `
                           -Profile Domain,Private
    }
    
    # Enable port forwarding from WSL2
    netsh interface portproxy add v4tov4 listenport=5678 listenaddress=0.0.0.0 connectport=5678 connectaddress=127.0.0.1
}

function Install-DevelopmentTools {
    Write-Host "Installing development tools..." -ForegroundColor Green
    
    # Install Chocolatey
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    
    # Install essential tools
    $tools = @(
        "git",
        "nodejs",
        "python",
        "vscode",
        "postman",
        "kubernetes-cli",
        "helm",
        "terraform"
    )
    
    foreach ($tool in $tools) {
        choco install $tool -y
    }
}

function Show-Summary {
    param(
        [string]$MachineName
    )
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "CORTEX Integration Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    
    Write-Host "`nMachine: $MachineName"
    Write-Host "Role: $($MachineRoles[$MachineName].Role)"
    Write-Host "Services: $($MachineRoles[$MachineName].Services -join ', ')"
    
    Write-Host "`nAccess Points:" -ForegroundColor Yellow
    Write-Host "- n8n: http://localhost:5678"
    Write-Host "- Grafana: http://localhost:3000"
    Write-Host "- Neo4j: http://localhost:7474"
    Write-Host "- Prometheus: http://localhost:9090"
    
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "1. Configure n8n workflows for your pipelines"
    Write-Host "2. Set up monitoring dashboards in Grafana"
    Write-Host "3. Connect to other CORTEX machines"
    Write-Host "4. Import initial workflows from /workflows/imports"
    
    Write-Host "`nCORTEX is ready for orchestration!" -ForegroundColor Green
}

# Main execution
Write-Host "CORTEX Integration Setup" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan

# Verify we're running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator!"
    exit 1
}

# Determine machine name
if ($Machine -eq (hostname)) {
    # Try to auto-detect based on hardware
    $gpu = Get-WmiObject Win32_VideoController | Where-Object {$_.Name -like "*NVIDIA*"} | Select-Object -First 1
    if ($gpu.Name -match "3090") { $Machine = "Melchior" }
    elseif ($gpu.Name -match "A5000") { $Machine = "Balthazar" }
    elseif ($gpu.Name -match "A4000") { $Machine = "Caspar" }
}

if (-not $MachineRoles.ContainsKey($Machine)) {
    Write-Error "Unknown machine: $Machine. Please specify -Machine parameter."
    exit 1
}

Write-Host "Configuring CORTEX for: $Machine" -ForegroundColor Green

# Install components
if (-not $SkipWSL) {
    Install-WSL2
}

if (-not $SkipDocker) {
    Install-DockerDesktop
    Configure-Docker -MachineName $Machine
}

Configure-Networking
Install-CORTEXStack -MachineName $Machine
Install-DevelopmentTools

# Show summary
Show-Summary -MachineName $Machine

Write-Host "`nNote: A system restart may be required for all changes to take effect." -ForegroundColor Yellow