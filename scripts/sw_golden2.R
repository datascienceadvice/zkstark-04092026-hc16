options(digits = 17)
for (zz in c(-6, -5.7, -5.66, -5.65, -5.6, 5.6, 5.65, 5.66, 5.7, 6, -8.3, 8.3)) {
  low <- pnorm(zz, lower.tail = TRUE)
  up <- pnorm(zz, lower.tail = FALSE)
  cat(sprintf("x=%.17g low=%.17g up=%.17g\n", zz, low, up))
}