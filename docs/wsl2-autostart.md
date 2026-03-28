# AIStack-Autostart — Task Scheduler Boot Automation

> **Gép:** ASUS Vivobook S 15 – vivo2 (10.10.20.200)  
> **OS:** Windows 11 Home 24H2 ARM64  
> **Dátum:** 2026-03-10  
> **Státusz:** ✅ Éles, tesztelve

---

## TL;DR

```
ONLOGON trigger (VIVO2\istva, PT45S delay, HighestAvailable)
  └── powershell.exe -File C:\AI\scripts\start-ai-stack.ps1
        ├── WSL2 Ubuntu ready check
        ├── Docker service health (+ auto-start ha leállt)
        ├── 4 container health: open-webui, searxng, chromadb, n8n
        ├── Ollama systemd status log
        └── HTTP smoke test: :11434, :3000
```

---

## 1. Architekturális döntések

### 1.1 Miért nem SYSTEM kontextus?

```
SYSTEM + WSL2 = WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED ❌

WSL2 Hyper-V VM-ként fut, amely felhasználói session-höz kötött.
SYSTEM account nem rendelkezik interaktív session-nel →
a WSL2 process launch API elutasítja a hívást.

Megoldás: ONLOGON trigger + InteractiveToken logon type ✅
```

### 1.2 Miért XML-alapú task definíció?

A `schtasks` CLI `/delay` paramétere ONLOGON trigger esetén **silently ignored** — dokumentálatlan viselkedés, de reprodukálható. Az egyetlen megbízható módszer a delay XML-ben definiálni:

```xml
<LogonTrigger>
  <Delay>PT45S</Delay>   <!-- Ez működik -->
</LogonTrigger>
```

```cmd
schtasks /create ... /sc ONLOGON /delay 0:00:45   <!-- Ez NEM működik ONLOGON esetén -->
```

### 1.3 RunLevel: HighestAvailable vs Highest

| RunLevel | Viselkedés | UAC |
|----------|-----------|-----|
| `HighestAvailable` | Elevated ha az account admin, normál ha nem | Prompt nélkül |
| `Highest` | Kötelezően elevated | Meghiúsul ha UAC tiltja |

`HighestAvailable` az ajánlott: elevált jogot ad (szükséges a Hyper-V FW rule kezeléséhez), de nem függ a UAC "Run as administrator" dialógustól.

### 1.4 Miért 45 másodperc delay?

```
Boot folyamat idővonala (Snapdragon X Elite, cold boot):
  0s   – Logon trigger aktivál
 ~10s  – Windows shell, tray inicializálódik
 ~20s  – WSL2 Hyper-V VM indul (ha még nincs fent)
 ~30s  – WSL2 systemd init (ha systemd=true)
 ~40s  – Docker daemon ready (ha systemd-en fut)
  45s  – Script indul → Docker már elérhető ✅
```

30s alatt a script dockert "nem fut"-nak látná és felesleges `service docker start`-ot indítana.

---

## 2. Fájlok

```
C:\AI\
├── scripts\
│   ├── start-ai-stack.ps1           ← Boot script (PS 5.1)
│   ├── start-ai-stack-task.xml      ← Task Scheduler XML definíció
│   └── start-ai-stack.log           ← Runtime log (auto-rotate 500 sor)
└── readme\
    └── README-aistack-autostart.md  ← Ez a dokumentum
```

---

## 3. Task Scheduler definíció

**Fájl:** `C:\AI\scripts\start-ai-stack-task.xml`

```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>AI Stack startup: WSL2 Docker containers + Ollama health check.</Description>
    <Author>VIVO2\istva</Author>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>VIVO2\istva</UserId>
      <Delay>PT45S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>VIVO2\istva</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File "C:\AI\scripts\start-ai-stack.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
```

**Kritikus beállítások magyarázata:**

| Beállítás | Érték | Indok |
|-----------|-------|-------|
| `LogonType` | `InteractiveToken` | WSL2 user session requirement |
| `RunLevel` | `HighestAvailable` | Elevated jogok, UAC prompt nélkül |
| `MultipleInstancesPolicy` | `IgnoreNew` | Párhuzamos futás megelőzése |
| `DisallowStartIfOnBatteries` | `false` | Laptop akkumulátoron is fusson |
| `StartWhenAvailable` | `true` | Ha logon alatt kimaradt, következő alkalommal pótolja |
| `ExecutionTimeLimit` | `PT10M` | Docker cold-start esetén elegendő, de védi a rendszert |
| `Command` | `powershell.exe` | PS 5.1 — nem `pwsh.exe` |

---

## 4. Boot Script logika

**Fájl:** `C:\AI\scripts\start-ai-stack.ps1`

```
Inicializálás
  ├── Log rotate (500 sor felett csonkítja)
  └── Session info log (username, PID)

1. WSL2 ready check
   ├── wsl --list --running | grep Ubuntu
   └── Ha nem fut: wsl -e bash -c "echo WSL2-ready" (lazy init)

2. Docker service
   ├── wsl -e bash -c "service docker status | grep -c 'active (running)'"
   └── Ha 0: wsl -u root -e sh -c "service docker start" + 10s várakozás

3. Container health (×4)
   ├── docker ps --filter name=^/<name>$ --filter status=running -q
   └── Ha üres: cd <compose_dir> && docker compose up -d

4. Ollama systemd check
   └── wsl -e bash -c "systemctl is-active ollama" → csak log, nem restart
       (systemd restart=always kezeli önállóan)

5. HTTP smoke test (nem blokkoló)
   ├── Invoke-WebRequest http://127.0.0.1:11434/ -TimeoutSec 3
   └── Invoke-WebRequest http://127.0.0.1:3000/  -TimeoutSec 3
```

**PS 5.1 specifikus megjegyzések:**
- `Invoke-WebRequest` kötelezően `-UseBasicParsing` — headless kontextusban az IE engine nem elérhető
- `wsl` hívások `2>$null`-lal, mert WSL stderr verbose és a log-ot szennyezi
- `Add-Content` atomikus append — párhuzamos írás nem problémás

---

## 5. Telepítés és verifikáció

### 5.1 Telepítés (admin CMD)

```cmd
:: Könyvtárak
mkdir C:\AI\scripts
mkdir C:\AI\readme

:: Task regisztrálás
schtasks /create /tn "AIStack-Autostart" /xml "C:\AI\scripts\start-ai-stack-task.xml" /f

:: Verifikáció
schtasks /query /tn "AIStack-Autostart" /fo LIST /v
```

**Elvárt output részletek:**
```
Status:           Ready
Logon Mode:       Interactive only
Run As User:      istva
Schedule Type:    At logon time
```

### 5.2 Manuális teszt (reboot nélkül)

```cmd
schtasks /run /tn "AIStack-Autostart"
```

```powershell
Start-Sleep 20
Get-Content "C:\AI\scripts\start-ai-stack.log" -Tail 30
```

### 5.3 TaskScheduler Operational log engedélyezése

Windows Home-on alapértelmezetten disabled — debug sessionökhöz:

```powershell
# Engedélyezés
wevtutil sl "Microsoft-Windows-TaskScheduler/Operational" /e:true

# Registry-alapú perzisztencia (Home editionön a wevtutil nem mindig marad meg)
$logName = "Microsoft-Windows-TaskScheduler/Operational"
$log = New-Object System.Diagnostics.Eventing.Reader.EventLogConfiguration($logName)
$log.IsEnabled = $true
$log.SaveChanges()

# Utolsó 10 TaskScheduler event
Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" -MaxEvents 10 |
    Select-Object TimeCreated, Id, Message | Format-List
```

**Releváns Event ID-k:**

| ID | Esemény |
|----|---------|
| 100 | Task instance started |
| 110 | Task triggered by user |
| 129 | Process created (PID logolva) |
| 200 | Action started |
| 201 | Action completed (return code itt!) |
| 102 | Task instance completed |

---

## 6. Troubleshooting

### Log nem jön létre

```powershell
# Írhatóság teszt
[System.IO.File]::WriteAllText("C:\AI\scripts\test.tmp", "ok")
Test-Path "C:\AI\scripts\test.tmp"
Remove-Item "C:\AI\scripts\test.tmp"

# Script közvetlen futtatás (Task Scheduler bypass)
powershell.exe -ExecutionPolicy Bypass -NonInteractive -File "C:\AI\scripts\start-ai-stack.ps1"
```

### Task fut, de exit code nem 0

```powershell
# Event log: return code az ID 201-es eseményben
Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" |
    Where-Object { $_.Id -eq 201 -and $_.Message -match "AIStack" } |
    Select-Object -First 3 TimeCreated, Message | Format-List
```

### Task nem indul logon után

```powershell
# UAC elevation szükséges-e?
# Ha a user nem admin, HighestAvailable = nem elevated → FW rule sikertelen lesz
whoami /groups | Select-String "S-1-5-32-544"  # Administrators SID

# Encoding ellenőrzés (UTF-16 LE BOM szükséges)
$bytes = [System.IO.File]::ReadAllBytes("C:\AI\scripts\start-ai-stack-task.xml")
"BOM: 0x{0:X2} 0x{1:X2}" -f $bytes[0], $bytes[1]
# Elvárt: 0xFF 0xFE
```

### Docker nem indul el a scriptből

```powershell
# WSL2 fut-e egyáltalán?
wsl --list --running

# Docker systemd státusz WSL2-ben
wsl -e bash -c "systemctl is-active docker; systemctl is-enabled docker"
# Ha not-found: docker nincs systemd-en, hanem sysvinit service-ként
wsl -e bash -c "service docker status"
```

---

## 7. Task kezelési referencia

```cmd
:: Task státusz
schtasks /query /tn "AIStack-Autostart" /fo LIST /v

:: Manuális futtatás
schtasks /run /tn "AIStack-Autostart"

:: Task leállítása ha éppen fut
schtasks /end /tn "AIStack-Autostart"

:: Törlés
schtasks /delete /tn "AIStack-Autostart" /f

:: Újratelepítés XML-ből
schtasks /create /tn "AIStack-Autostart" /xml "C:\AI\scripts\start-ai-stack-task.xml" /f

:: Log utolsó 30 sora
powershell -c "Get-Content C:\AI\scripts\start-ai-stack.log -Tail 30"
```

---

## 8. Ismert korlátok

| Korlát | Részlet | Mitigáció |
|--------|---------|-----------|
| WSL2 ≠ SYSTEM | `WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED` | ONLOGON + InteractiveToken |
| `/delay` ONLOGON-nal | Silently ignored CLI-ből | XML `<Delay>PT45S</Delay>` |
| TaskScheduler Operational log | Windows Home-on disabled by default | `wevtutil` + registry fix |
| Hyper-V FW rule | Nem perzisztens reboot után | `start-ai-stack.ps1` minden futáskor újralétrehozza (ld. Immich ML script) |
| Akkumulátor | `DisallowStartIfOnBatteries=false` → laptop akkun is fut | Szándékos — AI stack akkun is szükséges lehet |

---

*Dokumentálva: 2026-03-10 | vivo2 | AIStack-Autostart Task Scheduler deployment*

