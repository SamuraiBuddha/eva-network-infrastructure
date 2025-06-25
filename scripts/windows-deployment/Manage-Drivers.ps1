# Driver Management for Magi Workstations
# Handles driver installation for RTX 3090, A5000, A4000, and system-specific drivers

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Melchior", "Balthazar", "Caspar", "All")]
    [string]$Machine = "All",
    
    [Parameter(Mandatory=$false)]
    [string]$DriverRepository = "\\DEPLOYSERVER\Drivers$",
    
    [Parameter(Mandatory=$false)]
    [switch]$DownloadLatest,
    
    [Parameter(Mandatory=$false)]
    [switch]$ForceReinstall
)

# Driver versions and URLs
$DriverSources = @{
    NVIDIA = @{
        RTX3090 = @{
            Version = "566.14"
            URL = "https://us.download.nvidia.com/Windows/566.14/566.14-desktop-win10-win11-64bit-international-dch-whql.exe"
            Filename = "nvidia-rtx3090-566.14.exe"
        }
        RTXA5000 = @{
            Version = "566.14"
            URL = "https://us.download.nvidia.com/Windows/Quadro_Certified/566.14/566.14-quadro-rtx-desktop-notebook-win10-win11-64bit-international-dch-whql.exe"
            Filename = "nvidia-rtxa5000-566.14.exe"
        }
        RTXA4000 = @{
            Version = "566.14"
            URL = "https://us.download.nvidia.com/Windows/Quadro_Certified/566.14/566.14-quadro-rtx-desktop-notebook-win10-win11-64bit-international-dch-whql.exe"
            Filename = "nvidia-rtxa4000-566.14.exe"
        }
    }
    Intel = @{
        Z590 = @{
            Version = "10.1.19743.8493"
            URL = "https://downloadmirror.intel.com/819116/SetupChipset.exe"
            Filename = "intel-z590-chipset.exe"
        }
        Network10GbE = @{
            Version = "28.3"
            URL = "https://downloadmirror.intel.com/819425/Wired_driver_28.3_x64.exe"
            Filename = "intel-10gbe-28.3.exe"
        }
    }
    AMD = @{
        X570 = @{
            Version = "5.12.0.38"
            URL = "https://drivers.amd.com/drivers/amd_chipset_software_5.12.0.38.exe"
            Filename = "amd-x570-chipset.exe"
        }
    }
}

# Machine-specific driver mappings
$MachineDrivers = @{
    Melchior = @{
        GPU = "RTX3090"
        Chipset = "Z590"
        Network = "Network10GbE"
        Platform = "Intel"
    }
    Balthazar = @{
        GPU = "RTXA5000"
        Chipset = "Z590"
        Network = "Network10GbE"
        Platform = "Intel"
    }
    Caspar = @{
        GPU = "RTXA4000"
        Chipset = "X570"
        Network = "Network10GbE"
        Platform = "AMD"
    }
}

function Get-CurrentGPU {
    $gpu = Get-WmiObject Win32_VideoController | Where-Object {$_.Name -like "*NVIDIA*"} | Select-Object -First 1
    if ($gpu) {
        if ($gpu.Name -match "3090") { return "RTX3090" }
        elseif ($gpu.Name -match "A5000") { return "RTXA5000" }
        elseif ($gpu.Name -match "A4000") { return "RTXA4000" }
    }
    return $null
}

function Get-CurrentPlatform {
    $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
    if ($cpu.Manufacturer -like "*Intel*") { return "Intel" }
    elseif ($cpu.Manufacturer -like "*AMD*") { return "AMD" }
    return $null
}

function Download-Driver {
    param(
        [string]$URL,
        [string]$Destination
    )
    
    Write-Host "Downloading driver from $URL..."
    try {
        Start-BitsTransfer -Source $URL -Destination $Destination -DisplayName "Driver Download"
        return $true
    }
    catch {
        Write-Error "Failed to download driver: $_"
        return $false
    }
}

function Install-NVIDIADriver {
    param(
        [string]$DriverPath,
        [switch]$Silent
    )
    
    Write-Host "Installing NVIDIA driver..."
    $args = @(
        "-s"          # Silent
        "-clean"      # Clean install
        "-noreboot"   # No reboot
        "-noeula"     # Skip EULA
    )
    
    Start-Process -FilePath $DriverPath -ArgumentList $args -Wait
}

function Install-ChipsetDriver {
    param(
        [string]$DriverPath,
        [string]$Type
    )
    
    Write-Host "Installing $Type chipset driver..."
    if ($Type -eq "Intel") {
        Start-Process -FilePath $DriverPath -ArgumentList "-s", "-accepteula" -Wait
    }
    elseif ($Type -eq "AMD") {
        Start-Process -FilePath $DriverPath -ArgumentList "/S" -Wait
    }
}

function Install-NetworkDriver {
    param(
        [string]$DriverPath
    )
    
    Write-Host "Installing 10GbE network driver..."
    Start-Process -FilePath $DriverPath -ArgumentList "/quiet", "/norestart" -Wait
}

function Install-DriversForMachine {
    param(
        [string]$MachineName
    )
    
    Write-Host "`nInstalling drivers for $MachineName..."
    
    $config = $MachineDrivers[$MachineName]
    if (-not $config) {
        Write-Error "Unknown machine: $MachineName"
        return
    }
    
    # GPU Driver
    $gpuInfo = $DriverSources.NVIDIA[$config.GPU]
    $gpuPath = Join-Path $DriverRepository "GPU\$($gpuInfo.Filename)"
    
    if ($DownloadLatest -or -not (Test-Path $gpuPath)) {
        if (Download-Driver -URL $gpuInfo.URL -Destination $gpuPath) {
            Install-NVIDIADriver -DriverPath $gpuPath -Silent
        }
    }
    elseif (Test-Path $gpuPath) {
        Install-NVIDIADriver -DriverPath $gpuPath -Silent
    }
    
    # Chipset Driver
    $chipsetInfo = $DriverSources.$($config.Platform)[$config.Chipset]
    $chipsetPath = Join-Path $DriverRepository "Chipset\$($chipsetInfo.Filename)"
    
    if ($DownloadLatest -or -not (Test-Path $chipsetPath)) {
        if (Download-Driver -URL $chipsetInfo.URL -Destination $chipsetPath) {
            Install-ChipsetDriver -DriverPath $chipsetPath -Type $config.Platform
        }
    }
    elseif (Test-Path $chipsetPath) {
        Install-ChipsetDriver -DriverPath $chipsetPath -Type $config.Platform
    }
    
    # Network Driver
    $networkInfo = $DriverSources.Intel[$config.Network]
    $networkPath = Join-Path $DriverRepository "Network\$($networkInfo.Filename)"
    
    if ($DownloadLatest -or -not (Test-Path $networkPath)) {
        if (Download-Driver -URL $networkInfo.URL -Destination $networkPath) {
            Install-NetworkDriver -DriverPath $networkPath
        }
    }
    elseif (Test-Path $networkPath) {
        Install-NetworkDriver -DriverPath $networkPath
    }
    
    Write-Host "Driver installation complete for $MachineName"
}

function Get-DriverStatus {
    Write-Host "`nCurrent Driver Status:"
    Write-Host "===================="
    
    # GPU
    $gpu = Get-WmiObject Win32_VideoController | Where-Object {$_.Name -like "*NVIDIA*"} | Select-Object -First 1
    if ($gpu) {
        Write-Host "GPU: $($gpu.Name)"
        Write-Host "Driver Version: $($gpu.DriverVersion)"
        Write-Host "Driver Date: $($gpu.DriverDate)"
    }
    
    # Network
    $net = Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "*10G*" -or $_.LinkSpeed -eq "10 Gbps"}
    if ($net) {
        Write-Host "`nNetwork Adapter: $($net.InterfaceDescription)"
        Write-Host "Link Speed: $($net.LinkSpeed)"
        Write-Host "Status: $($net.Status)"
    }
    
    # System
    $sys = Get-ComputerInfo
    Write-Host "`nSystem: $($sys.CsManufacturer) $($sys.CsModel)"
    Write-Host "BIOS: $($sys.BiosManufacturer) $($sys.BiosVersion)"
}

# Main execution
Write-Host "Magi Workstation Driver Manager"
Write-Host "================================"

# Create driver repository structure
$folders = @(
    "$DriverRepository\GPU",
    "$DriverRepository\Chipset",
    "$DriverRepository\Network",
    "$DriverRepository\Audio",
    "$DriverRepository\USB"
)

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
}

# Install drivers based on parameter
if ($Machine -eq "All") {
    foreach ($m in $MachineDrivers.Keys) {
        Install-DriversForMachine -MachineName $m
    }
}
else {
    # Auto-detect if no machine specified
    if ($Machine -eq "") {
        $detectedGPU = Get-CurrentGPU
        $detectedPlatform = Get-CurrentPlatform
        
        foreach ($name in $MachineDrivers.Keys) {
            if ($MachineDrivers[$name].GPU -eq $detectedGPU -and 
                $MachineDrivers[$name].Platform -eq $detectedPlatform) {
                $Machine = $name
                Write-Host "Auto-detected machine: $Machine"
                break
            }
        }
    }
    
    if ($Machine) {
        Install-DriversForMachine -MachineName $Machine
    }
    else {
        Write-Error "Could not determine machine type. Please specify -Machine parameter."
    }
}

# Show final status
Get-DriverStatus

Write-Host "`nDriver management complete!"