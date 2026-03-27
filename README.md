# homelab-ai-stack

> **Local AI inference stack on Snapdragon X Elite (ARM64/NPU) + Immich ML offload.**  
> WSL2-based Docker on Windows 11 Home ARM64, with autostart automation and remote ML serving for Immich running on Proxmox LXC.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Snapdragon_X_Elite_ARM64-blue)](https://www.qualcomm.com/products/mobile/snapdragon/pcs-and-tablets/snapdragon-x-series)

---

## Architecture

```
Proxmox (pve-03, CT302)              Windows 11 ARM64 (vivo2, 10.10.20.200)
  Immich (photos/video)   ──ML──►   WSL2 Docker
  open-webui              ──API──►    ├── ollama          (GGUF, CPU)
  searxng                            ├── open-webui       (chat UI)
  n8n                                ├── immich-machine-learning (CLIP/face/OCR)
                                     ├── searxng          (meta-search)
                                     ├── chromadb         (vector store)
                                     └── n8n              (workflow automation)

                                   NPU (Snapdragon X Elite):
                                     GenieAPIService      (QNN GGUF, 40+ t/s)
                                     Foundry Local        (ONNX/QNN)
```

### Why WSL2 + Docker (not Proxmox VM)?

| Approach | Benefit | Drawback |
|---|---|---|
| WSL2 Docker (current) | Native ARM64, NPU accessible, zero virtualization overhead | Windows SYSTEM context cannot start WSL2 |
| Proxmox VM (ARM64) | Full isolation, easier backup | No NPU passthrough support in PVE 8.x |
| Native Linux bare metal | Best NPU driver support | No Windows coexistence |

NPU passthrough into Proxmox VMs is not currently supported for Snapdragon X Elite — WSL2 is the only path to NPU acceleration from a Linux container on this hardware.

---

## Model Tiers

### CPU/GGUF (Ollama) — always available
| Model | Size | Use case |
|---|---|---|
| `qwen2.5-coder:7b` | ~4.7 GB | Code, technical reasoning |
| `llama3.1:8b` | ~4.9 GB | General assistant |
| `deepseek-r1:8b` | ~5 GB | Multi-step reasoning |
| `gpt-oss:20b` | ~13 GB | High-quality general (slower) |

With 32 GB RAM, models up to ~20B run comfortably. Expected throughput: ~5–15 t/s for 8B, ~3–5 t/s for 20B.

### NPU/QNN (GenieAPIService, Foundry Local) — fast, quantized
| Model | Format | Throughput |
|---|---|---|
| `Llama3.2-3B (QNN)` | Genie | ~40–60 t/s |
| `Phi-4-mini (ONNX)` | Foundry | ~30–50 t/s |
| `Qwen2.5-7B (QNN)` | Genie | ~20–35 t/s |

NPU models require Qualcomm QNN/ONNX format — not compatible with Ollama. Managed separately via GenieAPIService or `foundry run`.

---

## Critical: WSL2 Autostart on Windows 11 Home

**Problem:** Windows Task Scheduler tasks running as `SYSTEM` cannot start WSL2:
```
Error 0xc03a001c: WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED
```

**Solution:** Task Scheduler `ONLOGON` trigger running as user context (`VIVO2\istva`).

**Additional gotcha:** `schtasks /create /sc ONLOGON /delay` silently ignores the delay parameter. Use XML import with `<Delay>PT45S</Delay>` inside the `<LogonTrigger>` element.

```xml
<!-- Critical: delay must be inside LogonTrigger, not as a standalone element -->
<Triggers>
  <LogonTrigger>
    <Enabled>true</Enabled>
    <UserId>VIVO2\istva</UserId>
    <Delay>PT45S</Delay>
  </LogonTrigger>
</Triggers>
```

See [wsl2/task-scheduler-setup.md](wsl2/task-scheduler-setup.md) for full XML and debugging guide.

---

## Immich ML Offload

Immich (running on CT302) offloads CLIP embeddings, face recognition, and OCR to the Snapdragon NPU via `immich-machine-learning` container on vivo2.

```yaml
# immich docker-compose.yml (partial)
environment:
  MACHINE_LEARNING_URL: http://10.10.20.200:3003
```

The ML container must be reachable from CT302 (cross-VLAN: SERVERS → MAIN). Ensure:
1. MikroTik forward rule: `10.10.40.32 → 10.10.20.200:3003`
2. Windows Hyper-V Firewall inbound rule on port 3003 (auto-created by boot script)

---

## Repository Structure

```
homelab-ai-stack/
├── README.md
├── docs/
│   ├── model-tiers.md             — CPU vs NPU model selection guide
│   ├── immich-ml-offload.md       — Full Immich ML remote setup
│   ├── disk-cleanup.md            — WSL VHDX compaction procedure
│   └── snapdragon-npu.md          — QNN/ONNX model formats explained
├── scripts/
│   ├── start-ai-stack.ps1         — PowerShell: WSL2 + Docker Compose start
│   └── compact-wsl-vhdx.ps1       — Reclaim space after large WSL deletions
├── wsl2/
│   ├── task-scheduler-setup.md    — Autostart XML + debugging guide
│   ├── ai-stack-task.xml          — Task Scheduler XML (import with schtasks)
│   ├── docker-compose.yml         — Full AI stack definition
│   └── .env.example               — Service ports, model paths
└── configs/
    └── env.example
```

---

## Security Notes

- **open-webui** should be bound to `0.0.0.0` only inside a trusted VLAN. Do not expose to WAN without auth.
- **n8n** webhooks are unauthenticated by default — enable basic auth in the n8n settings UI before exposing any webhook endpoints.
- **Hyper-V Firewall** rules created by the boot script are scoped to `10.10.40.0/24` (SERVERS VLAN) by default. Verify scope before widening.
- Windows Firewall rules persist across reboots but **not** across Windows updates that reset the Hyper-V virtual switch — the boot script recreates them automatically.

---

## Disk Management

WSL2 `ext4.vhdx` does **not** automatically shrink after large deletions. After removing model files inside WSL, compact manually:

```bash
# Inside WSL: zero free blocks
dd if=/dev/zero of=~/zero.tmp bs=1M status=progress; rm -f ~/zero.tmp
```
```powershell
# Windows: shutdown WSL (auto-compacts on shutdown)
wsl --shutdown
```

Expected result: ext4.vhdx shrinks from ~100 GB to ~40 GB after removing ~60 GB of model cache.

---

*Tested on: ASUS Vivobook S15 S5507QA, Snapdragon X Elite X1E78100, 32 GB RAM, Windows 11 Home ARM64 24H2*
