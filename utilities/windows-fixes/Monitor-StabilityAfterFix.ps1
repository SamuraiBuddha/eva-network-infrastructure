#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Monitors system stability after disabling WSL2/Docker integration
.DESCRIPTION
    This script helps monitor if the WSL2/Docker separation resolved BSOD issues
#>

Write-Host "Post-Configuration Stability Monitor" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green

# Check current Docker backend
function Test-DockerBackend {
    Write-Host "`n[Docker Backend Check]" -ForegroundColor Yellow
    
    $dockerInfo = docker version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Docker is running" -ForegroundColor Green
        
        # Check if WSL2 integration is disabled
        $settings = Get-Content "$env:APPDATA\Docker\settings.json" -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($settings) {
            if ($settings.wslEngineEnabled -eq $false) {
                Write-Host "✓ WSL2 integration is DISABLED (using Hyper-V)" -ForegroundColor Green
            } else {
                Write-Host "✗ WSL2 integration is still enabled!" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "Docker is not running or not accessible" -ForegroundColor Yellow
    }
}

# Check for new crash dumps since change
function Test-NewCrashes {
    Write-Host "`n[Crash Dump Analysis]" -ForegroundColor Yellow
    
    $changeTime = (Get-Date).AddHours(-1)  # Adjust based on when you made the change
    $newDumps = Get-ChildItem "C:\Windows\Minidump" -Filter "*.dmp" -ErrorAction SilentlyContinue | 
                Where-Object { $_.LastWriteTime -gt $changeTime }
    
    if ($newDumps) {
        Write-Host "⚠ New crash dumps detected since configuration change:" -ForegroundColor Red
        $newDumps | ForEach-Object { Write-Host "  - $($_.Name) at $($_.LastWriteTime)" }
    } else {
        Write-Host "✓ No new crashes since configuration change" -ForegroundColor Green
    }
}

# Check memory usage
function Test-MemoryHealth {
    Write-Host "`n[Memory Status]" -ForegroundColor Yellow
    
    $os = Get-WmiObject Win32_OperatingSystem
    $totalMem = $os.TotalVisibleMemorySize / 1MB
    $freeMem = $os.FreePhysicalMemory / 1MB
    $percentFree = ($freeMem / $totalMem) * 100
    
    Write-Host "Free Memory: $([math]::Round($freeMem, 2)) GB ($([math]::Round($percentFree, 1))%)"
    
    # Check commit charge
    $perfMem = Get-WmiObject Win32_PerfFormattedData_PerfOS_Memory
    $commitRatio = ($perfMem.PercentCommittedBytesInUse)
    Write-Host "Commit Charge: $commitRatio%"
    
    if ($commitRatio -lt 80) {
        Write-Host "✓ Memory pressure is normal" -ForegroundColor Green
    } else {
        Write-Host "⚠ High memory pressure detected" -ForegroundColor Yellow
    }
}

# Check running VMs
function Test-RunningVMs {
    Write-Host "`n[Virtual Machine Status]" -ForegroundColor Yellow
    
    # Check Hyper-V VMs
    $vms = Get-VM -ErrorAction SilentlyContinue
    if ($vms) {
        Write-Host "Active Hyper-V VMs:"
        $vms | ForEach-Object { 
            Write-Host "  - $($_.Name): $($_.State), Memory: $($_.MemoryAssigned / 1GB) GB"
        }
    }
    
    # Check WSL status
    $wslRunning = wsl -l --running 2>$null
    if ($wslRunning -and $wslRunning.Count -gt 1) {
        Write-Host "`nRunning WSL Distributions:"
        $wslRunning | Select-Object -Skip 1 | ForEach-Object { Write-Host "  - $_" }
    } else {
        Write-Host "No WSL distributions currently running"
    }
}

# Main execution
Write-Host "`nChecking system stability after WSL/Docker separation..." -ForegroundColor Cyan

Test-DockerBackend
Test-NewCrashes
Test-MemoryHealth
Test-RunningVMs

Write-Host "`n[Recommendations]" -ForegroundColor Cyan
Write-Host "1. Run both Docker and WSL2 workloads to test stability"
Write-Host "2. Monitor for 24-48 hours for any new crashes"
Write-Host "3. If stable, this confirms WSL/Docker conflict was the cause"
Write-Host "4. If crashes continue, run memory diagnostic tools"

Write-Host "`n[Alternative Solutions if Needed]" -ForegroundColor Yellow
Write-Host "- Use Docker in WSL2 directly (install Docker inside WSL2 distro)"
Write-Host "- Use Podman as Docker alternative"
Write-Host "- Limit memory for both Docker and WSL2 separately"
