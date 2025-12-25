#!/bin/bash
set -euo pipefail

# Universal NVIDIA Driver + CUDA installer for Ubuntu 22.04/24.04 LTS

# FLAGS (enable/disable steps here)
DO_OS_POLICY_CHECK=1                 # Enforce policy: only Ubuntu 22.04/24.04 LTS
ALLOWED_UBUNTU_VERSIONS=("22.04" "24.04")

DO_APT_UPGRADE=1                     # apt update/upgrade
DO_INSTALL_HWE_2204=1                # Install linux-generic-hwe-22.04 on 22.04
DO_INSTALL_BUILD_TOOLS=1             # Install GCC/G++
GCC_PACKAGES=("gcc-12" "g++-12")

DO_PURGE_OLD_PACKAGES=1              # Best effort purge old NVIDIA/CUDA packages
DO_SETUP_CUDA_REPO=1                 # Install CUDA apt repo via cuda-keyring
DO_INSTALL_CUDA_STACK=1              # Install CUDA packages (toolkit + meta if enabled)
DO_INSTALL_CUDA_META=1               # Install "cuda" meta package in addition to "cuda-toolkit"
CUDA_TOOLKIT_PKG="cuda-toolkit"
CUDA_META_PKG="cuda"

# Special-case GPU handling (example kept from original)
GTX1080TI_PCI_ID="10de:1b06"
DO_GTX1080TI_DRIVER_PIN=1
GTX1080TI_DRIVER_PKG="nvidia-driver-535"   # Same as your original

DO_BLACKLIST_NOUVEAU=1               # Create blacklist + update-initramfs (reboot needed)
DO_TRY_RMMOD_NOUVEAU=1               # Best effort rmmod nouveau (may fail if in use)

DO_USER_GROUPS=0                     # Add user to video,render (optional)
DO_BASHRC_CUDA_PATHS=1               # Add CUDA PATH/LD_LIBRARY_PATH via ~/.bashrc (idempotent)

DO_VERIFY_NVIDIA_SMI=1               # Run nvidia-smi
DO_VERIFY_NVCC=1                     # Run nvcc -V (only if nvcc exists)

DO_INSTALL_NVIDIA_CONTAINER_TOOLKIT=1  # Install NVIDIA Container Toolkit if docker exists
DO_CONFIGURE_DOCKER_RUNTIME=1          # Run nvidia-ctk runtime configure --runtime=docker
DO_RESTART_DOCKER=1                    # Restart docker service

# ---- Start ----
echo "Starting NVIDIA driver + CUDA installation..."

# Dependency checks
for cmd in lspci wget gpg curl sed awk uname; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd"; exit 1; }
done

# Load OS identification (prefer /etc, fallback to /usr/lib)
osr="/etc/os-release"
[[ -r "$osr" ]] || osr="/usr/lib/os-release"

if [[ ! -r "$osr" ]]; then
  echo "Cannot read os-release file. Exiting."
  exit 1
fi

# os-release is a shell-style KEY=VALUE file; source it to get ID/VERSION_ID/etc
set -a
. "$osr"
set +a

# Check this is Ubuntu
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script is intended for Ubuntu. Exiting."
  exit 1
fi

UBUNTU_VERSION="${VERSION_ID:-}"
UBUNTU_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"

if [[ -z "${UBUNTU_VERSION}" ]]; then
  echo "Cannot detect Ubuntu VERSION_ID from os-release. Exiting."
  exit 1
fi

if [[ "${DO_OS_POLICY_CHECK:-0}" -eq 1 ]]; then
  if ! declare -p ALLOWED_UBUNTU_VERSIONS >/dev/null 2>&1; then
    echo "ALLOWED_UBUNTU_VERSIONS is not defined. Exiting."
    exit 1
  fi

  ok=0
  for v in "${ALLOWED_UBUNTU_VERSIONS[@]}"; do
    if [[ "${UBUNTU_VERSION}" == "${v}" ]]; then
      ok=1
      break
    fi
  done

  if [[ "${ok}" -ne 1 ]]; then
    echo "Unsupported Ubuntu version by this script policy: ${UBUNTU_VERSION}"
    echo "Allowed: ${ALLOWED_UBUNTU_VERSIONS[*]}"
    exit 1
  fi
fi

# Detect NVIDIA GPU (vendor 10de)
NVIDIA_GPU_LINES="$(lspci -nn | grep -iE 'vga|3d' | grep -i '10de:' || true)"
if [[ -z "${NVIDIA_GPU_LINES}" ]]; then
  echo "No NVIDIA GPU detected (vendor 10de). Exiting."
  exit 1
fi
echo "NVIDIA GPUs detected:"
echo "${NVIDIA_GPU_LINES}"

REBOOT_REQUIRED=0

# Update/upgrade
if [[ "${DO_APT_UPGRADE}" -eq 1 ]]; then
  sudo apt update
  sudo apt upgrade -y
fi

# Kernel (HWE) for 22.04
if [[ "${DO_INSTALL_HWE_2204}" -eq 1 ]] && [[ "${UBUNTU_VERSION}" == "22.04" ]]; then
  echo "Ubuntu 22.04 detected: installing HWE kernel package..."
  sudo apt install -y linux-generic-hwe-22.04
  REBOOT_REQUIRED=1
fi

# Build tools for Nvidia
if [[ "${DO_INSTALL_BUILD_TOOLS}" -eq 1 ]]; then
  sudo apt install -y "${GCC_PACKAGES[@]}"
fi

# Purge old packages (best effort)
if [[ "${DO_PURGE_OLD_PACKAGES}" -eq 1 ]]; then
  echo "Purging previous NVIDIA/CUDA installations (best effort)..."
  sudo dpkg --configure -a || true
  sudo apt purge -y "nvidia-*" "libnvidia-*" "cuda-*" "nvidia-driver-*" "*cudnn*" "*nsight*" || true
  sudo apt remove --purge -y nvidia-cuda-toolkit nvidia-prime nvidia-settings || true
  sudo apt autoremove -y || true
  sudo apt --fix-broken install -y || true
  sudo apt clean -y || true
fi

# Setup CUDA repository via cuda-keyring
if [[ "${DO_SETUP_CUDA_REPO}" -eq 1 ]]; then
  # ubuntu22.04 -> 2204, ubuntu24.04 -> 2404
  RELEASE_VERSION="$(echo "${UBUNTU_VERSION}" | sed 's/\([0-9]\+\)\.\([0-9]\+\)/\1\2/')"
  echo "Setting up CUDA repo for ubuntu${RELEASE_VERSION}..."

  wget -q "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${RELEASE_VERSION}/x86_64/cuda-keyring_1.1-1_all.deb"
  sudo dpkg -i cuda-keyring_1.1-1_all.deb
  rm -f cuda-keyring_1.1-1_all.deb || true

  sudo apt update
fi

# Optional: blacklist nouveau (persistent; requires reboot)
if [[ "${DO_BLACKLIST_NOUVEAU}" -eq 1 ]]; then
  BL_FILE="/etc/modprobe.d/blacklist-nouveau.conf"
  if [[ ! -f "${BL_FILE}" ]] || ! grep -q "^blacklist nouveau" "${BL_FILE}"; then
    echo "Blacklisting nouveau (requires reboot)..."
    sudo tee "${BL_FILE}" >/dev/null <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
    sudo update-initramfs -u
    REBOOT_REQUIRED=1
  else
    echo "nouveau already blacklisted."
  fi
fi

# Install driver/CUDA
if lspci -nn | grep -q "${GTX1080TI_PCI_ID}"; then
  echo "Detected GTX 1080 Ti (${GTX1080TI_PCI_ID})."

  if [[ "${DO_GTX1080TI_DRIVER_PIN}" -eq 1 ]]; then
    echo "Installing pinned driver package: ${GTX1080TI_DRIVER_PKG}"
    sudo apt install -y "${GTX1080TI_DRIVER_PKG}"
  else
    echo "Installing default driver via meta packages..."
    sudo apt install -y nvidia-driver
  fi
else
  if [[ "${DO_INSTALL_CUDA_STACK}" -eq 1 ]]; then
    echo "Installing CUDA toolkit..."
    sudo apt install -y "${CUDA_TOOLKIT_PKG}"

    if [[ "${DO_INSTALL_CUDA_META}" -eq 1 ]]; then
      echo "Installing CUDA meta package: ${CUDA_META_PKG}"
      sudo apt install -y "${CUDA_META_PKG}"
    fi
  fi
fi

# Best effort: unload nouveau now (may fail)
if [[ "${DO_TRY_RMMOD_NOUVEAU}" -eq 1 ]]; then
  sudo rmmod -f nouveau 2>/dev/null || true
fi

# User groups (optional)
if [[ "${DO_USER_GROUPS}" -eq 1 ]]; then
  TARGET_USER="${SUDO_USER:-$USER}"
  sudo usermod -aG video,render "${TARGET_USER}" || true
  echo "User added to groups: video, render (${TARGET_USER}). Re-login or reboot required."
  REBOOT_REQUIRED=1
fi

# Add PATH/LD_LIBRARY_PATH in ~/.bashrc (idempotent block)
if [[ "${DO_BASHRC_CUDA_PATHS}" -eq 1 ]]; then
  TARGET_USER="${SUDO_USER:-$USER}"
  TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  TARGET_BASHRC="${TARGET_HOME}/.bashrc"
  MARKER="NVIDIA CUDA Paths"

  if [[ ! -f "${TARGET_BASHRC}" ]]; then
    sudo -u "${TARGET_USER}" touch "${TARGET_BASHRC}" || true
  fi

  if ! grep -q "${MARKER}" "${TARGET_BASHRC}" 2>/dev/null; then
    cat >> "${TARGET_BASHRC}" <<'EOF'

# NVIDIA CUDA Paths
export PATH="/usr/local/cuda/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
EOF
    echo "Added CUDA PATH/LD_LIBRARY_PATH to ${TARGET_BASHRC}"
  else
    echo "CUDA PATH block already present in ${TARGET_BASHRC}"
  fi
fi

# Verify nvidia-smi
if [[ "${DO_VERIFY_NVIDIA_SMI}" -eq 1 ]]; then
  echo "Running nvidia-smi..."
  nvidia-smi || true
fi

# Verify nvcc (only if present)
if [[ "${DO_VERIFY_NVCC}" -eq 1 ]]; then
  if command -v nvcc >/dev/null 2>&1; then
    echo "Running nvcc -V..."
    nvcc -V || true
  else
    echo "nvcc not found in PATH yet (this can be normal before re-login / reboot)."
  fi
fi

# NVIDIA Container Toolkit (Docker integration)
if [[ "${DO_INSTALL_NVIDIA_CONTAINER_TOOLKIT}" -eq 1 ]]; then
  if command -v docker >/dev/null 2>&1; then
    echo "Docker detected: installing NVIDIA Container Toolkit..."

    # Install prerequisites
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends curl gnupg2

    # Configure NVIDIA repo (production)
    sudo install -d -m 0755 /usr/share/keyrings
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit

    if [[ "${DO_CONFIGURE_DOCKER_RUNTIME}" -eq 1 ]]; then
      if command -v nvidia-ctk >/dev/null 2>&1; then
        sudo nvidia-ctk runtime configure --runtime=docker || true
      else
        echo "nvidia-ctk not found; skipping runtime auto-config."
      fi
    fi

    if [[ "${DO_RESTART_DOCKER}" -eq 1 ]]; then
      sudo systemctl restart docker || true
    fi
  else
    echo "Docker is not installed. Skipping NVIDIA Container Toolkit."
  fi
fi

# Final
echo "Installation finished."
if [[ "${REBOOT_REQUIRED}" -eq 1 ]]; then
  echo "Reboot required/recommended (kernel/modules/initramfs/groups may have changed)."
fi

echo "After reboot (or re-login), verify:"
echo "  nvidia-smi"
echo "  nvcc -V"
