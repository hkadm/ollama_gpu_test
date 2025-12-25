#!/bin/bash
set -euo pipefail

# Universal AMD GPU + ROCm ("latest") installer for Ubuntu 24.04+

# FLAGS (enable/disable steps here)

DO_APT_UPGRADE=1

DO_OS_POLICY_CHECK=1                 # Enforce policy: only Ubuntu 24.04 LTS
ALLOWED_UBUNTU_VERSIONS=("24.04")

DO_KERNEL_POLICY_CHECK=1          # Enforce policy "kernel >= REQUIRED_KERNEL_MM"
DO_INSTALL_MAINLINE_KERNEL=1      # If kernel is lower, try installing a mainline kernel
REQUIRED_KERNEL_MM="6.13"

DO_GRUB_PARAMS=0                  # Add GRUB params (conservatively disabled by default)
GRUB_PARAMS=("amdgpu.gpu_recovery=1" "amdgpu.runpm=0" "amdgpu.ppfeaturemask=0xffffffff")

DO_PURGE_OLD_PACKAGES=1           # Remove old rocm/amdgpu/hip packages (best effort)
DO_SETUP_ROCM_REPO=1              # Add ROCm repository
DO_INSTALL_ROCM=1                 # Install rocm-dev/rocm-libs/...
DO_LINK_OPT_ROCM=1                # Make /opt/rocm -> /opt/rocm-X.Y.Z (if found)

DO_USER_GROUPS=1                  # Add user to render,video
DO_BASHRC_PATH=1                  # Add /opt/rocm/bin to PATH via ~/.bashrc

DO_OLLAMA_AMDGPU_IDS_WORKAROUND=1 # Create amdgpu.ids link for some Ollama builds
DO_GPU_POWER_CONTROL_ON=1         # Best effort: set power/control=on (if available)


# Start
echo "Starting AMD ROCm installation..."

# Dependency checks
for cmd in lspci wget gpg curl lsb_release; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done


# Check this is Ubuntu (robust: don't grep raw file)

. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script is intended for Ubuntu. Exiting."
  exit 1
fi


# Restrict script to specific Ubuntu releases (only 24.04)
# ALLOWED_UBUNTU_VERSIONS=("24.04")
if [[ "${DO_OS_POLICY_CHECK}" -eq 1 ]]; then
  UBUNTU_VERSION="$(lsb_release -rs)"  # e.g. 24.04 [web:62]

  ok=0
  for v in "${ALLOWED_UBUNTU_VERSIONS[@]}"; do
    if [[ "${UBUNTU_VERSION}" == "${v}" ]]; then
      ok=1
      break
    fi
  done

  if [[ "${ok}" -ne 1 ]]; then
    echo "Unsupported Ubuntu version: ${UBUNTU_VERSION}"
    echo "Allowed versions: ${ALLOWED_UBUNTU_VERSIONS[*]}"
    exit 1
  fi
fi

# Detect AMD GPU (vendor 1002)
AMD_GPU_LINES="$(lspci -nn | grep -iE 'vga|3d' | grep -i '1002:' || true)"
if [[ -z "${AMD_GPU_LINES}" ]]; then
  echo "No AMD GPU detected (vendor 1002)."
  exit 1
fi
echo "AMD GPUs detected:"
echo "${AMD_GPU_LINES}"

# Update/upgrade
if [[ "${DO_APT_UPGRADE}" -eq 1 ]]; then
  sudo apt update
  sudo apt upgrade -y
fi

# Kernel check/upgrade (script policy)
KERNEL_INSTALLED=0
echo "Current kernel: $(uname -r)"

if [[ "${DO_KERNEL_POLICY_CHECK}" -eq 1 ]]; then
  KERNEL_VERSION="$(uname -r)"
  KERNEL_MM="$(echo "${KERNEL_VERSION}" | sed -nE 's/^([0-9]+)\.([0-9]+).*/\1.\2/p')"

  req_major="${REQUIRED_KERNEL_MM%.*}"
  req_minor="${REQUIRED_KERNEL_MM#*.}"
  cur_major="${KERNEL_MM%.*}"
  cur_minor="${KERNEL_MM#*.}"

  KERNEL_OK=0
  if [[ "${cur_major}" -gt "${req_major}" ]] || \
     [[ "${cur_major}" -eq "${req_major}" && "${cur_minor}" -ge "${req_minor}" ]]; then
    KERNEL_OK=1
  fi

  if [[ "${KERNEL_OK}" -ne 1 ]]; then
    echo "Kernel is older than required by this script policy (>= ${REQUIRED_KERNEL_MM})."
    if [[ "${DO_INSTALL_MAINLINE_KERNEL}" -eq 1 ]]; then
      echo "Installing latest mainline kernel..."
      sudo add-apt-repository ppa:cappelikan/ppa -y 2>/dev/null || true
      sudo apt update
      sudo apt install -y mainline pkexec
      sudo mainline install-latest
      echo "Mainline kernel installed. Reboot required to activate it."
      KERNEL_INSTALLED=1
    else
      echo "Mainline kernel install is disabled by flag DO_INSTALL_MAINLINE_KERNEL=0. Continuing."
    fi
  fi
fi


# Optional: GRUB parameters (append-only)
if [[ "${DO_GRUB_PARAMS}" -eq 1 ]]; then
  GRUB_FILE="/etc/default/grub"
  GRUB_CHANGED=0

  for param in "${GRUB_PARAMS[@]}"; do
    if ! sudo grep -qE "GRUB_CMDLINE_LINUX_DEFAULT=.*\b${param}\b" "${GRUB_FILE}"; then
      sudo cp -a "${GRUB_FILE}" "${GRUB_FILE}.backup.$(date +%F-%H%M%S)"
      sudo sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\")([^\"]*)\"/\1\2 ${param}\"/" "${GRUB_FILE}"
      echo "Added GRUB param: ${param}"
      GRUB_CHANGED=1
    else
      echo "GRUB param already present: ${param}"
    fi
  done

  if [[ "${GRUB_CHANGED}" -eq 1 ]]; then
    sudo update-grub
    echo "GRUB updated."
  fi
else
  echo "Skipping GRUB parameters (DO_GRUB_PARAMS=0)."
fi


# Best effort: purge old packages/repos
if [[ "${DO_PURGE_OLD_PACKAGES}" -eq 1 ]]; then
  echo "Removing previous ROCm/AMDGPU packages (best effort)..."
  sudo dpkg --configure -a || true
  sudo apt remove --purge -y rocminfo || true
  sudo apt purge -y 'rocm*' 'amdgpu*' 'graphics*' 'hip*' || true
  sudo apt autoremove -y || true
  sudo apt clean || true
  sudo rm -rf /etc/apt/sources.list.d/amdgpu* /etc/apt/sources.list.d/rocm* /etc/apt/sources.list.d/graphics* || true
  sudo apt update || true
else
  echo "Skipping purge old packages (DO_PURGE_OLD_PACKAGES=0)."
fi


# Add ROCm "latest" repository
if [[ "${DO_SETUP_ROCM_REPO}" -eq 1 ]]; then
  echo "Setting up ROCm 'latest' repository..."

  . /etc/os-release

  UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  if [[ -z "${UBUNTU_CODENAME}" ]]; then
  echo "Cannot detect Ubuntu codename (UBUNTU_CODENAME/VERSION_CODENAME)."
  exit 1
  fi

  sudo install -d -m 0755 /usr/share/keyrings
  wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/rocm-archive-keyring.gpg >/dev/null

  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/rocm-archive-keyring.gpg] https://repo.radeon.com/rocm/apt/latest/ ${UBUNTU_CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/rocm.list >/dev/null

  # Pin repo.radeon.com above Ubuntu
  sudo tee /etc/apt/preferences.d/rocm-pin-600 >/dev/null <<'EOF'
Package: *
Pin: origin repo.radeon.com
Pin-Priority: 600
EOF

else
  echo "Skipping ROCm repo setup (DO_SETUP_ROCM_REPO=0)."
fi


# Install ROCm packages
if [[ "${DO_INSTALL_ROCM}" -eq 1 ]]; then
  echo "Installing ROCm stack..."
  sudo apt update
  sudo apt install -y -o Dpkg::Options::="--force-overwrite" \
    rocm-dev rocm-libs rocm-hip-sdk rocm-smi-lib rocminfo
else
  echo "Skipping ROCm install (DO_INSTALL_ROCM=0)."
fi

# /opt/rocm -> /opt/rocm-X.Y.Z
if [[ "${DO_LINK_OPT_ROCM}" -eq 1 ]]; then
  INSTALLED_ROCM_DIR="$(ls -d /opt/rocm-[0-9]* 2>/dev/null | sort -V | tail -n 1 || true)"
  if [[ -n "${INSTALLED_ROCM_DIR}" ]]; then
    REAL_VERSION="$(echo "${INSTALLED_ROCM_DIR}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo latest)"
    sudo ln -sfn "${INSTALLED_ROCM_DIR}" /opt/rocm
    echo "ROCm detected: ${REAL_VERSION} (${INSTALLED_ROCM_DIR}); linked /opt/rocm -> ${INSTALLED_ROCM_DIR}"
  else
    echo "No /opt/rocm-X.Y.Z directory found; leaving /opt/rocm as-is."
  fi
else
  echo "Skipping /opt/rocm symlink (DO_LINK_OPT_ROCM=0)."
fi

# User groups: render,video
if [[ "${DO_USER_GROUPS}" -eq 1 ]]; then
  TARGET_USER="${SUDO_USER:-$USER}"
  sudo usermod -aG render,video "${TARGET_USER}" || true
  echo "User added to groups: render, video (${TARGET_USER}). Re-login or reboot required."
else
  echo "Skipping user groups (DO_USER_GROUPS=0)."
fi

# PATH + LD_LIBRARY_PATH in ~/.bashrc
if [[ "${DO_BASHRC_PATH}" -eq 1 ]]; then
  TARGET_USER="${SUDO_USER:-$USER}"
  TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  TARGET_BASHRC="${TARGET_HOME}/.bashrc"
  MARKER="AMD ROCm Paths"

  if [[ ! -f "${TARGET_BASHRC}" ]]; then
    sudo -u "${TARGET_USER}" touch "${TARGET_BASHRC}" || true
  fi

  # Determining the installed ROCm version
  ROCM_VERSION_DIR="$(ls -d /opt/rocm-[0-9]* 2>/dev/null | sort -V | tail -n 1 || true)"
  if [[ -n "${ROCM_VERSION_DIR}" ]]; then
    ROCM_VERSION="$(basename "${ROCM_VERSION_DIR}" | sed 's/rocm-//')"
    echo "Using ROCm version: ${ROCM_VERSION} (${ROCM_VERSION_DIR})"
  else
    ROCM_VERSION="unknown"
    echo "Warning: No /opt/rocm-X.Y.Z found; using generic paths"
  fi

  if ! grep -q "${MARKER}" "${TARGET_BASHRC}" 2>/dev/null; then
    cat >> "${TARGET_BASHRC}" <<EOF

# ${MARKER}
if [ -d "/opt/rocm-${ROCM_VERSION}" ]; then
  export PATH="/opt/rocm-${ROCM_VERSION}/bin:\$PATH"
  export LD_LIBRARY_PATH="/opt/rocm-${ROCM_VERSION}/hip/lib:/opt/rocm-${ROCM_VERSION}/lib:\$LD_LIBRARY_PATH"
  export ROCM_PATH="/opt/rocm-${ROCM_VERSION}"
  export HIP_CLANG_PATH="/opt/rocm-${ROCM_VERSION}/llvm/bin"
fi
EOF
    echo "Added full ROCm paths (PATH+LD_LIBRARY_PATH) to ${TARGET_BASHRC}"
  else
    echo "ROCm PATH block already present in ${TARGET_BASHRC}"
  fi

  # Apply to the current session
  if [[ -n "${ROCM_VERSION_DIR}" ]]; then
    export PATH="${ROCM_VERSION_DIR}/bin:${PATH}"
    export LD_LIBRARY_PATH="${ROCM_VERSION_DIR}/hip/lib:${ROCM_VERSION_DIR}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    export ROCM_PATH="${ROCM_VERSION_DIR}"
    export HIP_CLANG_PATH="${ROCM_VERSION_DIR}/llvm/bin"
  fi
else
  echo "Skipping .bashrc PATH (DO_BASHRC_PATH=0)."
fi


# AMD ROCm Paths
export PATH="/opt/rocm/bin:$PATH"
EOF
    echo "Added ROCm PATH to ${TARGET_BASHRC}"
  else
    echo "ROCm PATH block already present in ${TARGET_BASHRC}"
  fi
else
  echo "Skipping .bashrc PATH (DO_BASHRC_PATH=0)."
fi

# Workaround for amdgpu.ids (some Ollama builds)
if [[ "${DO_OLLAMA_AMDGPU_IDS_WORKAROUND}" -eq 1 ]]; then
  if [[ -f /usr/share/libdrm/amdgpu.ids ]]; then
    sudo mkdir -p /opt/amdgpu/share/libdrm
    sudo ln -sf /usr/share/libdrm/amdgpu.ids /opt/amdgpu/share/libdrm/amdgpu.ids
    echo "Created compatibility link: /opt/amdgpu/share/libdrm/amdgpu.ids -> /usr/share/libdrm/amdgpu.ids"
  else
    echo "amdgpu.ids not found at /usr/share/libdrm/amdgpu.ids; skipping workaround."
  fi
else
  echo "Skipping Ollama amdgpu.ids workaround (DO_OLLAMA_AMDGPU_IDS_WORKAROUND=0)."
fi

# Best effort: power/control=on
if [[ "${DO_GPU_POWER_CONTROL_ON}" -eq 1 ]]; then
  if [[ -w /sys/class/drm/card0/device/power/control ]]; then
    echo on | sudo tee /sys/class/drm/card0/device/power/control >/dev/null
    echo "Set /sys/class/drm/card0/device/power/control = on"
  else
    echo "No write access to /sys/class/drm/card0/device/power/control; skipping."
  fi
else
  echo "Skipping GPU power control (DO_GPU_POWER_CONTROL_ON=0)."
fi

# Final
echo "Installation finished."
if [[ "${KERNEL_INSTALLED}" -eq 1 ]]; then
  echo "Reboot required to activate the new kernel."
else
  echo "Reboot recommended to apply group membership changes."
fi

echo "After reboot, verify:"
echo "  rocminfo"
echo "  amd-smi (if installed)"
