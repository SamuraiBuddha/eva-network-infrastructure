#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Main deployment script for Magi Windows 11 Pro workstations
.DESCRIPTION
    Deploys Windows 11 Pro with role-specific configurations for Melchior, Balthazar, or Caspar
.PARAMETER Role
    The workstation role: Melchior, Balthazar, or Caspar
.PARAMETER ComputerName
    The name to assign to the computer
.PARAMETER SkipBase
    Skip base configuration (useful for re-runs)
.EXAMPLE
    .\Deploy-Magi.ps1 -Role "Melchior" -ComputerName "MELCHIOR-CAD"
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Melchior", "Balthazar", "Caspar")]
    [string]$Role,
    
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    
    [switch]$SkipBase
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Script configuration
$script:LogPath = "C:\MagiDeploy\Logs"
$script:TempPath = "C:\MagiDeploy\Temp"
$script:ConfigPath = $PSScriptRoot

# Create directories
New-Item -ItemType Directory -Force -Path $script:LogPath | Out-Null
New-Item -ItemType Directory -Force -Path $script:TempPath | Out-Null

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console output with color
    switch ($Level) {
        "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
        "Error" { Write-Host $logMessage -ForegroundColor Red }
        default { Write-Host $logMessage }
    }
    
    # File output
    Add-Content -Path "$script:LogPath\deployment-$(Get-Date -Format 'yyyyMMdd').log" -Value $logMessage
}

# Check prerequisites
function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    # Check Windows version
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.Caption -notlike "*Windows 11*") {
        throw "This script requires Windows 11"
    }
    
    # Check for internet connectivity
    if (-not (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet)) {
        throw "Internet connection required"
    }
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "PowerShell 5.0 or higher required"
    }
    
    Write-Log "Prerequisites check passed"
}

# Install Chocolatey
function Install-Chocolatey {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    } else {
        Write-Log "Chocolatey already installed"
    }
}

# Base system configuration
function Set-BaseConfiguration {
    Write-Log "Applying base system configuration..."
    
    # Set computer name
    if ($env:COMPUTERNAME -ne $ComputerName) {
        Write-Log "Setting computer name to $ComputerName"
        Rename-Computer -NewName $ComputerName -Force
        $script:RestartRequired = $true
    }
    
    # Disable unnecessary services
    $servicesToDisable = @(
        "DiagTrack",        # Connected User Experiences and Telemetry
        "dmwappushservice", # Device Management Wireless Application Protocol
        "RetailDemo",       # Retail Demo Service
        "TrkWks"            # Distributed Link Tracking Client
    )
    
    foreach ($service in $servicesToDisable) {
        if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
            Write-Log "Disabling service: $service"
            Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Enable features
    $featuresToEnable = @(
        "Microsoft-Windows-Subsystem-Linux",
        "VirtualMachinePlatform",
        "Microsoft-Hyper-V-All",
        "Containers"
    )
    
    foreach ($feature in $featuresToEnable) {
        Write-Log "Enabling feature: $feature"
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
    }
    
    # Power settings
    Write-Log "Configuring power settings..."
    powercfg -change -monitor-timeout-ac 0
    powercfg -change -disk-timeout-ac 0
    powercfg -change -standby-timeout-ac 0
    powercfg -change -hibernate-timeout-ac 0
    
    # Windows Update settings
    Write-Log "Configuring Windows Update..."
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $wuPath)) {
        New-Item -Path $wuPath -Force | Out-Null
    }
    Set-ItemProperty -Path $wuPath -Name "SetActiveHours" -Value 1
    Set-ItemProperty -Path $wuPath -Name "ActiveHoursStart" -Value 8
    Set-ItemProperty -Path $wuPath -Name "ActiveHoursEnd" -Value 18
}

# Install base software
function Install-BaseSoftware {
    Write-Log "Installing base software packages..."
    
    $basePackages = @(
        "7zip",
        "notepadplusplus",
        "git",
        "powershell-core",
        "microsoft-windows-terminal",
        "sysinternals",
        "treesizefree",
        "everything",
        "powertoys"
    )
    
    foreach ($package in $basePackages) {
        Write-Log "Installing $package..."
        choco install $package -y --no-progress | Out-Null
    }
}

# Role-specific deployment
function Deploy-Role {
    param([string]$Role)
    
    Write-Log "Deploying role-specific configuration for $Role..."
    
    $roleScript = Join-Path $script:ConfigPath "scripts\Deploy-$Role.ps1"
    if (Test-Path $roleScript) {
        Write-Log "Executing role script: $roleScript"
        & $roleScript
    } else {
        Write-Warning "Role script not found: $roleScript"
    }
}

# Main execution
try {
    Write-Log "="*60
    Write-Log "Starting Magi deployment for role: $Role"
    Write-Log "Target computer name: $ComputerName"
    Write-Log "="*60
    
    # Run checks
    Test-Prerequisites
    
    if (-not $SkipBase) {
        # Install package manager
        Install-Chocolatey
        
        # Base configuration
        Set-BaseConfiguration
        
        # Base software
        Install-BaseSoftware
    } else {
        Write-Log "Skipping base configuration as requested"
    }
    
    # Role-specific deployment
    Deploy-Role -Role $Role
    
    Write-Log "="*60
    Write-Log "Deployment completed successfully!"
    
    if ($script:RestartRequired) {
        Write-Log "*** RESTART REQUIRED ***"
        Write-Log "Please restart the computer to complete configuration"
        
        $restart = Read-Host "Restart now? (Y/N)"
        if ($restart -eq "Y") {
            Restart-Computer -Force
        }
    }
    
} catch {
    Write-Log "Deployment failed: $_" -Level Error
    Write-Log $_.ScriptStackTrace -Level Error
    exit 1
}
