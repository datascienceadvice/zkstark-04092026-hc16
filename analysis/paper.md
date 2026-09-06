# zkstark: ZK-протокол выбора между Уэлча t-тестом и медианным тестом Муда

Черновик статьи. Подробности структуры и запуска — в `README.md`; руководство
для агентов (включая механику композиции) — в `AGENTS.md`.

## Аннотация

We build a two-party zero-knowledge comparator for two independent samples on
the Risc Zero zkVM. The protocol automatically selects, based on the data, a
Welch t-test or Mood's median test with an exact Fisher two-sided p-value, so
laboratories publish only aggregate statistics and never raw observations.
Correctness of the whole comparison is a single, composable proof: on each of
the two protocol rounds the aggregator verifies both laboratory receipts
*inside the guest* via `env::verify`, so the final aggregator receipt is valid
only if all six laboratory proofs are valid and their journals match the input.

## Протокол (кратко)

Двухраундовая схема «лаборатория → агрегатор → лаборатория → агрегатор»,
6 доказательств на одно сравнение:

- **Раунд 1** — каждая лаборатория доказывает сводные статистики
  (n, sum, sum²), критерий Шапиро–Уилка (порт R `shapiro.test`,
  `swilk.c` + `shapiro.test.R`) и медиану группы. Агрегатор выбирает метод:
  обе группы нормальны → Уэлча t-тест; иначе → медианный тест Муда с
  M̂ = mean(median₁, median₂).
- **Раунд 2** — лаборатории повторно материализуют статистики и, только при
  Мood, считают `count_above(M̂)` по группам (a, b). Агрегатор формирует
  2×2-таблицу и вычисляет точный двусторонний р-уровень Фишера.
- **Композиция**: на обеих стадиях агрегатор проверяет лабораторные
  доказательства внутри гостя
  `env::verify(LAB_ID_DIGEST, &lab_journal)`; итоговый receipt верифицируется
  бенчмарком извне по method_id.

Весь численный слой реализован вручную в `core/src/*`, без внешних
стат-крейтов: спецфункции и распределения (Lanczos `ln_gamma`, неполная
бета NR, pnorm/qnorm по AS 66 / AS 241, swilk) — порты R и совпадают с
R 4.3.1 до ~1e-12.

## Приватность

Наружу (в journal) уходят только агрегаты:

- Уэлча-путь: (n, sum, sum²) каждой группы — эквивалент mean/sd.
- Mood-путь: дополнительно медианы групп, M̂ и `count_above(M̂)`. Суммарный
  ответ на порог M̂ — осознанный компромисс, необходимый для 2×2-таблицы.

## Композиция доказательств (техническая деталь)

Risc Zero: гостевой receipt’а лаборатории имеет контракт
`ReceiptClaim::ok(LAB_ID, journal)` (`pre: Pruned(image_id)`,
`post: {pc:0, merkle_root:0}`, `exit Halted(0)`, `input: None`, пустые
assumptions), поскольку вход гостя вводится через `env::read` без явного
`input_digest` (по умолчанию ZERO). Это делает лабораторные receipts
пригодными для `env::verify`. Раннер передаёт их агрегатору через
`ExecutorEnvBuilder::add_assumption`; агрегатор сверяет journal-байты
(`lab1_journal`/`lab2_journal` во входе) с теми, что подписаны доказательством.

`core::LAB_ID_DIGEST` держится синхронно с гостевой сборкой
(`methods::LAB_ID` из `target/release/build/methods-*/out/methods.rs`) —
image_id стабилен между пересборками, пока код гостя не менялся.

Гости собираются на **гостевом std** (`features=["std"]`): для таргета
`riscv32im-risc0-zkvm-elf` f64-математика (`sqrt`, `powf`, …) доступна только
в std, поэтому строгий `#![no_std]`-гость без libm-замен невозможен.
Математика `core` при этом остаётся no_std-совместимой.

## R2-оптимизация

При выборе Уэлча медиана группы в раунде 2 не нужна (метод не использует
M̂), поэтому гость пропускает сортировку медианы
(`materialize(sample, need_median)` при `need_median=false` кладёт
`median = f64::NAN`, у Уэлча `Stage1Decision.m_hat = None`).

## Результаты

- 20 фиксированных сценариев (`results/scenarios.csv`), golden из R 4.3.1
  (`results/golden.csv`), сверка каждого метрики journal в допуске (по
  умолчанию 1e-9); наблюдаемые погрешности ≤ ~2e-12.
- dev-матрица (`results/report_16.csv`): 20/20, 19 `ok` +
  1 `expected_error` (константная группа, намеренная SW-ошибка), все
  проверки `pass`, total ~86.6M циклов за ~9 c.
- full (настоящие STARK-proof, `results/report_17.csv`): n01, n02, n16 — все `pass`;
  композиция (`env::verify`) работает в боевом режиме (n01: 817 c,
  1.44M циклов). Медианный n06 в full упирается в память prover-сервера
  (`prove: rx len failed`, 11 сегментов) — не логика.

## Ограничения / открытые вопросы

- «Точный» медианный тест использует M̂ = mean(median₁, median₂), а не
  истинную объединённую медиану (аппроксимация 2×2-таблицы); сравнение
  `mood.approx.p` vs `mood.exact.p` — `analysis/tables/table_mood_approx_vs_exact.csv`.
  Погрешность зависит от сценария и не исчезает с ростом n: max |exact−approx|
  = 0.571 (n05, нормальные n=3/4), заметна и на умеренных n (n07 — гамма 40/40:
  0.562, n19: 0.429, n02: 0.305); исчезает лишь при малых p-значениях/больших
  эффектах (n06: ~7e-8, n18: ~6e-6).
- Производительность полного proof для крупных кейсов (n=1000, ~25M циклов)
  высока; в CI — dev-режим.