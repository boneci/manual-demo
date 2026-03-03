## Runner

`runner/` contains the scripts responsible for launching, managing, and monitoring Firecracker microVMs used for CI execution.

### Contents

#### `ci.sh`

Main script that configures networking and boots a Firecracker microVM.

**Responsibilities:**

* Creates and configures a TAP device (`tap0`)
* Enables IP forwarding
* Sets up isolated iptables NAT + forwarding rules
* Configures the Firecracker VM via its Unix API socket
* Attaches kernel, root filesystem, and network interface
* Starts the VM instance
* Waits while the CI workload executes inside the VM
* Automatically cleans up networking on exit

**Key configuration:**

* VM IP: `172.16.0.10`
* Host IP: `172.16.0.1`
* Subnet: `172.16.0.0/24`
* vCPU: 1
* Memory: 512 MiB


#### `mon-fc-inst.sh`

Resource monitor for running Firecracker instances.

**What it does:**

* Periodically samples CPU and memory usage of all `firecracker` processes
* Logs metrics to a CSV file for later analysis or graphing
* Useful for benchmarking CI workloads

**Output format (CSV):**

```
timestamp,pid,cpu_percent,memory_mb
2026-03-02 12:00:01,12345,15.2,128.50
```



#### `stop_all_firecracker.sh`

Forcefully stops all running Firecracker microVMs and cleans leftovers.

**Actions performed:**

* Detects and kills all Firecracker processes
* Terminates launcher scripts (if running)
* Removes stale API sockets
* Verifies cleanup success

Useful when:

* CI runs get stuck
* Development testing leaves orphan VMs
* System resources need to be reclaimed quickly



#### `rootfs-config.sh`

Prepares the VM root filesystem with CI logic.

**Steps performed:**

1. Mounts the rootfs image
2. Injects an `/init.sh` startup script that runs inside the VM
3. Configures `rc.local` to execute the CI script on boot
4. Enables `rc-local.service`
5. Disables automatic apt background jobs (important for deterministic CI)
6. Unmounts the image


### Typical Workflow

1. Prepare root filesystem (one-time or when updated)

```bash
./rootfs-config.sh
```

2. Start monitoring (optional)

```bash
./mon-fc-inst.sh
```

3. Launch CI VM

```bash
./ci.sh
```

4. Stop all VMs if needed

```bash
./stop_all_firecracker.sh
```
