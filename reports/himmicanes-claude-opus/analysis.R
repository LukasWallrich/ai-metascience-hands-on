# Reproduction and robustness analysis of Jung et al. (2014), PNAS, archival study.
# Run from this folder: Rscript analysis.R
# Writes: reproduction.csv, robustness.csv, robustness_forest.png; prints every reported number.

suppressPackageStartupMessages({
  library(glmmTMB)   # negative binomial ML with observed-information SEs (matches the published SEs)
  library(MASS)      # glm.nb, for sandwich SEs
  library(sandwich)
  library(ggplot2)
})

d <- read.csv("hurricanes.csv")
# MinPressure_before is the pressure series that reproduces the published AIC/BIC.
# Unstandardized models use pressure centred at its mean (P) and damage in $bn (N = NDAM/1000);
# on the raw scales glmmTMB's Hessian is not positive definite. Fits, predictions and
# interaction tests are unchanged; raw-scale coefficients are converted back where reported.
Pbar_exact <- mean(d$MinPressure_before)
d$P <- d$MinPressure_before - Pbar_exact
d$PU <- d$Minpressure_Updated_2014 - mean(d$Minpressure_Updated_2014)
d$N <- d$NDAM / 1000
z <- function(x) (x - mean(x)) / sd(x)
d$zM <- z(d$MasFem); d$zP <- z(d$P); d$zN <- z(d$NDAM)
d$lowN <- as.numeric(d$NDAM <= median(d$NDAM))   # paper codes high damage = 0, low damage = 1

nb <- function(f, data = d) {
  m <- glmmTMB(f, family = nbinom2, data = data)
  if (!m$sdr$pdHess) stop("Non-positive-definite Hessian: ", deparse(f))
  m
}
# Pearson chi2/df with the dispersion parameter counted as a parameter (paper's convention)
pearson_df <- function(m) {
  sum(residuals(m, type = "pearson")^2) / (nobs(m) - length(fixef(m)$cond) - 1)
}
coefs <- function(m) summary(m)$coefficients$cond

cat("\n== Descriptives ==\n")
cat(sprintf("n = %d; mean deaths = %.3f; variance = %.3f; mean pressure = %.2f\n",
            nrow(d), mean(d$alldeaths), var(d$alldeaths), Pbar_exact))
cors <- c(deaths_NDAM = cor(d$alldeaths, d$NDAM), deaths_P = cor(d$alldeaths, d$P),
          deaths_Cat = cor(d$alldeaths, d$Category), NDAM_P = cor(d$NDAM, d$P),
          NDAM_Cat = cor(d$NDAM, d$Category), P_Cat = cor(d$P, d$Category))
print(round(cors, 3))

cat("\n== Models 1-4 (Table S2 series) ==\n")
m0 <- nb(alldeaths ~ 1)
m1 <- nb(alldeaths ~ P)
m2 <- nb(alldeaths ~ P + MasFem + N)
m3 <- nb(alldeaths ~ MasFem * P + MasFem * N)
m4 <- nb(alldeaths ~ zM * zP + zM * zN)
lr4 <- 2 * (as.numeric(logLik(m4)) - as.numeric(logLik(m0)))
cat(sprintf("Pearson chi2/df: M1 %.3f, M2 %.3f, M3 %.3f, M4 %.3f\n",
            pearson_df(m1), pearson_df(m2), pearson_df(m3), pearson_df(m4)))
cat(sprintf("LR chi2 (M4 vs intercept-only NB) = %.3f, p = %.2g\n", lr4,
            pchisq(lr4, 5, lower.tail = FALSE)))
cat(sprintf("M3 AIC = %.2f, BIC = %.2f; theta = %.3f\n", AIC(m3), BIC(m3), sigma(m3)))
# interaction rows on the paper's raw scale (per mb of pressure, per $m of damage)
raw_int <- function(m, g) {
  out <- coefs(m)[c(paste0(g, ":P"), paste0(g, ":N")), c(1, 2, 4)]
  out[2, 1:2] <- out[2, 1:2] / 1000
  rownames(out) <- c(paste0(g, " x pressure"), paste0(g, " x NDAM"))
  out
}
cat("Model 3 interactions (raw scale):\n"); print(signif(raw_int(m3, "MasFem"), 4))
cat("Model 4 (standardized):\n"); print(round(coefs(m4), 4))

cat("\n== Binary gender robustness check (model 3 with Gender_MF) ==\n")
mb <- nb(alldeaths ~ Gender_MF * P + Gender_MF * N)
print(signif(raw_int(mb, "Gender_MF"), 4))

cat("\n== Dichotomized-damage model (basis of Fig. 1 and 15.15 vs 41.84) ==\n")
md <- nb(alldeaths ~ P + lowN + MasFem + MasFem:P + MasFem:lowN)
bd <- fixef(md)$cond
# back to raw pressure: b0 and b(MFI) absorb the centring constant
bd["(Intercept)"] <- bd["(Intercept)"] - bd["P"] * Pbar_exact
bd["MasFem"] <- bd["MasFem"] - bd["P:MasFem"] * Pbar_exact
print(round(bd, 6))
Pbar <- round(Pbar_exact, 2)   # 964.90, as in the paper
pred_d <- function(mfi, low) {
  unname(exp(bd["(Intercept)"] + bd["P"] * Pbar + bd["lowN"] * low + bd["MasFem"] * mfi +
        bd["P:MasFem"] * mfi * Pbar + bd["lowN:MasFem"] * mfi * low))
}
preds <- c(high_MFI1 = pred_d(1, 0), high_MFI11 = pred_d(11, 0), low_MFI1 = pred_d(1, 1),
           low_MFI11 = pred_d(11, 1), high_MFI3 = pred_d(3, 0), high_MFI9 = pred_d(9, 0),
           Charley = pred_d(2.889, 0), Eloise = pred_d(8.944, 0))
print(round(preds, 2))

cat("\n== Checks behind the analysis decisions ==\n")
m3u <- nb(alldeaths ~ MasFem * PU + MasFem * N)
cat(sprintf("Model 3 with updated pressure: AIC = %.2f\n", AIC(m3u)))
cat(sprintf("Max |ZMinPressure_A - z(updated pressure)| = %.1e; vs z(pressure before) = %.2f\n",
            max(abs(d$ZMinPressure_A - z(d$Minpressure_Updated_2014))),
            max(abs(d$ZMinPressure_A - d$zP))))
cat(sprintf("Max |ZMasFem - zM| = %.1e; max |ZNDAM - zN| = %.1e\n",
            max(abs(d$ZMasFem - d$zM)), max(abs(d$ZNDAM - d$zN))))
m4_expinfo <- glm.nb(alldeaths ~ zM * zP + zM * zN, data = d)
cat(sprintf("Model 4 SE with MASS::glm.nb (expected information): MFI x pressure %.3f, MFI x NDAM %.3f\n",
            sqrt(diag(vcov(m4_expinfo)))["zM:zP"], sqrt(diag(vcov(m4_expinfo)))["zM:zN"]))
d$lowN_alt <- as.numeric(d$NDAM < median(d$NDAM))   # ties at the median coded high
md_alt <- nb(alldeaths ~ P + lowN_alt + MasFem + MasFem:P + MasFem:lowN_alt)
b_alt <- fixef(md_alt)$cond
cat(sprintf("Split with ties coded high (%d low): b0 = %.4f, b(MFI) = %.4f\n", sum(d$lowN_alt),
            b_alt["(Intercept)"] - b_alt["P"] * Pbar_exact,
            b_alt["MasFem"] - b_alt["P:MasFem"] * Pbar_exact))
cat(sprintf("Median split used: %d low, %d high\n", sum(d$lowN), sum(1 - d$lowN)))
cat(sprintf("Storms before 1979: %d; 1979 onward: %d\n", sum(d$Year < 1979), sum(d$Year >= 1979)))
cat(sprintf("r(NDAM, updated pressure) = %.3f\n", cor(d$NDAM, d$Minpressure_Updated_2014)))
sandy <- d$Name == "Sandy"
cat(sprintf("Sandy: observed deaths = %d; model 4 fitted deaths = %.0f\n",
            d$alldeaths[sandy], fitted(m4)[sandy]))

rep_tab <- data.frame(
  quantity = c("Mean deaths", "Variance of deaths", "Mean minimum pressure",
               "r(deaths, NDAM)", "r(deaths, pressure)", "r(deaths, category)",
               "r(NDAM, pressure)", "r(NDAM, category)", "r(pressure, category)",
               "M1 Pearson chi2/df", "M2 Pearson chi2/df", "M3 Pearson chi2/df",
               "M3 MFI x pressure b", "M3 MFI x pressure SE", "M3 MFI x pressure p",
               "M3 MFI x NDAM b", "M3 MFI x NDAM SE", "M3 MFI x NDAM p",
               "LR chi2", "M3 AIC", "M3 BIC",
               "M4 MFI x pressure b", "M4 MFI x pressure SE", "M4 MFI x pressure p",
               "M4 MFI x NDAM b", "M4 MFI x NDAM SE", "M4 MFI x NDAM p",
               "Binary: gender x pressure b", "Binary: gender x pressure p",
               "Binary: gender x NDAM b", "Binary: gender x NDAM p",
               "Split model b0", "Split model b1 (pressure)", "Split model b2 (low damage)",
               "Split model b3 (MFI)", "Split model b4 (MFI x pressure)",
               "Split model b5 (MFI x low damage)",
               "Pred. deaths high damage MFI 1", "Pred. deaths high damage MFI 11",
               "Pred. deaths low damage MFI 1", "Pred. deaths low damage MFI 11",
               "Pred. deaths MFI 3", "Pred. deaths MFI 9",
               "Pred. deaths Charley (MFI 2.889)", "Pred. deaths Eloise (MFI 8.944)"),
  estimate = c(mean(d$alldeaths), var(d$alldeaths), Pbar_exact, cors,
               pearson_df(m1), pearson_df(m2), pearson_df(m3),
               t(raw_int(m3, "MasFem")),
               lr4, AIC(m3), BIC(m3),
               coefs(m4)["zM:zP", c(1, 2, 4)], coefs(m4)["zM:zN", c(1, 2, 4)],
               t(raw_int(mb, "Gender_MF")[, c(1, 3)]),
               bd[c("(Intercept)", "P", "lowN", "MasFem", "P:MasFem", "lowN:MasFem")],
               preds)
)
write.csv(rep_tab, "reproduction.csv", row.names = FALSE)

# ---------------------------------------------------------------------------
# Robustness. Common estimand: ratio of expected deaths, MFI 9 vs MFI 3
# (female vs male for binary gender), at mean pressure and NDAM at its sample
# 90th percentile (high damage) or median (low damage). Profile values come from
# the full sample for every specification. 95% CI by delta method on the log scale.
# ---------------------------------------------------------------------------
N_hi <- unname(quantile(d$NDAM, 0.9)); N_md <- median(d$NDAM)
prof <- data.frame(P = 0, PU = 0, Elapsed_Yrs = mean(d$Elapsed_Yrs))   # pressures are centred

specs <- list(
  list(id = "B",   label = "Baseline: paper's model 4", rhs = ~ MasFem * P + MasFem * N),
  list(id = "A1",  label = "log(NDAM)", rhs = ~ MasFem * P + MasFem * log(N)),
  list(id = "A2",  label = "1979 onward only (n = 54)", rhs = ~ MasFem * P + MasFem * N,
       data = subset(d, Year >= 1979)),
  list(id = "A3",  label = "Drop Sandy (2012)", rhs = ~ MasFem * P + MasFem * N,
       data = subset(d, Name != "Sandy")),
  list(id = "A4",  label = "Binary gender", rhs = ~ Gender_MF * P + Gender_MF * N, binary = TRUE),
  list(id = "A5",  label = "Updated pressure",
       rhs = ~ MasFem * PU + MasFem * N),
  list(id = "A6",  label = "Add years elapsed", rhs = ~ MasFem * P + MasFem * N + Elapsed_Yrs),
  list(id = "A7",  label = "Main effects only", rhs = ~ MasFem + P + N),
  list(id = "A8",  label = "Only MFI x NDAM interaction", rhs = ~ MasFem * N + P),
  list(id = "A9",  label = "OLS on log(deaths + 1)", rhs = ~ MasFem * P + MasFem * N, engine = "ols"),
  list(id = "A10", label = "Sandwich (HC3) SEs", rhs = ~ MasFem * P + MasFem * N, engine = "hc3")
)

fit_spec <- function(s) {
  dat <- if (is.null(s$data)) d else s$data
  f <- update(s$rhs, alldeaths ~ .)
  engine <- if (is.null(s$engine)) "nb" else s$engine
  if (engine == "nb") {
    m <- nb(f, dat); b <- fixef(m)$cond; V <- vcov(m)$cond
  } else if (engine == "hc3") {
    m <- glm.nb(f, data = dat); b <- coef(m); V <- vcovHC(m, type = "HC3")
  } else {
    m <- lm(update(s$rhs, log(alldeaths + 1) ~ .), data = dat); b <- coef(m); V <- vcov(m)
  }
  gvar <- if (isTRUE(s$binary)) "Gender_MF" else "MasFem"
  lo_hi <- if (isTRUE(s$binary)) c(0, 1) else c(3, 9)
  contrast <- function(ndam) {
    nd <- prof[c(1, 1), ]; nd$N <- ndam / 1000; nd[[gvar]] <- lo_hi
    X <- model.matrix(s$rhs, nd)[, names(b)]
    L <- X[2, ] - X[1, ]
    est <- sum(L * b); se <- sqrt(drop(t(L) %*% V %*% L))
    c(ratio = exp(est), lo = exp(est - 1.96 * se), hi = exp(est + 1.96 * se),
      p = 2 * pnorm(-abs(est / se)))
  }
  hi <- contrast(N_hi); md <- contrast(N_md)
  iname <- intersect(paste0(gvar, c(":N", ":log(N)")), names(b))
  iz <- if (length(iname)) b[iname] / sqrt(V[iname, iname]) else NA
  data.frame(id = s$id, spec = s$label, n = nrow(dat),
             ratio_high = hi["ratio"], lo_high = hi["lo"], hi_high = hi["hi"], p_high = hi["p"],
             ratio_med = md["ratio"], lo_med = md["lo"], hi_med = md["hi"], p_med = md["p"],
             int_z = unname(iz), int_p = unname(2 * pnorm(-abs(iz))), row.names = NULL)
}

rob <- do.call(rbind, lapply(specs, fit_spec))
cat(sprintf("\n== Robustness (NDAM 90th pct = %.0f, median = %.0f) ==\n", N_hi, N_md))
print(format(rob, digits = 3), row.names = FALSE)
write.csv(rob, "robustness.csv", row.names = FALSE)

# Same estimand from the paper's dichotomized model, high-damage group (reference only)
cat(sprintf("\nSplit model, high-damage group, MFI 9 vs 3 at pressure %.2f: ratio = %.2f\n",
            Pbar, preds["high_MFI9"] / preds["high_MFI3"]))

# ---------------------------------------------------------------------------
# Figure: forest plot of the ratio at high and median damage
# ---------------------------------------------------------------------------
long <- rbind(
  data.frame(rob[, c("id", "spec")], damage = "High damage (NDAM 90th percentile)",
             ratio = rob$ratio_high, lo = rob$lo_high, hi = rob$hi_high),
  data.frame(rob[, c("id", "spec")], damage = "Median damage",
             ratio = rob$ratio_med, lo = rob$lo_med, hi = rob$hi_med)
)
long$label <- factor(paste0(long$id, "  ", long$spec), levels = rev(paste0(rob$id, "  ", rob$spec)))
long$baseline <- long$id == "B"

p <- ggplot(long, aes(x = ratio, y = label, colour = baseline)) +
  geom_vline(xintercept = 1, colour = "#8a8985", linewidth = 0.4) +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, linewidth = 0.7, orientation = "y") +
  geom_point(size = 2.6) +
  facet_wrap(~ damage) +
  scale_x_log10(breaks = c(0.25, 0.5, 1, 2, 4, 8, 16)) +
  scale_colour_manual(values = c(`TRUE` = "#eb6834", `FALSE` = "#2a78d6"), guide = "none") +
  labs(x = "Ratio of expected deaths, feminine (MFI 9) vs masculine (MFI 3) name\n(log scale; 95% CI; binary spec: female vs male)",
       y = NULL,
       title = "Name femininity effect on hurricane deaths across specifications",
       subtitle = "Pressure at its mean. Baseline (orange) = the paper's model 4. A ratio of 1 means no name effect.") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
        strip.text = element_text(face = "bold", hjust = 0),
        plot.title.position = "plot")
ggsave("robustness_forest.png", p, width = 10, height = 5.2, dpi = 150, bg = "white")
cat("\nWrote reproduction.csv, robustness.csv, robustness_forest.png\n")
