# Reproduction and robustness analysis of Borjas & Breznau (2026), Table 1.
# Run from the project root:  Rscript analysis.R
# Input:  data/df.dta (model-level analysis file from the replication package)
# Output: output/*.csv, output/*.md (tables pasted into report.md), output/robustness.png

suppressMessages({
  library(haven)
  library(dplyr)
  library(sandwich)
  library(clubSandwich)
  library(lme4)
  library(ggplot2)
  library(patchwork)
})

set.seed(20260102)
dir.create("output", showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Data
# ---------------------------------------------------------------------------
raw <- read_dta("data/df.dta")
d <- raw |>
  filter(!is.na(ame)) |>          # one row without a team comes from the sem_p merge
  mutate(across(where(is.labelled), zap_labels)) |>
  as.data.frame()
stopifnot(nrow(d) == 1253, n_distinct(d$teamid) == 71)

# Rebuild the ideology groups and tail outcomes from their components and check
# them against the stored variables. att1-att3 are already reversed so that
# 6 = most pro-immigration.
att <- as.matrix(d[, c("att1", "att2", "att3")])
n_resp <- rowSums(!is.na(att))
share <- function(vals) rowSums(matrix(att %in% vals, nrow(att)), na.rm = TRUE) / n_resp
d$p12_chk <- share(1:2)
d$p56_chk <- share(5:6)
d$g3_chk <- as.numeric(d$p56_chk > 0.5)
d$g1_chk <- as.numeric(d$p12_chk > 0 & d$g3_chk == 0)   # teams 61 and 64 go to "pro"
# Stata treats a missing z as +infinity, so `z > 1.645` is true when z is missing
# (one model of team 75). This is kept to match the published sample.
sig <- is.na(d$z) | d$z > 1.645
d$neg_chk <- as.numeric(d$ame < -0.071 & sig)
d$pos_chk <- as.numeric(d$ame > 0.052 & sig)
stopifnot(
  max(abs(d$p12_chk - d$p12)) < 1e-6, max(abs(d$p56_chk - d$p56)) < 1e-6,   # Stata stores floats
  all(d$g1_chk == d$group1), all(d$g3_chk == d$group3),
  all(d$neg_chk == d$neg10s), all(d$pos_chk == d$pos10s)
)
d$group2 <- 1 - d$group1 - d$group3
d$w <- 1 / d$nmodel
d$mdegree_f <- factor(d$mdegree)
d$degree1_f <- factor(d$degree1)

team <- d |> group_by(teamid) |> slice(1) |> ungroup()
cat("Teams per group (anti / moderate / pro):",
    sum(team$group1), sum(team$group2), sum(team$group3), "\n")
cat("Anti teams alone in their mdegree cell:",
    team |> add_count(mdegree) |> filter(n == 1, group1 == 1) |> pull(teamid), "\n")

# ---------------------------------------------------------------------------
# 2. Estimation helpers
# ---------------------------------------------------------------------------
controls <- "stats_brw + topic_brw + t2 + t3"

# Weighted OLS with Stata-style CR1 cluster SEs:
# G/(G-1) * (N-1)/(N-K), which sandwich::vcovCL applies with type = "HC1".
fit_ols <- function(data, y, x, disc = "mdegree_f", weighted = TRUE) {
  rhs <- paste(c(x, controls, disc), collapse = " + ")
  f <- as.formula(paste(y, "~", rhs))
  m <- if (weighted) lm(f, data = data, weights = w) else lm(f, data = data)
  list(m = m, V = vcovCL(m, cluster = ~teamid, type = "HC1"))
}

lincom <- function(b, V, r, df) {
  est <- sum(r * b[names(r)])
  se <- sqrt(drop(t(r) %*% V[names(r), names(r)] %*% r))
  p <- if (is.infinite(df)) 2 * pnorm(-abs(est / se)) else 2 * pt(-abs(est / se), df)
  c(est = est, se = se, p = p)
}

G <- 71
term <- function(f, v) lincom(coef(f$m), f$V, setNames(1, v), G - 1)
diff31 <- function(f, df = G - 1) lincom(coef(f$m), f$V, c(group3 = 1, group1 = -1), df)
diff_p <- function(f) lincom(coef(f$m), f$V, c(p56 = 1, p12 = -1), G - 1)

# ---------------------------------------------------------------------------
# 3. Reproduce Table 1
# ---------------------------------------------------------------------------
# Published values: Table 1 of the article, taken from the Europe PMC full text
# https://www.ebi.ac.uk/europepmc/webservices/rest/PMC12757037/fullTextXML
# Stata log values: code/Log Files/02_Main_Regs.log (more decimals).
published <- tribble(
  ~col, ~outcome, ~term, ~pub_est, ~pub_se, ~log_est, ~log_se,
  1, "ame", "proindex", 0.011, 0.006, 0.0108737, 0.0056998,
  2, "ame", "p12", -0.050, 0.025, -0.0503799, 0.0252584,
  2, "ame", "p56", 0.023, 0.019, 0.0234775, 0.0193443,
  2, "ame", "p56 - p12", 0.074, 0.024, 0.0738574, 0.0242554,
  3, "ame", "group1", -0.057, 0.031, -0.0572476, 0.0306365,
  3, "ame", "group3", 0.027, 0.015, 0.0272754, 0.0147459,
  3, "ame", "group3 - group1", 0.085, 0.031, 0.0845230, 0.0310270,
  4, "neg10s", "proindex", -0.051, 0.021, -0.0514097, 0.0206502,
  5, "neg10s", "p12", 0.081, 0.103, 0.0809324, 0.1028085,
  5, "neg10s", "p56", -0.161, 0.064, -0.1606565, 0.0642693,
  5, "neg10s", "p56 - p12", -0.242, 0.107, -0.2415889, 0.1074294,
  6, "neg10s", "group1", 0.150, 0.123, 0.1499767, 0.1231782,
  6, "neg10s", "group3", -0.124, 0.044, -0.1238967, 0.0439937,
  6, "neg10s", "group3 - group1", -0.274, 0.125, -0.2738734, 0.1252005,
  7, "pos10s", "proindex", 0.019, 0.012, 0.0192455, 0.0115145,
  8, "pos10s", "p12", -0.130, 0.057, -0.1303656, 0.0568758,
  8, "pos10s", "p56", -0.016, 0.041, -0.0161202, 0.0412526,
  8, "pos10s", "p56 - p12", 0.114, 0.045, 0.1142454, 0.0458145,
  9, "pos10s", "group1", -0.070, 0.037, -0.0695299, 0.0377740,
  9, "pos10s", "group3", 0.017, 0.034, 0.0173149, 0.0339734,
  9, "pos10s", "group3 - group1", 0.087, 0.035, 0.0868448, 0.0346823
)
pub_r2 <- c(0.062, 0.065, 0.071, 0.096, 0.115, 0.133, 0.087, 0.090, 0.089)

specs <- list(c("proindex"), c("p12", "p56"), c("group1", "group3"))
outcomes <- c("ame", "neg10s", "pos10s")
rows <- list(); r2 <- numeric(0); col <- 0
for (y in outcomes) for (x in specs) {
  col <- col + 1
  f <- fit_ols(d, y, x)
  r2[col] <- summary(f$m)$r.squared
  for (v in x) rows[[length(rows) + 1]] <- c(col = col, term = v, term(f, v))
  if ("p56" %in% x) rows[[length(rows) + 1]] <- c(col = col, term = "p56 - p12", diff_p(f))
  if ("group3" %in% x) rows[[length(rows) + 1]] <- c(col = col, term = "group3 - group1", diff31(f))
}
repro <- bind_rows(lapply(rows, function(r) as.data.frame(as.list(r)))) |>
  mutate(col = as.numeric(col), across(c(est, se, p), as.numeric))
table1 <- published |>
  left_join(repro, by = c("col", "term")) |>
  mutate(r2_repro = r2[col], r2_pub = pub_r2[col])
write.csv(table1, "output/table1_reproduction.csv", row.names = FALSE)
cat("\nLargest |repro - Stata log| difference: estimate",
    signif(max(abs(table1$est - table1$log_est)), 3),
    "; SE", signif(max(abs(table1$se - table1$log_se)), 3), "\n")

# ---------------------------------------------------------------------------
# 4. Robustness: target = pro minus anti difference in AME (Table 1, col 3)
# ---------------------------------------------------------------------------
summ_row <- function(label, est, se, p, ci = est + c(-1, 1) * qt(0.975, G - 1) * se,
                     n_models, n_anti, n_pro, note = "") {
  data.frame(spec = label, est = est, se = se, lo = ci[1], hi = ci[2], p = p,
             n_models = n_models, n_anti = n_anti, n_pro = n_pro, note = note)
}
from_fit <- function(label, f, data, note = "") {
  x <- diff31(f)
  tm <- data[as.integer(rownames(f$m$model)), ] |> group_by(teamid) |> slice(1)   # fitted sample only
  summ_row(label, x["est"], x["se"], x["p"], n_models = nobs(f$m),
           n_anti = sum(tm$group1), n_pro = sum(tm$group3), note = note)
}

base <- fit_ols(d, "ame", c("group1", "group3"))
rob <- list(from_fit("Baseline (published spec)", base, d))

# A1 unweighted
rob[[length(rob) + 1]] <- from_fit("A1 No weights", fit_ols(d, "ame", c("group1", "group3"), weighted = FALSE), d)

# A2 team-level median AME, HC3 SEs. Teams alone in their mdegree cell have
# leverage 1 (HC3 undefined) and do not affect the estimates, so they are left out.
tl <- d |> group_by(teamid) |>
  summarise(ame_med = median(ame), across(c(group1, group3, stats_brw, topic_brw, t2, t3, mdegree_f), first)) |>
  add_count(mdegree_f) |> filter(n > 1) |> droplevels()
m2 <- lm(as.formula(paste("ame_med ~ group1 + group3 +", controls, "+ mdegree_f")), data = tl)
x2 <- lincom(coef(m2), vcovHC(m2, type = "HC3"), c(group3 = 1, group1 = -1), df.residual(m2))
rob[[length(rob) + 1]] <- summ_row("A2 Team median AME (team level, HC3)", x2["est"], x2["se"], x2["p"],
  ci = x2["est"] + c(-1, 1) * qt(0.975, df.residual(m2)) * x2["se"],
  n_models = nrow(tl), n_anti = sum(tl$group1), n_pro = sum(tl$group3), note = "teams in single-team discipline cells dropped")

# A3 winsorised AME
q <- quantile(d$ame, c(0.05, 0.95))
d$ame_w <- pmin(pmax(d$ame, q[1]), q[2])
rob[[length(rob) + 1]] <- from_fit("A3 AME winsorised at 5th/95th pct", fit_ols(d, "ame_w", c("group1", "group3")), d,
  note = sprintf("bounds %.3f, %.3f", q[1], q[2]))

# A4 binary-outcome models only
db <- filter(d, scale == 0)
rob[[length(rob) + 1]] <- from_fit("A4 Binary-outcome models only", fit_ols(db, "ame", c("group1", "group3")), db)

# A5 lead-author discipline FE; A6 no discipline FE
rob[[length(rob) + 1]] <- from_fit("A5 Lead-author discipline FE", fit_ols(d, "ame", c("group1", "group3"), disc = "degree1_f"), d,
  note = "team 33 has no discipline data and drops out")
rob[[length(rob) + 1]] <- from_fit("A6 No discipline FE", fit_ols(d, "ame", c("group1", "group3"), disc = NULL), d)

# A7 majority-rule groups
d7 <- d |> mutate(group1 = as.numeric(p12 > 0.5), group3 = as.numeric(p56 > 0.5))
rob[[length(rob) + 1]] <- from_fit("A7 Majority-rule groups", fit_ols(d7, "ame", c("group1", "group3")), d7)

# A8 random-intercept model (REML, unweighted); Wald test with normal reference
m8 <- lmer(as.formula(paste("ame ~ group1 + group3 +", controls, "+ mdegree_f + (1 | teamid)")), data = d)
x8 <- lincom(fixef(m8), as.matrix(vcov(m8)), c(group3 = 1, group1 = -1), Inf)
rob[[length(rob) + 1]] <- summ_row("A8 Team random intercepts (LMM)", x8["est"], x8["se"], x8["p"],
  ci = x8["est"] + c(-1, 1) * qnorm(0.975) * x8["se"],
  n_models = nrow(d), n_anti = sum(team$group1), n_pro = sum(team$group3))

# A9a CR2 SEs with Satterthwaite df. Reparameterise so the difference is one
# coefficient: b1*g1 + b3*g3 = b1*(g1 + g3) + (b3 - b1)*g3.
d$g13 <- d$group1 + d$group3
m9 <- lm(as.formula(paste("ame ~ g13 + group3 +", controls, "+ mdegree_f")), data = d, weights = w)
stopifnot(abs(coef(m9)["group3"] - diff31(base)["est"]) < 1e-10)
ct <- coef_test(m9, vcov = "CR2", cluster = d$teamid, test = "Satterthwaite", coefs = "group3")
rob[[length(rob) + 1]] <- summ_row("A9a CR2 + Satterthwaite df", ct$beta, ct$SE, ct$p_Satt,
  ci = ct$beta + c(-1, 1) * qt(0.975, ct$df_Satt) * ct$SE,
  n_models = nrow(d), n_anti = sum(team$group1), n_pro = sum(team$group3),
  note = sprintf("Satterthwaite df = %.1f", ct$df_Satt))

# A9b wild cluster restricted bootstrap (Webb 6-point weights), null b3 = b1 imposed.
wild_boot <- function(B = 9999) {
  X <- model.matrix(m9); y <- d$ame; w <- d$w; cl <- d$teamid
  N <- nrow(X); K <- ncol(X); cadj <- G / (G - 1) * (N - 1) / (N - K)
  A <- solve(crossprod(X, X * w))
  r <- as.numeric(colnames(X) == "group3")
  tstat <- function(Y) {                      # Y: N x B matrix of outcomes
    Bh <- A %*% crossprod(X, Y * w)
    U <- Y - X %*% Bh
    mvec <- drop(r %*% A %*% t(X * w))        # contribution of each row to the contrast score
    S <- rowsum(mvec * U, cl)
    (r %*% Bh) / sqrt(cadj * colSums(S^2))
  }
  t_obs <- drop(tstat(matrix(y)))
  mr <- lm.wfit(X[, colnames(X) != "group3"], y, w)   # restricted fit
  yhat <- y - mr$residuals
  webb <- c(-sqrt(1.5), -1, -sqrt(0.5), sqrt(0.5), 1, sqrt(1.5))
  ids <- match(cl, sort(unique(cl)))
  tb <- unlist(lapply(1:9, function(chunk) {   # 9 chunks of 1,111 draws keep memory small
    V <- matrix(sample(webb, G * B / 9, replace = TRUE), G)
    drop(tstat(yhat + mr$residuals * V[ids, ]))
  }))
  c(t_obs = t_obs, p = mean(abs(tb) >= abs(t_obs)))
}
wb <- wild_boot()
cat("Wild bootstrap t_obs (should equal CR1 t):", round(wb["t_obs"], 4),
    " CR1 t:", round(diff31(base)["est"] / diff31(base)["se"], 4), "\n")
b0 <- diff31(base)
rob[[length(rob) + 1]] <- summ_row("A9b Wild cluster bootstrap (Webb, 9,999 draws)", b0["est"], b0["se"], wb["p"],
  ci = c(NA, NA), n_models = nrow(d), n_anti = sum(team$group1), n_pro = sum(team$group3),
  note = "p from bootstrap; SE is CR1")

rob <- bind_rows(rob)
rownames(rob) <- NULL
write.csv(rob, "output/robustness.csv", row.names = FALSE)

# Diagnostic: leave one team out
loto <- bind_rows(lapply(sort(unique(d$teamid)), function(tid) {
  dd <- filter(d, teamid != tid)
  x <- lincom(coef(fit_ols(dd, "ame", c("group1", "group3"))$m),
              fit_ols(dd, "ame", c("group1", "group3"))$V, c(group3 = 1, group1 = -1), G - 2)
  tm <- team[team$teamid == tid, ]
  data.frame(teamid = tid, group = c("anti", "moderate", "pro")[1 * tm$group1 + 2 * tm$group2 + 3 * tm$group3],
             est = x["est"], se = x["se"], p = x["p"])
}))
write.csv(loto, "output/leave_one_team_out.csv", row.names = FALSE)

# Combination grid of the choices that alter the point estimate
grid <- expand.grid(weighted = c(TRUE, FALSE), outcome = c("ame", "ame_w"),
                    disc = c("mdegree_f", "degree1_f", "none"), groups = c("published", "majority"),
                    stringsAsFactors = FALSE)
grid_res <- bind_rows(lapply(seq_len(nrow(grid)), function(i) {
  g <- grid[i, ]
  dd <- if (g$groups == "majority") mutate(d, group1 = as.numeric(p12 > 0.5), group3 = as.numeric(p56 > 0.5)) else d
  f <- fit_ols(dd, g$outcome, c("group1", "group3"), disc = if (g$disc == "none") NULL else g$disc, weighted = g$weighted)
  cbind(g, t(diff31(f)))
}))
write.csv(grid_res, "output/spec_grid.csv", row.names = FALSE)

# ---------------------------------------------------------------------------
# 5. Figure
# ---------------------------------------------------------------------------
fmt_p <- function(p) ifelse(p < 0.001, "p < 0.001", sprintf("p = %.3f", p))

pa <- rob |>
  filter(!is.na(lo)) |>
  mutate(spec = factor(spec, levels = rev(spec)), baseline = spec == "Baseline (published spec)") |>
  ggplot(aes(est, spec, colour = baseline)) +
  geom_vline(xintercept = 0, colour = "grey60") +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0.2, orientation = "y") +
  geom_point(size = 2.4) +
  geom_text(aes(label = fmt_p(p)), nudge_y = 0.35, size = 3, colour = "grey30") +
  scale_colour_manual(values = c(`TRUE` = "#b2182b", `FALSE` = "#2166ac"), guide = "none") +
  labs(title = "A. Pro minus anti difference in AME, one change at a time",
       subtitle = sprintf("A9b (wild cluster bootstrap of the baseline) gives %s; it has no CI and is not drawn.",
                          fmt_p(rob$p[grepl("^A9b", rob$spec)])),
       x = "Difference in AME (95% CI)", y = NULL) +
  theme_minimal(base_size = 11)

pb <- loto |>
  arrange(est) |>
  mutate(rank = row_number()) |>
  ggplot(aes(rank, est, colour = group)) +
  geom_hline(yintercept = 0, colour = "grey60") +
  geom_hline(yintercept = b0["est"], colour = "#b2182b", linetype = 2) +
  geom_errorbar(aes(ymin = est - 1.96 * se, ymax = est + 1.96 * se), width = 0, alpha = 0.5) +
  geom_point(size = 1.8) +
  geom_text(data = \(x) filter(x, rank == 1), aes(label = paste("without team", teamid)),
            hjust = -0.15, size = 3, show.legend = FALSE) +
  geom_text(data = \(x) filter(x, rank == max(rank)), aes(label = paste("without team", teamid)),
            hjust = 1.15, size = 3, show.legend = FALSE) +
  scale_colour_manual(values = c(anti = "#d6604d", moderate = "grey50", pro = "#4393c3")) +
  labs(title = "B. Baseline without each team in turn", subtitle = "Dashed line: full-sample estimate",
       x = "Teams, ordered by estimate", y = "Difference in AME (95% CI)", colour = "Dropped team") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")

pc <- grid_res |>
  arrange(est) |>
  mutate(rank = row_number(),
         sig = ifelse(p < 0.05, "p < 0.05", "p >= 0.05"),
         Discipline = c(mdegree_f = "composition FE", degree1_f = "lead-author FE", none = "no FE")[disc]) |>
  ggplot(aes(rank, est, colour = sig, shape = Discipline)) +
  geom_hline(yintercept = 0, colour = "grey60") +
  geom_errorbar(aes(ymin = est - 1.96 * se, ymax = est + 1.96 * se), width = 0, alpha = 0.5) +
  geom_point(size = 2.2) +
  scale_colour_manual(values = c(`p < 0.05` = "#1b7837", `p >= 0.05` = "grey55")) +
  scale_shape_manual(values = c(16, 17, 1)) +
  labs(title = "C. All 24 combinations of A1, A3, A5/A6, A7",
       subtitle = "Rightmost point is the published specification",
       x = "Specifications, ordered by estimate", y = "Difference in AME (95% CI)", colour = NULL, shape = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", legend.box = "vertical", legend.margin = margin(0, 0, 0, 0))

fig <- pa / wrap_elements(full = pb | pc) + plot_layout(heights = c(1.1, 1))
ggsave("output/robustness.png", fig, width = 11, height = 10, dpi = 150, bg = "white")

# ---------------------------------------------------------------------------
# 6. Markdown tables for report.md
# ---------------------------------------------------------------------------
f3 <- function(x) ifelse(is.na(x), "–", sprintf("%.3f", x))
fp <- function(x) ifelse(!is.na(x) & x < 0.001, "< 0.001", f3(x))
md_table <- function(df) {
  c(paste("|", paste(names(df), collapse = " | "), "|"),
    paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|"),
    apply(df, 1, function(r) paste("|", paste(r, collapse = " | "), "|")))
}
t1_md <- table1 |>
  transmute(Col = col, Outcome = outcome, Term = term,
            `Published est (SE)` = sprintf("%s (%s)", f3(pub_est), f3(pub_se)),
            `Stata log est (SE)` = sprintf("%.4f (%.4f)", log_est, log_se),
            `Reproduced est (SE)` = sprintf("%.4f (%.4f)", est, se),
            `Reproduced p` = f3(p),
            `R² pub / repro` = sprintf("%.3f / %.3f", r2_pub, r2_repro))
rob_md <- rob |>
  transmute(Specification = spec, Estimate = f3(est), SE = f3(se),
            `95% CI` = ifelse(is.na(lo), "–", sprintf("[%.3f, %.3f]", lo, hi)),
            p = fp(p), `Models` = n_models, `Anti / pro teams` = paste(n_anti, "/", n_pro), Note = note)
loto_md <- loto |> arrange(est) |> slice(c(1:3, (n() - 2):n())) |>
  transmute(`Dropped team` = teamid, Group = group, Estimate = f3(est), SE = f3(se), p = f3(p))
grid_md <- grid_res |>
  transmute(Weights = ifelse(weighted, "1/nmodel", "none"),
            Outcome = ifelse(outcome == "ame", "AME", "winsorised"),
            Discipline = c(mdegree_f = "composition", degree1_f = "lead author", none = "none")[disc],
            Groups = groups, Estimate = f3(est), SE = f3(se), p = fp(p))
writeLines(c("<!-- generated by analysis.R -->", md_table(t1_md)), "output/table1.md")
writeLines(c("<!-- generated by analysis.R -->", md_table(rob_md)), "output/robustness.md")
writeLines(c("<!-- generated by analysis.R -->", md_table(loto_md)), "output/loto.md")
writeLines(c("<!-- generated by analysis.R -->", md_table(grid_md)), "output/grid.md")

cat("\nLeave-one-team-out: range", f3(min(loto$est)), "to", f3(max(loto$est)),
    "; share with p < 0.05:", mean(loto$p < 0.05), "; share with p < 0.10:", mean(loto$p < 0.10), "\n")
cat("Grid: share with p < 0.05:", mean(grid_res$p < 0.05), "; p < 0.10:", mean(grid_res$p < 0.10),
    "; estimate range", f3(min(grid_res$est)), "to", f3(max(grid_res$est)), "\n")
alt <- rob[grepl("^A[1-8] ", rob$spec), ]
cat("Single-change alternatives A1-A8 with p < 0.05:", sum(alt$p < 0.05), "of", nrow(alt),
    "; estimate range", f3(min(alt$est)), "to", f3(max(alt$est)), "\n")
cat("Grid by discipline control: specs with p < 0.05\n")
print(grid_res |> group_by(disc) |> summarise(n = n(), sig05 = sum(p < 0.05), min_est = min(est), max_est = max(est)))
cat("Published spec is the largest estimate in the grid:", which.max(grid_res$est) == 1, "\n")
print(rob[, c("spec", "est", "se", "p")], digits = 3)
