# collect-system-info.ps1
# Collects comprehensive system information for homelab documentation

param(
    [Parameter(Mandatory=$true)]
    [string]$MachineName,
    
    [string]$OutputPath = ".\workstations\$MachineName\hardware"
)

Write-Host "=== Homelab System Information Collector ===" -ForegroundColor Cyan
Write-Host "Machine: $MachineName" -ForegroundColor Yellow

# Create output directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "Created output directory: $OutputPath" -ForegroundColor Green
}

# Function to run and save command output
function Save-CommandOutput {
    param(
        [string]$Command,
        [string]$Arguments,
        [string]$OutputFile,
        [string]$Description
    )
    
    Write-Host "Collecting $Description..." -NoNewline
    try {
        $output = & $Command $Arguments.Split(' ') 2>&1
        $output | Out-File -FilePath "$OutputPath\$OutputFile" -Encoding UTF8
        Write-Host " Done" -ForegroundColor Green
    } catch {
        Write-Host " Failed: $_" -ForegroundColor Red
    }
}

# System Information
Write-Host "`nCollecting System Information..." -ForegroundColor Cyan

# Basic System Info
Get-ComputerInfo | Select-Object `
    CsName, CsManufacturer, CsModel, CsSystemType,
    OsName, OsVersion, OsBuildNumber, OsArchitecture,
    CsProcessors, CsTotalPhysicalMemory,
    BiosManufacturer, BiosVersion, BiosReleaseDate |
    ConvertTo-Json -Depth 10 | Out-File "$OutputPath\system-info.json" -Encoding UTF8

# CPU Information
Write-Host "Collecting CPU information..." -NoNewline
Get-WmiObject Win32_Processor | Select-Object `
    Name, Manufacturer, Description, Family, 
    NumberOfCores, NumberOfLogicalProcessors,
    MaxClockSpeed, L2CacheSize, L3CacheSize |
    ConvertTo-Json -Depth 10 | Out-File "$OutputPath\cpu-info.json" -Encoding UTF8
Write-Host " Done" -ForegroundColor Green

# Memory Information
Write-Host "Collecting Memory information..." -NoNewline
Get-WmiObject Win32_PhysicalMemory | Select-Object `
    Manufacturer, PartNumber, SerialNumber,
    Capacity, Speed, ConfiguredClockSpeed,
    DataWidth, FormFactor, MemoryType |
    ConvertTo-Json -Depth 10 | Out-File "$OutputPath\memory-info.json" -Encoding UTF8
Write-Host " Done" -ForegroundColor Green

# GPU Information
Write-Host "Collecting GPU information..." -NoNewline
Get-WmiObject Win32_VideoController | Select-Object `
    Name, VideoProcessor, AdapterRAM, DriverVersion,
    DriverDate, VideoModeDescription |
    ConvertTo-Json -Depth 10 | Out-File "$OutputPath\gpu-info.json" -Encoding UTF8

# NVIDIA specific info if available
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    nvidia-smi -q | Out-File "$OutputPath\nvidia-smi-full.txt" -Encoding UTF8
    nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,temperature.gpu,power.draw --format=csv |
        Out-File "$OutputPath\nvidia-smi-summary.csv" -Encoding UTF8
}
Write-Host " Done" -ForegroundColor Green

# Storage Information
Write-Host "Collecting Storage information..." -NoNewline
Get-PhysicalDisk | Select-Object `
    FriendlyName, MediaType, Size, HealthStatus,
    BusType, FirmwareVersion, Model |
    ConvertTo-Json -Depth 10 | Out-File "$OutputPath\storage-info.json" -Encoding UTF8

Get-Volume | Where-Object {$_.DriveLetter} | Select-Object `
    DriveLetter, FileSystemLabel, FileSystem,
    Size, SizeRemaining, HealthStatus |
    ConvertTo-Json -Depth 10 | Out-File "$OutputPath\volumes-info.json" -Encoding UTF8
Write-Host " Done" -ForegroundColor Green

# Network Information
Write-Host "Collecting Network information..." -NoNewline
Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object `
    Name, InterfaceDescription, MacAddress,
    LinkSpeed, MediaType, PhysicalMediaType |
    ConvertTo-Json -Depth 10 | Out-File "$OutputPath\network-adapters.json" -Encoding UTF8

Get-NetIPConfiguration | ConvertTo-Json -Depth 10 |
    Out-File "$OutputPath\network-config.json" -Encoding UTF8
Write-Host " Done" -ForegroundColor Green

# Motherboard Information
Write-Host "Collecting Motherboard information..." -NoNewline
Get-WmiObject Win32_BaseBoard | Select-Object `
    Manufacturer, Product, Version, SerialNumber |
    ConvertTo-Json -Depth 10 | Out-File "$OutputPath\motherboard-info.json" -Encoding UTF8
Write-Host " Done" -ForegroundColor Green

# BIOS Information
Write-Host "Collecting BIOS information..." -NoNewline
Get-WmiObject Win32_BIOS | Select-Object `
    Manufacturer, Name, Version, ReleaseDate,
    SMBIOSBIOSVersion, SMBIOSMajorVersion, SMBIOSMinorVersion |
    ConvertTo-Json -Depth 10 | Out-File "$OutputPath\bios-info.json" -Encoding UTF8
Write-Host " Done" -ForegroundColor Green

# Power Configuration
Write-Host "Collecting Power configuration..." -NoNewline
powercfg /list | Out-File "$OutputPath\power-plans.txt" -Encoding UTF8
powercfg /query SCHEME_CURRENT | Out-File "$OutputPath\power-current-plan.txt" -Encoding UTF8
Write-Host " Done" -ForegroundColor Green

# Docker Information (if available)
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host "Collecting Docker information..." -NoNewline
    docker version | Out-File "$OutputPath\docker-version.txt" -Encoding UTF8
    docker info --format json | Out-File "$OutputPath\docker-info.json" -Encoding UTF8
    docker ps -a --format json | Out-File "$OutputPath\docker-containers.json" -Encoding UTF8
    Write-Host " Done" -ForegroundColor Green
}

# Create summary report
Write-Host "`nGenerating summary report..." -NoNewline
$summary = @{
    CollectionDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    MachineName = $MachineName
    ComputerName = $env:COMPUTERNAME
    Username = $env:USERNAME
    FilesCollected = (Get-ChildItem $OutputPath).Count
}
$summary | ConvertTo-Json | Out-File "$OutputPath\collection-summary.json" -Encoding UTF8
Write-Host " Done" -ForegroundColor Green

Write-Host "`n=== Collection Complete ===" -ForegroundColor Cyan
Write-Host "Files saved to: $OutputPath" -ForegroundColor Yellow
Write-Host "Total files created: $((Get-ChildItem $OutputPath).Count)" -ForegroundColor Yellow

# Reminder about BIOS settings
Write-Host "`n[REMINDER] Don't forget to export BIOS settings:" -ForegroundColor Magenta
Write-Host "1. Restart and enter BIOS (DEL key)" -ForegroundColor White
Write-Host "2. F7 for Advanced Mode" -ForegroundColor White
Write-Host "3. Tool -> ASUS User Profile -> Save to USB" -ForegroundColor White
Write-Host "4. Copy .CMO file to: $OutputPath\..\bios\" -ForegroundColor White
