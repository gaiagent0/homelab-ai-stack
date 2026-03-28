# AI Stack – ASUS Vivobook S 15 (Snapdragon X Elite)

> **Utolsó frissítés:** 2026-03-12  
> **Gép:** ASUS Vivobook S 15 – vivo2 (`10.10.20.200`)  
> **OS:** Windows 11 Home 24H2 ARM64  
> **CPU:** Snapdragon X Elite X1E78100 – 12 core Oryon @ 3.42 GHz  
> **NPU:** Qualcomm Hexagon v73 – Driver 30.0.140.1000  
> **RAM:** 32 GB  

---

## TL;DR – Jelenlegi állapot

```
✅ GenieAPIService  – NPU, Llama 3.1 8B aktív, ~3.9 TPS, port 8912
✅ Ollama           – CPU, 5 modell, port 11434
✅ Open WebUI       – natív Windows (uvx), port 8080
✅ Immich ML        – WSL2 Docker, CLIP + face recognition offload
```

**Teljesítmény összehasonlítás (llama3.1:8b, azonos modell):**

| Backend | TPS | CPU | RAM |
|---------|-----|-----|-----|
| GenieAPIService (NPU) | ~3.9 | ~3-5% | 1.4 GB |
| Ollama (CPU/NEON) | ~2.4 | ~50-80% | ~5 GB |

---

## 1. Architektúra

```
Open WebUI :8080 (Windows natív, uvx)
      │
      ├── OpenAI API → GenieAPIService :8912  (NPU – Hexagon v73 / QnnHtp)
      │                  └── llama3.1-8b-8380-qnn2.38  ← AKTÍV ALAPMODELL
      │                  └── Llama3.2-3B
      │                  └── Llama3.2-1B
      │
      └── Ollama API  → Ollama :11434  (CPU – llama.cpp ARM NEON)
                         ├── deepseek-r1:8b
                         ├── qwen2.5-coder:7b
                         ├── llama3.1:8b
                         ├── qwen2.5-coder:1.5b
                         └── nomic-embed-text

WSL2 Ubuntu 24.04
  └── Docker: immich-machine-learning  (~4.5 GB RAM)
              └── CLIP + face recognition ← Immich (CT302) hívja

Tailscale: aktív (remote elérés)
```

---

## 2. GenieAPIService – NPU Backend

**Binary:** `C:\AI\GenieAPIService_cpp\GenieAPIService.exe`  
**Port:** `8912`  
**API:** OpenAI-kompatibilis (`/v1/chat/completions`, `/v1/models`)

### Aktív modell – Llama 3.1 8B

```
Forrás:   https://www.aidevhome.com/data/adh2/models/suggested/llama3.1-8b-8380-qnn2.38.zip
Helyszín: C:\AI\GenieAPIService_cpp\models\llama3.1-8b-8380-qnn2.38\
Backend:  QnnHtp (Hexagon v73)
RAM:      ~292 MB NPU protected domain + 1.4 GB total
TPS:      ~3.9 tok/sec
Load:     ~4 mp
```

### Indítás

```powershell
cd C:\AI\GenieAPIService_cpp
.\GenieAPIService.exe -c models\llama3.1-8b-8380-qnn2.38\config.json -l -d 3 -p 8912
```

### NPU betöltés ellenőrzése (startup log)

```
Backend library: QnnHtp.dll
QnnDevice_create done. device = 0x1
Key: Weight Sharing, Value: true
Allocated total size = 306545152   ← 292 MB NPU memória
load successfully! use second: 4.03
```

### Ismert quirk-ök (nem blokkolók)

| Quirk | Root cause |
|-------|-----------|
| `"model": ""` üres response-ban | GenieAPIService sajátosság |
| `"created": -590142444` negatív | int32 overflow |
| `usage tokens: 0` | nem számolja |
| `Initialization Time Acceleration not possible` | QNN DLL minor version mismatch, ~20-30% TPS veszteség |

### API ellenőrzés

```powershell
Invoke-RestMethod http://localhost:8912/v1/models

$body = @{
    model    = "llama3.1-8b-8380-qnn2.38"
    messages = @(@{role="user"; content="Hello!"})
    max_tokens = 100
} | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri "http://localhost:8912/v1/chat/completions" `
    -Method POST -Body $body -ContentType "application/json"
```

---

## 3. Ollama – CPU Backend

**Port:** `11434`  
**Backend:** llama.cpp, ARM NEON SIMD  
**Modellek:** `C:\Users\istva\.ollama\models`

| Modell | Méret | Use-case |
|--------|-------|---------|
| `deepseek-r1:8b` | 5.2 GB | Reasoning |
| `qwen2.5-coder:7b` | 4.7 GB | Kód generálás |
| `llama3.1:8b` | 4.9 GB | Általános chat (CPU fallback) |
| `qwen2.5-coder:1.5b` | 986 MB | Gyors kód snippetek |
| `nomic-embed-text` | 274 MB | RAG embedding |

---

## 4. Open WebUI – Frontend

**Telepítési mód:** Windows natív, uvx  
**Port:** `8080`  
**Adatkönyvtár:** `C:\AI\openwebui\`

### Indítás

```powershell
$env:DATA_DIR = "C:\AI\openwebui"
C:\Users\istva\.local\bin\uvx.exe --python 3.11 open-webui serve
```

### Backend kapcsolatok (Admin Panel → Connections)

```
OpenAI API:
  http://10.10.20.200:5272/v1   ← Foundry Local (régi entry, ki lehet kapcsolni)
  http://localhost:8912/v1      ← GenieAPIService NPU ✅ AKTÍV

Ollama API:
  http://localhost:11434         ✅ AKTÍV
```

**NPU inference használathoz:** chat modellválasztóban `llama3.1-8b-8380-qnn2.38` kiválasztása.

---

## 5. WSL2 Konfiguráció

```ini
# C:\Users\istva\.wslconfig
[wsl2]
memory=32GB
processors=8
swap=16GB
localhostForwarding=true
```

### Futó Docker konténerek

```bash
docker ps
# immich-machine-learning  ← ~4.5 GB RAM
```

---

## 6. Autostart – Task Scheduler

**Task:** `\AIStack-Autostart`  
**Script:** `C:\AI\scripts\start-ai-stack.ps1`  
**Log:** `C:\AI\logs\stack-startup.log`

```xml
Trigger: ONLOGON + PT90S delay
Limit:   PT10M
Action:  powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden
         -File "C:\AI\scripts\start-ai-stack.ps1"
```

Indítási sorrend a scriptben:
1. GenieAPIService → port 8912, max 90s polling
2. Open WebUI → port 8080, max 150s polling
3. Ollama: automatikusan indul (Windows service)

---

## 7. Port összefoglaló

| Service | URL | Backend | Státusz |
|---------|-----|---------|---------|
| Open WebUI | http://localhost:8080 | Windows natív | ✅ |
| GenieAPIService | http://localhost:8912/v1 | NPU Hexagon v73 | ✅ |
| Ollama | http://localhost:11434 | CPU NEON | ✅ |
| Foundry Local | http://localhost:5272/v1 | CPU | ⚠️ régi entry |

---

## 8. Fájlstruktúra

```
C:\AI\
├── GenieAPIService_cpp\
│   ├── GenieAPIService.exe
│   ├── QnnHtp.dll
│   └── models\
│       ├── llama3.1-8b-8380-qnn2.38\   ← AKTÍV
│       │   ├── config.json
│       │   ├── tokenizer.json
│       │   ├── htp_backend_ext_config.json
│       │   └── llama_v3_1_8b_chat_quantized_part_[1-5]_of_5.bin
│       └── Llama3.2-3B\
├── openwebui\
│   └── webui.db
├── scripts\
│   ├── start-ai-stack.ps1
│   └── AIStack-Autostart.xml
└── logs\
    └── stack-startup.log
```

---

## 9. aidevhome.com – X Elite modellek (Genie format)

Base URL: `https://www.aidevhome.com/data/adh2/models/suggested/`

| Modell | Fájlnév | Státusz |
|--------|---------|---------|
| Llama 3.2 3B | `llama3.2-3b-8380-qnn2.37.zip` | ✅ telepítve |
| Llama 3.1 8B | `llama3.1-8b-8380-qnn2.38.zip` | ✅ **aktív** |
| Qwen2.5-VL-3B | `qwen2.5vl3b-8380-2.42.zip` | ⬜ nem letöltve (vision) |
| Qwen3-Reranker | `qwen3-reranker-8380-2.38.zip` | ⬜ nem letöltve |

---

## 10. Lezárt fejlesztési utak

### Qwen2.5-7B NPU – ARM64 AIMET blocker
ONNX export ARM64/WSL2-ben nem lehetséges (`aimet-onnx` wheel nem létezik aarch64-re).  
AI Hub cloud compile pipeline lokális exportot vár első lépésként. → **LEZÁRT**

### Qwen2.0-7B-SSD NPU – Silicon memory limit
Error 1002: Hexagon v73 HTP Protected Domain limit. SSD-Q1 config egyszerre több modellt tölt → több PD memória kell. → **LEZÁRT**

### Foundry Local NPU – QNN verzióinkompatibilitás
`QnnHtp.dll v2.37.1` vs modellek `v2.44.x` compile. Error 14001.  
Monitor: `winget upgrade Microsoft.FoundryLocal` → **LEZÁRT (pending vendor fix)**

---

## 11. Nyitott feladatok

| Prioritás | Feladat |
|-----------|---------|
| 🟡 | Foundry `10.10.20.200:5272/v1` entry kikapcsolása Open WebUI-ban |
| 🟡 | Llama 3.1 8B TPS opt: config `"size": 2048` → ~20-30% TPS javulás |
| 🟡 | qaihub-env Python venv újraépítése 3.10/3.11-gyel (jelenlegi 3.14 inkompatibilis) |
| 🟢 | Qwen2.5-VL-3B letöltése (vision use case) |
| 🟢 | Qwen3-Reranker bekötése RAG pipeline-ba |

---

*Dokumentálva: 2026-03-12 | vivo2 | Snapdragon X Elite AI Stack*

