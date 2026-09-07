## analysis/paper_tables_xlsx.R
## Сводные (усреднённые) таблицы для статьи в формате xlsx — воспроизведение
## существующих md-таблиц (table_paper_dev/full/mood), но с усреднением
## числовых данных (по методу / по подмножеству) вместо построчных значений.
##
## Читает results/report_*.csv, golden.csv, scenario_meta.csv (тот же источник,
## что make_paper_tables.R) и пишет analysis/tables/paper_tables.xlsx:
##   лист "Dev-сводно"  — усреднение по методу (Уэлча / Муд / Все);
##   лист "Full-сводно" — одно сводное значение по full-прогону;
##   лист "Mood-сводно" — согласование M̂ и точной объединённой медианы.
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
ord <- names(mlabel)

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

golden <- read.csv(file.path(res, "golden.csv"), stringsAsFactors = FALSE)
gwide <- reshape(golden[, c("case", "metric", "value")],
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
ddev$desc <- unname(mlabel[ddev$case])
ddev$effect_p <- ifelse(ddev$method == "welch", ddev$welch_p, ddev$mood_p)

wb <- openxlsx::createWorkbook()
sty <- openxlsx::createStyle(textDecoration = "bold", halign = "center")
sty2 <- openxlsx::createStyle(numFmt = "0.00")

## ---- 1. Dev: усреднение по методу -----------------------------------------
dev_ok <- subset(ddev, status == "ok")
agg_dev <- do.call(rbind, lapply(c("welch", "mood", "all"), function(mm) {
  dd <- if (mm == "all") dev_ok else subset(dev_ok, method == mm)
  if (nrow(dd) == 0) return(NULL)
  data.frame(
    "Метод" = if (mm == "welch") "Уэлча" else if (mm == "mood") "Муд" else "Все",
    "Сценариев" = nrow(dd),
    "Значимых (p<0.05)" = sum(dd$effect_p < 0.05, na.rm = TRUE),
    "Средняя макс. отн. ошибка" = signif(mean(dd$max_rel_err, na.rm = TRUE), 3),
    "Среднее время, с" = round(mean(dd$wall_ms) / 1000, 2),
    "Всего циклов" = sum(dd$total_cycles),
    "Pass, %" = round(100 * mean(dd$pass), 1),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}))
openxlsx::addWorksheet(wb, "Dev-сводно")
openxlsx::writeData(wb, "Dev-сводно", agg_dev)
openxlsx::addStyle(wb, "Dev-сводно", sty, rows = 1, cols = 1:ncol(agg_dev), gridExpand = TRUE)
openxlsx::setColWidths(wb, "Dev-сводно", cols = 1:ncol(agg_dev), widths = c(8, 10, 12, 20, 13, 12, 9))
cat(sprintf("Dev-сводно: run %d, кейсов %d (ok %d, expect_err %d), pass %d/%d\n",
            dev_run, nrow(ddev), sum(ddev$status == "ok"),
            sum(ddev$status == "expected_error"), sum(ddev$pass), nrow(ddev)))

## ---- 2. Full: одно сводное значение ---------------------------------------
dfull <- if (is.na(full_run)) NULL else read.report(full_run)
if (!is.null(dfull) && nrow(dfull) > 0) {
  dfull_ok <- subset(dfull, status == "ok")
  full_row <- data.frame(
    "Кейсов" = nrow(dfull_ok),
    "Все pass" = ifelse(all(dfull_ok$pass), "да", "НЕТ"),
    "Средняя макс. отн. ошибка" = signif(mean(dfull_ok$max_rel_err, na.rm = TRUE), 3),
    "Среднее время, с" = round(mean(dfull_ok$wall_ms) / 1000, 0),
    "Всего циклов" = sum(dfull_ok$total_cycles),
    "Сегментов (см.)" = paste(unique(dfull_ok$segments), collapse = "/"),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  openxlsx::addWorksheet(wb, "Full-сводно")
  openxlsx::writeData(wb, "Full-сводно", full_row)
  openxlsx::addStyle(wb, "Full-сводно", sty, rows = 1, cols = 1:ncol(full_row), gridExpand = TRUE)
  openxlsx::setColWidths(wb, "Full-сводно", cols = 1:ncol(full_row), widths = c(8, 9, 20, 13, 12, 14))
  cat(sprintf("Full-сводно: run %d, кейсов %d, pass %s, ср.время %.0f с, циклов %d\n",
              full_run, nrow(dfull_ok), all(dfull_ok$pass),
              mean(dfull_ok$wall_ms)/1000, sum(dfull_ok$total_cycles)))
} else {
  cat("Full-сводно: не найдено full-прогона — лист пропущен\n")
}

## ---- 3. Mood: согласование M̂ против точной медианы ------------------------
mood <- subset(gwide, !is.na(mood.approx.p))
mood$diff <- mood$mood.exact.p - mood$mood.approx.p
alpha <- 0.05
sig_a <- sum(mood$mood.approx.p < alpha, na.rm = TRUE)
sig_e <- sum(mood$mood.exact.p < alpha, na.rm = TRUE)
agree <- mean((mood$mood.approx.p < alpha) == (mood$mood.exact.p < alpha), na.rm = TRUE)
fp <- sum(mood$mood.approx.p < alpha & !(mood$mood.exact.p < alpha), na.rm = TRUE)
fn <- sum(!(mood$mood.approx.p < alpha) & mood$mood.exact.p < alpha, na.rm = TRUE)
mood_row <- data.frame(
  "Сценариев" = nrow(mood),
  "Значимых по M̂" = sig_a,
  "Значимых по точной медиане" = sig_e,
  "ЛП (наш да, истинная нет)" = fp,
  "ЛО (наш нет, истинная да)" = fn,
  "Согласие решений, %" = round(100 * agree, 1),
  "Средняя |разность p|" = signif(mean(abs(mood$diff), na.rm = TRUE), 3),
  "Макс. |разность p|" = signif(max(abs(mood$diff), na.rm = TRUE), 3),
  "Совпало 100%" = ifelse(agree == 1, "да", "нет"),
  check.names = FALSE, stringsAsFactors = FALSE
)
openxlsx::addWorksheet(wb, "Mood-сводно")
openxlsx::writeData(wb, "Mood-сводно", mood_row)
openxlsx::addStyle(wb, "Mood-сводно", sty, rows = 1, cols = 1:ncol(mood_row), gridExpand = TRUE)
openxlsx::setColWidths(wb, "Mood-сводно", cols = 1:ncol(mood_row),
                       widths = c(9, 12, 18, 14, 14, 15, 15, 14, 12))
cat(sprintf("Mood-сводно: %d сценариев, значимых M̂=%d / точная=%d, ЛП=%d, ЛО=%d, согласие=%.1f%%\n",
            nrow(mood), sig_a, sig_e, fp, fn, 100 * agree))

## ---- запись ----------------------------------------------------------------
xlsx_file <- file.path(out, "paper_tables.xlsx")
openxlsx::saveWorkbook(wb, xlsx_file, overwrite = TRUE)
cat("Записано:", xlsx_file, "\n")