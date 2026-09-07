## golden.R — генератор набора сценариев и эталонных (golden) значений.
##
## Производит два CSV для bench-валидации zk-протокола:
##   results/scenarios.csv  — сырые данные (case, group, value) для входов гостей;
##   results/golden.csv     — длинный формат (case, metric, value):
##      median1, median2,              медианы групп (как median(x))
##      sw1.w, sw1.p, sw2.w, sw2.p,     shapiro.test обеих групп
##      welch.t, welch.df, welch.p,     t.test(x, y, var.equal=FALSE)
##      mood.exact.p,                  эталон: точный Фишер 2×2 по ИСТИННОЙ
##                                     объединённой медиане median(c(x,y))
##      m_hat, mood.approx.a, mood.approx.b, mood.approx.p   — наш протокол:
##         M̂=mean(median1,median2), count(>M̂) по группам, точный Фишер 2×2
##      method                        — выбор критерия при alpha: 1=welch, 2=mood
## Также: results/scenario_meta.csv — описания сценариев (для отчётности).
##
## NaN/NA ставятся когда метрика неприменима (напр. константная группа).
## Требуется базовый R (4.3.x). Запуск: Rscript golden.R

options(digits = 17)
options(scipen = 999)
set.seed(20260905)           # единый мастер-seed; последующие set.seed по сценариям

## Выходные файлы рядом со скриптом (.. = корень репозитория)
out_root <- file.path(dirname(normalizePath(if (exists("this_file")) this_file else
  sub("--file=", "", commandArgs(FALSE)[grepl("--file=", commandArgs(FALSE))][1]))), "..", "results")
dir.create(out_root, showWarnings = FALSE)

## ---- сценарии и медианные тесты (общий источник) -----------------------
source(file.path(dirname(normalizePath(
  sub("--file=", "", commandArgs(FALSE)[grepl("--file=", commandArgs(FALSE))][1]))),
  "scenarios_def.R"))

## ---- генерация данных + golden-значений -----------------------------------
out_scen <- data.frame(case = character(), group = integer(), value = numeric())
out_meta <- data.frame(case = character(), name = character(), alpha = numeric(),
                       n1 = integer(), n2 = integer())
out_gold <- data.frame(case = character(), metric = character(), value = numeric())

fmt <- function(v) {
  if (length(v) == 0 || is.null(v)) return(sprintf("%.17g", NA_real_))
  paste(sprintf("%.17g", v), collapse = "\n")
}

for (s in scen) {
  g1 <- tryCatch(s$fun(1, NULL), error = function(e) NULL)
  g2 <- tryCatch(s$fun(2, NULL), error = function(e) NULL)
  out_meta <- rbind(out_meta, data.frame(case = s$id, name = s$name,
                                         alpha = s$alpha,
                                         n1 = length(g1), n2 = length(g2)))
  if (!is.null(g1)) out_scen <- rbind(out_scen, data.frame(case = s$id, group = 1L, value = g1))
  if (!is.null(g2)) out_scen <- rbind(out_scen, data.frame(case = s$id, group = 2L, value = g2))

  add <- function(metric, value) {
    out_gold <<- rbind(out_gold, data.frame(case = s$id, metric = metric,
                                            value = as.numeric(value)))
  }

  ok1 <- !is.null(g1) && length(g1) >= 3 && diff(range(g1)) != 0
  ok2 <- !is.null(g2) && length(g2) >= 3 && diff(range(g2)) != 0

  sw1 <- if (ok1) tryCatch(shapiro.test(g1), error = function(e) NULL) else NULL
  sw2 <- if (ok2) tryCatch(shapiro.test(g2), error = function(e) NULL) else NULL

  add("median1", if (ok1) median(g1) else NA_real_)
  add("median2", if (ok2) median(g2) else NA_real_)
  add("sw1.w",   if (!is.null(sw1)) sw1$statistic else NA_real_)
  add("sw1.p",   if (!is.null(sw1)) sw1$p.value   else NA_real_)
  add("sw2.w",   if (!is.null(sw2)) sw2$statistic else NA_real_)
  add("sw2.p",   if (!is.null(sw2)) sw2$p.value   else NA_real_)

  if (ok1 && ok2) {
    tt <- t.test(g1, g2, var.equal = FALSE)
    add("welch.t", tt$statistic); add("welch.df", tt$parameter); add("welch.p", tt$p.value)
    mp <- mood_approx(g1, g2)
    add("m_hat", mp$m_hat); add("mood.approx.a", mp$a); add("mood.approx.b", mp$b)
    add("mood.approx.p", mp$p)
    add("mood.exact.p", mood_exact(g1, g2))
    both_normal <- !is.null(sw1) && !is.null(sw2) &&
      sw1$p.value > s$alpha && sw2$p.value > s$alpha
    add("method", if (both_normal) 1 else 2)   # 1=welch, 2=mood (нет в csv value? да, кодируем)
  } else {
    for (m in c("welch.t", "welch.df", "welch.p", "m_hat",
                "mood.approx.a", "mood.approx.b", "mood.approx.p",
                "mood.exact.p", "method"))
      add(m, NA_real_)
  }
}

write.csv(out_scen, file.path(out_root, "scenarios.csv"), row.names = FALSE)
write.csv(out_gold, file.path(out_root, "golden.csv"),   row.names = FALSE)
write.csv(out_meta, file.path(out_root, "scenario_meta.csv"), row.names = FALSE)
cat("scenarios.csv rows:", nrow(out_scen), "\n")
cat("golden.csv rows:", nrow(out_gold), "\n")
cat("cases:", nrow(out_meta), "\n")