# homelab-ai-stack

> **Local AI inference stack on Snapdragon X Elite (ARM64/NPU) + Proxmox AI Core.**  
> Windows 11 ARM64 edge node (vivo2) + Proxmox CT305/CT306 backend — hybrid local-first AI platform.  
> ⚠️ **Superseded by [ai-platform-os](https://github.com/gaiagent0/ai-platform-os)** — this repo documents the original WSL2-based stack; current canonical architecture is in ai-platform-os.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Snapdragon_X_Elite_ARM64-blue)](https://www.qualcomm.com/products/mobile/snapdragon/pcs-and-tablets/snapdragon-x-series)

---

## Current Architecture (2026)

```
Proxmox pve-03
  CT305 ai-infra (10.10.40.35)          CT306 observability (10.10.40.36)
    ├── PostgreSQL 16                      ├── Langfuse v3 (LLM tracing)
    ├── Qdrant (vector store, bge-m3)      ├── ClickHouse
    ├── Mem0 (AI memory, :8888)            ├── MinIO
    ├── n8n (workflow, :5678)              ├── Redis
    ├── SearXNG (web search, :8080)        └── Prometheus exporters
    ├── mem0-mcp (:8008, StreamableHTTP)
    └── cAdvisor, postgres-exporter

  CT208 grafana (10.10.40.208)
    ├── Grafana (:3000)
    └── Prometheus (:9090)

Windows 11 ARM64 — vivo2 (10.10.20.200)
  Native:
    ├── Open WebUI       (:8091)  — primary chat UI
    ├── Ollama           (:11434) — qwen3:8b, bge-m3, qwen2.5-coder:7b
    ├── GenieAPIService  (:8912)  — QNN NPU, llama3.1-8b
    ├── llama.cpp MTP    (:8081/:8083) — Qwen3-27B/8B
    └── LiteLLM          (:4001)  — WSL2 Docker, model router

  WSL2:
    └── LiteLLM proxy (→ Ollama + OpenRouter + Groq)
```

### Key changes from original stack

| Component | Was | Now |
|---|---|---|
| n8n | WSL2 Docker (vivo2) | CT305 (Proxmox LXC) |
| SearXNG | WSL2 Docker (vivo2) | CT305 (Proxmox LXC) |
| Vector store | ChromaDB (WSL2) | Qdrant v1.13.2 (CT305) |
| Embeddings | nomic-embed-text | bge-m3 (1024 dim) |
| Memory | — | Mem0 + PGVector (CT305) |
| LLM tracing | — | Langfuse v3 (CT306) |
| Open WebUI | WSL2 Docker | Windows-native (:8091) |
| Bifrost/LiteLLM (WSL2) | removed | LiteLLM kept in WSL2 only |

---

## Model Tiers (current)

### Ollama (Windows-native, always available)
| Model | Use case |
|---|---|
| `qwen3:8b` | General assistant, Mem0 LLM backend |
| `bge-m3` | Embeddings (1024 dim, Qdrant) |
| `qwen2.5-coder:7b` | Code |
| `qwen2.5:14b` | High-quality general |
| `deepseek-r1:8b` | Multi-step reasoning |
| `llama3.1:8b` | General |

### NPU (GenieAPIService, Windows-native)
| Model | Format | Notes |
|---|---|---|
| `llama3.1-8b-qnn` | QNN/Genie | ~40-60 t/s |
| `Qwen3-4B` | QNN/Genie (geniex) | via Nexa SDK |

### llama.cpp MTP (Windows-native)
| Model | Port | Notes |
|---|---|---|
| Qwen3-27B MTP | :8081 | Multi-token prediction |
| Qwen3-8B MTP | :8083 | Fast local inference |

---

## Critical: WSL2 Autostart on Windows 11

**Problem:** Windows Task Scheduler tasks running as `SYSTEM` cannot start WSL2:
```
Error 0xc03a001c: WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED
```

**Solution:** Task Scheduler `ONLOGON` trigger running as user context (`VIVO2\istva`).

```xml
<Triggers>
  <LogonTrigger>
    <Enabled>true</Enabled>
    <UserId>VIVO2\istva</UserId>
    <Delay>PT45S</Delay>
  </LogonTrigger>
</Triggers>
```

WSL2 portproxy stability: `WSL2-PortProxy-NetworkChange` Scheduled Task via XML trigger (NetworkProfile Event ID 10000).

---

## MikroTik VLAN Routing (VLAN20 ↔ VLAN40)

Required firewall rules for CT305 → vivo2:
```
#39: chain=forward accept tcp 10.10.40.35→10.10.20.200:4001  (LiteLLM)
#40: chain=forward accept tcp 10.10.40.35→10.10.20.200:11434 (Ollama)
```

---

## Immich ML Offload

Immich (CT302) offloads CLIP/face/OCR to `immich-machine-learning` on vivo2 (:8002).

```yaml
environment:
  MACHINE_LEARNING_URL: http://10.10.20.200:8002
```

MikroTik rule required: `10.10.40.32 → 10.10.20.200:3003`

---

## Related Repos

- [ai-platform-os](https://github.com/gaiagent0/ai-platform-os) — canonical architecture, decision log, infra templates
- [proxmox-mcp](https://github.com/gaiagent0/proxmox-mcp) — Proxmox MCP server (CT150)
- [pve-ai-agent](https://github.com/gaiagent0/pve-ai-agent) — AI monitoring agent (CT304)
- [vivo2-ai-stack-2026](https://github.com/gaiagent0/vivo2-ai-stack-2026) — vivo2 edge stack detail
- [snapdragon-ai-stack](https://github.com/gaiagent0/snapdragon-ai-stack) — Snapdragon NPU setup guide

---

*Hardware: ASUS Vivobook S15 S5507QA, Snapdragon X Elite X1E78100, 32 GB RAM, Windows 11 ARM64*  
*Last updated: 2026-06-26*
