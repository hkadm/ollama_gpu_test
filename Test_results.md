# Basic Performance Metrics for Testing Nvidia and AMD GPUs

The value of speed in (tokens per second) does not depend on the size of `ctx`.
Prompt: Generate Tetris game on HTML and JS.

| GPU | VRAM | Model | Tokens/sec (average) | max ctx | Load (sec) average | Generate (sec) average | Note |
|----------------------------------|------|-------------------|----------------------|---------|--------------------|------------------------|-----|
| NVIDIA RTX 6000 PRO Blackwell (gen5) | 96 GB | deepseek-r1:14b | 114.02 | 128 000 | 1.74 | 22.71 | |
| NVIDIA RTX 6000 PRO Blackwell (gen5) | 96 GB | deepseek-r1:32b | 58.73 | 128 000 | 2.44 | 42.91 | |
| NVIDIA RTX 6000 PRO Blackwell (gen5) | 96 GB | deepseek-r1:70b | 30.19 | 112 000 | 4.5 | 84,23 | |
| 2xNVIDIA GeForce RTX 5090 (gen5) | 2x32 GB | deepseek-r1:14b | 127.09 | 72 000  | 3.99 | 19.78 | model does not scale to the second GPU |
| 2xNVIDIA GeForce RTX 5090 (gen5) | 2×32 GB | deepseek-r1:32b | 65.10 | 32 000  | 5.29 | 37.30 | model does not scale to the second GPU |
| 2xNVIDIA GeForce RTX 5090 (gen5) | 2×32 GB | deepseek-r1:70b | 33.35 | 28 000  | 8.39 | 75.41 | |
| NVIDIA GeForce RTX 5090 (gen5) | 32 GB | deepseek-r1:14b | 126.68 | 76 000  | 2.01 | 20.97 | |
| NVIDIA GeForce RTX 5090 (gen5) | 32 GB | deepseek-r1:32b | 65.38 | 32 000  | 3.02 | 39.35 | |
| 2xNVIDIA GeForce RTX 4090 (gen4) | 2x24 GB | deepseek-r1:14b | 82.09 | 48 000  | 3.99 | 31.54 | model does not scale to the second GPU |
| 2xNVIDIA GeForce RTX 4090 (gen4) | 2x24 GB | deepseek-r1:32b | 40.52 | 56 000  | 4.89 | 59.80 | |
| NVIDIA GeForce RTX 4090 (gen3) | 24 GB | deepseek-r1:14b | 83.13 | 48 000  | 7.30 | 33.66 | |
| NVIDIA GeForce RTX 4090 (gen3) | 24 GB | deepseek-r1:32b | 40.94 | 12 000  | 9.19 | 58.62 | |
| NVIDIA RTX A5000 (gen3) | 24 GB | deepseek-r1:14b | 53.15 | 48 000  | 9.15 | 49.11 | |
| NVIDIA RTX A5000 (gen3) | 24 GB | deepseek-r1:32b | 25.77 | 12 000  | 11.49 | 94.10 | |
| NVIDIA RTX A5000 (gen3) | 24 GB | gpt-oss:20b | 119.46 | 128 000 | 6.12  | 22.72 | Mixture of Experts |
| NVIDIA RTX A4000 (gen4) | 16 GB | deepseek-r1:14b | 35.81 | 24 000  | 11.72 | 74.37 | |
| NVIDIA RTX A4000 (gen4) | 16 GB | ministral-3:8b | 65.42 | 64 000  | 12.92 | 44.98 | Visual |
| NVIDIA RTX A4000 (gen4) | 16 GB | ministral-3:14b | 42.28 | 36 000  | 13.99 | 86.12 | Visual |
| NVIDIA RTX A4000 (gen4) | 16 GB | gpt-oss:20b | 84.06 | 120 000 | 14.89 | 30.85 | Mixture of Experts |
| NVIDIA RTX PRO 2000 Blackwell | 16 GB | deepseek-r1:14b | 27.79 | 24 000  | 3.68 | 91.91 | |
| NVIDIA RTX PRO 2000 Blackwell | 16 GB | ministral-3:8b | 48.21 | 68 000  | 3.17 | 63.97 | Visual |
| NVIDIA RTX PRO 2000 Blackwell | 16 GB | ministral-3:14b | 30.97 | 36 000  | 3.68 | 115.42 | Visual |
| NVIDIA RTX PRO 2000 Blackwell | 16 GB | gpt-oss:20b | 62.54 | 120 000 | 4.23 | 43.26 | Mixture of Experts |
| AMD RADEON AI PRO R9700 | 32 GB | deepseek-r1:14b | 53.52 | 80 000 | 6.74 | 50.50 | |
| AMD RADEON AI PRO R9700 | 32 GB | deepseek-r1:32b | 26.29 | 36 000 | 8.11 | 92.89 | |
| AMD RADEON AI PRO R9700 | 32 GB | gpt-oss:20b | 102.40 | 128 000 | 5.71 | 28.22 | Mixture of Experts |
| 2xNVIDIA Tesla V100-SXM2 | 2x16 GB | deepseek-r1:14b | 65.47 | 56 000 | 4.63 | 39.38 | Max Nvidia drivers version 535 and CUDA 12.2 |
| 2xNVIDIA Tesla V100-SXM2 | 2x16 GB | deepseek-r1:32b | 32.79 | 24 000 | 7.81 | 78.37 | Max Nvidia drivers version 535 and CUDA 12.2 |
| 2xNVIDIA Tesla V100-SXM2 | 2x16 GB | gpt-oss:20b | 120.65 | 128 000 | 6.07 | 23.25 | Max Nvidia drivers version 535 and CUDA 12.2 |
| 2xNVIDIA Tesla V100-SXM2 | 2x16 GB | qwen3:14b | 59.70 | 52 000 | 4.38 | 160.83 | Max Nvidia drivers version 535 and CUDA 12.2 |
| 2xAMD RADEON AI PRO R9700 | 2×32 GB | deepseek-r1:14b | 52.15 | 128 000 | 12.5 | 50.3 | |
| 2xAMD RADEON AI PRO R9700 | 2×32 GB | deepseek-r1:32b | 25.90 | 96 000 | 15.2 | 92.1 |  |
| 2xAMD RADEON AI PRO R9700 | 2×32 GB | deepseek-r1:70b | 12.75 | 36 000 | 22.3 | 191.2 |  |