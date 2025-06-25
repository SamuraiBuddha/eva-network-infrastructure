# Windows Fixes and Utilities

This directory contains fixes and utilities for Windows-specific issues, particularly around WSL2, Docker Desktop, and memory management.

## Contents

- **WSL2/Docker Memory Fixes**: Scripts to diagnose and fix memory conflicts causing BSODs
- **Windows Deployment Utilities**: Helper scripts for Windows system configuration

---

# WSL2/Docker Memory Conflict Resolution Guide

## Problem Summary
When Docker Desktop uses WSL2 integration, it can cause MEMORY_MANAGEMENT BSODs with corrupt Page Table Entries (PTEs). This occurs due to conflicts between multiple virtualization layers trying to manage memory simultaneously.

## Immediate Solution
✅ **Disable WSL2 Integration in Docker Desktop**
- Docker now uses Hyper-V backend exclusively
- WSL2 and Docker operate independently
- This should resolve the memory conflicts

## Testing Your Fix

### 1. Restart Docker Desktop
After disabling WSL2 integration:
```powershell
# Restart Docker Desktop
Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
& "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
```

### 2. Verify Docker is Using Hyper-V
```powershell
docker version
# Should show "Server: Docker Desktop" without WSL2 mentions
```

### 3. Monitor for Stability
Run the included `Monitor-StabilityAfterFix.ps1` script periodically

## Alternative Configurations

### Option 1: Keep Current Setup (Recommended)
- Docker → Hyper-V backend
- WSL2 → Separate Linux environments
- ✅ Most stable configuration

### Option 2: Docker Inside WSL2
If you need tighter integration:
```bash
# Inside your WSL2 distro (Ubuntu/Kali)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

### Option 3: Memory Limits for Both

#### WSL2 Configuration
Create/edit `%USERPROFILE%\.wslconfig`:
```ini
[wsl2]
memory=8GB       # Limit WSL2 to 8GB (adjust based on your 64/128GB)
processors=4     # Limit CPU cores
swap=8GB         # Swap size
localhostForwarding=true
kernelCommandLine = vsyscall=emulate
```

#### Docker Desktop Resources
In Docker Desktop Settings → Resources:
- Memory: 8GB (separate from WSL2)
- CPUs: 4
- Disk image size: As needed

### Option 4: Use Podman (Docker Alternative)
```powershell
# Install Podman for Windows
winget install RedHat.Podman
# Podman has better WSL2 integration without conflicts
```

## Long-term Monitoring

### Check for New Crashes
```powershell
# List recent minidumps
Get-ChildItem C:\Windows\Minidump -Filter "*.dmp" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object Name, LastWriteTime, @{N='SizeMB';E={[math]::Round($_.Length/1MB,2)}}
```

### Memory Health Check
```powershell
# Quick memory status
Get-WmiObject Win32_OperatingSystem | 
    Select @{N='TotalGB';E={[math]::Round($_.TotalVisibleMemorySize/1MB,2)}},
           @{N='FreeGB';E={[math]::Round($_.FreePhysicalMemory/1MB,2)}},
           @{N='UsedPct';E={[math]::Round((($_.TotalVisibleMemorySize-$_.FreePhysicalMemory)/$_.TotalVisibleMemorySize)*100,1)}}
```

## When to Re-enable WSL2 Integration

Only consider re-enabling if:
1. ✅ No crashes for 1+ week with current setup
2. ✅ Applied all Windows Updates
3. ✅ Updated Docker Desktop to latest version
4. ✅ Configured memory limits for both WSL2 and Docker
5. ✅ Have a specific need for the integration

## Red Flags to Watch For

If you see any of these, the issue may not be fully resolved:
- 🚨 New MEMORY_MANAGEMENT BSODs
- 🚨 High commit charge (>90%)
- 🚨 Docker or WSL2 consuming excessive memory
- 🚨 System freezes during container operations

## Hardware Considerations

Given high-end systems (64-128GB RAM), also verify:
- XMP/DOCP profiles are stable
- RAM is properly cooled
- No single-bit errors in memory tests
- BIOS/UEFI is up to date

## Scripts in This Directory

- `Monitor-StabilityAfterFix.ps1` - Post-fix monitoring script
- More scripts to be added as consolidated from other repos

## Support Resources

- [Docker Desktop WSL2 Backend](https://docs.docker.com/desktop/wsl/)
- [WSL2 Configuration](https://docs.microsoft.com/en-us/windows/wsl/wsl-config)
- [Windows Debugging Tools](https://docs.microsoft.com/en-us/windows-hardware/drivers/debugger/)

---

> **Note**: This content was migrated from the `wsl-docker-memory-fix` repository as part of the infrastructure consolidation effort. The original repository can be archived.

Remember: The safest configuration is keeping Docker and WSL2 separate. Only re-integrate if absolutely necessary for your workflow.
