# start-ai-stack.ps1
# Starts the WSL2-based AI stack on login.
# Called by Task Scheduler ONLOGON task with 45s delay.
# Source: https://github.com/gaiagent0/homelab-ai-stack

$LogFile = "C:\AI\logs\ai-stack-start.log"
$ComposeFile = "C:\AI\wsl2\docker-compose.yml"
$EnvFile = "C:\AI\wsl2\.env"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Add-Content $LogFile "[$Timestamp] AI stack startup initiated"

# Ensure WSL is running (first access wakes it)
wsl -e echo "WSL2 ready" | Out-Null

# Recreate Hyper-V Firewall rule for Immich ML port (reset on updates)
$ImmichRule = Get-NetFirewallRule -DisplayName "ImmichML3003" -ErrorAction SilentlyContinue
if (-not $ImmichRule) {
    New-NetFirewallRule -DisplayName "ImmichML3003" `
        -Direction Inbound -Protocol TCP -LocalPort 3003 `
        -RemoteAddress "10.10.40.0/24" `
        -Action Allow -Profile Any | Out-Null
    Add-Content $LogFile "[$Timestamp] Hyper-V Firewall rule ImmichML3003 created"
}

# Start Docker Compose stack inside WSL2
wsl -e bash -c "cd /mnt/c/AI/wsl2 && docker compose --env-file .env up -d >> /tmp/ai-stack-compose.log 2>&1"
$ExitCode = $LASTEXITCODE

if ($ExitCode -eq 0) {
    Add-Content $LogFile "[$Timestamp] Docker Compose up successful"
} else {
    Add-Content $LogFile "[$Timestamp] Docker Compose up FAILED (exit $ExitCode) — check /tmp/ai-stack-compose.log"
}
