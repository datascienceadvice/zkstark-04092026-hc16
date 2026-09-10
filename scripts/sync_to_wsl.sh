#!/bin/bash
# Синхронизация исходников из Windows-копии в WSL-копию.
# Правки пишутся в Windows (инструменты), сборки идут в WSL (ext4).
# Пропускаем .git, target, results, scripts, todo.
set -e

# Задайте переменные окружения SRC и DST перед запуском, например:
#   export SRC=/mnt/c/path/to/zkstark
#   export DST=/home/user/zkstark
# или передайте через окружение при вызове.
SRC=${SRC:?Ошибка: переменная SRC не задана.}
DST=${DST:?Ошибка: переменная DST не задана.}

for d in core methods tests bench host; do
  if [ -d "$SRC/$d" ]; then
    mkdir -p "$DST/$d"
    rsync -a --delete "$SRC/$d"/ "$DST/$d"/
  fi
done
rsync -a "$SRC"/Cargo.toml "$SRC/.gitignore" "$DST"/ 2>/dev/null || true
echo "SYNCED $(date +%H:%M:%S)"