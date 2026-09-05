#!/bin/bash
# Синхронизация исходников из Windows-копии (D:\lair\zkstark) в WSL-копию (~/zkstark).
# Правки пишутся в D:\ (инструменты), сборки идут в ~/zkstark (ext4).
# Пропускаем .git, target, results, scripts, todo.
set -e
SRC=/mnt/d/lair/zkstark
DST=/home/test/zkstark
for d in core methods tests bench; do
  if [ -d "$SRC/$d" ]; then
    mkdir -p "$DST/$d"
    rsync -a --delete "$SRC/$d"/ "$DST/$d"/
  fi
done
rsync -a "$SRC"/Cargo.toml "$SRC/Cargo.lock" "$SRC/.gitignore" "$DST"/ 2>/dev/null || true
echo "SYNCED $(date +%H:%M:%S)"