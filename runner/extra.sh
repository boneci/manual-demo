#!/bin/bash
set -e

# -------------------------
# CONFIG
# -------------------------
TAP_DEV="tap0"
SUBNET="172.16.0.0/24"
HOST_IP="172.16.0.1"
VM_IP="172.16.0.10"
FC_NAT_CHAIN="FC_NAT"
FC_FWD_CHAIN="FC_FWD"
FC_SOCK="/run/firecracker.socket"

WAN_IFACE=$(ip route | awk '/default/ {print $5}')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VM_DIR="$REPO_ROOT/utils/firecracker-vm"

KERNEL_IMG="$VM_DIR/vmlinux-6.1.155"
ORIG_ROOTFS_IMG="$VM_DIR/ubuntu-24.04.ext4"
ROOTFS_IMG="$VM_DIR/ubuntu-24.04-2gb.ext4"

NEW_ROOTFS_SIZE_MB=10240

# -------------------------
# CLEANUP EXISTING TAP DEVICE
# -------------------------
cleanup_existing() {
    echo "[-] Checking for existing TAP device..."
    
    # Check if tap0 exists
    if ip link show "$TAP_DEV" >/dev/null 2>&1; then
        echo "[-] Found existing $TAP_DEV, removing it..."
        sudo ip link del "$TAP_DEV" 2>/dev/null || true
    fi
    
    # Also check for other tap devices that might be conflicting
    for tap in $(ip link show | grep -o 'tap[0-9]\+'); do
        echo "[-] Found existing $tap, removing it..."
        sudo ip link del "$tap" 2>/dev/null || true
    done
}

# -------------------------
# CREATE LARGER ROOTFS IF NEEDED
# -------------------------
create_larger_rootfs() {
    if [ ! -f "$ORIG_ROOTFS_IMG" ]; then
        echo "[-] Original rootfs not found at $ORIG_ROOTFS_IMG"
        exit 1
    fi

    if [ ! -f "$ROOTFS_IMG" ]; then
        echo "[-] Creating larger rootfs (${NEW_ROOTFS_SIZE_MB}MB)..."
        
        dd if=/dev/zero of="$ROOTFS_IMG" bs=1M count="$NEW_ROOTFS_SIZE_MB" status=progress
        mkfs.ext4 -F "$ROOTFS_IMG"
        
        TEMP_MOUNT_OLD=$(mktemp -d)
        TEMP_MOUNT_NEW=$(mktemp -d)
        
        echo "[-] Copying contents from original rootfs..."
        
        sudo mount -o loop "$ORIG_ROOTFS_IMG" "$TEMP_MOUNT_OLD"
        sudo mount -o loop "$ROOTFS_IMG" "$TEMP_MOUNT_NEW"
        
        sudo cp -a "$TEMP_MOUNT_OLD"/* "$TEMP_MOUNT_NEW/"
        sudo mkdir -p "$TEMP_MOUNT_NEW"/{proc,sys,dev,run,tmp,var/cache/apt/archives}
        sudo chmod 755 "$TEMP_MOUNT_NEW"
        
        sudo umount "$TEMP_MOUNT_OLD"
        sudo umount "$TEMP_MOUNT_NEW"
        
        rmdir "$TEMP_MOUNT_OLD" "$TEMP_MOUNT_NEW"
        
        echo "[✔] Created larger rootfs at $ROOTFS_IMG"
    else
        echo "[-] Larger rootfs already exists at $ROOTFS_IMG"
    fi
}

# -------------------------
# CLEANUP FUNCTION
# -------------------------
cleanup() {
    echo "[-] Cleaning up network..."
    
    # Remove TAP device
    sudo ip link del "$TAP_DEV" 2>/dev/null || true
    
    # Clean iptables
    sudo iptables -t nat -D POSTROUTING -j "$FC_NAT_CHAIN" 2>/dev/null || true
    sudo iptables -D FORWARD -j "$FC_FWD_CHAIN" 2>/dev/null || true
    
    sudo iptables -t nat -F "$FC_NAT_CHAIN" 2>/dev/null || true
    sudo iptables -F "$FC_FWD_CHAIN" 2>/dev/null || true
    
    sudo iptables -t nat -X "$FC_NAT_CHAIN" 2>/dev/null || true
    sudo iptables -X "$FC_FWD_CHAIN" 2>/dev/null || true
    
    echo "[✔] Network cleanup done"
}

trap cleanup EXIT INT TERM ERR

# -------------------------
# CLEANUP EXISTING TAP DEVICES FIRST
# -------------------------
cleanup_existing

# -------------------------
# CREATE LARGER ROOTFS
# -------------------------
create_larger_rootfs

# -------------------------
# NETWORK SETUP
# -------------------------
echo "[-] Setting up TAP device..."

# Create TAP device
sudo ip tuntap add "$TAP_DEV" mode tap
sudo ip addr add "$HOST_IP/24" dev "$TAP_DEV"
sudo ip link set "$TAP_DEV" up

sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

# -------------------------
# IPTABLES
# -------------------------
echo "[-] Configuring iptables..."

sudo iptables -t nat -N "$FC_NAT_CHAIN" 2>/dev/null || true
sudo iptables -N "$FC_FWD_CHAIN" 2>/dev/null || true

sudo iptables -t nat -C POSTROUTING -j "$FC_NAT_CHAIN" 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -j "$FC_NAT_CHAIN"

sudo iptables -C FORWARD -j "$FC_FWD_CHAIN" 2>/dev/null || \
sudo iptables -A FORWARD -j "$FC_FWD_CHAIN"

sudo iptables -t nat -A "$FC_NAT_CHAIN" -s "$SUBNET" -o "$WAN_IFACE" -j MASQUERADE

sudo iptables -A "$FC_FWD_CHAIN" -i "$WAN_IFACE" -o "$TAP_DEV" \
    -m state --state RELATED,ESTABLISHED -j ACCEPT

sudo iptables -A "$FC_FWD_CHAIN" -i "$TAP_DEV" -o "$WAN_IFACE" -j ACCEPT

# -------------------------
# WAIT FOR FIRECRACKER SOCKET
# -------------------------
echo "[-] Waiting for Firecracker API socket at $FC_SOCK..."
echo "[-] Make sure Firecracker is running in another terminal with: sudo ./firecracker"
while [ ! -e "$FC_SOCK" ]; do
    sleep 2
    echo "[-] Still waiting for Firecracker to start... (socket not found)"
done
echo "[✔] Firecracker socket detected!"

# -------------------------
# SEND CURL REQUESTS TO CONFIGURE VM
# -------------------------
echo "[-] Sending configuration to Firecracker..."

# Configure machine
curl --unix-socket "$FC_SOCK" -X PUT http://localhost/machine-config \
    -H "Content-Type: application/json" \
    -d '{
        "vcpu_count": 1,
        "mem_size_mib": 512,
        "smt": false
    }'
echo " - Machine config done"

# Configure boot source
curl --unix-socket "$FC_SOCK" -X PUT http://localhost/boot-source \
    -H "Content-Type: application/json" \
    -d "{
        \"kernel_image_path\": \"${KERNEL_IMG}\",
        \"boot_args\": \"console=ttyS0 root=/dev/vda rw reboot=k panic=1 pci=off ip=${VM_IP}::${HOST_IP}:255.255.255.0::eth0:off\"
    }"
echo " - Boot source done"

# Configure rootfs drive
curl --unix-socket "$FC_SOCK" -X PUT http://localhost/drives/rootfs \
    -H "Content-Type: application/json" \
    -d "{
        \"drive_id\": \"rootfs\",
        \"path_on_host\": \"${ORIG_ROOTFS_IMG}\",
        \"is_root_device\": true,
        \"is_read_only\": false
    }"
echo " - Rootfs drive done"

# Configure network interface
curl --unix-socket "$FC_SOCK" -X PUT http://localhost/network-interfaces/eth0 \
    -H "Content-Type: application/json" \
    -d "{
        \"iface_id\": \"eth0\",
        \"host_dev_name\": \"${TAP_DEV}\",
        \"guest_mac\": \"AA:FC:00:00:00:01\"
    }"
echo " - Network interface done"

# Start the instance
curl --unix-socket "$FC_SOCK" -X PUT http://localhost/actions \
    -H "Content-Type: application/json" \
    -d '{"action_type":"InstanceStart"}'
echo " - Instance start command sent"

echo "[✔] VM configuration complete!"
echo "[-] VM should now be booting"
echo "[-] Press Ctrl+C to cleanup network when done"

# Keep script running to maintain trap
while true; do
    sleep 60
done
