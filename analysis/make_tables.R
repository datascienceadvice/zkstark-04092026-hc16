## analysis/make_tables.R
## Сводные таблицы для статьи из результатов bench (report_<run>.csv, golden.csv).
## Без внешних пакетов — только базовый R. Запуск: Rscript analysis/make_tables.R
##
## Выбирает автоматически: полный dev-прогон = самый свежий report с максимальным
## числом кейсов; full-подмножество = самый свежий report с меньшим числом кейсов.
## Лог дублируется в analysis/make_tables_out.txt в UTF-8 (исправляет прежнюю
## проблему с кодировкой при перенаправлении stdout).

options(digits = 12, scipen = 4)
## Репозиторий = родитель каталога скрипта (не зависит от рабочей директории)
this_dir <- dirname(normalizePath(if (exists("this_file")) this_file else
  sub("--file=", "", commandArgs(FALSE)[grepl("--file=", commandArgs(FALSE))][1])))
base <- dirname(this_dir)
res   <- file.path(base, "results")
out   <- file.path(base, "analysis", "tables")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

## ---- лог в UTF-8 -----------------------------------------------------------
logcon <- file(file.path(base, "analysis", "make_tables_out.txt"),
               open = "wt", encoding = "UTF-8")
on.exit(close(logcon))
log0 <- function(...) {
  txt <- paste0(..., collapse = "")
  cat(txt, "\n", sep = "")
  cat(txt, "\n", file = logcon, sep = "")
}

read.report <- function(run_id) {
  p <- file.path(res, sprintf("report_%d.csv", run_id))
  if (!file.exists(p)) return(NULL)
  d <- read.csv(p, stringsAsFactors = FALSE)
  d$run <- run_id
  d
}

golden <- read.csv(file.path(res, "golden.csv"), stringsAsFactors = FALSE)
meta   <- read.csv(file.path(res, "scenario_meta.csv"), stringsAsFactors = FALSE)

gwide <- reshape(golden[, c("case", "metric", "value")],
                 idvar = "case", timevar = "metric", direction = "wide")
names(gwide) <- sub("^value\\.", "", names(gwide))

files <- list.files(res, pattern = "^report_[0-9]+\\.csv$")
runs  <- sort(as.integer(sub(".*?report_([0-9]+)\\.csv$", "\\1", files)))
all   <- do.call(rbind, lapply(runs, read.report))

## ---- dev-матрица (полный набор, fake-рецепты) ------------------------------
ncase <- tapply(all$case, all$run, function(x) length(unique(x)))
mx <- max(ncase)
## самый свежий прогон с максимальным числом кейсов = dev-матрица
dev_run <- max(as.integer(names(ncase)[ncase == mx]))
r2 <- read.report(dev_run)
if (!is.null(r2)) {
  ship <- merge(r2, meta[, c("case", "name", "n1", "n2", "alpha")], by = "case")
  ship <- merge(ship, gwide[, c("case", "method", "mood.exact.p", "welch.p")],
                by = "case", all.x = TRUE)
  ship <- ship[order(ship$case), ]
  write.csv(ship, file.path(out, "table_dev_by_case.csv"), row.names = FALSE)

  log0(sprintf("DEV-матрица (run %d): сценариев %d, ok=%d, expected_error=%d, pass=%d",
              dev_run, nrow(r2), sum(r2$status=="ok"),
              sum(r2$status=="expected_error"), sum(r2$pass)))
  log0(sprintf("  max_rel_err по ok-кейсам: %.3e | протоколов: %s",
              max(r2$max_rel_err[r2$status=="ok"], na.rm=TRUE),
              paste(names(table(r2$method[r2$status=="ok"])),
                    table(r2$method[r2$status=="ok"]), collapse=", ")))
  log0(sprintf("  циклы total: %.0f | wall dev-суммарно: %.1f c",
              sum(r2$total_cycles), sum(r2$wall_ms)/1000))
}

## ---- full-подмножество (настоящие STARK) -----------------------------------
sub_runs <- setdiff(runs, dev_run)
## самый свежий прогон, отличный от dev-матрицы, — full-STARK подмножество
full_run <- if (length(sub_runs) == 0) NA else max(sub_runs)
fr <- if (is.na(full_run)) NULL else read.report(full_run)
if (!is.null(fr)) {
  log0(sprintf("\nFULL-подмножество (run %d): кейсов %d, все pass=%s",
               full_run, nrow(fr), all(fr$pass)))
  log0("  кейс | method | max_rel_err | wall(мс) | циклы | сегментов-сумма")
  for (k in seq_len(nrow(fr))) {
    log0(sprintf("  %-4s | %-6s | %.3e | %8d | %9.0f | %s",
                fr$case[k], fr$method[k], fr$max_rel_err[k], fr$wall_ms[k],
                fr$total_cycles[k], fr$segments[k]))
  }
  write.csv(fr, file.path(out, "table_full_by_case.csv"), row.names = FALSE)
  log0(sprintf("  средний wall на proof: %.1f c (6 proof/кейс)",
              mean(fr$wall_ms)/6/1000))
} else {
  log0("\nFULL-подмножество: не найдено (нет неполных прогонов)")
}

## ---- Mood: наша аппроксимация vs эталон по истинной медиане -----------------
mood <- subset(gwide, !is.na(mood.approx.p))
mood$mood.diff <- mood$mood.exact.p - mood$mood.approx.p
log0(sprintf("\nMood: max|exact - approx| = %s на %d сценариях",
             format(max(abs(mood$mood.diff), na.rm=TRUE), digits=3), nrow(mood)))
write.csv(mood[, c("case", "m_hat", "mood.approx.a", "mood.approx.b",
                   "mood.approx.p", "mood.exact.p", "mood.diff")],
          file.path(out, "table_mood_approx_vs_exact.csv"), row.names = FALSE)

log0(sprintf("\nТаблицы записаны в %s%s (лог: make_tables_out.txt, UTF-8)",
             out, .Platform$file.sep))