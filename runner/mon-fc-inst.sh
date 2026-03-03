#!/bin/bash

INTERVAL=1
OUTFILE="firecracker_stats.csv"

echo "Logging to $OUTFILE"
echo "Press Ctrl+C to stop"

# Write header (only once)
if [ ! -f "$OUTFILE" ]; then
    echo "timestamp,pid,cpu_percent,memory_mb" > "$OUTFILE"
fi

while true; do
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    ps -C firecracker -o pid=,%cpu=,rss= | while read pid cpu rss; do
        rss_mb=$(awk "BEGIN {printf \"%.2f\", $rss/1024}")
        echo "$timestamp,$pid,$cpu,$rss_mb" >> "$OUTFILE"
    done

    sleep "$INTERVAL"
done
