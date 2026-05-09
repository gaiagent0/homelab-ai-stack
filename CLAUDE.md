# CLAUDE.md — homelab-ai-stack
> Frissítve: 2026-05

## Projekt

vivo2 (Snapdragon X Elite) + Proxmox homelab AI integráció — dokumentáció.
Repo: `gaiagent0/homelab-ai-stack`

---

## Architektúra

```
Proxmox pve-03 (CT302 · 10.10.40.32):   vivo2 Windows ARM64 (10.10.20.200):
  Gitea      :3000                         WSL2 Docker:
  Immich     :2283  ──ML──▶                  ├── immich-machine-learning :3003
  LibreNMS   :8080                           ├── chromadb :8001 (vector store)
  AdGuard    :3000                           └── n8n :5678 (workflow)
                                           Windows natív:
                                             ├── GenieAPIService :8912 (QNN Hexagon v73)
                                             ├── Ollama :11434 (CPU NEON)
                                             ├── LiteLLM Proxy :4000 (sk-local-vivo2)
                                             ├── Open WebUI :8080 (uvx --python 3.11)
                                             ├── Nexa CLI :18181 (NPU · Parakeet ASR)
                                             ├── Free Claude Code :8082 (proxy)
                                             └── AI Control Center :5757
```

---

## OCI (Oracle Cloud — Frankfurt)

```
OKE klaszter endpoint: 130.162.62.141:6443
Node: 10.0.1.128 (AMD, v1.31.10)
AMD VM: 92.5.75.8

Deployok:
  chat.istvanszechenyi.uk   → hu-ai-chat
  infra.istvanszechenyi.uk  → infra-insight

Ingress: ingress-nginx + cert-manager (Cloudflare DNS01)
```

---

## AI Control Center

Elérés: `http://localhost:5757`
Backend: FastAPI (Python 3.12 ARM64), `C:\AI\control-center\backend\main.py`
Frontend: statikus HTML, `C:\AI\control-center\frontend\index.html`
Indítás: `C:\AI\control-center\start.ps1`

Funkciók:
- Service start/stop (Genie, Nexa, Ollama, LiteLLM, Open WebUI, LM Studio, Immich ML)
- Hermes WSL2 actions: `update` / `gateway` / `doctor`
- Free Claude Code proxy start/stop + `Launch Claude` terminal
- Quick Launch tiles (Open WebUI, Bolt.diy, LiteLLM UI, FCC Docs, Chat)
- GenieAPI CORS proxy (`/v1/models`, `/v1/chat/completions`)
- Auto-refresh 4s

---

## Free Claude Code

Repo: `C:\Users\istva\free-claude-code`
Port: 8082
Providers: NVIDIA NIM, OpenRouter, DeepSeek, LM Studio, Ollama
Config: `C:\Users\istva\free-claude-code\.env`
Telegram bot: aktív (token konfigurálva)

Kézi indítás:
```powershell
cd C:\Users\istva\free-claude-code
uv run uvicorn server:app --host 0.0.0.0 --port 8082
```
Claude CLI indítás (új terminálban):
```powershell
$env:ANTHROPIC_AUTH_TOKEN="<token az .env-ből>"
$env:ANTHROPIC_BASE_URL="http://localhost:8082"
$env:CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY="1"
claude
```

---

## Hermes (WSL2)

Gateway: port 18789 (OpenClaw-ból migrálva)
Parancsok: `hermes update` / `hermes gateway` / `hermes doctor`
LiteLLM proxy: `--host 127.0.0.1 --port 4000`
Fallback lánc: Gemini Flash → Nexa NPU → Ollama qwen2.5:14b → OpenRouter → Claude → GenieAPI

---

## Immich ML offload

```yaml
# immich docker-compose.yml
environment:
  MACHINE_LEARNING_URL: http://10.10.20.200:3003
```

Feltétel: MikroTik forward rule `10.10.40.32 → 10.10.20.200:3003`
+ Windows Hyper-V Firewall inbound port 3003 (start-ai-stack.ps1 hozza létre)

---

## Autostart (Task Scheduler)

KRITIKUS: SYSTEM context NEM tudja indítani WSL2 (`WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED`)
→ ONLOGON trigger, user context (`VIVO2\istva`), delay: PT45S (XML-ben, nem CLI-ben!)

Task: `\AIStack-Autostart`, script: `C:\AI\scripts\start-ai-stack.ps1`

---

## .wslconfig

```ini
[wsl2]
memory=32GB
processors=8
swap=16GB
localhostForwarding=true
```

---

## Proxmox klaszter

```
pve-01: 10.10.40.11
pve-02: 10.10.40.12
pve-03: 10.10.40.32  (CT302 Docker host)
MikroTik hEX RB750Gr3 + TP-Link SG105E
VLAN10: Management 10.10.10.0/24
VLAN20: Services 10.10.20.0/24
VLAN40: Homelab 10.10.40.0/24
```

---

## Repo tartalom

Dokumentációs repo — tényleges Docker Compose és konfig fájlok `C:\AI\` alatt.
```
docs/     ← architekturális döntések, disk mgmt, Immich ML setup
scripts/  ← start-ai-stack.ps1, compact-wsl-vhdx.ps1
wsl2/     ← docker-compose.yml, task-scheduler XML, env.example
configs/  ← env.example
```

---

## Nyitott feladatok

- Qwen3-Reranker RAG pipeline-ba kötése
- LiteLLM proxy systemd service WSL2-ben
- SEO AI pipeline: Astro 5.x + Cloudflare Pages + Qwen API
- Web3 roadmap: EOA → DeFi → Solidity → ERC-6551
