# Ollama LLM test for Nvidia and AMD GPUs

This repository contains GPU testing scripts using Ollama, as well as open-source models for the Ubuntu (22.04/24.04) operating system. Currently, the testing script has been verified on Nvidia and AMD graphics cards starting from the RTX series and RADEON PRO with 16 GB of video memory on our [VGPU](https://hostkey.com/gpu-dedicated-servers/vm/) and [dedicated GPU](https://hostkey.com/gpu-dedicated-servers/dedicated/) servers.

The structure of the repository is as follows:

```bash
|
|- gpu_drivers – Script for installing Nvidia+CUDA and AMD+ROCm on Ubuntu 22.04/24.04
|- gpu_test – Testing script for Nvidia RTX graphics cards and AMD cards.
|- test_result - HTML files with result table
```

Please send the test results in the `-t test` mode through the Issues section, providing details about the configuration of the hardware for system being tested.

