## sim_median_test.R
## Сравнение истинного медианного теста (Mood, RVAideMemoire) с "нашей"
## архитектурой (вариант B): счетчики относительно согласованной медианы,
## полученной ТОЛЬКО из квартильных сводных статистик.
##
## Сравниваемые тесты на таблице 2x2 (count_above/count_below относительно m0):
##   mood        - эталон: RVAideMemoire::mood.medtest (истинная медиана, chi2)
##   fisher/{m0} - наша схема: счетчики от m0 + точный тест Фишера
##   chisq/{m0}  - наша схема: счетчики от m0 + chi2 (Yates)
##
## m0 варианты:
##   m0_wmean - взвешенное по n среднее Q2 (простая робастная оценка)
##   m0_interp- интерполяция по объединенным квартильным узлам
##   m0_true  - истинная объединенная медиана (НЕдоступна в реальности;
##              добавлена только чтобы отделить погрешность согласования m0
##              от погрешности выбора статистики fisher vs chi2)
##
## p-value тестов не обязаны совпадать (разные гипотезы/статистики),
## поэтому сравниваем МОЩНОСТЬ и долю СОВПАВШИХ вердиктов при alpha.

suppressPackageStartupMessages({ library(RVAideMemoire) })
set.seed(2026)

## ------------------------------------------------------------ параметры
M  <- 150
alpha <- 0.05
nsets <- list("20x20" = c(20, 20),
              "15x40" = c(15, 40),
              "40x15" = c(40, 15))

## скошенные <- базовые генераторы (центрир. к ~0), плюс bimodal (смесь 2 normal)
dists <- list(
  lognormal = function(n, d) rlnorm(n, 0, 1) - exp(0.5) + d,
  gamma     = function(n, d) rgamma(n, 2, 1) - 2 + d,
  weibull   = function(n, d) rweibull(n, shape = 1.5, scale = 1) - gamma(1 + 1/1.5) + d,
  chisq     = function(n, d) rchisq(n, 3) - 3 + d,
  exp       = function(n, d) rexp(n, 1) - 1 + d,
  ## bimodal: 60%/40% смесь двух нормалей, центрир. к 0
  bimodal   = function(n, d) {
    u <- runif(n)
    x <- ifelse(u < 0.6, rnorm(n, -2, 0.6), rnorm(n, 2, 0.6))
    x - (-0.4 + 0.8) + d   # ~центрируем к 0
  }
)
deltas <- c(0, 0.5, 1.0, 2.0)

## ------------------------------------------------- оценка m0 из сводных
m0_wmean <- function(qA, qB, nA, nB) (qA[2] * nA + qB[2] * nB) / (nA + nB)

m0_interp <- function(qA, qB, nA, nB) {
  pts_x <- c(qA, qB)
  pA <- c(0.25, 0.5, 0.75) * nA
  pB <- c(0.25, 0.5, 0.75) * nB
  ord <- order(pts_x)
  f <- c(pA, pB)[ord] / (nA + nB)
  x <- pts_x[ord]
  if (0.5 <= min(f)) return(min(x))
  if (0.5 >= max(f)) return(max(x))
  approx(f, x, xout = 0.5, rule = 2)$y
}

## ------------------------------------------------------------- наш тест
ours_test <- function(X, Y, m0) {
  nA <- length(X); nB <- length(Y)
  cA <- sum(X > m0); cB <- sum(Y > m0)
  tab <- matrix(c(cA, nA - cA, cB, nB - cB), nrow = 2, byrow = TRUE)
  pf <- fisher.test(tab)$p.value
  pc <- suppressWarnings(chisq.test(tab, correct = TRUE)$p.value)
  list(p_fisher = pf, p_chisq = pc)
}

## ---------------------------------------------------------- одна реплика
run_one <- function(gen, delta, n1, n2) {
  X <- gen(n1, 0); Y <- gen(n2, delta)
  grp <- factor(rep(c("X", "Y"), c(n1, n2)))
  mr <- tryCatch(mood.medtest(c(X, Y) ~ grp), error = function(e) NA)
  pmood <- if (is.logical(mr) && length(mr) == 1L && is.na(mr)) NA else mr$p.value

  qA <- quantile(X, c(0.25, 0.5, 0.75))
  qB <- quantile(Y, c(0.25, 0.5, 0.75))

  m0w <- m0_wmean(qA, qB, n1, n2)
  m0i <- m0_interp(qA, qB, n1, n2)
  m0t <- median(c(X, Y))

  ow <- ours_test(X, Y, m0w)
  oi <- ours_test(X, Y, m0i)
  ot <- ours_test(X, Y, m0t)

  data.frame(p_mood = pmood,
             pf_w = ow$p_fisher, pf_i = oi$p_fisher, pf_t = ot$p_fisher,
             pc_w = ow$p_chisq,  pc_i = oi$p_chisq,  pc_t = ot$p_chisq,
             m0w = m0w, m0i = m0i, m0t = m0t)
}

## ------------------------------------------------------------- симуляция
res <- data.frame()
for (ns in names(nsets)) {
  n1 <- nsets[[ns]][1]; n2 <- nsets[[ns]][2]
  for (dn in names(dists)) {
    gen <- dists[[dn]]
    for (d in deltas) {
      print(glue::glue("ns: {ns}, dn: {dn}, d: {d}"))
      R <- matrix(NA, nrow = M, ncol = 7)
      colnames(R) <- c("p_mood","pf_w","pf_t","pc_w","pc_t","m0w","m0t")
      for (i in seq_len(M)) {
        r <- run_one(gen, d, n1, n2)
        R[i, ] <- unlist(r[c("p_mood","pf_w","pf_t","pc_w","pc_t","m0w","m0t")])
      }
      v <- !is.na(R[, "p_mood"])
      pow <- function(p) mean(p[v] < alpha)
      agree <- function(p) mean((R[v,"p_mood"]<alpha) == (p[v]<alpha))
      bias_w <- mean(R[v,"m0w"] - R[v,"m0t"])
      res <- rbind(res, data.frame(
        ns=ns, dist=dn, delta=d, n1=n1, n2=n2,
        power_mood = pow(R[,"p_mood"]),
        power_fw   = pow(R[,"pf_w"]), power_ft = pow(R[,"pf_t"]),
        power_cw   = pow(R[,"pc_w"]), power_ct = pow(R[,"pc_t"]),
        agree_fw   = agree(R[,"pf_w"]), agree_ft = agree(R[,"pf_t"]),
        agree_cw   = agree(R[,"pc_w"]), agree_ct = agree(R[,"pc_t"]),
        bias_w = bias_w))
    }
  }
}

## ------------------------------------------------------------- вывод
cat("=== Мощность (доля отбраковок при alpha=0.05) ===")
cat("\nns | dist | d | mood | f:w(fzt) | chi2:w(t)   [t=истинная m0]\n")
for (k in seq_len(nrow(res))) {
  r <- res[k,]
  cat(sprintf("%-5s | %-9s | d=%3.1f | %.3f | %.3f (%.3f) | %.3f (%.3f)\n",
      r$ns, r$dist, r$delta, r$power_mood,
      r$power_fw, r$power_ft, r$power_cw, r$power_ct))
}
cat("\n=== Совпадение вердиктов с эталонным mood.medtest ===\n")
cat("ns | dist | d | f:w(t) | chi2:w(t)\n")
for (k in seq_len(nrow(res))) {
  r <- res[k,]
  cat(sprintf("%-5s | %-9s | d=%3.1f | %.3f (%.3f) | %.3f (%.3f)\n",
      r$ns, r$dist, r$delta, r$agree_fw, r$agree_ft, r$agree_cw, r$agree_ct))
}
cat("\n=== Среднее смещение m0_w относительно истинной медианы ===")
cat("(w = взвешенное по n среднее квартильной медианы Q2)\n")
print(res[, c("ns","dist","delta","bias_w")], row.names = FALSE)

cat("\nВывод: разница (w vs t) = погрешность из-за неточного согласования m0;\n")
cat("разница (t vs mood) = чистая разница fisher/chisq при одной m0 (должна быть ~0).\n")
