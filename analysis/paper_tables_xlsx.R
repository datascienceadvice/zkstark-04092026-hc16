## analysis/paper_tables_xlsx.R
## Перенос таблиц для статьи из Markdown в xlsx без изменения данных:
## листы Dev / Full / Mood повторяют построчно содержимое
## table_paper_dev.md, table_paper_full.md, table_paper_mood.md.
## Источник тот же, что у make_paper_tables.R: results/report_*.csv,
## results/golden.csv, results/scenario_meta.csv.
## Запуск: Rscript analysis/paper_tables_xlsx.R [--dev <id> --full <id>]

options(digits = 6, scipen = 4, warn = 1)
suppressMessages({ if (!requireNamespace("openxlsx", quietly = TRUE))
  stop("нужен пакет openxlsx") })

this_dir <- dirname(normalizePath(sub("--file=", "", commandArgs(FALSE)[
  grepl("--file=", commandArgs(FALSE))][1])))
base <- dirname(this_dir)
res  <- file.path(base, "results")
out  <- file.path(base, "analysis", "tables")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

## ---- русские описания сценариев (идентично make_paper_tables.R) ------------
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
runs  <- sort(as.integer(sub(".*?report_([0-9]+)\\.csv$", "\\1", basename(files))))
all   <- do.call(rbind, lapply(runs, read.report))
meta  <- read.csv(file.path(res, "scenario_meta.csv"), stringsAsFactors = FALSE)

golden <- read.csv(file.path(res, "golden.csv"), stringsAsFactors = FALSE)
gwide  <- reshape(golden[, c("case", "metric", "value")],
                  idvar = "case", timevar = "metric", direction = "wide")
names(gwide) <- sub("^value\\.", "", names(gwide))

if (is.na(dev_override)) {
  ncase <- tapply(all$case, all$run, function(x) length(unique(x)))
  mx <- max(ncase)
  dev_run <- max(as.integer(names(ncase)[ncase == mx]))
} else dev_run <- dev_override
if (is.na(full_override)) {
  sub_runs <- setdiff(runs, dev_run)
  full_run <- if (length(sub_runs) == 0) NA else max(sub_runs)
} else full_run <- full_override

ddev <- read.report(dev_run)
dfull <- if (is.na(full_run)) NULL else read.report(full_run)

## ---- форматирование (идентично make_paper_tables.R) ------------------------
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

wb <- openxlsx::createWorkbook()

## ---- 1. Dev: ровно как table_paper_dev.md ----------------------------------
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
PEs <- ifelse(dev$method == "welch",
              sprintf("%s / %s", fmt_num(dev$welch_mean1), fmt_num(dev$welch_mean2)),
              ifelse(dev$method == "mood",
                     sprintf("m₁ %s / m₂ %s", fmt_num(dev$median1), fmt_num(dev$median2)),
                     "—"))
dev_t <- cbind(dev_t[, 1:7], data.frame("mean₁/mean₂ · med₁/med₂" = PEs,
                                        check.names = FALSE),
               dev_t[, 8:ncol(dev_t)])
openxlsx::addWorksheet(wb, "Dev")
openxlsx::writeData(wb, "Dev", dev_t)
openxlsx::setColWidths(wb, "Dev", cols = 1:12, widths = c(9, 32, 8, 12, 9, 9, 12, 16, 7, 10, 12, 24))
cat(sprintf("DEV лист: run %d, кейсов %d\n", dev_run, nrow(dev_t)))

## ---- 2. Full: ровно как table_paper_full.md --------------------------------
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
  openxlsx::addWorksheet(wb, "Full")
  openxlsx::writeData(wb, "Full", ful_t)
  openxlsx::setColWidths(wb, "Full", cols = 1:9, widths = c(9, 32, 8, 12, 16, 24, 10, 12, 12))
  cat(sprintf("FULL лист: run %d, кейсов %d\n", full_run, nrow(ful_t)))
} else {
  cat("FULL лист: не найдено неполных (full) runs — пропускаю\n")
}

## ---- 3. Mood: ровно как table_paper_mood.md --------------------------------
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
openxlsx::addWorksheet(wb, "Mood")
openxlsx::writeData(wb, "Mood", mood_t)
openxlsx::setColWidths(wb, "Mood", cols = 1:10, widths = c(9, 32, 10, 10, 10, 6, 6, 13, 16, 12))
cat(sprintf("MOOD лист: %d сценариев\n", nrow(mood_t)))

## ---- запись ----------------------------------------------------------------
xlsx_file <- file.path(out, "paper_tables.xlsx")
openxlsx::saveWorkbook(wb, xlsx_file, overwrite = TRUE)
cat("Записано:", xlsx_file, "\n")