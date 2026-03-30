# Snapdragon NPU — QNN and ONNX Model Formats Explained

> Understanding the NPU inference formats for Snapdragon X Elite: when to use Genie (QNN), when to use ONNX/Foundry Local, and what the limitations are.

---

## NPU Architecture

The Snapdragon X Elite (X1E78100) NPU is the **Hexagon v73 DSP**, exposed via the Qualcomm AI Engine (QAI). It supports two primary inference paths:

```
Windows ARM64
  ├── QnnHtp.dll (Qualcomm Neural Network HTP backend)
  │     ├── GenieAPIService  ← Genie format (.bin chunks + config.json)
  │     └── AI Hub SDK       ← programmatic QNN inference
  │
  └── ONNX Runtime with QNNExecutionProvider
        └── Foundry Local / Windows AI (Phi-4-mini, Phi-3.5-mini, etc.)
```

---

## Format Comparison

| Property | Genie (QNN) | ONNX/QNN |
|---|---|---|
| File format | `.bin` chunks + `config.json` | `.onnx` with QNN-compiled weights |
| Inference server | GenieAPIService | Foundry Local / ONNX Runtime |
| API | OpenAI-compatible (port 8912) | OpenAI-compatible (port 5272) |
| Model source | aidevhome.com | Hugging Face, Azure AI Foundry |
| Conversion from HuggingFace | ❌ Requires Qualcomm AI Hub (cloud) | ⚠️ ONNX export + QNN compile needed |
| NPU memory | Protected domain (~5 GB) | Protected domain (~5 GB) |
| Speed (Llama 3.1 8B) | ~3.9 TPS | ~30–50 TPS (Phi-4-mini) |
| Model variety | Limited (10–15 pre-compiled) | Growing (Azure AI Foundry catalog) |

---

## GenieAPIService (Genie Format)

**What it is:** An OpenAI-compatible server that wraps the Qualcomm QNN runtime and serves pre-compiled Genie models.

**Binary location:** `C:\AI\GenieAPIService_cpp\GenieAPIService.exe`

**Model format:**
```
models/llama3.1-8b-8380-qnn2.38/
├── config.json                          ← model metadata + backend config
├── tokenizer.json                       ← HuggingFace tokenizer
├── htp_backend_ext_config.json          ← HTP (Hexagon Tensor Processor) config
└── llama_v3_1_8b_chat_quantized_part_[1-5]_of_5.bin  ← model weights (5 shards)
```

**Start command:**
```powershell
cd C:\AI\GenieAPIService_cpp
.\GenieAPIService.exe -c models\llama3.1-8b-8380-qnn2.38\config.json -l -d 3 -p 8912
```

**Key startup log indicators:**
```
Backend library: QnnHtp.dll        ← confirms NPU backend
QnnDevice_create done              ← NPU device acquired
Weight Sharing: true               ← memory optimization active
Allocated total size = 306545152   ← ~292 MB NPU protected memory
load successfully! use second: 4.03 ← model ready in 4 seconds
```

**Known quirks (non-blocking):**
- `"model": ""` in API response — GenieAPIService bug, functional
- `"created": -590142444` — int32 overflow, functional
- `Initialization Time Acceleration not possible` — minor QNN DLL version mismatch, ~20–30% TPS reduction

---

## Foundry Local (ONNX/QNN)

**What it is:** Microsoft's local AI inference runtime for Windows, supporting ONNX models with QNN acceleration on Snapdragon.

**Install:**
```powershell
winget install Microsoft.FoundryLocal
```

**Usage:**
```powershell
foundry model list        # browse available models
foundry run phi-4-mini    # download + start (port 5272)
```

**Supported models (QNN-accelerated, as of early 2026):**
- Phi-4-mini (~4.6 GB, ~30–50 TPS NPU)
- Phi-3.5-mini (~1.8 GB)

**Current limitation:** QNN DLL version mismatches between Foundry Local and GenieAPIService. If both are running, ensure they use compatible `QnnHtp.dll` versions. Check: `Get-Item C:\Windows\System32\QnnHtp.dll | Select-Object VersionInfo`.

---

## QNN Driver Requirements

| Component | Required version | Check |
|---|---|---|
| Snapdragon NPU driver | 30.0.140.1000+ | Device Manager → Neural Processing Unit |
| QNN SDK (QnnHtp.dll) | v2.37–v2.44 | `C:\Windows\System32\QnnHtp.dll` |
| Windows build | 24H2 (Build 26100+) | `winver` |

---

## Why Not GGUF on NPU?

Ollama uses `llama.cpp` with GGUF models. On Windows ARM64, `llama.cpp` has no NPU/GPU backend — it uses CPU NEON SIMD only. The NPU is not exposed as a standard compute API (no CUDA, no ROCm, no DirectML for Hexagon v73 in llama.cpp as of 2026).

**Short answer:** GGUF + NPU is not possible on Snapdragon X Elite. Use Genie or ONNX formats for NPU inference.

---

## Model Conversion (Advanced)

To convert a HuggingFace model to QNN format:

1. **Qualcomm AI Hub** (cloud, easiest): Upload model → compile to QNN → download `.bin` shards
2. **AIMET + QAI AppBuilder** (local): Requires specific Python versions (`py310/py311`) and Linux/WSL2. The `aimet-onnx` package is not available for `aarch64` as of March 2026 — conversion must run on x86 Linux.
3. **ONNX export + `qnn-onnx-converter`**: For ONNX-format targets (Foundry Local).

For homelab use, pre-compiled models from `aidevhome.com` or Azure AI Foundry catalog are recommended.

---

*Tested on: Snapdragon X Elite X1E78100, QNN Driver 30.0.140.1000, Windows 11 24H2 ARM64*
