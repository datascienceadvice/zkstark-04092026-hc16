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

## ---- определение сценариев ----------------------------------------------
## Каждый сценарий: id, описание, alpha; данные генерируются функцией
## gen$fun(1L) / gen$fun(2L) с set.seed(id*1000 + grp). NULL-группа = ошибка
## (например константы: shapiro.test получает ошибку).
scen <- list(
  list(id = "n01", name = "normal_equal_small",       alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rnorm(30, 100, 15) else rnorm(25, 100, 15)),
  list(id = "n02", name = "normal_equal_tiny",        alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rnorm(8, 0, 1) else rnorm(8, 0.5, 1)),
  list(id = "n03", name = "normal_unequal_var",       alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rnorm(60, 50, 5) else rnorm(60, 52, 25)),
  list(id = "n04", name = "normal_unequal_n",         alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rnorm(200, 1, 1) else rnorm(30, 1.3, 1)),
  list(id = "n05", name = "normal_n3_n4",             alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rnorm(3, 0, 1) else rnorm(4, 1, 1)),
  list(id = "n06", name = "lognormal_shifted",        alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) exp(rnorm(40, 0.0, 0.5)) else exp(rnorm(40, 0.7, 0.5))),
  list(id = "n07", name = "gamma_shape2",             alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rgamma(40, 2, 1) else rgamma(40, 2, 1.6)),
  list(id = "n08", name = "exponential",              alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rexp(50, 0.5) else rexp(50, 0.3)),
  list(id = "n09", name = "uniform",                  alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) runif(35, 0, 1) else runif(35, 0.5, 1.5)),
  list(id = "n10", name = "t3_heavytail",             alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rt(45, 3) else rt(45, 3) + 1),
  list(id = "n11", name = "bimodal_mixture",          alpha = 0.05,
       fun = function(grp, seed) if (grp == 1)
         c(rnorm(20, -2, 0.7), rnorm(20, 3, 0.7)) else c(rnorm(20, -1, 0.7), rnorm(20, 4, 0.7))),
  list(id = "n12", name = "discrete_counts",          alpha = 0.05,
       fun = function(grp, seed) if (grp == 1)
         sample(1:5, 50, replace = TRUE) else sample(1:5, 50, replace = TRUE)),
  list(id = "n13", name = "large_normal_n1000",       alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rnorm(1000, 10, 2) else rnorm(1000, 10.5, 2)),
  list(id = "n14", name = "boundary_n11_n12",         alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rnorm(11, 0, 1) else rnorm(12, 1, 1)),
  list(id = "n15", name = "constant_group",           alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rep(5.0, 20) else rnorm(20, 5, 1)),
  list(id = "n16", name = "n3_exact_t",               alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rt(3, 2) else rt(3, 2) + 2),
  list(id = "n17", name = "halfnormal_skew",          alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) abs(rnorm(38, 0, 1)) else abs(rnorm(38, 1, 1))),
  list(id = "n18", name = "poisson_counts",           alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rpois(60, 4) else rpois(60, 6)),
  list(id = "n19", name = "normal_difflag",           alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rnorm(25, 0, 1) else rnorm(25, 0, 3)),
  list(id = "n20", name = "scale_diff_normal",        alpha = 0.05,
       fun = function(grp, seed) if (grp == 1) rnorm(32, 0, 1) else rnorm(32, 1, 1))
)

## ---- вспомогательные функции ---------------------------------------------
## Наш протокол: M̂=mean(median1,median2) и count(>M̂), затем точный Фишер 2×2.
mood_approx <- function(x, y) {
  m_hat <- unname(mean(c(median(x), median(y))))
  a <- sum(x > m_hat)
  b <- sum(y > m_hat)
  nx <- length(x); ny <- length(y)
  tab <- matrix(c(a, nx - a, b, ny - b), nrow = 2, byrow = TRUE)
  p <- fisher.test(tab, alternative = "two.sided")$p.value
  list(m_hat = m_hat, a = a, b = b, p = p)
}

## "Идеальный" медианный тест: та же статистика Фишера, но по ИСТИННОЙ
## объединённой медиане (m0 = median(c(x,y))) — недостижимо в zk-протоколе,
## полезно как отдельный референс при обсуждении точности согласования M̂.
mood_exact <- function(x, y) {
  m0 <- median(c(x, y))
  a <- sum(x > m0)
  b <- sum(y > m0)
  nx <- length(x); ny <- length(y)
  tab <- matrix(c(a, nx - a, b, ny - b), nrow = 2, byrow = TRUE)
  tryCatch(fisher.test(tab, alternative = "two.sided")$p.value, error = function(e) NA)
}

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