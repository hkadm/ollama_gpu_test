# Instructions for Using the Script to Test Video Cards with Ollama and LLM Models

A special script has been created for testing GPUs on inference in AI. 

## Script for Testing GPU through Ollama

The script automatically:

- Installs Ollama and dependencies,
- Determines the amount of available video memory (VRAM),
- Runs one or more LLM models from the default group,
- Tests them with gradually increasing context (`ctx`) from 4000 to 128000 in steps of 4000,
- Saves generated HTML games and performance metrics,
- Generates an HTML report with results (in `test` mode).

## Server Requirements

- A server with an Nvidia GPU (file `gpu_nvidia_test.sh`). Supported video cards have a memory size ranging from 16 to 96 GB. This includes models such as A4000, A5000, A6000, the RTX series, A100, H100, RTX 6000/5000 Blackwell, and others. For testing video cards with larger memory capacities, it is necessary to modify the script by adding models with a larger size or using a different degree of quantization.
- Internet access.
- Root or sudo permissions.
- At least **16 GB of video memory** to run the smallest model.

!!! warning "Attention"
    The script does not work on CPU-only systems and will stop with an error if VRAM < 16 GB.

## Installation and Launch

1. **Save the script** in a file, for example `gpu_nvidia_test.sh`:  
   ```bash
   nano gpu_nvidia_test.sh
   ```

3. **Run it as root or with sudo via bash**:  
   ```bash
   sudo bash ./gpu_nvidia_test.sh
   ```

## Launch Parameters

```bash
./gpu_test.sh [-t MODE] [-p "prompt"] [-m MODEL] [-c CONTEXT] [-g GROUP] [-h]
```

| Parameter | Description |
|-----------|-------------|
| `-t MODE` | Mode of operation: `max` (best model from the group) or `test` (all models from the group). Default is `max`. |
| `-p "prompt"` | Prompt for generation. Default: `"Generate Tetris game on HTML and JS"`. |
| `-m MODEL` | **Overrides `-t` and `-g`**. Runs **only the specified model** (downloads and tests it). |
| `-c NUMBER` | Use a fixed context size (e.g., `8192`). Without `-c`, iterates from 4000 to 128000 with steps of 4000. |
| `-g GROUP` | Select a group of models: `deepseekr1` (default), `gpt-oss`, `qwen3`, `ministral3`. |
| `-h` | Show help. |

## Available Groups and Models

| Group (`-g`) | Models | Min. VRAM |
|--------------|--------|-----------|
| `deepseekr1` (default) | `deepseek-r1:14b`, `deepseek-r1:32b`, `deepseek-r1:70b` | 15 / 23 / 48 GiB |
| `gpt-oss` | `gpt-oss:20b`, `gpt-oss:120b` | 18 / 70 GiB |
| `qwen3` | `qwen3:14b`, `qwen3:32b`, `qwen3-next:80b`| 15 / 24 / 59 GiB |
| `ministral3` | `ministral-3:8b`, `ministral-3:14b` | 7 / 15 Gib |


!!! warning "Attention"
    The script automatically skips models for which there is insufficient video memory.

## Usage Examples

### 1. **Default**: Best model from `deepseekr1`, context iteration
```bash
./gpu_test.sh
```

Selects `deepseek-r1:70b` (if ≥48 GiB), otherwise `32b` or `14b`.

### 2. **Test all models from the group `qwen3`**
```bash
./gpu_test.sh -t test -g qwen3
```
Creates an HTML report `/root/gpu_test/test_result.html` with all results.

### 3. **Run only one model (ignoring group and mode)**
```bash
./gpu_test.sh -m gpt-oss:20b
```
Downloads `gpt-oss:20b` and tests it with context iteration.

### 4. **One model with a fixed context**
```bash
./gpu_test.sh -m qwen3:32b -c 16384
```
Tests **only at `num_ctx=16384`**, without iteration.

### 5. **Test the entire group `gpt-oss` with a fixed context**
```bash
./gpu_test.sh -t test -g gpt-oss -c 8192
```
Each suitable model from `gpt-oss` will be tested **only at 8192 tokens of context**.

### 6. **With your own prompt and group**
```bash
./gpu_test.sh -g qwen3 -p "Explain transformers in simple terms" -t max
```
Runs the best available model from `qwen3` with your prompt.

### 7. **Check which models are supported at all**
```bash
./gpu_test.sh -h
```
Outputs help with a description of parameters and list of groups.

Or just try to run a non-existent model:
```bash
./gpu_test.sh -m unknown:model
```
The script will display the full list of supported models.

## Where to Find Results?

- **HTML files with generation**: `/root/gpu_test/tetris_*.html`
- **JSON responses from API**: `/root/gpu_test/ollama_response_*.json`
- **Summary report (in `-t test` mode)**: `/root/gpu_test/test_result.html`

## Important

- The script **automatically installs Ollama**, `jq`, `bc`, if they are missing.
- For working with GPU, the **NVIDIA driver must be installed** and `nvidia-smi`.
- If memory is insufficient — the script will notify you and terminate.

## Where Are Results Stored?

All files are saved in the directory `/root/gpu_test/`:

- Generated response in HTML:    
  `inference_<model>_ctx<context>.html`
- Temporary JSON responses from Ollama:    
  `ollama_response_<model>_ctx<context>.json`
- Final report (only in `-t test` mode):    
  `test_result.html`

> Open `test_result.html` in a browser to see a table with:
> - load time and generation time,
> - speed (tokens/sec),
> - GPU usage (through `nvidia-smi`),
> - links to inference at the given context size,
> - indication of used prompt.

## What Is Measured

For each combination of **model + context**, the script records:

- Model loading time (`load_duration`)
- Generation time (`eval_duration`)
- Total number of tokens (`eval_count`)
- Generation speed (tokens/sec)
- GPU usage (from `ollama ps` and `nvidia-smi`)
- Indicators of fallback to CPU (if VRAM is exhausted)

Testing stops if:

- the model cannot process the current context,
- CPU usage instead of GPU is detected,
- an empty response is received.
- insufficient video memory for the current request `model-context`.

!!! warning "Attention"

    - Do not run the script on systems without a GPU — it is not intended for CPU-only.
    - Ensure that drivers are installed for the graphics card and CUDA.

## Tips

- For quick verification of GPU power, use mode `-t max`.
- For comparing performance of different models, use mode `-t test`.
- Change the prompt via `-p` to test various types of generation (code, text, logic, etc.).
- To test a specific model: `-m` and `-c`.
- To change the group of models from default: `-g`
