## analysis/mood_mc_validation.R
## Monte Carlo val: Mood* vs classical Mood median test.
## Usage: Rscript analysis/mood_mc_validation.R [NREP]

args <- commandArgs(trailingOnly = TRUE)
NREP <- if (length(args) >= 1L) as.integer(args[1]) else 50000L
MASTER_SEED <- 20260910L
ALPHA <- 0.05

suppressPackageStartupMessages({
  library(openxlsx)
  library(matrixStats)
})

## --- helpers ---
wilson_ci <- function(x, n) {
  if (n == 0L) return(c(lo = NA_real_, hi = NA_real_))
  z <- 1.96; p <- x/n; d <- 1+z^2/n
  c <- (p+z^2/(2*n))/d
  s <- z*sqrt((p*(1-p)+z^2/(4*n))/n)/d
  c(lo=max(0,c-s), hi=min(1,c+s))
}

precompute_fisher <- function(n1, n2) {
  m <- matrix(NA_real_, n1+1L, n2+1L)
  for (a in 0:n1) for (b in 0:n2) {
    k <- a+b
    if (k==0L||k==n1+n2) { m[a+1L,b+1L] <- 1; next }
    x <- max(0L,k-n2):min(n1,k)
    pr <- dhyper(as.double(x), n1, n2, k)
    m[a+1L, b+1L] <- sum(pr[pr <= dhyper(a, n1, n2, k) + 1e-300])
  }
  m
}

## --- distributions ---
distributions <- list(
  list(id="normal", name="Нормальное", sigma=1,
       gen=function(n) rnorm(n,0,1)),
  list(id="halfnorm", name="Полунормальное", sigma=sqrt(1-2/pi),
       gen=function(n) abs(rnorm(n,0,1))),
  list(id="lognorm", name="Логнормальное", sigma=NA,
       gen=function(n) exp(rnorm(n,0,0.7))),
  list(id="gamma", name="Гамма (shape=2)", sigma=sqrt(2),
       gen=function(n) rgamma(n,shape=2,rate=1)),
  list(id="exp", name="Экспоненциальное", sigma=1,
       gen=function(n) rexp(n,1)),
  list(id="poisson", name="Пуассоновское", sigma=2,
       gen=function(n) rpois(n,4)),
  list(id="uniform", name="Равномерное", sigma=1/sqrt(12),
       gen=function(n) runif(n,0,1)),
  list(id="t3", name="Тяжёлые хвосты (t3)", sigma=sqrt(3),
       gen=function(n) rt(n,df=3)),
  list(id="bimodal", name="Бимодальная смесь", sigma=NA,
       gen=function(n) { h<-n%/%2; c(rnorm(h,-2,0.7), rnorm(n-h,3,0.7)) }),
  list(id="discrete", name="Дискретное (1:5)", sigma=sqrt(2),
       gen=function(n) sample(1:5,n,replace=TRUE))
)

## compute empirical sigmas
set.seed(MASTER_SEED)
distributions[[3]]$sigma <- sd(distributions[[3]]$gen(200000))
distributions[[9]]$sigma <- sd(distributions[[9]]$gen(200000))

## shift function: additive location shift by d * sigma
make_shifted <- function(dist, d_val) {
  function(n) dist$gen(n) + d_val * dist$sigma
}

## --- sizes ---
sizes <- list(
  c(3,3), c(5,5), c(10,10), c(20,20), c(50,50), c(100,100),
  c(3,4), c(5,10), c(10,20), c(20,50)
)
size_labels <- vapply(sizes, function(s) paste0(s[1],"/",s[2]), "")

## --- effects ---
effects <- c(0.2, 0.5, 0.8)
effect_labels <- c("Малый (d=0.2)", "Средний (d=0.5)", "Большой (d=0.8)")

## --- precompute Fisher tables ---
cat("Предвычисление таблиц Фишера...\n")
ftabs <- list()
for (sk in unique(size_labels)) {
  ns <- as.integer(strsplit(sk,"/")[[1]])
  ftabs[[sk]] <- precompute_fisher(ns[1], ns[2])
}

## --- main computation ---
N <- length(distributions); S <- length(sizes); E <- length(effects)
cat(sprintf("NREP=%s, расп=%d, размеров=%d, эффектов=%d\n",
            format(NREP,big.mark=" "), N, S, E))

df_ti <- vector("list", N*S)
df_pow <- vector("list", N*S*E)
df_dis <- vector("list", N*S*(1+E))
idx_ti <- 0L; idx_pow <- 0L; idx_dis <- 0L

for (di in seq_len(N)) {
  D <- distributions[[di]]
  cat(sprintf("[%d/%d] %s\n", di, N, D$name))
  for (si in seq_len(S)) {
    sz <- sizes[[si]]; n1 <- sz[1]; n2 <- sz[2]
    sl <- size_labels[si]; ft <- ftabs[[sl]]

    set.seed(MASTER_SEED + di*1000003L + si*997L)
    X <- matrix(D$gen(n1*NREP), NREP, n1)
    Y_null <- matrix(D$gen(n2*NREP), NREP, n2)

    ## --- classical Mood: pooled median ---
    m0 <- rowMedians(cbind(X, Y_null))
    a_cm <- rowSums(X  > matrix(m0, NREP, n1))
    b_cm <- rowSums(Y_null > matrix(m0, NREP, n2))
    p_cm <- ft[cbind(a_cm+1L, b_cm+1L)]

    ## --- Mood*: weighted median M_hat ---
    med1 <- rowMedians(X); med2 <- rowMedians(Y_null)
    q1 <- rowQuantiles(X,  probs=c(0.25,0.75))
    q2 <- rowQuantiles(Y_null, probs=c(0.25,0.75))
    iqr1 <- q1[,2]-q1[,1]; iqr2 <- q2[,2]-q2[,1]
    d1 <- ifelse(iqr1>0, 0.5/iqr1, 0)
    d2 <- ifelse(iqr2>0, 0.5/iqr2, 0)
    w1 <- n1*d1; w2 <- n2*d2; tw <- w1+w2
    mh <- ifelse(tw>0, (w1*med1+w2*med2)/tw, (n1*med1+n2*med2)/(n1+n2))
    a_cs <- rowSums(X  > matrix(mh, NREP, n1))
    b_cs <- rowSums(Y_null > matrix(mh, NREP, n2))
    p_cs <- ft[cbind(a_cs+1L, b_cs+1L)]

    ## Type I error
    rej_cm <- p_cm < ALPHA; rej_cs <- p_cs < ALPHA
    ti_cm <- mean(rej_cm); ti_cs <- mean(rej_cs)
    ci_cm <- wilson_ci(sum(rej_cm), NREP)
    ci_cs <- wilson_ci(sum(rej_cs), NREP)
    dis_pct <- 100*mean(rej_cm != rej_cs)
    dp <- abs(p_cm - p_cs)

    ## near-alpha analysis
    near <- (abs(p_cm - ALPHA) < 0.01) | (abs(p_cs - ALPHA) < 0.01)
    n_near <- sum(near)
    dis_near <- if (n_near > 0) 100*mean(rej_cm[near] != rej_cs[near]) else NA_real_

    idx_ti <- idx_ti + 1L
    df_ti[[idx_ti]] <- data.frame(
      Distribution=D$name, n1_n2=sl, N_sim=NREP,
      TypeI_Mood=round(ti_cm,5), CI_lo_Mood=round(ci_cm[1],5),
      CI_hi_Mood=round(ci_cm[2],5),
      TypeI_MoodStar=round(ti_cs,5), CI_lo_MoodStar=round(ci_cs[1],5),
      CI_hi_MoodStar=round(ci_cs[2],5),
      Disagreement_pct=round(dis_pct,2),
      stringsAsFactors=FALSE, check.names=FALSE)

    idx_dis <- idx_dis + 1L
    df_dis[[idx_dis]] <- data.frame(
      Distribution=D$name, n1_n2=sl, Scenario="Null", Effect="—",
      mean_abs_dp=round(mean(dp),6), median_abs_dp=round(median(dp),6),
      max_abs_dp=round(max(dp),6), Disagreement_pct=round(dis_pct,2),
      N_near_alpha=n_near, Disag_near=if(!is.na(dis_near)) round(dis_near,2) else NA,
      stringsAsFactors=FALSE, check.names=FALSE)

    ## --- Power: shifted group 2 ---
    for (ei in seq_len(E)) {
      ed <- effects[ei]; el <- effect_labels[ei]
      set.seed(MASTER_SEED + di*1000003L + si*997L + ei*7919L)
      X2 <- matrix(D$gen(n1*NREP), NREP, n1)
      Y2 <- matrix(D$gen(n2*NREP) + ed*D$sigma, NREP, n2)

      m0p <- rowMedians(cbind(X2, Y2))
      a_pm <- rowSums(X2  > matrix(m0p, NREP, n1))
      b_pm <- rowSums(Y2  > matrix(m0p, NREP, n2))
      p_pm <- ft[cbind(a_pm+1L, b_pm+1L)]

      med1p <- rowMedians(X2); med2p <- rowMedians(Y2)
      q1p <- rowQuantiles(X2, probs=c(0.25,0.75))
      q2p <- rowQuantiles(Y2, probs=c(0.25,0.75))
      iqr1p <- q1p[,2]-q1p[,1]; iqr2p <- q2p[,2]-q2p[,1]
      d1p <- ifelse(iqr1p>0, 0.5/iqr1p, 0)
      d2p <- ifelse(iqr2p>0, 0.5/iqr2p, 0)
      w1p <- n1*d1p; w2p <- n2*d2p; twp <- w1p+w2p
      mhp <- ifelse(twp>0, (w1p*med1p+w2p*med2p)/twp,
                    (n1*med1p+n2*med2p)/(n1+n2))
      a_ps <- rowSums(X2  > matrix(mhp, NREP, n1))
      b_ps <- rowSums(Y2  > matrix(mhp, NREP, n2))
      p_ps <- ft[cbind(a_ps+1L, b_ps+1L)]

      rej_pm <- p_pm < ALPHA; rej_ps <- p_ps < ALPHA
      pw_cm <- mean(rej_pm); pw_cs <- mean(rej_ps)
      ci_pm <- wilson_ci(sum(rej_pm), NREP)
      ci_ps <- wilson_ci(sum(rej_ps), NREP)
      dp_p <- abs(p_pm - p_ps)
      dis_p <- 100*mean(rej_pm != rej_ps)
      near_p <- (abs(p_pm-ALPHA)<0.01)|(abs(p_ps-ALPHA)<0.01)
      n_near_p <- sum(near_p)
      dis_near_p <- if(n_near_p>0) 100*mean(rej_pm[near_p]!=rej_ps[near_p]) else NA

      idx_pow <- idx_pow + 1L
      df_pow[[idx_pow]] <- data.frame(
        Distribution=D$name, n1_n2=sl, Effect=el, N_sim=NREP,
        Power_Mood=round(pw_cm,5), CI_lo_Mood=round(ci_pm[1],5),
        CI_hi_Mood=round(ci_pm[2],5),
        Power_MoodStar=round(pw_cs,5), CI_lo_MoodStar=round(ci_ps[1],5),
        CI_hi_MoodStar=round(ci_ps[2],5),
        Disagreement_pct=round(dis_p,2),
        stringsAsFactors=FALSE, check.names=FALSE)

      idx_dis <- idx_dis + 1L
      df_dis[[idx_dis]] <- data.frame(
        Distribution=D$name, n1_n2=sl, Scenario="Alternative",
        Effect=el,
        mean_abs_dp=round(mean(dp_p),6), median_abs_dp=round(median(dp_p),6),
        max_abs_dp=round(max(dp_p),6), Disagreement_pct=round(dis_p,2),
        N_near_alpha=n_near_p,
        Disag_near=if(!is.na(dis_near_p)) round(dis_near_p,2) else NA,
        stringsAsFactors=FALSE, check.names=FALSE)
    }
  }
}

df_ti  <- do.call(rbind, df_ti)
df_pow <- do.call(rbind, df_pow)
df_dis <- do.call(rbind, df_dis)

## --- write xlsx ---
this_dir <- dirname(normalizePath(sub("--file=","",commandArgs(FALSE)[
  grepl("--file=",commandArgs(FALSE))][1])))
base <- dirname(this_dir)
xlsx_file <- file.path(base, "analysis", "tables", "paper_tables.xlsx")

wb <- loadWorkbook(xlsx_file)
for (s in c("MC Type I","MC Power","MC Disag")) {
  if (s %in% names(wb)) removeSheet(wb, s)
}

addWorksheet(wb, "MC Type I")
writeData(wb, "MC Type I", df_ti)
addStyle(wb, "MC Type I", createStyle(textDecoration="bold"), rows=1, cols=1:ncol(df_ti))

addWorksheet(wb, "MC Power")
writeData(wb, "MC Power", df_pow)
addStyle(wb, "MC Power", createStyle(textDecoration="bold"), rows=1, cols=1:ncol(df_pow))

addWorksheet(wb, "MC Disag")
writeData(wb, "MC Disag", df_dis)
addStyle(wb, "MC Disag", createStyle(textDecoration="bold"), rows=1, cols=1:ncol(df_dis))

saveWorkbook(wb, xlsx_file, overwrite=TRUE)
cat(sprintf("\nЗаписано: %s\n  Листы: MC Type I (%d строк), MC Power (%d строк), MC Disag (%d строк)\n",
            xlsx_file, nrow(df_ti), nrow(df_pow), nrow(df_dis)))

## --- interpretation (Section 10) ---
cat("\n=== ИНТЕРПРЕТАЦИЯ ===\n\n")
for (di in seq_len(N)) {
  D <- distributions[[di]]
  ti <- df_ti[df_ti$Distribution==D$name, ]
  pw <- df_pow[df_pow$Distribution==D$name, ]
  cat(sprintf("### %s\n", D$name))

  ## Type I error assessment
  all_ok <- all(ti$CI_lo_MoodStar <= ALPHA & ti$CI_hi_MoodStar >= ALPHA, na.rm=TRUE)
  any_bad <- any(ti$CI_hi_MoodStar < ALPHA | ti$CI_lo_MoodStar > ALPHA, na.rm=TRUE)
  if (all_ok) {
    cat("  Mood*: по всем 10 конфигурациям объёмов выборок 95% CI ошибки I рода\n")
    cat("  включает 0.05. Наблюдаемая ошибка I рода не продемонстрировала\n")
    cat("  статистически значимого отклонения от номинального уровня 0.05.\n")
  } else {
    bad <- ti[ti$CI_hi_MoodStar < ALPHA | ti$CI_lo_MoodStar > ALPHA, ]
    cat(sprintf("  Mood*: для конфигураций [%s] ошибка I рода выходит за 0.05.\n",
                paste(bad$n1_n2, collapse=", ")))
  }

  ## Power comparison
  for (ei in seq_len(E)) {
    pw_e <- pw[pw$Effect==effect_labels[ei], ]
    if (nrow(pw_e)==0) next
    pm <- mean(pw_e$Power_Mood, na.rm=TRUE)
    ps <- mean(pw_e$Power_MoodStar, na.rm=TRUE)
    cat(sprintf("  Мощность (%s): Mood %.1f%%, Mood* %.1f%%, дельта %+.1f%%\n",
                effect_labels[ei], 100*pm, 100*ps, 100*(ps-pm)))
  }
  cat("\n")
}

cat("=== Готово ===\n")
