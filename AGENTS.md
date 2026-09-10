# AGENTS.md — руководство для агентов в этом репозитории

## Проект

zkstark — ZK-протокол сравнения двух независимых выборок на Risc Zero zkVM.
Конвейер «Уэлча t-тест или медианный тест Муда» с приватностью (лаборатории
публикуют только сводные статистики). Детали и математика — в `README.md`.

## Критично: среда сборки

- Исходник может быть на Windows и/или в Linux (WSL2/Ubuntu).
- **Нативный сбор в Windows невозможен**: гости Risc Zero требуют
  `riscv32im-risc0-zkvm-elf`, тулчейна `risc0` (rzup), которых нет на Windows.
  Все `cargo ...` команды запускать внутри WSL/Linux.
- После правок на Windows синхронизировать в WSL:
  ```bash
  export SRC=/mnt/c/path/to/zkstark   # путь к Windows-копии в WSL
  export DST=/home/user/zkstark        # путь к WSL-копии (будет создана)
  bash scripts/sync_to_wsl.sh
  ```
- Guest'ы пересобираются автоматически (methods/build.rs → ризк0_build
  embed_methods) при сборке crates `methods`/`host`/`bench`.

## Команды (выполнять в WSL, cwd — корень репозитория)

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

## Композиция доказательств (Фаза A, обязательно)

- Встроенная верификация: агрегатор оба раунда вызывает
  `env::verify(LAB_ID_DIGEST, &journal)` для журналов обеих лабораторий
  (`methods/guest/src/bin/aggregator.rs`). journal-байты лабораторий приходят
  агрегатору полями `lab1_journal`/`lab2_journal` в `AggInput::Stage1/Stage2`.
- Механика: раннер передаёт лабораторные receipts агрегатору через
  `ExecutorEnvBuilder::add_assumption` (`bench/src/runner.rs` `prove_with`),
  они подмешиваются в env для разрешения `env::verify` внутри гостя.
  Итоговый receipt агрегатора достоверен только если верны лабораторные
  receipts и их журналы совпадают с входом.
- `core::LAB_ID_DIGEST` держится синхронно с реальным метод-id гостя
  (`methods::LAB_ID` из `target/release/build/methods-*/out/methods.rs`).
  После любых правок гостевой программы он меняется — обновить вручную,
  иначе `env::verify` упадёт. image_id стабилен между пересборками при
  неизменном коде.
- R2-оптимизация: в раунде 2 при выборе Уэлча медиана и квартили группы не
  нужны (m_hat=None), поэтому `materialize(sample, need_median)` пропускает
  сортировку и кладёт `median=q1=q3=f64::NAN`.
- M̂ (квартильно-взвешенная): `stage1` агрегатора считает
  `mhat_quartile(n1, med1, q3-q1, n2, med2, q3-q1)` — веса n×IQR-плотность,
  при обеих IQR=0 веса сводятся к объёмам. Эталон и определение — в
  `scripts/scenarios_def.R::mood_approx` (квартили типа 7, как R quantile).

## Гостевой std (не no_std)

- Гости собираются на гостевом `std` risc0-zkvm
  (`default-features=false, features=["std"]`). Для f64-математики
  (`sqrt`, `powf`, …) у таргета `riscv32im-risc0-zkvm-elf` нет интринсиков
  в core — строгое `#![no_std]` для гостей без libm-замен невозможно.
  Математика самого `core` при этом остаётся no_std-совместимой.

## R (валидация, таблицы)

- R 4.3.1 (или совместимая версия).
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