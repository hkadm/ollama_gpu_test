# Instructions for Using Scripts to Test GPU with Ollama and LLM Models

Specialized scripts have been created for testing GPU inference in AI for **NVIDIA** and **AMD** GPUs.

## Available Scripts

| Script | Purpose |
|--------|---------|
| `gpu_nvidia_test_en.sh` | For servers with NVIDIA GPUs |
| `gpu_amd_test_en.sh` | For servers with AMD GPUs |

## What the Scripts Do

The scripts automatically:

- install Ollama and all dependencies,
- determine available video memory (VRAM),
- run one or more LLM models from the selected group,
- test them with gradually increasing context (ctx) from 4000 to 128000 in 4000-step increments,
- save generated HTML games and performance metrics,
- generate an HTML report with results (in `test` mode).

## Server Requirements

### For NVIDIA GPU (`gpu_nvidia_test_en.sh`)
- Server with NVIDIA GPU (supports any cards with VRAM from 16 to 96+ GB: A4000, A5000, A6000, RTX series, A100, H100, RTX 6000/5000 Blackwell, etc.)
- Installed NVIDIA driver and `nvidia-smi`

### For AMD GPU (`gpu_amd_test_en.sh`)
- Server with AMD GPU (supports cards with VRAM from 7 GB: Radeon PRO, Instinct, etc.)
- Installed ROCm and `rocm-smi` (installed automatically)

### Common Requirements
- Internet access
- `root` or `sudo` privileges
- Minimum **7 GB of video memory** to run the smallest model (ministral-3:8b)

> **⚠️ WARNING**  
> Scripts do not work on CPU-only systems and will stop with an error if VRAM is insufficient.

## Installation and Launch

1. **Save the desired script** to a file. For example, for NVIDIA:
   ```bash
   nano gpu_nvidia_test_en.sh
   ```
   Or for AMD:
   ```bash
   nano gpu_amd_test_en.sh
   ```

2. **Make the script executable**:
   ```bash
   chmod +x gpu_nvidia_test_en.sh
   ```

3. **Run as root or with sudo**:
   ```bash
   sudo ./gpu_nvidia_test_en.sh
   ```

## Launch Parameters (common for both scripts)

```bash
./gpu_<nvidia/amd>_test_en.sh [-t MODE] [-p "prompt"] [-m MODEL] [-c CONTEXT] [-g GROUP] [-h]
```

| Parameter | Description |
|-----------|-------------|
| `-t MODE` | Execution mode: `max` (single best model from group) or `test` (all models from group). Default: `max`. |
| `-p "prompt"` | Generation prompt. Default: `"Generate Tetris game on HTML and JS"`. |
| `-m MODEL` | **Ignores `-t` and `-g`**. Runs **only the specified model** (downloads and tests). |
| `-c NUMBER` | Use **fixed context size** (e.g., `8192`). Without `-c` — iterates from 4000 to 128000 in 4000-step increments. |
| `-g GROUP` | Select model group: `deepseekr1` (default), `gpt-oss`, `qwen3`, `ministral3`. |
| `-h` | Show help. |

## Available Groups and Models

| Group (`-g`) | Models | Min. VRAM |
|--------------|--------|-----------|
| `deepseekr1` (default) | `deepseek-r1:14b`<br>`deepseek-r1:32b`<br>`deepseek-r1:70b` | 15 GiB<br>23 GiB<br>48 GiB |
| `gpt-oss` | `gpt-oss:20b`<br>`gpt-oss:120b` | 14 GiB<br>66 GiB |
| `qwen3` | `qwen3:14b`<br>`qwen3:32b`<br>`qwen3-coder-next:q4_K_M`<br>`qwen3-coder-next:q8_0` | 15 GiB<br>23 GiB<br>55 GiB<br>87 GiB |
| `ministral3` | `ministral-3:8b`<br>`ministral-3:14b` | 7 GiB<br>11 GiB |

> **⚠️ WARNING**  
> Scripts automatically skip models for which there is insufficient video memory.

## Usage Examples

### 1. **Default**: best model from `deepseekr1`, context iteration
```bash
./gpu_nvidia_test_en.sh
```
Will select `deepseek-r1:70b` (if ≥48 GiB), otherwise `32b` or `14b`.

### 2. **Test all models from `qwen3` group**
```bash
./gpu_amd_test_en.sh -t test -g qwen3
```
Creates HTML report `/root/gpu_test/test_result.html` with all results.

### 3. **Run only one model (ignoring group and mode)**
```bash
./gpu_nvidia_test_en.sh -m gpt-oss:120b
```
Downloads `gpt-oss:120b` and tests it with context iteration.

### 4. **Single model with fixed context**
```bash
./gpu_amd_test_en.sh -m qwen3:32b -c 16384
```
Tests **only with `num_ctx=16384`**, without iteration.

### 5. **Test entire `gpt-oss` group with fixed context**
```bash
./gpu_nvidia_test_en.sh -t test -g gpt-oss -c 8192
```
Each suitable model from `gpt-oss` will be tested **only with 8192 context tokens**.

### 6. **Custom prompt and group**
```bash
./gpu_amd_test_en.sh -g qwen3 -p "Explain transformers in simple terms" -t max
```
Runs the best available model from `qwen3` with your prompt.

### 7. **Check which models are supported**
```bash
./gpu_nvidia_test_en.sh -h
```
Displays help with parameter descriptions and group list.

Or try to run a non-existent model:
```bash
./gpu_amd_test_en.sh -m unknown:model
```
The script will show the full list of supported models.

## Where to Find Results?

All files are saved in the `/root/gpu_test/` directory:

- **Generated HTML files**: `tetris_<model>_ctx<context>.html`
- **API JSON responses**: `ollama_response_<model>_ctx<context>.json`
- **Summary report (in `-t test` mode)**: `test_result.html`

> Open `test_result.html` in your browser to see a table with:
> - load and generation times,
> - speed (tokens/sec),
> - GPU usage (via `ollama ps` and `nvidia-smi`/`amd-smi`),
> - links to generated HTML files,
> - the prompt used.

## What Gets Measured

For each **model + context** combination, the script records:
- Model load time (`load_duration`)
- Generation time (`eval_duration`)
- Total number of tokens (`eval_count`)
- Generation speed (tokens/sec)
- GPU usage (from `ollama ps`)
- For NVIDIA: detailed statistics from `nvidia-smi` (memory, temperature, power consumption)
- For AMD: detailed statistics from `amd-smi` (memory, temperature, GFX utilization, power consumption)
- Signs of CPU fallback (if VRAM runs out)

Testing stops if:
- the model cannot process the current context,
- CPU usage is detected instead of GPU,
- an empty response is received,
- there is insufficient video memory for the current request.

> **⚠️ IMPORTANT**  
> - Do not run scripts on systems without GPUs — they are not designed for CPU-only.  
> - For NVIDIA, make sure drivers and CUDA are installed.  
> - For AMD, make sure ROCm is installed (the script will attempt to install `rocm-smi` automatically).

## Features for AMD GPU

The `gpu_amd_test_en.sh` script uses:
- `rocm-smi` for basic monitoring
- `amd-smi` (if available) for extended statistics with nice formatting

The AMD GPU report displays:
- Temperature (`edge`)
- Memory utilization (`umc_activity`)
- VRAM usage in GB
- GFX utilization
- Power consumption

## Tips

- For quick GPU power testing, use `-t max` mode.
- To compare performance of different models, use `-t test` mode.
- Change the prompt with `-p` to test different types of generation (code, text, logic, etc.).
- To test a specific model: `-m` and `-c`.
- To change the default model group: `-g`.
- For large models (70B+, 120B), make sure you have enough VRAM or use quantized versions.
