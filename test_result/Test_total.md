# Basic Performance Metrics for Testing Nvidia Video Cards

The value of speed in (tokens per second) does not depend on the size of `ctx`.


| GPU                              | Model             | Tokens/sec (average) | max ctx | Load (sec) average | Generate (sec) average | Note |
|----------------------------------|-------------------|----------------------|---------|--------------------|------------------------|------|
| 2xNVIDIA GeForce RTX 5090 (gen5) | deepseek-r1:14b   | 127.09               | 72 000  | 3.99               | 19.78                  | model does not scale to the second GPU |
| 2xNVIDIA GeForce RTX 5090 (gen5) | deepseek-r1:32b   | 65.10                | 32 000  | 5.29               | 37.30                  | model does not scale to the second GPU |
| 2xNVIDIA GeForce RTX 5090 (gen5) | deepseek-r1:70b   | 33.35                | 28 000  | 8.39               | 75.41                  |      |
| NVIDIA GeForce RTX 5090 (gen5)   | deepseek-r1:14b   | 126.68               | 76 000  | 2.01               | 20.97                  |      |
| NVIDIA GeForce RTX 5090 (gen5)   | deepseek-r1:32b   | 65.38                | 32 000  | 3.02               | 39.35                  |      |
| 2xNVIDIA GeForce RTX 4090 (gen4) | deepseek-r1:14b   | 82.09                | 48 000  | 3.99               | 31.54                  | model does not scale to the second GPU |
| 2xNVIDIA GeForce RTX 4090 (gen4) | deepseek-r1:32b   | 40.52                | 56 000  | 4.89               | 59.80                  |      |
| NVIDIA GeForce RTX 4090 (gen3)   | deepseek-r1:14b   | 83.13                | 48 000  | 7.30               | 33.66                  |      |
| NVIDIA GeForce RTX 4090 (gen3)   | deepseek-r1:32b   | 40.94                | 12 000  | 9.19               | 58.62                  |      |
| NVIDIA RTX A5000 (gen3)          | deepseek-r1:14b   | 53.15                | 48 000  | 9.15               | 49.11                  |      |
| NVIDIA RTX A5000 (gen3)          | deepseek-r1:32b   | 25.77                | 12 000  | 11.49              | 94.10                  |      |
| NVIDIA RTX A4000 (gen4)          | deepseek-r1:14b   | 35.81                | 24 000  | 11.72              | 74.37                  |      |

