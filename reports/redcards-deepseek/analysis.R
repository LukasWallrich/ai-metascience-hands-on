#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# Red cards and skin tone: many-analysts case B (Silberzahn et al., 2018)
# One script, clean start:
#   (1) primary analysis -> odds ratio with 95% CI
#   (2) robustness grid: 10 defensible alternative analysis choices
#   (3) summary table (estimates.csv) + forest plot (robustness.png)
#   (4) comparison with the 29 published team estimates (OSF fa743)
# -----------------------------------------------------------------------------

suppressMessages({
  library(ggplot2)
  library(lme4)
  library(sandwich)
  library(lmtest)
})

set.seed(20180101)
options(stringsAsFactors = FALSE)

dir      <- "/Users/lukaswallrich/Documents/Coding/presentations/ai-metascience-hands-on-prerun/runs/redcards-deepseek"
data_csv <- file.path(dir, "CrowdstormingDataJuly1st.csv")

# --- load and prepare --------------------------------------------------------
d <- read.csv(data_csv)

# Skin tone: two raters on a 0-1 (5-level) scale; missing on the same rows.
d$st      <- rowMeans(cbind(d$rater1, d$rater2))          # average of raters
d$st_r1   <- d$rater1
d$st_r2   <- d$rater2
d$dark    <- as.integer(d$st > 0.5)                       # binary dark vs light
d$sendoff <- d$redCards + d$yellowReds                    # all send-offs

# Player age at the start of the 2012/13 season; BMI; NA position as own level.
d$age <- as.numeric(difftime(as.Date("2012-07-01"),
                             as.Date(d$birthday, format = "%d.%m.%Y"),
                             units = "weeks")) / 52.25
d$bmi <- d$weight / (d$height / 100)^2
d$position[is.na(d$position)] <- "Unknown"
d$club          <- factor(d$club)
d$leagueCountry <- factor(d$leagueCountry)
d$position      <- factor(d$position)

m <- d[!is.na(d$st), ]                                    # complete skin-tone cases

# --- estimation engines ------------------------------------------------------
# Population-averaged logistic regression with two-way cluster-robust SE.
cr2_spec <- function(data, st_var, outcome = "red", rhs = "", label, desc) {
  oc <- if (outcome == "red") "redCards" else "sendoff"
  form <- as.formula(paste0("cbind(", oc, ", games - ", oc, ") ~ ", st_var,
                            if (nzchar(rhs)) paste0(" + ", rhs) else ""))
  g  <- glm(form, data = data, family = binomial)
  ct <- lmtest::coeftest(g, vcov = sandwich::vcovCL(g, cluster = ~ playerShort + refNum))
  b  <- ct[st_var, 1]; se <- ct[st_var, 2]
  data.frame(spec = label, description = desc, engine = "GLM, cluster-robust (CR2)",
             n_rows = nrow(data), n_events = sum(data[[oc]]),
             or = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
             p = ct[st_var, 4], stringsAsFactors = FALSE)
}

# One row per player: career red cards / career games.
player_spec <- function(data, label, desc) {
  agg <- aggregate(cbind(red = redCards, games = games) ~ playerShort, data = data, FUN = sum)
  agg <- merge(agg, aggregate(st ~ playerShort, data = data, FUN = mean), by = "playerShort")
  g  <- glm(cbind(red, games - red) ~ st, data = agg, family = binomial)
  co <- summary(g)$coefficients["st", ]
  data.frame(spec = label, description = desc, engine = "GLM, player level",
             n_rows = nrow(agg), n_events = sum(agg$red),
             or = exp(co[1]), lo = exp(co[1] - 1.96 * co[2]),
             hi = exp(co[1] + 1.96 * co[2]), p = co[4], stringsAsFactors = FALSE)
}

# Poisson count model for red cards with the number of games as an offset.
pois_spec <- function(data, st_var, label, desc) {
  g  <- glm(as.formula(paste0("redCards ~ ", st_var, " + offset(log(games))")),
            data = data, family = poisson)
  ct <- lmtest::coeftest(g, vcov = sandwich::vcovCL(g, cluster = ~ playerShort + refNum))
  b  <- ct[st_var, 1]; se <- ct[st_var, 2]
  data.frame(spec = label, description = desc, engine = "GLM Poisson, cluster-robust (CR2)",
             n_rows = nrow(data), n_events = sum(data$redCards),
             or = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
             p = ct[st_var, 4], stringsAsFactors = FALSE)
}

# Mixed model adjusting for club without separating the many club fixed effects.
glmm_club_spec <- function(data, st_var, label, desc) {
  form <- as.formula(paste0("cbind(redCards, games - redCards) ~ ", st_var,
                            " + leagueCountry + (1|playerShort) + (1|club)"))
  fit <- lme4::glmer(form, data = data, family = binomial, nAGQ = 0)
  b   <- lme4::fixef(fit)[st_var]
  se  <- sqrt(diag(as.matrix(vcov(fit))))[st_var]
  data.frame(spec = label, description = desc, engine = "Mixed model",
             n_rows = nrow(data), n_events = sum(data$redCards),
             or = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
             p = 2 * pnorm(-abs(b / se)), stringsAsFactors = FALSE)
}

# =============================================================================
# 1. PRIMARY + 2. ROBUSTNESS GRID
# =============================================================================
gtot <- aggregate(games ~ playerShort, data = m, FUN = sum)
keep <- gtot$playerShort[gtot$games >= 20]

specs <- list(
  list(f = function() cr2_spec(
    m, "st", "red", "",
    "PRIMARY: mean skin tone, red cards, cluster-robust GLM",
    "average of both raters; red cards; population-averaged logistic with SE clustered by player and referee (n=124,621)")),
  list(f = function() cr2_spec(m, "st_r1", "red", "", "Rater 1 only",
    "use one rater's skin-tone rating instead of the average")),
  list(f = function() cr2_spec(m, "st_r2", "red", "", "Rater 2 only",
    "use the other rater's skin-tone rating")),
  list(f = function() cr2_spec(m, "dark", "red", "", "Binary dark (>0.5) vs light",
    "dichotomise skin tone instead of treating it as continuous")),
  list(f = function() cr2_spec(m, "st", "sendoff", "", "Outcome = all send-offs (red + 2nd yellow)",
    "count second-yellow dismissals as red cards too")),
  list(f = function() cr2_spec(m, "st", "red", "position", "Adjust for player position",
    "add 12-level position fixed effect")),
  list(f = function() cr2_spec(m, "st", "red", "position + height + bmi + age",
    "Adjust for position, height, BMI, age",
    "add player physical and age covariates")),
  list(f = function() glmm_club_spec(m, "st",
    "Adjust for league country and club (club as random intercept)",
    "mixed model: league country fixed, player and club random intercepts")),
  list(f = function() cr2_spec(m[m$position != "Goalkeeper", ], "st", "red", "",
    "Exclude goalkeepers", "drop goalkeepers, who rarely get red cards")),
  list(f = function() pois_spec(m, "st",
    "Poisson model, log(games) offset",
    "count model for red cards instead of binomial; cluster-robust SE")),
  list(f = function() player_spec(m, "Player-level aggregation",
    "one row per player: career red cards / career games, ordinary logistic"))
)

grid_list <- lapply(specs, function(s) {
  cat("fitting:", "\n"); flush.console()
  r <- tryCatch(s$f(), error = function(e) data.frame(
    spec = "FAILED", description = conditionMessage(e), engine = "FAILED",
    n_rows = NA, n_events = NA, or = NA, lo = NA, hi = NA, p = NA,
    stringsAsFactors = FALSE))
  cat("  ->", ifelse(is.na(r$or), paste("FAILED:", r$description),
                     sprintf("%s  OR %.3f [%.3f, %.3f]", r$spec, r$or, r$lo, r$hi)), "\n")
  flush.console()
  r
})

grid <- do.call(rbind, grid_list)
write.csv(grid, file.path(dir, "estimates.csv"), row.names = FALSE)

main <- grid[1, ]
cat(sprintf("\nPRIMARY OR per 1-unit (lightest -> darkest) = %.3f (95%% CI %.3f-%.3f), p=%.4f\n",
            main$or, main$lo, main$hi, main$p))

# =============================================================================
# 3. FOREST PLOT
# =============================================================================
grid$spec_f <- factor(grid$spec, levels = rev(grid$spec))
p <- ggplot(grid, aes(x = or, y = spec_f)) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "grey40") +
  geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.18, colour = "grey30") +
  geom_point(aes(colour = engine), size = 2.7) +
  scale_x_log10() +
  labs(x = "Odds ratio per 1-unit increase in skin tone (95% CI)",
       y = NULL, colour = "Engine",
       title = "Robustness of the red-card / skin-tone association",
       subtitle = "Dashed line: OR = 1 (no association)") +
  theme_bw(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(dir, "robustness.png"), p, width = 9, height = 6.2, dpi = 150)
cat("\nWrote robustness.png and estimates.csv\n")

# =============================================================================
# 4. COMPARISON WITH THE 29 PUBLISHED TEAM ESTIMATES (OSF fa743)
# =============================================================================
osf_url  <- "https://osf.io/download/fa743/"
osf_file <- file.path(dir, "osf_fa743")
if (!file.exists(osf_file)) download.file(osf_url, osf_file, mode = "wb", quiet = TRUE)
osf <- read.csv(osf_file, check.names = FALSE)
osf$OR <- as.numeric(osf$OR); osf$OR_lo <- as.numeric(osf$OR_lo); osf$OR_hi <- as.numeric(osf$OR_hi)

cat(sprintf(paste0("\n--- 29 published team estimates (OSF fa743) ---\n",
                   "n teams = %d; median OR = %.3f; mean OR = %.3f\n",
                   "range = %.3f to %.3f; %d of %d CIs exclude 1\n",
                   "my primary OR = %.3f; rank = %d of %d (%.0fth percentile)\n"),
            nrow(osf), median(osf$OR), mean(osf$OR), min(osf$OR), max(osf$OR),
            sum(osf$OR_lo > 1 | osf$OR_hi < 1), nrow(osf),
            main$or, sum(osf$OR < main$or) + 1, nrow(osf) + 1,
            100 * (sum(osf$OR < main$or) + 1) / (nrow(osf) + 1)))

# Combined figure: 29 teams plus this analysis.
osf$Team  <- factor(paste0("Team ", osf$Team), levels = paste0("Team ", osf$Team)[order(osf$OR)])
osf$panel <- "29 published team estimates"
mine <- data.frame(Team = "This analysis", OR = main$or, OR_lo = main$lo,
                   OR_hi = main$hi, panel = "This analysis")
cmp <- rbind(osf[, c("Team", "OR", "OR_lo", "OR_hi", "panel")], mine)
cmp$Team <- factor(cmp$Team, levels = c("This analysis",
                                        levels(osf$Team)[order(osf$OR)]))
pc <- ggplot(cmp, aes(x = OR, y = Team)) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "grey40") +
  geom_errorbar(aes(xmin = OR_lo, xmax = OR_hi, colour = panel),
                orientation = "y", width = 0.18) +
  geom_point(aes(colour = panel), size = 2.4) +
  scale_x_log10() +
  scale_colour_manual(values = c("This analysis" = "firebrick",
                                 "29 published team estimates" = "grey40")) +
  labs(x = "Odds ratio per 1-unit increase in skin tone (95% CI)", y = NULL,
       colour = NULL, title = "This analysis among the 29 published estimates",
       subtitle = "Source: https://osf.io/download/fa743/") +
  theme_bw(base_size = 10) +
  theme(legend.position = "bottom")
ggsave(file.path(dir, "comparison.png"), pc, width = 9, height = 7, dpi = 150)
cat("Wrote comparison.png\n")
write.csv(osf[, c("Team", "Analytic.Approach", "OR", "OR_lo", "OR_hi")],
          file.path(dir, "teams29.csv"), row.names = FALSE)
