## analysis/mood_power_comparison.R
## Сравнение «нашего» медианного теста (M̂ = mean(median1, median2)) против
## «истинного» медианного теста R (объединённая медиана median(c(x,y)) + Фишер)
## на NREP независимых выборках каждого сценария (разные seed, фиксированный
## воспроизводимый базис). Сводка — согласие решений <0.05 / >=0.05.
##
## Выход: analysis/tables/mood_power_comparison.xlsx
##   Лист "Согласие"   — сводная по сценарию (готова для вставки);
##   Лист "Все проходы" — длинный формат (scenario, rep, p_approx, p_exact, sig).
##
## Запуск: Rscript analysis/mood_power_comparison.R [NREP]

args <- commandArgs(trailingOnly = TRUE)
NREP <- if (length(args) >= 1) as.integer(args[1]) else 1000L
ALPHA <- 0.05
MASTER_SEED <- 20260905L

suppressMessages({
  if (!requireNamespace("openxlsx", quietly = TRUE)) stop("нужен пакет openxlsx")
})

this_dir <- dirname(normalizePath(sub("--file=", "", commandArgs(FALSE)[
  grepl("--file=", commandArgs(FALSE))][1])))
base <- dirname(this_dir)
source(file.path(base, "scripts", "scenarios_def.R"))
out_dir <- file.path(base, "analysis", "tables")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

mlabel <- c(
  n01 = "Нормальные, равные (30/25)",  n02 = "Нормальные, смещение среднего (8/8)",
  n03 = "Нормальные, неравные дисперсии (60/60)", n04 = "Нормальные, неравные n (200/30)",
  n05 = "Нормальные, n = 3/4",          n06 = "Логнормальные (40/40)",
  n07 = "Гамма, shape = 2 (40/40)",     n08 = "Экспоненциальные (50/50)",
  n09 = "Равномерные (35/35)",          n10 = "t₃, тяжёлый хвост (45/45)",
  n11 = "Бимодальная смесь (40/40)",    n12 = "Дискретные 1:5 (50/50)",
  n13 = "Крупные нормальные (1000/1000)", n14 = "Граница n = 11/12",
  n15 = "Константная группа (20/20)",   n16 = "t₂, n = 3/3",
  n17 = "Полунормальные (38/38)",       n18 = "Пуассоновские счёта (60/60)",
  n19 = "Равные средние, разные sd (25/25)", n20 = "Разность средних (32/32)"
)
ord <- names(mlabel)

## ---- ген-функция: выборка с фиксированным воспроизводимым seed -----------
gen_pair <- function(s, rep) {
  # база из номера сценария, чтобы разные сценарии не пересекались
  sid <- as.numeric(sub("n", "", s$id))
  set.seed((MASTER_SEED + sid * 1000003L + rep * 999983L) %% .Machine$integer.max)
  x <- s$fun(1, rep)
  set.seed((MASTER_SEED + sid * 1000003L + rep * 999983L + 1L) %% .Machine$integer.max)
  y <- s$fun(2, rep)
  list(x = x, y = y)
}

## ---- прогон одного сценария ----------------------------------------------
run_scenario <- function(s) {
  ok <- rep(NA, NREP)      # оба теста применимы
  sig_a <- rep(FALSE, NREP)
  sig_e <- rep(FALSE, NREP)
  p_a <- rep(NA_real_, NREP)
  p_e <- rep(NA_real_, NREP)
  bad <- 0L
  for (r in seq_len(NREP)) {
    xy <- gen_pair(s, r)
    x <- xy$x; y <- xy$y
    # константная группа -> Фишер может быть вырожден; пропускаем
    if (is.null(x) || is.null(y) || length(x) < 3 || length(y) < 3) { bad <- bad + 1L; next }
    if (diff(range(x)) == 0 || diff(range(y)) == 0) { bad <- bad + 1L; next }
    pa <- tryCatch(mood_approx(x, y)$p, error = function(e) NA_real_)
    pe <- tryCatch(mood_exact(x, y), error = function(e) NA_real_)
    if (is.na(pa) || is.na(pe)) { bad <- bad + 1L; next }
    ok[r] <- TRUE
    p_a[r] <- pa; p_e[r] <- pe
    sig_a[r] <- pa < ALPHA
    sig_e[r] <- pe < ALPHA
  }
  list(ok = ok, sig_a = sig_a, sig_e = sig_e, p_a = p_a, p_e = p_e, bad = bad, n_valid = sum(ok, na.rm = TRUE))
}

cat(sprintf("Сравнение наш/M̂ vs истинный медианный тест; NREP=%d, alpha=%.2f, master_seed=%d\n",
            NREP, ALPHA, MASTER_SEED))

res <- lapply(scen, function(s) {
  cat(sprintf("  %s ... ", s$id))
  R <- run_scenario(s)
  cat(sprintf("valid=%d/%d\n", R$n_valid, NREP))
  R
})
names(res) <- vapply(scen, `[[`, "", "id")

## ---- сводная по сценариям -------------------------------------------------
round1 <- function(x) round(x, 1)
sum_tab <- do.call(rbind, lapply(ord, function(id) {
  s <- scen[[match(id, vapply(scen, `[[`, "", "id"))]]
  R <- res[[id]]
  n <- R$n_valid
  ag <- mean(R$sig_a == R$sig_e, na.rm = TRUE)
  fp <- sum(R$sig_a & !R$sig_e, na.rm = TRUE)   # ложные положительные
  fn <- sum(!R$sig_a & R$sig_e, na.rm = TRUE)   # ложные отрицательные
  data.frame(
    "Сценарий" = id,
    "Описание" = unname(mlabel[id]),
    "N валидных" = n,
    "% значим (наш, M̂)" = round(100 * mean(R$sig_a, na.rm = TRUE), 1),
    "% значим (истинный)" = round(100 * mean(R$sig_e, na.rm = TRUE), 1),
    "сред. p (наш, M̂)" = mean(R$p_a, na.rm = TRUE),
    "сред. p (истинный)" = mean(R$p_e, na.rm = TRUE),
    "дельта mean(p)" = mean(R$p_e, na.rm = TRUE) - mean(R$p_a, na.rm = TRUE),
    "Согласие решений, %" = round1(100 * ag),
    "Совпало 100%" = if (ag == 1) "да" else "нет",
    "ЛП (наш да, истинный нет)" = fp,
    "ЛО (наш нет, истинный да)" = fn,
    check.names = FALSE, stringsAsFactors = FALSE
  )
}))

## ---- запись xlsx (только сводная) -----------------------------------------
sum_tab$"N валидных"[sum_tab$"N валидных" == 0] <- NA
that <- sum_tab$"N валидных"
for (cc in c("% значим (наш, M̂)", "% значим (истинный)", "сред. p (наш, M̂)",
             "сред. p (истинный)", "дельта mean(p)", "Согласие решений, %"))
  sum_tab[[cc]][is.na(that)] <- NA
sum_tab$"Совпало 100%"[is.na(that)] <- "—"
sum_tab$"ЛП (наш да, истинный нет)"[is.na(that)] <- NA
sum_tab$"ЛО (наш нет, истинный да)"[is.na(that)] <- NA

xlsx_file <- file.path(out_dir, "mood_power_comparison.xlsx")
wb <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb, "Согласие")
openxlsx::writeData(wb, sheet = "Согласие", x = sum_tab)
## числовой формат для p и согласия: 3 значащих
openxlsx::addStyle(wb, "Согласие", openxlsx::createStyle(numFmt = "0.000"), rows = 2:(nrow(sum_tab)+1),
                   cols = c(6, 7, 8), gridExpand = TRUE)
openxlsx::addStyle(wb, "Согласие", openxlsx::createStyle(numFmt = "0.0"), rows = 2:(nrow(sum_tab)+1),
                   cols = c(4, 5, 9), gridExpand = TRUE)
nms <- names(sum_tab)
openxlsx::setColWidths(wb, "Согласие", cols = seq_along(nms),
                       widths = c(9, 32, 9, 13, 13, 13, 13, 13, 13, 12, 18, 18))
openxlsx::saveWorkbook(wb, xlsx_file, overwrite = TRUE)

cat(sprintf("Записано: %s\n", xlsx_file))
cat(sprintf("Сценариев в сводной: %d\n", nrow(sum_tab)))