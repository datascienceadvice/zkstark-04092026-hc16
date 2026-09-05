cat(R.version.string, "\n")
print(shapiro.test(c(1,2,3,4,5)))
print(shapiro.test(rnorm(50, 5, 3)))
print(shapiro.test(rlnorm(100, 0, 1)))
z <- 1.645
cat("qnorm(.95)=", qnorm(0.95), "\n")
cat("pnorm(1.645upper)=", pnorm(1.645, lower.tail=FALSE), "\n")