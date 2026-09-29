#!/usr/bin/env Rscript
# Reproduce and stress-test Jung et al. (2014), "Female hurricanes are deadlier
# than male hurricanes", PNAS 111(24):8782-8787, doi:10.1073/pnas.1402786111.
#
# Run from a clean start:  Rscript reproduce_hurricanes.R
# All numbers reported in report.md are produced by this script.

suppressPackageStartupMessages({
  library(MASS)
  library(pscl)
  library(ggplot2)
})

set.seed(1)
OUT <- "output"
dir.create(OUT, showWarnings = FALSE)

d <- read.csv("hurricanes.csv", stringsAsFactors = FALSE)
NDAM_HI <- as.numeric(quantile(d$NDAM, 0.90))  # "severe storm" reference damage
P_MEAN    <- mean(d$Minpressure_Updated_2014)

## ------------------------------------------------------------------ ##
## 0. Descriptives                                                     ##
## ------------------------------------------------------------------ ##
cat("== Descriptives ==\n")
cat(sprintf("n hurricanes               : %d\n", nrow(d)))
cat(sprintf("mean deaths                : %.3f\n", mean(d$alldeaths)))
cat(sprintf("variance deaths            : %.3f\n", var(d$alldeaths)))
cat(sprintf("mean min pressure (updated): %.2f\n", P_MEAN))
cat("correlations with alldeaths:\n")
for (v in c("NDAM", "Minpressure_Updated_2014", "Category", "MasFem", "Gender_MF")) {
  cat(sprintf("  %-26s r = % .3f\n", v, cor(d$alldeaths, d[[v]])))
}
cat("correlation NDAM vs pressure:",
    round(cor(d$NDAM, d$Minpressure_Updated_2014), 3), "\n")

## ------------------------------------------------------------------ ##
## 1. Main models (paper's models 3 and 4)                             ##
## ------------------------------------------------------------------ ##
m3 <- glm.nb(alldeaths ~ MasFem + Minpressure_Updated_2014 + NDAM +
               MasFem:Minpressure_Updated_2014 + MasFem:NDAM, data = d)
m4 <- glm.nb(alldeaths ~ ZMasFem + ZMinPressure_A + ZNDAM +
               ZMasFem:ZMinPressure_A + ZMasFem:ZNDAM, data = d)

pearson_ratio <- function(m) sum(residuals(m, type = "pearson")^2) / m$df.residual
cat("\n== Model 3 (raw, negative binomial) ==\n")
print(round(summary(m3)$coefficients, 6))
cat(sprintf("Pearson chi2/df = %.3f ; LR chi2 = %.2f\n",
            pearson_ratio(m3), m3$null.deviance - m3$deviance))
cat("\n== Model 4 (standardised, negative binomial) ==\n")
print(round(summary(m4)$coefficients, 4))
cat(sprintf("Pearson chi2/df = %.3f\n", pearson_ratio(m4)))

## ------------------------------------------------------------------ ##
## 2. Predicted deaths (paper's interaction-interpretation model)      ##
##    The paper factorises NDAM into "high" and "low" but never states
##    the split rule; we use a median split.                           ##
## ------------------------------------------------------------------ ##
d$Dcat <- as.numeric(d$NDAM > median(d$NDAM))   # 1 = high damage, 0 = low
mcat <- glm.nb(alldeaths ~ Minpressure_Updated_2014 + Dcat + MasFem +
                 MasFem:Minpressure_Updated_2014 + MasFem:Dcat, data = d)
cat("\n== Categorical-NDAM interpretation model (median split) ==\n")
print(round(coef(mcat), 6))

pred_cat <- function(mfi, high) {
  nd <- data.frame(Minpressure_Updated_2014 = P_MEAN, Dcat = as.numeric(high), MasFem = mfi)
  predict(mcat, newdata = nd, type = "response")
}
cat(sprintf("Predicted deaths, high-damage group:  MFI=1 %.2f | MFI=3 %.2f | MFI=9 %.2f | MFI=11 %.2f\n",
    pred_cat(1, TRUE), pred_cat(3, TRUE), pred_cat(9, TRUE), pred_cat(11, TRUE)))
cat(sprintf("Predicted deaths, low-damage group :  MFI=1 %.2f | MFI=3 %.2f | MFI=9 %.2f | MFI=11 %.2f\n",
    pred_cat(1, FALSE), pred_cat(3, FALSE), pred_cat(9, FALSE), pred_cat(11, FALSE)))
cat(sprintf("Headline ratio (high damage, MFI 9 vs MFI 3) = %.2f\n",
    pred_cat(9, TRUE) / pred_cat(3, TRUE)))

## Figure 1 reproduction: predicted deaths by MFI, continuous model,
## damage held at the 90th percentile (a strong storm) and at the median.
grid <- data.frame(MasFem = seq(1, 11, by = 0.1))
fig1 <- do.call(rbind, lapply(c(median(d$NDAM), NDAM_HI), function(ndv) {
  nd <- data.frame(MasFem = grid$MasFem,
                   Minpressure_Updated_2014 = P_MEAN, NDAM = ndv)
  data.frame(MFI = grid$MasFem,
             NDAM = ndv,
             deaths = predict(m3, newdata = nd, type = "response"))
}))
fig1$damage <- ifelse(fig1$NDAM == median(d$NDAM),
                      sprintf("median damage ($%.0f)", median(d$NDAM)),
                      sprintf("severe damage ($%.0f)", NDAM_HI))
p_fig <- ggplot(fig1, aes(MFI, deaths, colour = damage)) +
  geom_line(linewidth = 1) +
  labs(x = "Masculinity-femininity index (MFI; 1 = masculine, 11 = feminine)",
       y = "Predicted deaths", colour = NULL,
       title = "Predicted hurricane deaths by name femininity",
       subtitle = "Negative binomial model (paper's model 3), pressure held at its mean") +
  theme_minimal(base_size = 12)
ggsave(file.path(OUT, "figure1_predicted_deaths.png"), p_fig, width = 8, height = 5, dpi = 150)

## ------------------------------------------------------------------ ##
## 3. Robustness across defensible analyst choices                     ##
## ------------------------------------------------------------------ ##
# Unified target: ratio of predicted deaths for a feminine vs a masculine
# storm at severe (90th-percentile) damage and mean pressure.
#  - continuous-name models: MFI = 9 vs MFI = 3 (the paper's headline contrast)
#  - binary-name models    : female vs male
fem_ratio <- function(model, d, mfi_hi = 9, mfi_lo = 3, ndam = NDAM_HI,
                      gender = FALSE) {
  hi <- lo <- data.frame(Minpressure_Updated_2014 = P_MEAN,
                         NDAM = ndam, NDAM_c = ndam,
                         MinPressure_before = mean(d$MinPressure_before),
                         ZMasFem = 0, ZMinPressure_A = 0, ZNDAM = 0,
                         MasFem = mfi_hi, Gender_MF = as.numeric(gender),
                         Dcat = 1, Year = mean(d$Year))
  lo$MasFem <- mfi_lo
  lo$Gender_MF <- 0
  if (inherits(model, "zeroinfl")) {
    r <- as.numeric(predict(model, hi, type = "response") /
                    predict(model, lo, type = "response"))
    return(c(est = log(r), se = NA_real_, lo = NA_real_, hi = NA_real_))
  }
  tt <- terms(model)
  X  <- model.matrix(delete.response(tt), hi, xlev = model$xlevels)
  Xl <- model.matrix(delete.response(tt), lo, xlev = model$xlevels)
  dvec <- X[1, ] - Xl[1, ]
  V <- vcov(model)
  est <- sum(dvec * coef(model))
  se  <- sqrt(as.numeric(t(dvec) %*% V %*% dvec))
  c(est = est, se = se, lo = est - 1.96 * se, hi = est + 1.96 * se)
}

# term whose p-value we track (the femininity x damage interaction, or the
# femininity main effect when no interaction is fitted)
term_p <- function(model, pattern) {
  cf <- if (inherits(model, "zeroinfl")) summary(model)$coefficients$count
       else summary(model)$coefficients
  hit <- grep(pattern, rownames(cf), value = TRUE)
  if (length(hit) == 0) return(NA_real_)
  cf[hit[length(hit)], ncol(cf)]
}

specs <- list()

specs[["S0_paper"]] <- list(
  label = "S0  Paper replication (NB, MFI, both interactions)",
  data = d, form = alldeaths ~ MasFem + Minpressure_Updated_2014 + NDAM +
                              MasFem:Minpressure_Updated_2014 + MasFem:NDAM,
  fam = "nb", pat = "MasFem:NDAM")

specs[["S1_keep_outliers"]] <- list(
  label = "S1  Keep all 94 storms (retain Katrina & Audrey)",
  data = subset(read.csv("hurricanes.csv"), TRUE),   # re-read: full 94 not in file
  form = alldeaths ~ MasFem + Minpressure_Updated_2014 + NDAM +
           MasFem:Minpressure_Updated_2014 + MasFem:NDAM,
  fam = "nb", pat = "MasFem:NDAM", note = "CSV already excludes the 2 outliers; not runnable")

specs[["S2_post1979"]] <- list(
  label = "S2  Post-1979 only (alternating male/female naming)",
  data = subset(d, Year >= 1979),
  form = alldeaths ~ MasFem + Minpressure_Updated_2014 + NDAM +
           MasFem:Minpressure_Updated_2014 + MasFem:NDAM,
  fam = "nb", pat = "MasFem:NDAM")

specs[["S3_binary_gender"]] <- list(
  label = "S3  Binary Gender_MF instead of continuous MFI",
  data = d,
  form = alldeaths ~ Gender_MF + Minpressure_Updated_2014 + NDAM +
           Gender_MF:Minpressure_Updated_2014 + Gender_MF:NDAM,
  fam = "nb", pat = "Gender_MF:NDAM", gender = TRUE)

specs[["S4_orig_pressure"]] <- list(
  label = "S4  Original min pressure (MinPressure_before)",
  data = d,
  form = alldeaths ~ MasFem + MinPressure_before + NDAM +
           MasFem:MinPressure_before + MasFem:NDAM,
  fam = "nb", pat = "MasFem:NDAM")

specs[["S5_poisson"]] <- list(
  label = "S5  Poisson instead of negative binomial",
  data = d,
  form = alldeaths ~ MasFem + Minpressure_Updated_2014 + NDAM +
           MasFem:Minpressure_Updated_2014 + MasFem:NDAM,
  fam = "poisson", pat = "MasFem:NDAM")

specs[["S6_ols_log"]] <- list(
  label = "S6  OLS on log(deaths + 1)",
  data = transform(d, log_deaths = log(alldeaths + 1)),
  form = log_deaths ~ MasFem + Minpressure_Updated_2014 + NDAM +
           MasFem:Minpressure_Updated_2014 + MasFem:NDAM,
  fam = "ols", pat = "MasFem:NDAM")

specs[["S7_drop_mfi_pressure"]] <- list(
  label = "S7  Drop MFI x pressure interaction (keep MFI x damage)",
  data = d,
  form = alldeaths ~ MasFem + Minpressure_Updated_2014 + NDAM + MasFem:NDAM,
  fam = "nb", pat = "MasFem:NDAM")

specs[["S8_main_only"]] <- list(
  label = "S8  No interactions (main effects only)",
  data = d,
  form = alldeaths ~ MasFem + Minpressure_Updated_2014 + NDAM,
  fam = "nb", pat = "MasFem$")

specs[["S9_zeroinfl"]] <- list(
  label = "S9  Zero-inflated negative binomial",
  data = d,
  form = alldeaths ~ MasFem + Minpressure_Updated_2014 + NDAM +
           MasFem:Minpressure_Updated_2014 + MasFem:NDAM | 1,
  fam = "zeroinfl", pat = "MasFem:NDAM")

specs[["S10_catNDAM"]] <- list(
  label = "S10 Median-split NDAM (paper's interpretation model)",
  data = transform(d, Dcat = as.numeric(NDAM > median(NDAM))),
  form = alldeaths ~ MasFem + Minpressure_Updated_2014 + Dcat +
           MasFem:Minpressure_Updated_2014 + MasFem:Dcat,
  fam = "nb", pat = "MasFem:Dcat")

fit_spec <- function(s) {
  fam <- s$fam
  if (fam == "nb")      m <- suppressWarnings(glm.nb(s$form, data = s$data))
  else if (fam == "poisson") m <- glm(s$form, family = poisson, data = s$data)
  else if (fam == "ols")     m <- lm(s$form, data = s$data)
  else if (fam == "zeroinfl") m <- suppressWarnings(zeroinfl(s$form, data = s$data, dist = "negbin"))
  list(model = m, fam = fam)
}

rows <- list()
for (nm in names(specs)) {
  s <- specs[[nm]]
  if (!is.null(s$note)) {
    rows[[nm]] <- data.frame(spec = s$label, n = NA, est = NA, lo = NA, hi = NA,
                             p = NA, note = s$note)
    next
  }
  res <- tryCatch({
    fr <- fit_spec(s)
    m  <- fr$model
    r  <- fem_ratio(m, s$data, gender = isTRUE(s$gender))
    p  <- term_p(m, s$pat)
    data.frame(spec = s$label, n = nrow(s$data),
               est = unname(r["est"]), lo = unname(r["lo"]),
               hi = unname(r["hi"]), p = unname(p), note = "")
  }, error = function(e) {
    data.frame(spec = s$label, n = nrow(s$data), est = NA, lo = NA, hi = NA,
               p = NA, note = paste("failed:", conditionMessage(e)))
  })
  rows[[nm]] <- res
  cat(sprintf("%-58s n=%3d ratio=%.2f [%.2f, %.2f] p=%.3g %s\n",
              s$label, nrow(s$data), exp(res$est), exp(res$lo), exp(res$hi),
              res$p, res$note))
}

rob <- do.call(rbind, rows)
rob$ratio <- exp(rob$est)
rob$ratio_lo <- exp(rob$lo)
rob$ratio_hi <- exp(rob$hi)
write.csv(rob, file.path(OUT, "robustness_table.csv"), row.names = FALSE)

## Forest plot
pf <- subset(rob, !is.na(est))
pf$spec <- factor(pf$spec, levels = rev(pf$spec))
p_rob <- ggplot(pf, aes(x = ratio, y = spec)) +
  geom_vline(xintercept = 1, linetype = 2, colour = "grey50") +
  geom_pointrange(aes(xmin = ratio_lo, xmax = ratio_hi), colour = "#1f4e79",
                  na.rm = TRUE) +
  geom_point(data = subset(pf, is.na(ratio_lo)), colour = "#1f4e79", size = 2.6) +
  scale_x_log10() +
  labs(x = "Ratio of predicted deaths, feminine vs masculine name\n(severe storm, 90th-percentile damage; log scale)",
       y = NULL,
       title = "Robustness of the femininity effect on hurricane deaths",
       subtitle = "Point estimate = exp(femininity x damage contrast); bars = 95% CI (S9: point only)") +
  theme_minimal(base_size = 11)
ggsave(file.path(OUT, "robustness_forest.png"), p_rob, width = 9, height = 5, dpi = 150)

## ------------------------------------------------------------------ ##
## 4. Reproduction comparison table                                    ##
## ------------------------------------------------------------------ ##
b3 <- summary(m3)$coefficients
b4 <- summary(m4)$coefficients
comp <- data.frame(
  quantity = c(
    "n analysed",
    "mean deaths", "variance of deaths",
    "MFI x pressure, raw (beta)", "MFI x pressure, raw (SE)", "MFI x pressure, raw (p)",
    "MFI x damage, raw (beta)", "MFI x damage, raw (SE)", "MFI x damage, raw (p)",
    "MFI x pressure, standardised (beta)", "MFI x pressure, standardised (p)",
    "MFI x damage, standardised (beta)", "MFI x damage, standardised (p)",
    "Pearson chi2/df, model 3",
    "predicted deaths, high damage, MFI=1", "predicted deaths, high damage, MFI=11",
    "predicted deaths, low damage, MFI=1",  "predicted deaths, low damage, MFI=11",
    "predicted deaths, high damage, MFI=3", "predicted deaths, high damage, MFI=9"),
  reproduced = c(
    92, round(mean(d$alldeaths), 3), round(var(d$alldeaths), 3),
    round(b3["MasFem:Minpressure_Updated_2014", "Estimate"], 6),
    round(b3["MasFem:Minpressure_Updated_2014", "Std. Error"], 4),
    round(b3["MasFem:Minpressure_Updated_2014", "Pr(>|z|)"], 3),
    round(b3["MasFem:NDAM", "Estimate"], 6),
    round(b3["MasFem:NDAM", "Std. Error"], 6),
    signif(b3["MasFem:NDAM", "Pr(>|z|)"], 3),
    round(b4["ZMasFem:ZMinPressure_A", "Estimate"], 3),
    round(b4["ZMasFem:ZMinPressure_A", "Pr(>|z|)"], 3),
    round(b4["ZMasFem:ZNDAM", "Estimate"], 3),
    signif(b4["ZMasFem:ZNDAM", "Pr(>|z|)"], 3),
    round(pearson_ratio(m3), 3),
    round(pred_cat(1, TRUE), 2), round(pred_cat(11, TRUE), 2),
    round(pred_cat(1, FALSE), 2), round(pred_cat(11, FALSE), 2),
    round(pred_cat(3, TRUE), 2), round(pred_cat(9, TRUE), 2)),
  published = c(
    "92", "20.652", "1673.152",
    "0.006", "0.0025", "0.012",
    "0.00002", "0.00001", "<0.001",
    "0.395", "0.012", "0.705", "<0.001",
    "1.107",
    "10.80", "58.70", "5.86", "3.69", "15.15", "41.84")
)
write.csv(comp, file.path(OUT, "comparison_table.csv"), row.names = FALSE)

cat("\n== Reproduction comparison ==\n")
print(comp)
cat("\nWrote output/comparison_table.csv, output/robustness_table.csv,",
    "output/figure1_predicted_deaths.png, output/robustness_forest.png\n")
