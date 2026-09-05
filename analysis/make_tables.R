## analysis/make_tables.R
## Сводные таблицы для статьи из результатов bench (report_<run>.csv, golden.csv).
## Без внешних пакетов — только базовый R. Запуск: Rscript analysis/make_tables.R

options(digits = 12, scipen = 4)
## Репозиторий = родитель каталога скрипта (не зависит от рабочей директории)
this_dir <- dirname(normalizePath(if (exists("this_file")) this_file else
  sub("--file=", "", commandArgs(FALSE)[grepl("--file=", commandArgs(FALSE))][1])))
base <- dirname(this_dir)
res   <- file.path(base, "results")
out   <- file.path(base, "analysis", "tables")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

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

## ---- dev-матрица (run 2: полный набор, fake-рецепты) ----------------------
r2 <- read.report(2)
if (!is.null(r2)) {
  ship <- merge(r2, meta[, c("case", "name", "n1", "n2", "alpha")], by = "case")
  ship <- merge(ship, gwide[, c("case", "method", "mood.exact.p", "welch.p")],
                by = "case", all.x = TRUE)
  ship <- ship[order(ship$case), ]
  write.csv(ship, file.path(out, "table_dev_by_case.csv"), row.names = FALSE)

  cat(sprintf("DEV-матрица (run %d): сценариев %d, ok=%d, expected_error=%d, pass=%d\n",
              unique(r2$run), nrow(r2), sum(r2$status=="ok"),
              sum(r2$status=="expected_error"), sum(r2$pass)))
  cat(sprintf("  max_rel_err по ok-кейсам: %.3e | протоколов: %s\n",
              max(r2$max_rel_err[r2$status=="ok"], na.rm=TRUE),
              paste(names(table(r2$method[r2$status=="ok"])), table(r2$method[r2$status=="ok"]),
                    collapse=", ")))
  cat(sprintf("  циклы total: %.0f | wall dev-суммарно: %.1f c\n",
              sum(r2$total_cycles), sum(r2$wall_ms)/1000))
}

## ---- full-подмножество (runs 3..5: настоящие STARK) -----------------------
fr <- do.call(rbind, lapply(3:5, read.report))
if (!is.null(fr)) {
  cat(sprintf("\nFULL-подмножество: прогонов %d, кейсов %d, все pass=%s\n",
              length(unique(fr$run)), nrow(fr), all(fr$pass)))
  cat("  кейс | method | max_rel_err | wall(мс) | циклы | сегментов-сумма\n")
  for (k in seq_len(nrow(fr))) {
    cat(sprintf("  %-4s | %-6s | %.3e | %8d | %9.0f | %s\n",
                fr$case[k], fr$method[k], fr$max_rel_err[k], fr$wall_ms[k],
                fr$total_cycles[k], fr$segments[k]))
  }
  write.csv(fr, file.path(out, "table_full_by_case.csv"), row.names = FALSE)
  # стоимость «одного доказательства» в среднем по полным прогонам
  cat(sprintf("  средний wall на proof: %.1f c (6 proof/кейс)\n",
              mean(fr$wall_ms)/6/1000))
}

## ---- Mood: наша аппроксимация vs эталон по истинной медиане -----------------
mood <- subset(gwide, !is.na(mood.approx.p))
  mood$mood.diff <- mood$mood.exact.p - mood$mood.approx.p
  cat("\nMood: max|exact - approx| =", format(max(abs(mood$mood.diff), na.rm=TRUE), digits=3),
      "на", nrow(mood), "сценариях\n")
  write.csv(mood[, c("case", "m_hat", "mood.approx.a", "mood.approx.b",
                     "mood.approx.p", "mood.exact.p", "mood.diff")],
            file.path(out, "table_mood_approx_vs_exact.csv"), row.names = FALSE)

cat("\nТаблицы записаны в", out, "\n")