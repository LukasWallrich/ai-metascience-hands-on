# Reproduction + robustness of Jung et al. (2014), PNAS. Run: Rscript analysis.R
suppressPackageStartupMessages({library(MASS); library(glmmTMB)})
d <- read.csv("hurricanes.csv")
z <- function(x) (x - mean(x)) / sd(x)
d$ZMinP_upd <- z(d$Minpressure_Updated_2014)  # ZMinPressure_A in the file is standardised from MinPressure_before
d$ZlogNDAM <- z(log(d$NDAM))

# Published Model 4: NB GLM, standardized MFI x pressure and MFI x damage
m4 <- glm.nb(alldeaths ~ ZMasFem * ZMinPressure_A + ZMasFem * ZNDAM, data = d)
cat("== Model 4 reproduction ==\n"); print(round(coef(summary(m4)), 3))

# Predicted deaths, MFI = 3 vs 9, pressure at mean; "severe" damage taken as +1 SD
pz <- function(mfi) (mfi - mean(d$MasFem)) / sd(d$MasFem)
nd <- data.frame(ZMasFem = pz(c(3, 9)), ZMinPressure_A = 0, ZNDAM = 1)
cat("\nPredicted deaths MFI 3 vs 9 (ZNDAM=+1):", round(predict(m4, nd, type = "response"), 2), "\n")

# Robustness: estimand = effect of +1 SD femininity (or female vs male) on log deaths
# at mean pressure; damage at +1 SD for interaction models (as in the paper) and main effect otherwise.
eff <- function(m, term, dmg = "ZNDAM") {
  b <- fixef(m)$cond; V <- vcov(m)$cond; L <- setNames(rep(0, length(b)), names(b)); L[term] <- 1
  ia <- paste0(term, ":", dmg); if (ia %in% names(b)) L[ia] <- 1
  est <- sum(L * b); se <- sqrt(drop(t(L) %*% V %*% L))
  c(est = est, lo = est - 1.96 * se, hi = est + 1.96 * se, p = 2 * pnorm(-abs(est / se)))
}
spec <- list(
  "0 Published Model 4"                 = list(f = alldeaths ~ ZMasFem * ZMinPressure_A + ZMasFem * ZNDAM, t = "ZMasFem"),
  "1 Main effects only"                 = list(f = alldeaths ~ ZMasFem + ZMinPressure_A + ZNDAM, t = "ZMasFem"),
  "2 Binary gender instead of MFI"      = list(f = alldeaths ~ Gender_MF * ZMinPressure_A + Gender_MF * ZNDAM, t = "Gender_MF"),
  "3 log(damage) instead of raw damage" = list(f = alldeaths ~ ZMasFem * ZMinPressure_A + ZMasFem * ZlogNDAM, t = "ZMasFem", dmg = "ZlogNDAM"),
  "4 Only 1979+ (male names in use)"    = list(f = alldeaths ~ ZMasFem * ZMinPressure_A + ZMasFem * ZNDAM, t = "ZMasFem", sub = d$Year >= 1979),
  "5 Updated 2014 pressure values"      = list(f = alldeaths ~ ZMasFem * ZMinP_upd + ZMasFem * ZNDAM, t = "ZMasFem"),
  "6 Control for year"                  = list(f = alldeaths ~ ZMasFem * ZMinPressure_A + ZMasFem * ZNDAM + Year, t = "ZMasFem"),
  "7 Drop 3 deadliest hurricanes"       = list(f = alldeaths ~ ZMasFem * ZMinPressure_A + ZMasFem * ZNDAM, t = "ZMasFem", sub = rank(-d$alldeaths, ties.method = "first") > 3),
  "8 Drop 3 most damaging hurricanes"   = list(f = alldeaths ~ ZMasFem * ZMinPressure_A + ZMasFem * ZNDAM, t = "ZMasFem", sub = rank(-d$NDAM, ties.method = "first") > 3),
  "9 log(damage), main effects only"    = list(f = alldeaths ~ ZMasFem + ZMinPressure_A + ZlogNDAM, t = "ZMasFem")
)
res <- do.call(rbind, lapply(names(spec), function(n) {
  s <- spec[[n]]; dd <- if (is.null(s$sub)) d else d[s$sub, ]
  # glmmTMB maximises the NB likelihood directly; glm.nb's IRLS fails to converge for spec 3
  m <- glmmTMB(s$f, data = dd, family = nbinom2)
  data.frame(spec = n, n = nrow(dd), t(eff(m, s$t, if (is.null(s$dmg)) "ZNDAM" else s$dmg)),
             theta = round(sigma(m), 2), converged = m$fit$convergence == 0)
}))
res[, 3:6] <- round(res[, 3:6], 3)
cat("\n== Robustness: effect of femininity on log deaths ==\n"); print(res, row.names = FALSE)
write.csv(res, "robustness.csv", row.names = FALSE)

png("robustness.png", width = 900, height = 520, res = 110)
par(mar = c(4, 17, 1, 1)); k <- nrow(res):1
plot(res$est, k, xlim = range(res$lo, res$hi), yaxt = "n", pch = 19, ylab = "",
     xlab = "Femininity effect on log(deaths) (95% CI)")
segments(res$lo, k, res$hi, k); abline(v = 0, lty = 2)
axis(2, at = k, labels = res$spec, las = 1, cex.axis = .8)
invisible(dev.off())
