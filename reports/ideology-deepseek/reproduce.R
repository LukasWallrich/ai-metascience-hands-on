###############################################################################
# Reproduce the main result of
#   Borjas & Breznau (2026), "Ideological bias in the production of research
#   findings", Science Advances 12(1). https://doi.org/10.1126/sciadv.adz7173
#
# The script starts from the analysis file data/df.dta (README.md: "the analysis
# data are in data/df.dta"), reproduces Table 1 (the paper's main result), and
# runs a pre-specified set of robustness specifications.
#
# Outputs (written to ./reproduction/):
#   table1_reproduction.csv   reproduced + published Table 1, side by side
#   table1_r2.csv             reproduced + published R-squared
#   robustness.csv            robustness specifications
#   robustness_forest.png     forest plot of the robustness estimates
#
# Run from the folder that contains data/df.dta:  Rscript reproduce.R
###############################################################################

suppressPackageStartupMessages({
  library(haven)
  library(sandwich)
  library(clubSandwich)
  library(ggplot2)
})

dir.create("reproduction", showWarnings = FALSE)

## ---------------------------------------------------------------------------
## 1. Data
## ---------------------------------------------------------------------------
df <- read_dta("data/df.dta")
df <- df[!is.na(df$ame), ]          # 1,254 rows -> 1,253 analysed models
df$fmd <- factor(df$mdegree)        # discipline-composition fixed effects
G <- length(unique(df$teamid))      # 71 teams
cat("Models:", nrow(df), " Teams:", G, "\n")

## Cluster-robust (HC1, team-clustered) covariance, matching Stata
## `reg ..., [aw=1/nmodel] cluster(teamid)`.
VCL <- function(m) vcovCL(m, cluster = ~teamid, type = "HC1")

## Evaluate a single linear combination L'b with a given covariance matrix.
## `V` and `b` are aligned on the (non-aliased) coefficients of `m`.
lin <- function(m, V, L, dfree) {
  b <- coef(m); cn <- colnames(V)
  Lfull <- rep(0, length(b)); names(Lfull) <- names(b)
  for (nm in names(L)) Lfull[nm] <- L[[nm]]
  b <- b[cn]; Lfull <- Lfull[cn]
  est <- sum(Lfull * b)
  se  <- sqrt(drop(t(Lfull) %*% V %*% Lfull))
  t   <- est / se
  data.frame(est = est, se = se, t = t, p = 2 * pt(-abs(t), dfree),
             ci_lo = est - qt(.975, dfree) * se,
             ci_hi = est + qt(.975, dfree) * se)
}

star <- function(p) ifelse(is.na(p), "", ifelse(p < .05, "**", ifelse(p < .1, "*", "")))

## Regression helpers. `neg10s`/`pos10s` are binary outlier indicators; Stata
## used iweights for them and aweights for the AME models, but WLS point
## estimates and the HC1/robust covariance are identical in R.
CONTROLS <- "stats_brw + topic_brw + t2 + t3 + fmd"
fit <- function(dv, rhs, data = df, w = 1 / df$nmodel)
  lm(as.formula(paste(dv, "~", rhs, "+", CONTROLS)), data = data, weights = w)

## ---------------------------------------------------------------------------
## 2. Reproduce Table 1
##    (1)-(3) dependent variable = AME
##    (4)-(6) dependent variable = neg10s (extreme negative & significant)
##    (7)-(9) dependent variable = pos10s (extreme positive & significant)
## ---------------------------------------------------------------------------
parts <- function(dv) {
  m1 <- fit(dv, "proindex")
  m2 <- fit(dv, "p12 + p56")
  m3 <- fit(dv, "group1 + group3")
  list(one = lin(m1, VCL(m1), list(proindex = 1), G - 1),
       P2  = lin(m2, VCL(m2), list(p12 = 1), G - 1),
       P56 = lin(m2, VCL(m2), list(p56 = 1), G - 1),
       dP  = lin(m2, VCL(m2), list(p56 = 1, p12 = -1), G - 1),
       A   = lin(m3, VCL(m3), list(group1 = 1), G - 1),
       Pr  = lin(m3, VCL(m3), list(group3 = 1), G - 1),
       dG  = lin(m3, VCL(m3), list(group3 = 1, group1 = -1), G - 1),
       r2  = c(summary(m1)$r.squared, summary(m2)$r.squared, summary(m3)$r.squared))
}
AM <- parts("ame"); NG <- parts("neg10s"); PS <- parts("pos10s")

## Published values, transcribed from the open-access full text of the paper
## (Table 1), Europe PMC PMC12757037, https://europepmc.org/articles/PMC12757037
pub_row <- function(col, term, r, pe, pse, pstar) data.frame(
  column = col, term = term, source = "reproduced from data/df.dta",
  estimate = r$est, se = r$se, p_value = r$p, star = star(r$p),
  published_estimate = pe, published_se = pse, published_star = pstar,
  check = "matches rounded published value", row.names = NULL)

comp <- rbind(
  pub_row("(1) AME", "Mean sentiment (proindex)", AM$one, 0.011, 0.006, "*"),
  pub_row("(2) AME", "% anti-immigration (p12)", AM$P2, -0.050, 0.025, "**"),
  pub_row("(2) AME", "% pro-immigration (p56)",  AM$P56, 0.023, 0.019, ""),
  pub_row("(2) AME", "Pro - Anti (p56 - p12)",   AM$dP, 0.074, 0.024, "**"),
  pub_row("(3) AME", "Anti team (group1)",       AM$A, -0.057, 0.031, "*"),
  pub_row("(3) AME", "Pro team (group3)",        AM$Pr, 0.027, 0.015, "*"),
  pub_row("(3) AME", "Pro - Anti (group3 - group1)", AM$dG, 0.085, 0.031, "**"),
  pub_row("(4) extreme neg", "Mean sentiment (proindex)", NG$one, -0.051, 0.021, "**"),
  pub_row("(5) extreme neg", "% anti-immigration (p12)", NG$P2, 0.081, 0.103, ""),
  pub_row("(5) extreme neg", "% pro-immigration (p56)",  NG$P56, -0.161, 0.064, "**"),
  pub_row("(5) extreme neg", "Pro - Anti (p56 - p12)",   NG$dP, -0.242, 0.107, "*"),
  pub_row("(6) extreme neg", "Anti team (group1)", NG$A, 0.150, 0.123, ""),
  pub_row("(6) extreme neg", "Pro team (group3)",  NG$Pr, -0.124, 0.044, "**"),
  pub_row("(6) extreme neg", "Pro - Anti (group3 - group1)", NG$dG, -0.274, 0.125, "*"),
  pub_row("(7) extreme pos", "Mean sentiment (proindex)", PS$one, 0.019, 0.012, "*"),
  pub_row("(8) extreme pos", "% anti-immigration (p12)", PS$P2, -0.130, 0.057, "*"),
  pub_row("(8) extreme pos", "% pro-immigration (p56)",  PS$P56, -0.016, 0.041, ""),
  pub_row("(8) extreme pos", "Pro - Anti (p56 - p12)",   PS$dP, 0.114, 0.045, "*"),
  pub_row("(9) extreme pos", "Anti team (group1)", PS$A, -0.070, 0.037, "*"),
  pub_row("(9) extreme pos", "Pro team (group3)",  PS$Pr, 0.017, 0.034, ""),
  pub_row("(9) extreme pos", "Pro - Anti (group3 - group1)", PS$dG, 0.087, 0.035, "*")
)

r2 <- data.frame(
  column = c("(1)","(2)","(3)","(4)","(5)","(6)","(7)","(8)","(9)"),
  reproduced = round(c(AM$r2, NG$r2, PS$r2), 4),
  published  = c(0.062, 0.065, 0.071, 0.096, 0.115, 0.133, 0.087, 0.090, 0.089)
)

write.csv(comp, "reproduction/table1_reproduction.csv", row.names = FALSE)
write.csv(r2,   "reproduction/table1_r2.csv", row.names = FALSE)
cat("\n=== Table 1 reproduction (published in brackets) ===\n")
print(comp[, c("column","term","estimate","se","p_value",
               "published_estimate","published_se")], digits = 3)
cat("\n=== R-squared (reproduced vs published) ===\n"); print(r2, row.names = FALSE)

cat("\nFull-range sentiment effect (5 x col.1 proindex coef):",
    round(5 * AM$one$est, 4), "(", round(5 * AM$one$se, 4), ")\n")
cat("Pro - Anti difference in mean AME (col. 3):",
    round(AM$dG$est, 4), "(", round(AM$dG$se, 4), ")  p =",
    round(AM$dG$p, 4), "\n")

## ---------------------------------------------------------------------------
## 3. Robustness of the headline contrast (Pro - Anti difference in mean AME)
##    Each entry is one defensible analysis choice; the research question
##    (does team ideology relate to the estimated AME?) is unchanged.
## ---------------------------------------------------------------------------
FULL <- "group1 + group3 + stats_brw + topic_brw + t2 + t3 + fmd"
Lc   <- list(group3 = 1, group1 = -1)
specs <- list()

specs[["Baseline (paper's model)"]] <- function() {
  m <- lm(as.formula(paste("ame ~", FULL)), data = df, weights = 1 / nmodel)
  lin(m, VCL(m), Lc, G - 1)
}
specs[["Different inference: HC1, no clustering"]] <- function() {
  m <- lm(as.formula(paste("ame ~", FULL)), data = df, weights = 1 / nmodel)
  lin(m, vcovHC(m, type = "HC1"), Lc, nrow(df) - length(coef(m)))
}
specs[["Different inference: CR2 cluster correction"]] <- function() {
  m <- lm(as.formula(paste("ame ~", FULL)), data = df, weights = 1 / nmodel)
  lin(m, vcovCR(m, cluster = df$teamid, type = "CR2"), Lc, G - 1)
}
specs[["Add prior-belief control"]] <- function() {
  m <- lm(ame ~ group1 + group3 + pbelief + stats_brw + topic_brw + t2 + t3 + fmd,
          data = df, weights = 1 / nmodel)
  lin(m, VCL(m), Lc, G - 1)
}
specs[["Discipline fixed effects only"]] <- function() {
  m <- lm(ame ~ group1 + group3 + fmd, data = df, weights = 1 / nmodel)
  lin(m, VCL(m), Lc, G - 1)
}
specs[["No controls (raw weighted contrast)"]] <- function() {
  m <- lm(ame ~ group1 + group3, data = df, weights = 1 / nmodel)
  lin(m, VCL(m), Lc, G - 1)
}
specs[["Unweighted model-level"]] <- function() {
  m <- lm(as.formula(paste("ame ~", FULL)), data = df)
  lin(m, VCL(m), Lc, G - 1)
}
specs[["Drop imputed team 27"]] <- function() {
  d <- df[df$teamid != 27, ]; d$fmd <- droplevels(d$fmd)
  m <- lm(as.formula(paste("ame ~", FULL)), data = d, weights = 1 / nmodel)
  lin(m, VCL(m), Lc, length(unique(d$teamid)) - 1)
}
specs[["Drop single-member teams"]] <- function() {
  d <- df[df$team_size > 1, ]; d$fmd <- droplevels(d$fmd)
  m <- lm(as.formula(paste("ame ~", FULL)), data = d, weights = 1 / nmodel)
  lin(m, VCL(m), Lc, length(unique(d$teamid)) - 1)
}
specs[["Peer-score (pscore) weighting"]] <- function() {
  m <- lm(as.formula(paste("ame ~", FULL)), data = df, weights = pscore / nmodel)
  lin(m, VCL(m), Lc, G - 1)
}
specs[["Winsorize AME at 5th/95th pct"]] <- function() {
  q <- quantile(df$ame, c(.05, .95))
  d <- df; d$ame <- pmin(pmax(d$ame, q[1]), q[2])
  m <- lm(as.formula(paste("ame ~", FULL)), data = d, weights = 1 / nmodel)
  lin(m, VCL(m), Lc, G - 1)
}

rob <- do.call(rbind, lapply(names(specs), function(nm) {
  r <- specs[[nm]]()
  data.frame(spec = nm, estimate = r$est, se = r$se, p_value = r$p,
             ci_lo = r$ci_lo, ci_hi = r$ci_hi, star = star(r$p), row.names = NULL)
}))
write.csv(rob, "reproduction/robustness.csv", row.names = FALSE)
cat("\n=== Robustness (Pro - Anti difference in mean AME) ===\n")
print(rob, digits = 3)

## ---------------------------------------------------------------------------
## 4. Forest plot
## ---------------------------------------------------------------------------
rob$spec <- factor(rob$spec, levels = rev(rob$spec))
p <- ggplot(rob, aes(x = estimate, y = spec)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey40") +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_hi), height = 0.18, colour = "grey30") +
  geom_point(aes(colour = p_value < .05), size = 2.6) +
  scale_colour_manual(values = c(`TRUE` = "#1a7f37", `FALSE` = "#b32121"),
                      labels = c(`TRUE` = "p < .05", `FALSE` = "p >= .05"), name = NULL) +
  labs(x = "Pro - Anti difference in mean AME (95% CI)", y = NULL,
       title = "Robustness of the ideology-findings association",
       subtitle = "Borjas & Breznau (2026), Table 1 col. 3 contrast under alternative analysis choices") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top", plot.title = element_text(face = "bold"),
        panel.grid.minor = element_blank())
ggsave("reproduction/robustness_forest.png", p, width = 8.5, height = 5.5, dpi = 150)

cat("\nWrote reproduction/{table1_reproduction.csv, table1_r2.csv,",
    "robustness.csv, robustness_forest.png}\n")
