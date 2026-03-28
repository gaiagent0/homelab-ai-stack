# Immich Remote Machine Learning — Snapdragon X Elite ML Host

**Architektúra:** Proxmox Cluster (pve-03 / CT 302 docker-host) → ASUS Vivobook S15 (vivo2)  
**Cél:** Immich ML worker (arcfelismerés + CLIP keresés + OCR) kiszervezése Snapdragon X Elite CPU-ra  
**Státusz:** ✅ Production | 2026-03-08  
**Immich verzió:** v2.5.6

---

## Architektúra áttekintés

```
┌─────────────────────────────────────────────────────────────┐
│                    Proxmox Cluster                          │
│  pve-03 (10.10.40.13)                                       │
│  └── CT 302 docker-host (10.10.40.32)                       │
│       ├── immich-server          :2283  ◄── http://immich.lan│
│       ├── immich-postgres        :5432                      │
│       ├── immich-redis           :6379                      │
│       ├── immich-power-tools     :8002                      │
│       └── [immich-ml ELTÁVOLÍTVA] ← ML kiszervezve!        │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTP :3003 (ML inference API)
                       │ SERVERS VLAN → MAIN VLAN
                       │ MikroTik forward rule (pos.29)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│          ASUS Vivobook S15 — vivo2 (10.10.20.200)           │
│          Snapdragon X Elite X1E78100 | 32 GB RAM            │
│          Windows 11 + WSL2 Ubuntu 24.04 (systemd=true)      │
│                                                             │
│  Networking stack (kritikus rétegek!):                      │
│  ├── .wslconfig: networkingMode=mirrored                    │
│  ├── Docker: network_mode: host                             │
│  ├── Hyper-V Firewall rule: ImmichML3003 (inbound :3003)    │
│  └── Windows Firewall rule: 3003/tcp ← 10.10.40.0/24       │
│                                                             │
│  WSL2 / Docker:                                             │
│  └── immich-machine-learning  :3003                         │
│       ├── CLIP: ViT-B-16-SigLIP2__webli                    │
│       ├── Face: buffalo_l                                   │
│       └── OCR:  PP-OCRv5_mobile (Latin — magyar ✅)         │
└─────────────────────────────────────────────────────────────┘
```

**Adatfolyam:** `immich-server → HTTP POST :3003/predict → WSL2 Docker → Oryon CPU inference → JSON embedding → Postgres`

> A fotók **nem másolódnak** a laptopra — csak embedding vektorok és thumbnail-ek utaznak a hálózaton.

---

## 1. Kritikus architekturális tanulságok

### WSL2 mirrored + Docker network_mode döntési fa

```
Bridge networking (-p 0.0.0.0:3003:3003)
  ├── Bridge: saját network namespace
  ├── iptables DNAT NEM propagál Windows TCP stackre
  └── ❌ netstat üres, LAN timeout

network_mode: host (HELYES megoldás)
  ├── Container WSL2 Linux namespace-t használja
  ├── mirrored mode: WSL2 namespace = Windows hálózat
  └── ✅ Port közvetlenül látható Windows netstat-ban

⚠️ KÉT KÜLÖNBÖZŐ tűzfal réteg létezik:
  ├── Windows Firewall  — standard TCP stack
  └── Hyper-V Firewall  — WSL2 VM-be bejövő forgalom
      VMCreatorId: {40E0AC32-46A5-438A-A0B2-2B479E8F2E90}
      → MINDKETTŐ szükséges!
```

### Task Scheduler — kritikus korlát

```
SYSTEM kontextus + WSL2 = WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED ❌
  WSL2 csak interaktív felhasználói session-ből indítható

MEGOLDÁS: ONLOGON trigger + VIVO2\istva felhasználó ✅
  Interaktív session kontextus → WSL2 elindul
```

### Hyper-V Firewall rule perzisztencia

A Hyper-V FW rule **reboot után törlődhet** — ezért a boot script minden futáskor ellenőrzi és újralétrehozza, ha hiányzik.

---

## 2. vivo2 — Windows konfiguráció

### 2.1 WSL2 beállítások

Fájl: `%USERPROFILE%\.wslconfig`

```ini
[wsl2]
memory=16GB
processors=8
swap=8GB

[experimental]
networkingMode=mirrored
```

### 2.2 Hyper-V Firewall rule (admin PowerShell)

```powershell
New-NetFirewallHyperVRule `
    -Name "ImmichML3003" `
    -DisplayName "Immich ML API - WSL2" `
    -Direction Inbound `
    -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' `
    -Protocol TCP `
    -LocalPorts 3003
```

### 2.3 Windows Firewall rule (admin PowerShell)

```powershell
New-NetFirewallRule `
    -DisplayName "Immich ML API 3003 - LAN" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 3003 `
    -RemoteAddress "10.10.40.0/24" `
    -Action Allow `
    -Profile Any
```

### 2.4 Energiagazdálkodás (admin PowerShell)

```powershell
# AC tápegényen soha ne aludjon / hibernáljon
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
```

---

## 3. vivo2 — Boot script

### 3.1 Script

Fájl: `C:\Scripts\wsl-portforward.ps1`

```powershell
# WSL2 Immich ML — Boot script
# FONTOS: ONLOGON triggerrel, VIVO2\istva jogon fusson (nem SYSTEM)
# WSL2 SYSTEM kontextusból nem indítható (WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED)
# 2026-03-08

$logFile = "C:\Scripts\wsl-portforward.log"

function Write-Log { param([string]$msg)
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" | Add-Content $logFile
}

Write-Log "Script indul (user: $env:USERNAME)"

# Hyper-V Firewall rule újralétrehozása (reboot után törlődhet)
$hvRule = Get-NetFirewallHyperVRule -Name "ImmichML3003" -ErrorAction SilentlyContinue
if (-not $hvRule) {
    New-NetFirewallHyperVRule `
        -Name "ImmichML3003" `
        -DisplayName "Immich ML API - WSL2" `
        -Direction Inbound `
        -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' `
        -Protocol TCP `
        -LocalPorts 3003 | Out-Null
    Write-Log "Hyper-V FW rule létrehozva"
} else {
    Write-Log "Hyper-V FW rule már létezik"
}

# Docker service ellenőrzése
Start-Sleep -Seconds 15
$dockerStatus = wsl -e bash -c "service docker status 2>&1 | grep -c 'active (running)'" 2>$null
if ($dockerStatus -ne "1") {
    wsl -u root -e sh -c "service docker start" 2>$null
    Start-Sleep -Seconds 8
    Write-Log "Docker service elindítva"
} else {
    Write-Log "Docker fut"
}

# Immich ML container indítása ha nem fut
$running = wsl -e bash -c "docker ps --filter name=immich-machine-learning --filter status=running -q 2>/dev/null" 2>$null
if (-not $running) {
    wsl -e bash -c "cd ~/immich-ml && docker compose up -d 2>/dev/null" 2>$null
    Write-Log "Immich ML container elindítva"
} else {
    Write-Log "Immich ML container fut: $running"
}

Write-Log "Kesz"
```

### 3.2 Task Scheduler — XML-alapú létrehozás

Fájl: `C:\Scripts\immich-ml-task.xml`

```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
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
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File "C:\Scripts\wsl-portforward.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
```

**Task telepítés (admin CMD):**

```cmd
schtasks /create /tn "WSL2-Immich-ML-Boot" /xml "C:\Scripts\immich-ml-task.xml" /f
```

**Manuális teszt (reboot nélkül):**

```cmd
schtasks /run /tn "WSL2-Immich-ML-Boot"
```

**Log ellenőrzés:**

```cmd
type C:\Scripts\wsl-portforward.log
```

---

## 4. vivo2 — WSL2 Docker konfiguráció

### 4.1 Docker Compose

Könyvtár: `~/immich-ml/` (WSL2) = `C:\Users\istva\immich-ml\` (Windows)

```yaml
services:
  immich-machine-learning:
    container_name: immich-machine-learning
    image: ghcr.io/immich-app/immich-machine-learning:release
    platform: linux/arm64
    restart: unless-stopped
    network_mode: host          # kötelező mirrored WSL2 networking mellett
    # ports: blokk SZÁNDÉKOSAN HIÁNYZIK — host mode esetén felesleges
    volumes:
      - ./model-cache:/cache
    environment:
      MACHINE_LEARNING_WORKERS: "2"
      MACHINE_LEARNING_WORKER_TIMEOUT: "300"
      MACHINE_LEARNING_CACHE_FOLDER: "/cache"
      MACHINE_LEARNING_PRELOAD__CLIP: "ViT-B-16-SigLIP2__webli"
      MACHINE_LEARNING_PRELOAD__FACIAL_RECOGNITION: "buffalo_l"
      OMP_NUM_THREADS: "8"
      OPENBLAS_NUM_THREADS: "8"
    healthcheck:
      test: ["CMD", "python3", "-c", "import urllib.request; r=urllib.request.urlopen('http://localhost:3003/ping'); exit(0 if r.status==200 else 1)"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s
```

> `ports:` blokk + `network_mode: host` = port ütközés → container azonnal kilép. A `ports:` blokk kötelezően hiányzik.

### 4.2 WSL2 systemd boot chain

```
WSL2 systemd (wsl.conf: systemd=true)
  └── docker.service: enabled (S01docker rc.d-ben)
       └── immich-machine-learning: restart=unless-stopped
            └── automatikusan indul Docker startkor
```

A Task Scheduler script **redundáns backup** — a systemd chain önállóan is kezeli a boot-time indítást. A script elsősorban a Hyper-V FW rule perzisztenciáját garantálja.

---

## 5. CT 302 — Immich szerver konfiguráció

### 5.1 Docker Compose

Könyvtár: `/root/mediaserver/immich/`

```yaml
services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:release
    restart: unless-stopped
    ports:
      - 2283:2283
    volumes:
      - /mnt/mediastore/immich/upload:/usr/src/app/upload
      - /mnt/mediastore/immich/photos:/mnt/photos
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
    depends_on:
      - redis
      - database
    deploy:
      resources:
        limits:
          cpus: '1.5'
          memory: 2G

  immich-power-tools:
    container_name: immich_power_tools
    image: ghcr.io/immich-power-tools/immich-power-tools:latest
    restart: unless-stopped
    ports:
      - "8002:3000"
    environment:
      IMMICH_URL: "http://immich_server:2283"
      IMMICH_API_KEY: ${IMMICH_POWER_TOOLS_API_KEY}
      POWER_TOOLS_ENDPOINT_URL: "http://10.10.40.32:8002"
      JWT_SECRET: ${IMMICH_POWER_TOOLS_JWT_SECRET}
      DB_USERNAME: ${DB_USERNAME}
      DB_PASSWORD: ${DB_PASSWORD}
      DB_HOST: database
      DB_PORT: 5432
      DB_DATABASE_NAME: ${DB_DATABASE_NAME}

  redis:
    container_name: immich_redis
    image: redis:6.2-alpine
    restart: unless-stopped

  database:
    container_name: immich_postgres
    image: tensorchord/pgvecto-rs:pg14-v0.2.0
    restart: unless-stopped
    env_file:
      - .env
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_DB: ${DB_DATABASE_NAME}
    volumes:
      - immich_pgdata:/var/lib/postgresql/data

volumes:
  immich_pgdata:
    driver: local
```

### 5.2 .env fájl

```env
# Adatbázis
DB_USERNAME=immich
DB_PASSWORD=<db_jelszó>
DB_DATABASE_NAME=immich
REDIS_HOSTNAME=redis

# Távoli ML worker — vivo2 Snapdragon
IMMICH_MACHINE_LEARNING_URL=http://10.10.20.200:3003

# Immich Power Tools
IMMICH_POWER_TOOLS_API_KEY=<immich_api_kulcs>
IMMICH_POWER_TOOLS_JWT_SECRET=<openssl rand -base64 48>
```

---

## 6. MikroTik tűzfalszabályok

```routeros
# CT302 (SERVERS 10.10.40.x) → vivo2 (MAIN 10.10.20.x) — ML API
# Pozíció: 29-es sorszám, a "SERVERS -> MAIN: TILTVA" DROP rule előtt
/ip firewall filter add \
    chain=forward \
    src-address=10.10.40.32 \
    dst-address=10.10.20.200 \
    dst-port=3003 \
    protocol=tcp \
    action=accept \
    comment="CT302 docker-host -> vivo2 Immich ML API" \
    place-before=30

# Ellenőrzés
/ip firewall filter print where comment~"vivo2"
```

---

## 7. Immich Admin UI beállítások

`http://immich.lan → Administration → Machine Learning`

| Setting | Érték |
|---------|-------|
| Machine Learning URL | `http://10.10.20.200:3003` |
| CLIP Model | `ViT-B-16-SigLIP2__webli` |
| Face Detection Model | `buffalo_l` |
| OCR Model | `PP-OCRv5_mobile (Latin script languages)` |

> **OCR és magyar:** `PP-OCRv5_mobile Latin script` tartalmazza a magyarban használt ékezetes karaktereket (á, é, ő, ű, ö, ü stb.). A `server` variáns kerülendő — ~6-8 GB RAM igény, WSL2-ben crashelhet.

---

## 8. Immich Power Tools

Elérés: `http://10.10.40.32:8002`

Főbb funkciók: People Merge (duplikált személyek összevonása), Bulk Date Offset, Update Missing Locations (GPS pótlás), Analytics, Duplicate Detection.

---

## 9. Monitoring

**vivo2 WSL2-ben:**

```bash
# Container státusz
docker ps | grep immich-machine-learning

# API válasz
curl http://localhost:3003/ping

# Erőforrás használat
docker stats immich-machine-learning --no-stream

# Logok
docker logs immich-machine-learning --tail 30 -f
```

**CT302-ről (LAN teszt):**

```bash
curl -s --max-time 5 http://10.10.20.200:3003/ping
docker logs immich_server --tail 50 | grep -i "machine\|learning"
```

**Windows netstat (kapcsolat ellenőrzés):**

```cmd
netstat -ano | findstr ":3003"
```

Várt output: `TCP 0.0.0.0:3003 LISTENING` + `TIME_WAIT` sorok CT302 IP-vel = ML API aktívan kiszolgál.

---

## 10. Hibaelhárítási mátrix

| Tünet | Root cause | Megoldás |
|-------|------------|----------|
| Container nem indul bootkor | Task SYSTEM jogon fut | Task törlés + újralétrehozás `VIVO2\istva` ONLOGON triggerrel |
| `WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED` a logban | SYSTEM account nem indíthat WSL2-t | Ld. fent |
| LAN timeout, localhost pong | Hyper-V FW rule hiányzik (reboot után törlődött) | Script automatikusan újrakreálja; vagy manuálisan `New-NetFirewallHyperVRule` |
| Container kilép indulás után | `ports:` + `network_mode: host` port ütközés | `ports:` blokk törlése a compose-ból |
| Container restartol (`Up 1 second`) | Healthcheck false negative | python3 urllib healthcheck HTTP 200 ellenőrzéssel |
| `Empty reply from server` curl-ből | Modellek még töltődnek (start_period alatt) | Várni ~60-120 másodpercet, újra tesztelni |
| MikroTik forward timeout | Rule rossz pozícióban (DROP után) | `place-before` paraméterrel DROP elé helyezni |

---

## 11. Teljesítmény referencia

| Metrika | Érték |
|---------|-------|
| CLIP modell cache | ~400 MB |
| Face modell cache (~buffalo_l) | ~500 MB |
| Model cache összesen | ~1.7 GB |
| CPU terhelés (batch indexelés) | 200–600% (2–6 Oryon mag) |
| RAM (modellek betöltve) | ~4–8 GB |
| Hálózati forgalom | ~1–5 MB/s |
| ONNX provider | CPUExecutionProvider (ARM64 natív) |
| Modell betöltési idő (hideg) | ~60–120 s |

---

*Kapcsolódó docs: README-ai-stack-snapdragon.md, README-mediaserver-v3.md*  
*2026-03-08 | homelab cluster*

