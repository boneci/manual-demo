#!/bin/bash
set -euxo pipefail

# --- Network (needed in minimal VMs) ---
printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /etc/resolv.conf

echo "=== CI START (cfxpool 32-bit build) ==="
echo "IP: $(hostname -I || true)"

export DEBIAN_FRONTEND=noninteractive

# --- Install dependencies ---
dpkg --add-architecture i386

apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=10

apt-get install -y \
    gcc-multilib \
    git \
    make \
    ca-certificates

# --- Clone your repository ---
git clone https://github.com/ankushT369/cfxpool.git /tmp/test
cd /tmp/test 

# --- Create build directory ---
mkdir -p build

# --- Compile object files (32-bit PIC) ---
gcc -m32 -fPIC -I. -c fxerror.c -o build/fxerror.o
gcc -m32 -fPIC -I. -c fxlog.c   -o build/fxlog.o
gcc -m32 -fPIC -I. -c fxpool.c  -o build/fxpool.o
gcc -m32 -fPIC -I. -c fxsys.c   -o build/fxsys.o

# --- Build libraries ---
gcc -m32 -shared -o build/libcfx.so \
    build/fxerror.o build/fxlog.o build/fxpool.o build/fxsys.o

ar rcs build/libcfx.a \
    build/fxerror.o build/fxlog.o build/fxpool.o build/fxsys.o

# --- Compile example program ---
gcc -m32 -I. example/main.c -o example/program -Lbuild -lcfx

# --- Run program ---
export LD_LIBRARY_PATH=build
./example/program

echo "=== CI DONE ==="

sync
sleep 1
poweroff
EOF

