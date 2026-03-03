
# Getting Started

This is a minimal setup for running a **Firecracker-based CI job**.

The project is organized into 5 main directories:

* `bin/`
* `rootfs/`
* `runner/`
* `utils/`
* `script/`



## `bin/`

Contains helper binaries and download utilities.

### `download.sh`

Downloads the latest Firecracker binary and places it in the correct location.

What it does:

* Fetches the Firecracker release
* Makes it executable
* Prepares it for local execution

This ensures you don’t manually track versions.



## `rootfs/`

This directory is responsible for preparing and configuring the root filesystem image used by the VM.

It includes:

* Mounting the `.ext4` image
* Injecting CI startup scripts
* Enabling boot-time execution (`rc.local`)
* Disabling unnecessary background services (like apt timers)
* Unmounting the image safely

The root filesystem defines what the VM will execute when it boots.


## `runner/`

This is the heart of the system. It controls VM lifecycle and CI execution.

It contains:

### `ci.sh`

Responsible for launching and configuring the Firecracker microVM.

It performs:

* TAP device creation
* NAT and forwarding setup via iptables
* VM configuration (CPU, memory)
* Kernel attachment
* Rootfs attachment
* Network interface setup
* Instance start via Firecracker API
* Automatic cleanup on exit

This is effectively your lightweight CI executor.



### `mon-fc-inst.sh`

Monitors running Firecracker processes.

It:

* Tracks CPU and memory usage
* Logs metrics into a CSV file
* Helps benchmark CI workloads
* Useful for performance comparisons (e.g., vs Docker or GitHub Actions)


### `stop_all_firecracker.sh`

Emergency cleanup script.

It:

* Kills all Firecracker processes
* Stops launcher scripts
* Removes leftover API sockets
* Verifies everything is fully stopped

Helpful when development runs get stuck.



## `utils/`

Contains supporting artifacts required by the VM.

Typically includes:

* Kernel image (`vmlinux`)
* Base Ubuntu rootfs image
* Pre-baked CI images
* Supporting build utilities

This directory holds static assets used by the runner.



## `script/`

Contains automation and helper scripts.

Examples:

* Rootfs preparation scripts
* Environment setup scripts
* Build automation helpers
* Cleanup scripts

This folder keeps the project modular and avoids mixing setup logic with runtime logic.


# Workflow (Step-by-Step Execution Order)

This is the exact order you should run things.

Think of it in 3 phases:

1. One-time setup
2. Rootfs preparation
3. CI execution



## Phase 1 — One-Time Setup

This only needs to be done once (or when updating Firecracker).

### Download Firecracker binary

```bash
cd bin/
./download.sh
```

What this does:

* Downloads the Firecracker binary
* Makes it executable
* Prepares your environment

After this step, Firecracker is ready to run.



## Phase 2 — Prepare the Root Filesystem

This step configures what the VM will execute when it boots.

### Configure the rootfs

```bash
./runner/rootfs-config.sh
```

What happens here:

* Mounts the Ubuntu `.ext4` image
* Injects `/init.sh` (your CI job logic)
* Configures `rc.local`
* Enables `rc-local.service`
* Disables background apt timers
* Unmounts the image

You only need to run this again if:

* You modify the CI job logic
* You change dependencies
* You rebuild the rootfs image


## Phase 3 — Run the CI VM

Now we actually launch the microVM.

### Start Firecracker (daemon)

In one terminal:

```bash
sudo ./firecracker
```

Leave this running.



###  Launch the CI job

In another terminal:

```bash
cd runner/
sudo ./ci.sh
```

What happens:

* TAP device is created
* Networking + NAT rules are set
* Kernel + rootfs are attached
* VM is started
* CI script runs inside VM
* VM shuts down after completion
* Networking cleanup runs automatically



## Optional — Monitor Resources

If you want to track performance:

In another terminal:

```bash
cd runner/
./mon-fc-inst.sh
```

This logs CPU and memory usage into:

```
firecracker_stats.csv
```

Useful for benchmarking.



## Emergency Cleanup (If Something Gets Stuck)

If a VM doesn’t shut down cleanly:

```bash
cd runner/
./stop_all_firecracker.sh
```

This will:

* Kill all Firecracker processes
* Remove leftover sockets
* Clean stuck launchers



# Full Execution Order (Quick Summary)

Here’s the minimal sequence:

```
1. bin/download.sh              (one-time)
2. rootfs/rootfs-config.sh      (when rootfs changes)
3. sudo ./firecracker
4. runner/ci.sh
```

Optional:
```
runner/mon-fc-inst.sh           (monitoring)
runner/stop_all_firecracker.sh  (cleanup)
```
