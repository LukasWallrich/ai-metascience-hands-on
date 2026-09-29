# Robustness analyses A1-A9 (defined with predictions in robustness_plan.md).
# Run from this folder after analysis.R (reads primary_estimate.csv): Rscript robustness.R
# Writes robustness_estimates.csv and robustness_forest.png.

suppressPackageStartupMessages({
  library(data.table)
  library(glmmTMB)
  library(ggplot2)
})
source("analysis.R")  # prep_data(), or_row(); its main block does not run when sourced

d <- prep_data()
dm <- d[!is.na(skin)]
controls <- "position + leagueCountry"
re <- "(1 | playerShort) + (1 | refNum)"

glmm <- function(data, rhs, outcome = "cbind(redCards, games - redCards)", term = "skin", label) {
  t0 <- Sys.time()
  fit <- glmmTMB(as.formula(paste(outcome, "~", rhs)), family = binomial, data = data)
  if (!isTRUE(fit$sdr$pdHess)) warning(label, ": Hessian not positive definite")
  cat(sprintf("%-28s fitted in %s\n", label, format(Sys.time() - t0, digits = 3)))
  or_row(fit, term, label)
}

glm_or <- function(fit, term, label, n) {
  ct <- summary(fit)$coefficients
  b <- ct[term, 1]; se <- ct[term, 2]
  data.table(model = label, OR = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
             p = ct[term, 4], n_dyads = n)
}

a1 <- dm[skin != 0.5][, dark := as.integer(skin > 0.5)]
a5 <- dm[!is.na(height) & !is.na(weight) & !is.na(age)]
a5[, `:=`(height_z = scale(height)[, 1], weight_z = scale(weight)[, 1], age_z = scale(age)[, 1])]
big_refs <- d[, .N, by = refNum][N >= 50, refNum]  # counted in the full dataset

# Mixed-model alternatives, fitted in parallel (about 5 min each)
specs <- list(
  # A1: binary dark (> 0.5) vs light (< 0.5); neutral players dropped
  A1  = function() glmm(a1, paste("dark +", controls, "+", re), term = "dark", label = "A1 Binary dark vs light"),
  A2  = function() glmm(dm[rater1 == rater2], paste("skin +", controls, "+", re), label = "A2 Raters agree"),
  A3a = function() glmm(dm, paste("rater1 +", controls, "+", re), term = "rater1", label = "A3a Rater 1 only"),
  A3b = function() glmm(dm, paste("rater2 +", controls, "+", re), term = "rater2", label = "A3b Rater 2 only"),
  A4  = function() glmm(dm, paste("skin +", re), label = "A4 No covariates"),
  # A5: complete cases on height, weight, age
  A5  = function() glmm(a5, paste("skin +", controls, "+ height_z + weight_z + age_z +", re),
                        label = "A5 + height, weight, age"),
  A6  = function() glmm(dm, paste("skin +", controls, "+", re),
                        outcome = "cbind(redCards + yellowReds, games - redCards - yellowReds)",
                        label = "A6 Red + yellow-red"),
  A7  = function() glmm(dm[refNum %in% big_refs], paste("skin +", controls, "+", re),
                        label = "A7 Referees >= 50 dyads")
)
res <- parallel::mclapply(specs, function(f) f(), mc.cores = length(specs))
failed <- names(res)[!vapply(res, is.data.frame, logical(1))]
if (length(failed)) stop("Fits failed: ", paste(failed, collapse = ", "), "\n", paste(res[failed], collapse = "\n"))
res <- c(list(primary = fread("primary_estimate.csv")), res)

# A8: logistic GLM, no random effects
f8 <- glm(as.formula(paste("cbind(redCards, games - redCards) ~ skin +", controls)),
          family = binomial, data = dm)
res$A8 <- glm_or(f8, "skin", "A8 Logistic GLM, no RE", nobs(f8))

# A9: player-level aggregation, quasi-binomial
pl <- dm[, .(red = sum(redCards), games = sum(games), skin = skin[1],
             position = position[1], leagueCountry = leagueCountry[1]), by = playerShort]
f9 <- glm(as.formula(paste("cbind(red, games - red) ~ skin +", controls)),
          family = quasibinomial, data = pl)
res$A9 <- glm_or(f9, "skin", "A9 Player-level quasi-binomial", nrow(pl))
res$A9[, n_dyads := NA_integer_]
cat("A9 dispersion:", summary(f9)$dispersion, " players:", nrow(pl), "\n")

est <- rbindlist(res)
est[, n_players := c(uniqueN(dm$playerShort), uniqueN(a1$playerShort),
                     uniqueN(dm[rater1 == rater2, playerShort]), rep(uniqueN(dm$playerShort), 3),
                     uniqueN(a5$playerShort), uniqueN(dm$playerShort),
                     uniqueN(dm[refNum %in% big_refs, playerShort]), uniqueN(dm$playerShort), nrow(pl))]
print(est, digits = 3)
fwrite(est, "robustness_estimates.csv")

# Forest plot
est[, model := factor(model, levels = rev(model))]
est[, is_primary := model == "Primary"]
p <- ggplot(est, aes(OR, model, colour = is_primary)) +
  geom_vline(xintercept = 1, colour = "#8a8984", linewidth = 0.4) +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, linewidth = 0.8, orientation = "y") +
  geom_point(size = 2.6) +
  geom_text(aes(x = hi, label = sprintf("%.2f [%.2f, %.2f]", OR, lo, hi)),
            hjust = -0.1, size = 3, colour = "#52514e") +
  scale_x_log10(breaks = c(0.8, 1, 1.25, 1.5, 2, 2.5), expand = expansion(mult = c(0.05, 0.35))) +
  scale_colour_manual(values = c(`TRUE` = "#2a78d6", `FALSE` = "#52514e"), guide = "none") +
  labs(x = "Odds ratio for a red card (log scale)", y = NULL,
       title = "Skin tone and red cards: primary model and nine alternatives",
       subtitle = "OR for very dark vs very light skin tone (A1: dark vs light group). 95% CI.") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
        plot.title.position = "plot")
ggsave("robustness_forest.png", p, width = 8, height = 4.8, dpi = 200, bg = "white")
