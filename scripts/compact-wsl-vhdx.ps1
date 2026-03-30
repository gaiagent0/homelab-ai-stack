# compact-wsl-vhdx.ps1
# Reclaim disk space after large deletions inside WSL2 (e.g. model cache cleanup).
# The ext4.vhdx file does NOT shrink automatically — this script compacts it.
#
# Source: https://github.com/gaiagent0/homelab-ai-stack
#
# Usage:
#   Run as Administrator:
#   powershell -ExecutionPolicy Bypass -File compact-wsl-vhdx.ps1
#
# Expected: ext4.vhdx shrinks from ~100 GB to ~40 GB after removing ~60 GB of model cache.

param(
    [string]$DistroName = "Ubuntu"
)

$LogFile = "C:\AI\logs\compact-vhdx.log"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log { param([string]$Msg)
    $line = "[$Timestamp] $Msg"
    Write-Host $line
    Add-Content $LogFile $line
}

Write-Log "=== WSL2 VHDX Compact ==="
Write-Log "Distro: $DistroName"

# Step 1: Zero out free blocks inside WSL2 (makes compression effective)
Write-Log "Step 1: Zeroing free blocks inside WSL2 (this may take a few minutes)..."
wsl -d $DistroName -e bash -c "dd if=/dev/zero of=~/zero.tmp bs=1M status=progress 2>&1 | tail -1; rm -f ~/zero.tmp"
Write-Log "Step 1 complete."

# Step 2: Shut down WSL2 to release VHDX lock
Write-Log "Step 2: Shutting down WSL2..."
wsl --shutdown
Start-Sleep -Seconds 5
Write-Log "WSL2 shutdown complete."

# Step 3: Find VHDX path
$VhdxPath = (Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Recurse -Filter "ext4.vhdx" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match $DistroName -or $_.FullName -match "Ubuntu" } |
    Select-Object -First 1).FullName

if (-not $VhdxPath) {
    # Fallback: common paths
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc\LocalState\ext4.vhdx",
        "$env:USERPROFILE\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc\LocalState\ext4.vhdx"
    )
    $VhdxPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $VhdxPath) {
    Write-Log "ERROR: ext4.vhdx not found. Check distro name: wsl --list --verbose"
    exit 1
}

$SizeBefore = [math]::Round((Get-Item $VhdxPath).Length / 1GB, 2)
Write-Log "VHDX path: $VhdxPath"
Write-Log "Size before: $SizeBefore GB"

# Step 4: Compact via Optimize-VHD (requires Hyper-V role or diskpart)
Write-Log "Step 4: Compacting VHDX via diskpart..."
$DiskpartScript = @"
select vdisk file="$VhdxPath"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@
$TempScript = [System.IO.Path]::GetTempFileName() + ".txt"
$DiskpartScript | Out-File -Encoding ASCII $TempScript
diskpart /s $TempScript | Out-Null
Remove-Item $TempScript -ErrorAction SilentlyContinue

$SizeAfter = [math]::Round((Get-Item $VhdxPath).Length / 1GB, 2)
$Saved = [math]::Round($SizeBefore - $SizeAfter, 2)
Write-Log "Size after:  $SizeAfter GB"
Write-Log "Reclaimed:   $Saved GB"
Write-Log "=== Compact complete ==="

Write-Host ""
Write-Host "Done! Reclaimed $Saved GB. VHDX: $SizeBefore GB → $SizeAfter GB" -ForegroundColor Green
