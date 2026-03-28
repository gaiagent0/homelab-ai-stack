# Lemez takarítás és AI stack optimalizálás
**Dátum:** 2026. március 15.  
**Gép:** ASUS Vivobook S15 S5507QA — Snapdragon X Elite (X1E78100) — 32 GB RAM  
**Eredmény:** 9.6 GB → 130.7 GB szabad hely a C: meghajtón (+121 GB)

---

## 1. Elvégzett takarítások

### Windows oldal

| Törölt | Hely | Felszabadítva |
|--------|------|---------------|
| `%TEMP%` swap.vhdx + egyéb temp fájlok | `AppData\Local\Temp` | 17.7 GB |
| Modell ZIP archívumok | `Downloads\` | 5.7 GB |
| Kicsomagolt modell bin fájlok | `Downloads\modells\elite\` | 11.6 GB |
| Kicsomagolt telepítő mappa | `Downloads\v2.44.0.260225\` | 3.5 GB |
| LM Studio modellek (3 db) | `.lmstudio\models\` | 11.9 GB |
| DeepSeek Foundry cache | `.foundry\cache\models\Microsoft\deepseek-r1-...` | 3.7 GB |
| `AI\models\llama3.1-8b` duplikátum | `C:\AI\models\` | 4.78 GB |
| `AI\models\llama32-1b-qnn` sérült másolat | `C:\AI\models\` | 1.61 GB |
| `GenieAPIService\models\Qwen2.0-7B-SSD` | `C:\AI\GenieAPIService_cpp\models\` | 4.72 GB |

**Windows összesen: ~65 GB**

---

### WSL (Ubuntu) belső takarítás

| Törölt | Hely | Felszabadítva |
|--------|------|---------------|
| QAI Hub Models cache | `~/.qaihm/qai-hub-models/models/` | ~34.5 GB |
| HuggingFace model cache (Llama 1B) | `~/.cache/huggingface/hub/` | 2.32 GB |
| pip cache | `~/.cache/pip/` | 2.04 GB |
| conda pkgs cache | `~/miniconda3/pkgs/` | 1.04 GB |
| apt cache | `/var/cache/apt/` | 0.25 GB |
| journal logok | `/var/log/journal/` | 0.016 GB |
| `qaihub-py310` duplikált venv | `~/qaihub-py310/` | 1.34 GB |

**WSL belső összesen: ~41 GB**

### WSL VHDX compact

A törlések után a `ext4.vhdx` automatikusan zsugorodott (`dd` + `wsl --shutdown`):

| | Előtte | Utána |
|-|--------|-------|
| `ext4.vhdx` mérete | 98.8 GB | 42.6 GB |
| Visszaadva Windowsnak | | **+56 GB** |

---

## 2. Végeredmény

| | Érték |
|-|-------|
| C: szabad hely takarítás előtt | **9.6 GB** |
| C: szabad hely takarítás után | **130.7 GB** |
| Összes felszabadítva | **~121 GB** |

---

## 3. Megtartott AI stack

### Rétegek

```
Ollama (CPU / GGUF)
  └─ gpt-oss:20b       — 13 GB
  └─ deepseek-r1:8b    —  5 GB
  └─ qwen2.5-coder:7b  —  4.7 GB
  └─ llama3.1:8b       —  4.9 GB
  └─ bge-m3 / nomic    — embedding modellek

GenieAPIService (QNN / NPU natív, Genie formátum)
  └─ llama3.1-8b-8380-qnn2.38  — 4.78 GB
  └─ Llama3.2-3B               — 2.46 GB
  └─ Llama3.2-1B               — 1.60 GB
  └─ Qwen2.5-7B                — 4.72 GB

Foundry Local (ONNX / QNN, NPU)
  └─ Phi-4-mini    — 4.59 GB
  └─ Phi-3.5-mini  — 1.84 GB

AI\models (ONNX, Foundry / AI Toolkit kompatibilis)
  └─ qnn (Llama3.2-3B ONNX verzió)  — 2.47 GB
  └─ qwen25-15b                      — 0.95 GB

Open WebUI — egységes felület Ollama + Foundry fölé
```

### Miért ez a stack?

- **Snapdragon X Elite NPU** csak ONNX/QNN formátumot tud futtatni — GenieAPI és Foundry Local kezeli
- **Ollama GGUF** modellek CPU-n futnak — 32 GB RAM-mal a 13B+ modellek is kényelmesek
- **LM Studio törölve** — átfed Ollama-val, de kevésbé hatékony ARM64 Windowson
- **Duplikátumok eltávolítva** — ugyanaz a modell legfeljebb egy helyen van jelen

---

## 4. WSL VHDX compact eljárás (jövőre)

Ha a WSL-ben nagy mennyiségű fájlt törölsz, a `ext4.vhdx` **nem zsugorodik automatikusan**.

```bash
# 1. WSL-ben: szabad blokkok nullázása
dd if=/dev/zero of=~/zero.tmp bs=1M status=progress; rm -f ~/zero.tmp
```

> ⚠️ **Figyelem:** A WSL `/dev/sdd` virtuálisan 1007 GB-osnak látszik, de a valódi limit
> a C: meghajtó szabad helye. Ha kevés a szabad hely, a `dd` betöltheti a C: meghajtót.
> Figyeld a szabad helyet, és szükség esetén állítsd le Ctrl+C-vel, majd töröld: `rm -f ~/zero.tmp`

```powershell
# 2. Windows PowerShellben — WSL leállítás (automatikusan compact-ol)
wsl --shutdown
```

---

## 5. Rendszeres takarítás (havonta ajánlott)

```bash
# WSL-ben
pip cache purge
conda clean --all -y
sudo apt-get clean
sudo journalctl --vacuum-size=50M
```

```powershell
# Windows admin PowerShell
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue

# Ollama modellek kezelése
ollama list
ollama rm <model_neve>
```

---

## 6. Opcionális további takarítás (~10 GB)

| | Méret | Megjegyzés |
|-|-------|------------|
| `GenieAPIService\models\Qwen2.5-7B` | 4.72 GB | Ha nem használod a Genie API-t |
| `qaihub-env` (py3.11 venv) | 1.70 GB | Ha csak py3.10 kell a QAI Hub munkához |
| `jan` projekt | 4.32 GB | Ha nem fejlesztesz rajta aktívan |
| `bolt-diy/node_modules` | 1.58 GB | `pnpm install` újragenerálja |

---

*Generálta: Claude Sonnet 4.6 — 2026-03-15*

