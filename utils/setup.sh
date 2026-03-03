#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Firecracker VM setup utility
# Downloads latest kernel + Ubuntu rootfs from Firecracker CI
# and prepares an ext4 disk image with SSH access.
# ------------------------------------------------------------

# ------------------------------------------------------------
# Create workspace directory
# ------------------------------------------------------------
WORKSPACE="firecracker-vm"

echo "[*] Creating workspace: ${WORKSPACE}"
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

# Run script
ARCH="$(uname -m)"
RELEASE_URL="https://github.com/firecracker-microvm/firecracker/releases"

echo "[*] Detecting latest Firecracker release..."
LATEST_VERSION="$(
  curl -fsSLI -o /dev/null -w '%{url_effective}' "${RELEASE_URL}/latest" \
  | xargs basename
)"

CI_VERSION="${LATEST_VERSION%.*}"

echo "[*] Architecture : ${ARCH}"
echo "[*] CI Version   : ${CI_VERSION}"

# ------------------------------------------------------------
# Helper: fetch newest artifact key from S3 index
# ------------------------------------------------------------
get_latest_key() {
  local prefix="$1"

  curl -fsSL "http://spec.ccfc.min.s3.amazonaws.com/?prefix=${prefix}&list-type=2" \
    | grep -oP '(?<=<Key>)[^<]+' \
    | sort -V \
    | tail -n 1
}

# ------------------------------------------------------------
# Download kernel
# ------------------------------------------------------------
echo "[*] Fetching latest kernel..."

KERNEL_KEY="$(
  curl -fsSL "http://spec.ccfc.min.s3.amazonaws.com/?prefix=firecracker-ci/${CI_VERSION}/${ARCH}/vmlinux-&list-type=2" \
  | grep -oP "(?<=<Key>)(firecracker-ci/${CI_VERSION}/${ARCH}/vmlinux-[0-9]+\.[0-9]+\.[0-9]+)(?=</Key>)" \
  | sort -V \
  | tail -n 1
)"

KERNEL_FILE="$(basename "${KERNEL_KEY}")"

wget -q --show-progress \
  "https://s3.amazonaws.com/spec.ccfc.min/${KERNEL_KEY}"

echo "[+] Kernel downloaded: ${KERNEL_FILE}"

# ------------------------------------------------------------
# Download Ubuntu rootfs
# ------------------------------------------------------------
echo "[*] Fetching Ubuntu rootfs..."

UBUNTU_KEY="$(get_latest_key "firecracker-ci/${CI_VERSION}/${ARCH}/ubuntu-")"
UBUNTU_VERSION="$(basename "${UBUNTU_KEY}" .squashfs | grep -oE '[0-9]+\.[0-9]+')"

ROOTFS_SQUASH="ubuntu-${UBUNTU_VERSION}.squashfs.upstream"

wget -q --show-progress \
  -O "${ROOTFS_SQUASH}" \
  "https://s3.amazonaws.com/spec.ccfc.min/${UBUNTU_KEY}"

echo "[+] Rootfs downloaded: ${ROOTFS_SQUASH}"

# ------------------------------------------------------------
# Prepare root filesystem with SSH access
# ------------------------------------------------------------
echo "[*] Preparing writable ext4 rootfs..."

WORKDIR="squashfs-root"

unsquashfs -f "${ROOTFS_SQUASH}"

echo "[*] Generating SSH key..."
ssh-keygen -q -f id_rsa -N ""

install -Dm600 id_rsa.pub "${WORKDIR}/root/.ssh/authorized_keys"
mv id_rsa "ubuntu-${UBUNTU_VERSION}.id_rsa"

sudo chown -R root:root "${WORKDIR}"

EXT4_IMAGE="ubuntu-${UBUNTU_VERSION}.ext4"

truncate -s 1G "${EXT4_IMAGE}"
sudo mkfs.ext4 -d "${WORKDIR}" -F "${EXT4_IMAGE}" >/dev/null

echo "[+] Ext4 image created: ${EXT4_IMAGE}"

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------
echo "[✔] Setup complete"

if [[ -f "${KERNEL_FILE}" ]]; then
  echo "Kernel  : ${KERNEL_FILE}"
else
  echo "ERROR   : Kernel missing"
fi

if e2fsck -fn "${EXT4_IMAGE}" &>/dev/null; then
  echo "Rootfs  : ${EXT4_IMAGE}"
else
  echo "ERROR   : Invalid ext4 image"
fi

KEY_FILE="ubuntu-${UBUNTU_VERSION}.id_rsa"

if [[ -f "${KEY_FILE}" ]]; then
  echo "SSH Key : ${KEY_FILE}"
else
  echo "ERROR   : SSH key missing"
fi

echo "[✔] Ready to boot with Firecracker"
echo
echo "[*] You can connect to the VM using:"
echo "  ssh -i ${KEY_FILE} root@<vm-ip>"
echo
