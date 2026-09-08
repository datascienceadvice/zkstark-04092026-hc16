## analysis/mood_weighted.R
## Сравнение вариантов оценки общей медианы M̂ для модифицированного теста
## Муда против «истинного» теста (объединённая медиана median(c(x,y)) + Фишер).
##
## Варианты M̂:
##   mean        — текущий: (med1 + med2) / 2                        (равные веса)
##   size        — веса по объёмам выборок: (n1·med1 + n2·med2)/N
##   size_iqr    — веса по объёмам и плотности (через IQR):
##                 (n1·d1·med1 + n2·d2·med2)/(n1·d1 + n2·d2), d_j = 0.5/IQR_j
##   size_sd     — веса по объёмам и разбросу (через квантильный sd):
##                 то же, но d_j ~ 1/(Q3_j − Q1_j) с медианной оценкой
##                 разброса (альтернативная плотность).
##
## Определение d_j: IQR = Q3−Q1 (квартили типа 7, как в R). Если IQR == 0
## (например дискретные данные), плотность зажимаем — вес становится
## пропорционален n_j, и оценка вырождается в size.
##
## Сравниваем по 1000 независимым выборкам каждого сценария:
##  1) близость M̂ к истинной объединённой медиане (ср. |M̂ − m0|);
##  2) согласие решения <0.05/>=0.05 с истинным тестом (доля, ЛП, ЛО).
##
## Запуск: Rscript analysis/mood_weighted.R [NREP]

args <- commandArgs(trailingOnly = TRUE)
NREP   <- if (length(args) >= 1) as.integer(args[1]) else 1000L
ALPHA  <- 0.05
MASTER_SEED <- 20260905L

suppressMessages({ if (!requireNamespace("openxlsx", quietly = TRUE))
  stop("нужен openxlsx, если нужен xlsx; для консоли достаточно базы") })

this_dir <- dirname(normalizePath(sub("--file=", "", commandArgs(FALSE)[
  grepl("--file=", commandArgs(FALSE))][1])))
base <- dirname(this_dir)
source(file.path(base, "scripts", "scenarios_def.R"))
out_dir <- file.path(base, "analysis", "tables")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

mlabel <- c(
  n01 = "Нормальные, равные (30/25)",  n02 = "Нормальные, смещение среднего (8/8)",
  n03 = "Нормальные, неравные дисперсии (60/60)", n04 = "Нормальные, неравные n (200/30)",
  n05 = "Нормальные, n = 3/4",           n06 = "Логнормальные (40/40)",
  n07 = "Гамма, shape = 2 (40/40)",      n08 = "Экспоненциальные (50/50)",
  n09 = "Равномерные (35/35)",           n10 = "t₃, тяжёлый хвост (45/45)",
  n11 = "Бимодальная смесь (40/40)",     n12 = "Дискретные 1:5 (50/50)",
  n13 = "Крупные нормальные (1000/1000)", n14 = "Граница n = 11/12",
  n15 = "Константная группа (20/20)",    n16 = "t₂, n = 3/3",
  n17 = "Полунормальные (38/38)",        n18 = "Пуассоновские счёта (60/60)",
  n19 = "Равные средние, разные sd (25/25)", n20 = "Разность средних (32/32)"
)
ord <- names(mlabel)

## плотность-вес через межквартильный размах
## (линейная аппроксимация CDF к 0.5: P(m) ≈ 0.5 + d·(m − med), d = 0.5/IQR)
iqr_weight <- function(x) {
  q <- quantile(x, c(0.25, 0.75), na.rm = TRUE)
  iqr <- q[2] - q[1]
  if (is.na(iqr) || iqr <= 0) 0 else 0.5 / iqr
}

## M̂ по выбранному варианту; x,y — выборки. Возвращает число >M̂ для 2×2.
mhat_variants <- function(x, y, variant) {
  med1 <- median(x); med2 <- median(y)
  n1 <- length(x); n2 <- length(y)
  m <- switch(variant,
    mean    = (med1 + med2) / 2,
    size    = (n1 * med1 + n2 * med2) / (n1 + n2),
    size_iqr = {
      d1 <- iqr_weight(x); d2 <- iqr_weight(y)
      if (d1 + d2 > 0) (n1 * d1 * med1 + n2 * d2 * med2) / (n1 * d1 + n2 * d2)
      else (n1 * med1 + n2 * med2) / (n1 + n2)
    },
    stop("unknown variant"))
  m
}

## точный двусторонний Фишер 2×2
fisher_p <- function(a, n1, b, n2) {
  tab <- matrix(c(a, n1 - a, b, n2 - b), nrow = 2, byrow = TRUE)
  tryCatch(fisher.test(tab, alternative = "two.sided")$p.value, error = function(e) NA)
}

set.seed(MASTER_SEED)
res <- lapply(ord, function(id) {
  sid <- as.numeric(sub("n", "", id))
  cat(sprintf("  %s ... ", id))
  r <- list()
  r$mhat <- list(); r$dev <- list(); r$sig <- list()
  n_valid <- 0L
  for (k in seq_len(NREP)) {
    ## разные (сценарий, проход) — новый seed; группы — независимые
    set.seed((MASTER_SEED + sid * 1000003L + k * 999983L) %% .Machine$integer.max)
    x <- scen[[match(id, vapply(scen, `[[`, "", "id"))]]$fun(1, k)
    set.seed((MASTER_SEED + sid * 1000003L + k * 999983L + 1L) %% .Machine$integer.max)
    y <- scen[[match(id, vapply(scen, `[[`, "", "id"))]]$fun(2, k)
    if (is.null(x) || is.null(y) || length(x) < 3 || length(y) < 3) next
    if (diff(range(x)) == 0 || diff(range(y)) == 0) next

    m0    <- median(c(x, y))
    p_exact <- fisher_p(sum(x > m0), length(x), sum(y > m0), length(y))
    if (is.na(p_exact)) next

    for (v in c("mean", "size", "size_iqr")) {
      m <- mhat_variants(x, y, v)
      a <- sum(x > m); b <- sum(y > m)
      pv <- fisher_p(a, length(x), b, length(y))
      r$mhat[[v]] <- c(r$mhat[[v]], m)
      r$dev[[v]] <- c(r$dev[[v]], abs(m - m0))
      r$sig[[v]] <- c(r$sig[[v]], pv < ALPHA)
    }
    r$sig_exact <- c(r$sig_exact, p_exact < ALPHA)
    n_valid <- n_valid + 1L
  }
  cat(sprintf("valid=%d\n", n_valid))
  r$n_valid <- n_valid
  r
})
names(res) <- ord

## ---- сводка ----------------------------------------------------------------
variants <- c("mean", "size", "size_iqr")
vname <- c(mean = "среднее равных весов (текущий)",
           size = "по объёмам выборок",
           size_iqr = "по объёмам × плотность (IQR)")

sum_tab <- do.call(rbind, lapply(variants, function(v) {
  dev <- unlist(lapply(res, function(r) r$dev[[v]]))
  sig_all <- unlist(lapply(res, function(r) r$sig[[v]]))
  sig_exact <- unlist(lapply(res, function(r) r$sig_exact))
  agree <- mean(sig_all == sig_exact, na.rm = TRUE)
  fp <- sum(sig_all & !sig_exact, na.rm = TRUE)
  fn <- sum(!sig_all & sig_exact, na.rm = TRUE)
  data.frame(
    "Вариант M̂" = vname[v],
    "Ср. |M̂−истинная медиана|" = signif(mean(unlist(lapply(res, function(r) r$dev[[v]])), na.rm = TRUE), 4),
    "Макс. ср. |M̂−m₀| по сценарию" = signif(max(vapply(res, function(r) mean(r$dev[[v]], na.rm = TRUE), numeric(1))), 4),
    "Согласие решений, %" = round(100 * agree, 2),
    "ЛП (наш да, истинный нет)" = fp,
    "ЛО (наш нет, истинный да)" = fn,
    check.names = FALSE, stringsAsFactors = FALSE
  )
}))

cat("\n=== СВОДКА (все сценарии, все проходы) ===\n")
print(sum_tab, row.names = FALSE)

## ---- по сценариям ----------------------------------------------------------
per_tab <- do.call(rbind, lapply(ord, function(id) {
  r <- res[[id]]
  n <- r$n_valid
  row <- data.frame("Сценарий" = id, "Описание" = unname(mlabel[id]),
                    "N" = n, check.names = FALSE, stringsAsFactors = FALSE)
  for (v in variants) {
    row[[paste0("согл.% (", v, ")")]] <- round(100 * mean(r$sig[[v]] == r$sig_exact, na.rm = TRUE), 1)
    row[[paste0("|M̂−m₀| (", v, ")")]] <- signif(mean(r$dev[[v]], na.rm = TRUE), 3)
  }
  row
}))

cat("\n=== ПО СЦЕНАРИЯМ: cогласие с истинным тестом, % ===\n")
print(per_tab[, c("Сценарий", "Описание", "N",
                  "согл.% (mean)", "согл.% (size)", "согл.% (size_iqr)")], row.names = FALSE)

cat("\n=== ПО СЦЕНАРИЯМ: среднее |M̂ − истинная объединённая медиана| ===\n")
print(per_tab[, c("Сценарий", "|M̂−m₀| (mean)", "|M̂−m₀| (size)", "|M̂−m₀| (size_iqr)")], row.names = FALSE)

## ---- итог ------------------------------------------------------------------
best <- which.max(sum_tab$"Согласие решений, %")
cat(sprintf("\nЛучший вариант по согласию: %s (%.2f%%)\n",
            sum_tab$"Вариант M̂"[best], sum_tab$"Согласие решений, %"[best]))
besti <- which.min(sum_tab$"Ср. |M̂−истинная медиана|")
cat(sprintf("Лучший вариант по близости к истинной медиане: %s\n",
            sum_tab$"Вариант M̂"[besti]))