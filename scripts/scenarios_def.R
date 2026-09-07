## scripts/scenarios_def.R — общие определения для сценариев и медианных тестов.
##
## Источник единой правды для:
##   - scen: список сценариев (id, name, alpha, fun(grp, seed));
##   - mood_approx: наш протокол (M̂=mean(median1,median2) + Фишер 2×2);
##   - mood_exact:  истинный медианный тест (объединённая медиана + Фишер 2×2).
##
## Подключается и golden.R, и analysis/mood_power_comparison.R, чтобы
## определения не расходились.

## ---- определение сценариев ----------------------------------------------
## Каждый сценарий: id, описание, alpha; данные генерируются функцией
## gen$fun(1L, seed) / gen$fun(2L, seed). seed игнорируется генераторами,
## которые полагаются на глобальный set.seed перед вызовом (стабильность).
## NULL-группа = ошибка (например константы: shapiro.test получает ошибку).
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
## объединённой медиане (m0 = median(c(x,y))) — недостижимо в zk-протоколе.
mood_exact <- function(x, y) {
  m0 <- median(c(x, y))
  a <- sum(x > m0)
  b <- sum(y > m0)
  nx <- length(x); ny <- length(y)
  tab <- matrix(c(a, nx - a, b, ny - b), nrow = 2, byrow = TRUE)
  tryCatch(fisher.test(tab, alternative = "two.sided")$p.value, error = function(e) NA)
}