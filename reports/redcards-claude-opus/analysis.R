# Primary analysis: are dark-skin-toned players more likely to receive red cards?
# Data: CrowdstormingDataJuly1st.csv (Silberzahn et al., 2018), in this folder.
# Run from this folder: Rscript analysis.R
#
# Model: binomial GLMM on player-referee dyads.
#   outcome   red cards out of games played in the dyad (logit link)
#   predictor skin tone = mean of the two raters' codes, 0 = very light, 1 = very dark
#   controls  player position (missing = own level), league country
#   random    crossed intercepts for player and referee
# The reported odds ratio compares a very dark (1) with a very light (0) player.

suppressPackageStartupMessages({
  library(data.table)
  library(glmmTMB)
})

prep_data <- function(path = "CrowdstormingDataJuly1st.csv") {
  d <- fread(path)
  d[, skin := (rater1 + rater2) / 2]
  d[, position := fifelse(is.na(position) | position == "", "Missing", position)]
  d[, position := relevel(factor(position), ref = "Center Back")]
  d[, leagueCountry := factor(leagueCountry)]
  d[, age := as.numeric(as.Date("2013-01-01") - as.Date(birthday, "%d.%m.%Y")) / 365.25]
  d[, `:=`(playerShort = factor(playerShort), refNum = factor(refNum))]
  d[]
}

or_row <- function(fit, term = "skin", label = "") {
  ct <- summary(fit)$coefficients$cond
  b <- ct[term, "Estimate"]; se <- ct[term, "Std. Error"]
  data.table(model = label, OR = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
             p = ct[term, "Pr(>|z|)"], n_dyads = nobs(fit))
}

if (sys.nframe() == 0L) {
  d <- prep_data()
  cat("Players with skin-tone ratings:", uniqueN(d[!is.na(skin), playerShort]),
      "of", uniqueN(d$playerShort), "\n")
  dm <- d[!is.na(skin)]

  t0 <- Sys.time()
  fit <- glmmTMB(cbind(redCards, games - redCards) ~ skin + position + leagueCountry +
                   (1 | playerShort) + (1 | refNum),
                 family = binomial, data = dm)
  cat("Fit time:", format(Sys.time() - t0), "\n")
  stopifnot(isTRUE(fit$sdr$pdHess))
  print(summary(fit))

  res <- or_row(fit, label = "Primary")
  cat("\nPrimary estimate (very dark vs very light skin tone), Wald 95% CI:\n")
  print(res, digits = 3)
  fwrite(res, "primary_estimate.csv")
}
