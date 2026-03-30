# WSL2 Task Scheduler Setup — Autostart Debugging Guide

> Complete guide for setting up and troubleshooting the AI stack Task Scheduler task on Windows 11 ARM64. Covers the `WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED` pitfall, the `schtasks /delay` silent-ignore bug, and XML-based task definition.

---

## The Problem

On Windows 11 (including Home edition), two non-obvious issues affect WSL2 autostart via Task Scheduler:

### Issue 1: SYSTEM account cannot start WSL2

```
Error: WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED (0xc03a001c)
```

WSL2 runs as a Hyper-V VM tied to an interactive user session. The SYSTEM account has no interactive session, so any task running as SYSTEM fails to launch WSL2.

**Fix:** Use `ONLOGON` trigger with `InteractiveToken` logon type, running as your actual user account.

### Issue 2: `schtasks /delay` is silently ignored for ONLOGON triggers

```cmd
schtasks /create /sc ONLOGON /delay 0:00:45 /...
:: The /delay parameter is accepted without error but has NO effect.
```

This is a documented bug in Windows Task Scheduler CLI. The delay is silently dropped.

**Fix:** Define the task via XML with `<Delay>PT45S</Delay>` inside the `<LogonTrigger>` element. XML-imported tasks respect the delay correctly.

---

## The XML Task Definition

**File:** `wsl2/ai-stack-task.xml` (included in this repo)

```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Start WSL2 AI Docker stack on user login</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>VIVO2\istva</UserId>  <!-- CHANGE: your COMPUTERNAME\username -->
      <Delay>PT45S</Delay>          <!-- 45-second delay after logon -->
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>VIVO2\istva</UserId>  <!-- CHANGE: same as above -->
      <LogonType>InteractiveToken</LogonType>  <!-- CRITICAL: not SYSTEM -->
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\AI\scripts\start-ai-stack.ps1</Arguments>
    </Exec>
  </Actions>
</Task>
```

**Before importing:** Edit `<UserId>` entries to match your `COMPUTERNAME\username`.

Find your values:

```powershell
$env:COMPUTERNAME   # machine name
$env:USERNAME       # your username
# Combined: VIVO2\istva → YOURPC\yourusername
```

---

## Installation

### Step 1 — Prepare directories

```powershell
New-Item -ItemType Directory -Force -Path "C:\AI\scripts"
New-Item -ItemType Directory -Force -Path "C:\AI\logs"
```

### Step 2 — Copy scripts

```powershell
Copy-Item "scripts\start-ai-stack.ps1" "C:\AI\scripts\"
Copy-Item "wsl2\ai-stack-task.xml" "C:\AI\scripts\"
```

### Step 3 — Edit XML (set your username)

```powershell
notepad "C:\AI\scripts\ai-stack-task.xml"
# Replace VIVO2\istva with your COMPUTERNAME\username
```

### Step 4 — Register the task (run as Administrator)

```cmd
schtasks /create /tn "AIStack-Autostart" /xml "C:\AI\scripts\ai-stack-task.xml" /f
```

### Step 5 — Verify

```cmd
schtasks /query /tn "AIStack-Autostart" /fo LIST /v
```

Expected output:
```
Task To Run:     powershell.exe -NonInteractive -WindowStyle Hidden ...
Run As User:     gaiagent0
Schedule Type:   At logon time
Logon Mode:      Interactive only
Status:          Ready
```

### Step 6 — Test without rebooting

```cmd
schtasks /run /tn "AIStack-Autostart"
```

```powershell
Start-Sleep 20
Get-Content "C:\AI\logs\ai-stack-start.log" -Tail 30
```

---

## XML Encoding Requirement

Task Scheduler XML files **must be UTF-16 LE with BOM**. When editing:
- Use Notepad (saves UTF-16 correctly on Windows)
- Avoid VS Code unless you explicitly set encoding to `UTF-16 LE`

Verify encoding:

```powershell
$bytes = [System.IO.File]::ReadAllBytes("C:\AI\scripts\ai-stack-task.xml")
"BOM bytes: 0x{0:X2} 0x{1:X2}" -f $bytes[0], $bytes[1]
# Expected: 0xFF 0xFE (UTF-16 LE BOM)
```

---

## Troubleshooting

### Task runs but WSL2 doesn't start

```powershell
# Check if task is running as SYSTEM (wrong)
schtasks /query /tn "AIStack-Autostart" /fo LIST /v | Select-String "Run As"
# Must show your username, NOT "SYSTEM" or "NT AUTHORITY\SYSTEM"

# If SYSTEM: delete and re-import XML
schtasks /delete /tn "AIStack-Autostart" /f
schtasks /create /tn "AIStack-Autostart" /xml "C:\AI\scripts\ai-stack-task.xml" /f
```

### No log file created after logon

```powershell
# Run the script directly to see errors:
powershell.exe -ExecutionPolicy Bypass -File "C:\AI\scripts\start-ai-stack.ps1"

# Check if C:\AI\logs\ exists and is writable:
Test-Path "C:\AI\logs"
New-Item -Path "C:\AI\logs\test.tmp" -ItemType File -Force
Remove-Item "C:\AI\logs\test.tmp"
```

### Enable Task Scheduler operational logging

```powershell
# Enable (requires admin):
wevtutil sl "Microsoft-Windows-TaskScheduler/Operational" /e:true

# View last 10 task events:
Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" -MaxEvents 10 |
    Where-Object { $_.Message -match "AIStack" } |
    Format-List TimeCreated, Id, Message
```

Key Event IDs: `100` (started), `201` (completed + return code), `102` (instance done).

### Delay not working (task fires immediately)

The task was likely created via CLI and the delay was silently ignored. Delete and re-import from XML:

```cmd
schtasks /delete /tn "AIStack-Autostart" /f
schtasks /create /tn "AIStack-Autostart" /xml "C:\AI\scripts\ai-stack-task.xml" /f
```

---

## Boot Timing Reference

Why 45 seconds? This is the measured cold-boot sequence on Snapdragon X Elite:

| Time after logon | Event |
|---|---|
| 0s | ONLOGON trigger fires |
| ~10s | Windows shell + tray initialized |
| ~20s | WSL2 Hyper-V VM boots |
| ~30s | WSL2 systemd init completes |
| ~40s | Docker daemon ready |
| 45s | Script starts → Docker available ✅ |

Adjust `<Delay>` in the XML if your hardware boots faster or slower.

---

## Task Management Reference

```cmd
:: Status
schtasks /query /tn "AIStack-Autostart" /fo LIST /v

:: Manual run
schtasks /run /tn "AIStack-Autostart"

:: Stop if running
schtasks /end /tn "AIStack-Autostart"

:: Delete
schtasks /delete /tn "AIStack-Autostart" /f

:: Re-register from XML
schtasks /create /tn "AIStack-Autostart" /xml "C:\AI\scripts\ai-stack-task.xml" /f
```

---

*Tested on: Windows 11 Home 24H2 ARM64, Build 26100 · Snapdragon X Elite*
