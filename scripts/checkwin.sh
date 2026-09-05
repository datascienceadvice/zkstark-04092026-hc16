#!/bin/bash
for f in host design.txt sim_median_test.R todo.txt zkstark.Rproj README.md; do
  if [ -e /mnt/d/lair/zkstark/$f ]; then
    echo "WIN HAS: $f"
  else
    echo "WIN MISSING: $f"
  fi
done