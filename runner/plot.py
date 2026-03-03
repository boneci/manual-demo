import pandas as pd
import matplotlib.pyplot as plt

# Load CSV
df = pd.read_csv("firecracker_stats.csv")

# Convert timestamp to datetime
df["timestamp"] = pd.to_datetime(df["timestamp"])

# ---- CPU GRAPH ----
plt.figure()
for pid in df["pid"].unique():
    data = df[df["pid"] == pid]
    plt.plot(data["timestamp"], data["cpu_percent"], label=f"PID {pid}")

plt.title("Firecracker CPU Usage")
plt.xlabel("Time")
plt.ylabel("CPU (%)")
plt.legend()
plt.show()

# ---- MEMORY GRAPH ----
plt.figure()
for pid in df["pid"].unique():
    data = df[df["pid"] == pid]
    plt.plot(data["timestamp"], data["memory_mb"], label=f"PID {pid}")

plt.title("Firecracker Memory Usage")
plt.xlabel("Time")
plt.ylabel("Memory (MB)")
plt.legend()
plt.show()
