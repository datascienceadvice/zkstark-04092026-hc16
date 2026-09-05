# AGENTS.md — руководство для агентов в этом репозитории

## Проект

zkstark — ZK-протокол сравнения двух независимых выборок на Risc Zero zkVM.
Конвейер «Уэлча t-тест или медианный тест Муда» с приватностью (лаборатории
публикуют только сводные статистики). Детали и математика — в `README.md`.

## Критично: среда сборки

- Исходник на Windows: `D:\lair\zkstark` (это cwd). Реальное ядро —
  WSL2/Ubuntu, `~/zkstark` (`wsl -e bash -lc "..."`).
- **Нативный сбор в Windows невозможен**: гости Risc Zero требуют
  `riscv32im-risc0-zkvm-elf`, тулчейна `risc0` (rzup), которых нет на Windows.
  Все `cargo ...` команды запускать внутри WSL.
- После правок на Windows синхронизировать в WSL:
  `wsl -e bash -lc "bash /mnt/d/lair/zkstark/scripts/sync_to_wsl.sh"`
- Guest'ы пересобираются автоматически (methods/build.rs → ризк0_build
  embed_methods) при сборке crates `methods`/`host`/`bench`.

## Команды (выполнять в WSL, cwd `~/zkstark`)

```bash
# тесты ядра и протокола
cargo test -p zkstark-core

# bench, dev-режим (fake-receipts, честный journal) — быстрый
cargo run -p bench --release --bin bench -- --mode dev            # вся матрица (~10 c)
cargo run -p bench --release --bin bench -- --mode dev --cases n01,n20

# bench, full-режим (настоящие STARK-proof) — МЕДЛЕННО
cargo run -p bench --release --bin bench -- --mode full --cases n16  # ~4 мин на n16

# экспорт результата в CSV
target/release/bench --export-run <run_id>    # результаты в results/report_<run_id>.csv
```

## Ограничения прогонов (знать обязательно)

- **full-режим**: ~40–70 c на одно доказательство. Большие сценарии (n13 =
  1000×1000, ~26M циклов) и медианные (n06, ~11 сегментов/proof) могут
  убить prover-сервер по памяти: ошибка `prove: rx len failed` — это падение
  r0vm-процесса (читается как «нехватка памяти», а не логика).
  Никогда не запускайте `--mode full` на всех кейсах сразу.
- dev-прогон на всю матрицу — безопасен и быстр.
- Авто-запуск тяжёлых задач в фоне через `nohup … &` внутри `wsl -e bash -lc`
  **не переживает** завершение сессии/таймаут команды. Либо делайте
  foreground с большим `timeout`, либо убедитесь, что WSL-сессия живёт.

## Конвенции кода

- Комментарии и пользовательские строки — по-русски, UTF-8 (cp1251 не использовать).
- Ядро/гости — без внешних стат-крейтов; вся математика в `core/src/*` своими
  реализациями (порты R: swilk, AS 66/AS 241, NR-неполная бета).
- Типы journal — serde derive; вход/выход гостей через `env::read`/`env::commit`
  (типы в `core/src/lib.rs`: LabInput/LabOutput, AggInput/AggOutput).
- Криптографическая корректность: никогда не доверять journal без
  `receipt.verify(method_id)`.

## R (валидация, таблицы)

- R: `D:\R\R-4.3.1\bin\Rscript.exe` (Windows).
- `scripts/golden.R` — генерация `results/golden.csv` (не менять сценарии
  без перегенерации golden и сверки с R).
- `analysis/make_tables.R` — таблицы статьи из `results/report_*.csv`.
- Скрипты R рассчитывают пути относительно своего каталога — запускать как
  есть, не полагаясь на cwd.

## Артефакты

- `results/zkstark.db` — SQLite (runs/case_runs/assertion_errors); коммитится,
  а `*.db-wal`/`*.db-shm` — в .gitignore.
- `results/report_<run>.csv`, `errors_<run>.csv`, `golden.csv`,
  `scenario_meta.csv`, `scenarios.csv` — фиксируемые артефакты.
- Коммитить можно/нужно, когда просит пользователь; самостоятельно не коммитить.