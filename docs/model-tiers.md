# Model Tiers — CPU vs NPU Selection Guide

> When to use which inference backend on Snapdragon X Elite + WSL2.

---

## Overview

This stack runs three inference backends simultaneously:

| Backend | API port | Format | Hardware |
|---|---|---|---|
| GenieAPIService | `:8912` | QNN Genie | NPU (Hexagon v73) |
| Ollama | `:11434` | GGUF | CPU (Oryon NEON) |
| LiteLLM Proxy | `:4000` | OpenAI-compat | routes to all above + cloud |

---

## When to Use NPU (GenieAPIService)

**Use GenieAPIService when:**
- You need the fastest possible response (real-time chat, autocomplete)
- CPU load must stay low (running other tasks simultaneously)
- The model fits in NPU memory (~5 GB protected domain)
- Privacy is critical (fully local, no network)

**NPU throughput benchmarks (Llama 3.1 8B):**

| Metric | Value |
|---|---|
| Tokens/sec | ~3.9 TPS |
| CPU load during inference | 3–5% |
| RAM usage | ~1.4 GB |
| NPU protected memory | ~292 MB |
| Model load time (cold) | ~4 seconds |

**NPU limitations:**
- Only Qualcomm QNN/Genie format models work (not GGUF)
- Model size is capped by Hexagon v73 protected domain (~5 GB)
- No batching (single-turn inference only)
- Model must be pre-converted — cannot use arbitrary HuggingFace models

---

## When to Use CPU (Ollama)

**Use Ollama when:**
- The model you need is not available in QNN/Genie format
- You need models larger than ~5 GB (13B, 20B, 70B quantized)
- You want to run multiple models without reloading
- You need embedding models (`nomic-embed-text`, `bge-m3`)

**CPU throughput benchmarks:**

| Model | Size | Tokens/sec | RAM |
|---|---|---|---|
| `qwen2.5-coder:1.5b` | 986 MB | ~12–18 TPS | ~1.2 GB |
| `llama3.1:8b` | 4.9 GB | ~2.4 TPS | ~5 GB |
| `qwen2.5-coder:7b` | 4.7 GB | ~2.5 TPS | ~5 GB |
| `deepseek-r1:8b` | 5.2 GB | ~2.2 TPS | ~5.5 GB |
| `gpt-oss:20b` (Q4) | ~13 GB | ~0.8 TPS | ~14 GB |

---

## Decision Matrix

| Use case | Recommended backend | Model |
|---|---|---|
| Real-time chat | GenieAPIService NPU | `llama3.1-8b-8380-qnn2.38` |
| Code completion | Ollama CPU | `qwen2.5-coder:1.5b` |
| Code review | Ollama CPU | `qwen2.5-coder:7b` |
| Long reasoning | Ollama CPU | `deepseek-r1:8b` |
| Document analysis | GenieAPIService NPU | `llama3.1-8b-8380-qnn2.38` |
| RAG embeddings | Ollama CPU | `nomic-embed-text` |
| High-quality (slow) | Ollama CPU | `gpt-oss:20b` |
| Sensitive/private data | GenieAPIService NPU | any QNN model |

---

## Available NPU Models (Genie format)

Source: `https://www.aidevhome.com/data/adh2/models/suggested/`

| Model | Filename | Size | Status |
|---|---|---|---|
| Llama 3.1 8B | `llama3.1-8b-8380-qnn2.38.zip` | ~4.9 GB | ✅ Default |
| Llama 3.2 3B | `llama3.2-3b-8380-qnn2.37.zip` | ~2.0 GB | ✅ Available |
| Llama 3.2 1B | `llama3.2-1b-8380-qnn2.37.zip` | ~0.8 GB | ✅ Available |
| Qwen2.5-VL 3B | `qwen2.5vl3b-8380-2.42.zip` | ~2.1 GB | ⬜ Vision |
| Qwen3-Reranker | `qwen3-reranker-8380-2.38.zip` | ~1.5 GB | ⬜ RAG reranker |

---

## Switching the Active NPU Model

GenieAPIService loads **one model at a time**. To switch:

```powershell
# Stop the current instance (Ctrl+C or kill the process)
Stop-Process -Name "GenieAPIService" -ErrorAction SilentlyContinue

# Start with a different model config
cd C:\AI\GenieAPIService_cpp
.\GenieAPIService.exe -c models\llama3.2-3b-8380-qnn2.37\config.json -l -d 3 -p 8912
```

Verify the new model is active:

```powershell
Invoke-RestMethod http://localhost:8912/v1/models
```

---

## LiteLLM Routing

With [litellm-local-config](https://github.com/gaiagent0/litellm-local-config), you can abstract backend selection behind aliases:

```yaml
# config.yaml excerpt
model_list:
  - model_name: "fast"
    litellm_params:
      model: openai/llama3.1-8b-8380-qnn2.38
      api_base: http://localhost:8912/v1
      api_key: none

  - model_name: "local-cpu"
    litellm_params:
      model: ollama/llama3.1:8b
      api_base: http://localhost:11434
```

Then clients use `model: "fast"` or `model: "local-cpu"` without knowing which backend serves them.

---

*Tested on: ASUS Vivobook S15 S5507QA · Snapdragon X Elite X1E78100 · 32 GB RAM · Windows 11 Home 24H2 ARM64*
