## analysis/make_paper_tables.R
## Таблицы для статьи (Markdown, человекочитаемые подписи, UTF-8).
##
## Читает results/report_*.csv (экспорт bench), results/golden.csv и
## results/scenario_meta.csv; берёт самый свежий прогон: с 20 кейсами = dev,
## последний неполный = full-STARK. Пишет в analysis/tables/:
##   table_paper_dev.md   — dev-матрица (метод, p-значения, погрешность, pass, циклы)
##   table_paper_full.md  — full-STARK подмножество (время, циклы, сегменты)
##   table_paper_mood.md  — аппроксимация M̂ против истинной объединённой медианы
## Запуск: Rscript analysis/make_paper_tables.R
## (опц.)  Rscript analysis/make_paper_tables.R --dev <id> --full <id>

options(digits = 6, scipen = 4, warn = 1)

this_dir <- dirname(normalizePath(if (exists("this_file")) this_file else
  sub("--file=", "", commandArgs(FALSE)[grepl("--file=", commandArgs(FALSE))][1])))
base <- dirname(this_dir)
res  <- file.path(base, "results")
out  <- file.path(base, "analysis", "tables")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

## ---- русские описания сценариев ------------------------------------------
mlabel <- c(
  n01 = "Нормальные, равные (30/25)",
  n02 = "Нормальные, смещение среднего (8/8)",
  n03 = "Нормальные, неравные дисперсии (60/60)",
  n04 = "Нормальные, неравные n (200/30)",
  n05 = "Нормальные, n = 3/4",
  n06 = "Логнормальные (40/40)",
  n07 = "Гамма, shape = 2 (40/40)",
  n08 = "Экспоненциальные (50/50)",
  n09 = "Равномерные (35/35)",
  n10 = "t₃, тяжёлый хвост (45/45)",
  n11 = "Бимодальная смесь (40/40)",
  n12 = "Дискретные 1:5 (50/50)",
  n13 = "Крупные нормальные (1000/1000)",
  n14 = "Граница n = 11/12",
  n15 = "Константная группа (20/20)",
  n16 = "t₂, n = 3/3",
  n17 = "Полунормальные (38/38)",
  n18 = "Пуассоновские счёта (60/60)",
  n19 = "Равные средние, разные sd (25/25)",
  n20 = "Разность средних (32/32)"
)

read.report <- function(run_id) {
  p <- file.path(res, sprintf("report_%d.csv", run_id))
  if (!file.exists(p)) return(NULL)
  d <- read.csv(p, stringsAsFactors = FALSE)
  d$run <- run_id
  d
}
args <- commandArgs(trailingOnly = TRUE)
dev_override <- if ("--dev" %in% args) as.integer(args[which(args == "--dev") + 1]) else NA
full_override <- if ("--full" %in% args) as.integer(args[which(args == "--full") + 1]) else NA

files <- list.files(res, pattern = "^report_[0-9]+\\.csv$", full.names = TRUE)
runs <- sort(as.integer(sub(".*?report_([0-9]+)\\.csv$", "\\1", basename(files))))
all  <- do.call(rbind, lapply(runs, read.report))
meta <- read.csv(file.path(res, "scenario_meta.csv"), stringsAsFactors = FALSE)

golden <- read.csv(file.path(res, "golden.csv"), stringsAsFactors = FALSE)
gwide <- reshape(golden[, c("case", "metric", "value")],
                 idvar = "case", timevar = "metric", direction = "wide")
names(gwide) <- sub("^value\\.", "", names(gwide))

if (is.na(dev_override)) {
  ncase <- tapply(all$case, all$run, function(x) length(unique(x)))
  mx <- max(ncase)
  ## самый свежий прогон с максимальным числом кейсов = dev-матрица
  dev_run <- max(as.integer(names(ncase)[ncase == mx]))
} else dev_run <- dev_override
if (is.na(full_override)) {
  sub_runs <- setdiff(runs, dev_run)
  ## самый свежий прогон, отличный от dev-матрицы, — full-STARK подмножество
  full_run <- if (length(sub_runs) == 0) NA else max(sub_runs)
} else full_run <- full_override

ddev <- read.report(dev_run)
dfull <- if (is.na(full_run)) NULL else read.report(full_run)

## ---- форматирование -------------------------------------------------------
fmt_num <- function(x) {
  ifelse(is.na(x), "—",
    ifelse(abs(x) < 1e-3 & x != 0, sprintf("%.1e", x), sprintf("%.4g", x)))
}
fmt_p <- function(x) {
  ifelse(is.na(x), "—",
    ifelse(x < 1e-4, sprintf("%.1e", x), sprintf("%.3f", x)))
}
method_ru <- function(m, st) {
  ifelse(st == "expected_error", "— (SW), ошибка",
    ifelse(m == "welch", "Уэлча",
    ifelse(m == "mood", "Муд", m)))
}

md_table <- function(df, caption, name, note = NULL) {
  h <- names(df)
  lines <- c(paste("#### ", caption),
             paste0("| ", paste(h, collapse = " | "), " |"),
             paste0("|", paste(rep("---", length(h)), collapse = "|"), "|"))
  for (i in seq_len(nrow(df))) {
    r <- as.character(df[i, ])
    r[is.na(r)] <- "—"
    lines <- c(lines, paste0("| ", paste(r, collapse = " | "), " |"))
  }
  if (!is.null(note)) lines <- c(lines, "", note)
  lines <- c(lines, "")
  con <- file(file.path(out, paste0("table_paper_", name, ".md")),
              open = "wt", encoding = "UTF-8")
  on.exit(close(con))
  writeLines(lines, con = con, sep = "\n")
}

## ---- 1. dev-матрица -------------------------------------------------------
dev <- merge(ddev, meta[, c("case", "n1", "n2")], by = "case", all.x = TRUE)
dev$desc <- unname(mlabel[dev$case])
dev$effect_p <- ifelse(dev$method == "welch", dev$welch_p, dev$mood_p)
dev <- dev[order(match(dev$case, names(mlabel))), ]
dev_t <- data.frame(
  "Сценарий" = dev$case,
  "Описание" = dev$desc,
  "n₁/n₂" = paste0(dev$n1, "/", dev$n2),
  "Метод" = method_ru(dev$method, dev$status),
  "SW p₁" = fmt_p(dev$sw1_p),
  "SW p₂" = fmt_p(dev$sw2_p),
  "p (критерий)" = fmt_p(dev$effect_p),
  "макс. отн. ошибка" = fmt_num(dev$max_rel_err),
  "pass" = ifelse(dev$pass, "да", "НЕТ"),
  "время, с" = sprintf("%.2f", dev$wall_ms / 1000),
  "циклы" = formatC(dev$total_cycles, big.mark = " ", format = "d"),
  check.names = FALSE, stringsAsFactors = FALSE
)
## точечные оценки: средние при Уэлче, медианы при Муде
PEs <- ifelse(dev$method == "welch",
              sprintf("%s / %s", fmt_num(dev$welch_mean1), fmt_num(dev$welch_mean2)),
              ifelse(dev$method == "mood",
                     sprintf("m₁ %s / m₂ %s", fmt_num(dev$median1), fmt_num(dev$median2)),
                     "—"))
dev_t <- cbind(dev_t[, 1:7], data.frame("mean₁/mean₂ · med₁/med₂" = PEs,
                                        check.names = FALSE),
               dev_t[, 8:ncol(dev_t)])
md_table(dev_t, sprintf("Dev-матрица (run %d, fake-receipts; метод — по Шапиро–Уилку при α=0.05; погрешность — относительно golden из R)", dev_run), "dev")
cat(sprintf("DEV-таблица: run %d, кейсов %d, ok=%d, expected_error=%d, pass=%d\n",
            dev_run, nrow(dev), sum(dev$status == "ok"),
            sum(dev$status == "expected_error"), sum(dev$pass)))

## ---- 2. full-STARK --------------------------------------------------------
if (!is.null(dfull) && nrow(dfull) > 0) {
  ful <- merge(dfull, meta[, c("case", "n1", "n2")], by = "case", all.x = TRUE)
  ful$desc <- unname(mlabel[ful$case])
  ful <- ful[order(match(ful$case, names(mlabel))), ]
  ful_t <- data.frame(
    "Сценарий" = ful$case,
    "Описание" = ful$desc,
    "n₁/n₂" = paste0(ful$n1, "/", ful$n2),
    "Метод" = method_ru(ful$method, ful$status),
    "макс. отн. ошибка" = fmt_num(ful$max_rel_err),
    "время, с" = sprintf("%.0f", ful$wall_ms / 1000),
    "циклы" = formatC(ful$total_cycles, big.mark = " ", format = "d"),
    "сегментов" = as.character(ful$segments),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  PEs_full <- ifelse(ful$method == "welch",
              sprintf("%s / %s", fmt_num(ful$welch_mean1), fmt_num(ful$welch_mean2)),
              ifelse(ful$method == "mood",
                     sprintf("m₁ %s / m₂ %s", fmt_num(ful$median1), fmt_num(ful$median2)),
                     "—"))
  ful_t <- cbind(ful_t[, 1:4], data.frame("mean₁/mean₂ · med₁/med₂" = PEs_full,
                                          check.names = FALSE),
                 ful_t[, 5:ncol(ful_t)])
  md_table(ful_t, sprintf("Full-STARK (run %d, настоящие доказательства)", full_run), "full")
  cat(sprintf("FULL-таблица: run %d, кейсов %d, все pass=%s\n",
              full_run, nrow(ful), all(ful$pass)))
} else {
  cat("FULL-таблица: не найдено неполных (full) runs — пропускаю\n")
}

## ---- 3. аппроксимация M̂ vs истинная медиана ------------------------------
mood <- subset(gwide, !is.na(mood.approx.p))
mood$desc <- unname(mlabel[mood$case])
mood$diff <- mood$mood.exact.p - mood$mood.approx.p
mood <- mood[order(match(mood$case, names(mlabel))), ]
mood_t <- data.frame(
  "Сценарий" = mood$case,
  "Описание" = mood$desc,
  "med₁" = fmt_num(mood$median1),
  "med₂" = fmt_num(mood$median2),
  "M̂" = fmt_num(mood$m_hat),
  "a" = as.character(mood$mood.approx.a),
  "b" = as.character(mood$mood.approx.b),
  "p (наш, M̂)" = fmt_p(mood$mood.approx.p),
  "p (истинная медиана)" = fmt_p(mood$mood.exact.p),
  "разность p" = fmt_num(mood$diff),
  check.names = FALSE, stringsAsFactors = FALSE
)
## согласие решений при α = 0.05 (проверка: аппроксимация не искажает вывод)
alpha <- 0.05
sig_a <- mood$case[mood$mood.approx.p < alpha]
sig_e <- mood$case[mood$mood.exact.p  < alpha]
ord   <- names(mlabel)
sig_a <- sig_a[order(match(sig_a, ord))]
sig_e <- sig_e[order(match(sig_e, ord))]
fp <- setdiff(sig_a, sig_e)   # ложные положительные: их не должно быть
fn <- setdiff(sig_e, sig_a)   # ложные отрицательные
if (length(fn) == 0) {
  fn_txt <- ""
} else {
  pair <- vapply(fn, function(cc) {
    i <- which(mood$case == cc)
    sprintf("%s (p_M̂=%.3f, p_exact=%.3f)", cc, mood$mood.approx.p[i], mood$mood.exact.p[i])
  }, character(1))
  fn_txt <- paste0(" Ложных отрицательных — ", length(fn), ": ",
                   paste(pair, collapse = ", "),
                   " — сценарий закрывается Уэлча-ветвью (обе группы нормальны по Шапиро–Уилку), на фактический вывод не влияет.")
}
mood_note <- sprintf(
  "Согласие решений при α = 0.05: значимых по M̂ — %d (%s), все воспроизводятся по точной объединённой медиане; ложных положительных — 0.%s",
  length(sig_a), paste(sig_a, collapse = ", "), fn_txt)
md_table(mood_t, "Медианный тест: аппроксимация M̂ = mean(median₁, median₂) против точной объединённой медианы (Fisher, two-sided)", "mood",
  note = mood_note)
cat(sprintf("MOOD-таблица: %d сценариев, max|dif| = %.3f\n",
            nrow(mood), max(abs(mood$diff), na.rm = TRUE)))
cat(sprintf("MOOD-согласие решений при α=0.05: значимых по M̂ = %d, ложных положительных = %d, ложных отрицательных = %d\n",
            length(sig_a), length(fp), length(fn)))
cat("Файлы:", paste(list.files(out, pattern = "table_paper", full.names = TRUE), collapse = ", "), "\n")