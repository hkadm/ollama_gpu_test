#!/bin/bash

#Check Ubuntu 25.04 and exit
if lsb_release -a | grep -q "25.04"; then
echo "Detected Ubuntu 25.04. NVIDIA do not support official CUDA for non-LTS release. Use Ubuntu 24.04 or 22.04 instead!"
exit
fi

# Update and upgrade the system using apt
sudo apt update
sudo apt upgrade -y

#Check Ubuntu 22.04 and update kernel
lsb_release=$(lsb_release -a | grep "22.04")
if [[ -n "$lsb_release" ]]; then
    sudo apt install -y linux-generic-hwe-22.04
fi

# Install GCC compiler for CUDA install
sudo apt install gcc-12 g++-12

# Get the release version of Ubuntu
RELEASE_VERSION=$(lsb_release -rs | sed 's/\([0-9]\+\)\.\([0-9]\+\)/\1\2/')

# Download and install CUDA package for Ubuntu and Nvidia drivers
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${RELEASE_VERSION}/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb

# Update and upgrade the system again to ensure all packages are installed correctly
sudo apt update
sudo apt install cuda -y
sudo apt install cuda-toolkit -y

# Add PATH and LD_LIBRARY_PATH environment variables for CUDA in .bashrc file
echo 'export PATH="/sbin:/bin:/usr/sbin:/usr/bin:${PATH}:/usr/local/cuda/bin"' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}' >> ~/.bashrc
source ~/.bashrc

#Initialize kernel modules without reboot

sudo rmmod -f nouveau
sudo nvidia-smi

nvcc -V

#Installing Docker binding for Nvidia. Please install Docker first!

if command -v docker &> /dev/null; then

    if lsb_release -a | grep -q "22.04"; then
    echo "Detected Ubuntu 22.04. Installing nvidia-docker2..."
    sudo apt install -y nvidia-docker2
    sudo systemctl restart docker
    fi

    if lsb_release -a | grep -q "24.04"; then
    echo "Detected Ubuntu 24.04. Installing nvidia-container-toolkit..."
    sudo apt install -y nvidia-container-toolkit
    sudo systemctl restart docker
    fi

else
  echo "Docker is not installed."
fi
