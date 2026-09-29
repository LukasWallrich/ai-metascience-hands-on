# Red cards and skin tone: main model + robustness variants. Run: Rscript analysis.R
suppressPackageStartupMessages({library(parallel); library(data.table); library(glmmTMB); library(ggplot2)})
set.seed(1)
d <- fread("CrowdstormingDataJuly1st.csv")
d <- d[!is.na(rater1) & !is.na(rater2)]
d[, skin := (rater1 + rater2) / 2]
d[, position := ifelse(position == "" | is.na(position), "Unknown", position)]
d[, age := 2013 - as.integer(substr(birthday, 7, 10))]
d[, sendoff := redCards + yellowReds]
nref <- d[, .N, by = refNum]; d[nref, ref_n := i.N, on = "refNum"]

fit_or <- function(label, formula, data, family = binomial, term = "skin", w = TRUE) {
  wt <- data$games; m <- if (w) glmmTMB(formula, data = data, family = family, weights = wt)
       else glmmTMB(formula, data = data, family = family)
  s <- summary(m)$coefficients$cond[term, ]
  data.table(model = label, OR = exp(s[1]), lo = exp(s[1] - 1.96 * s[2]), hi = exp(s[1] + 1.96 * s[2]),
             n_dyads = nrow(data), n_players = uniqueN(data$playerShort))
}
d[, prop := redCards / games]; d[, prop_so := pmin(sendoff / games, 1)]
re <- "+ (1|playerShort) + (1|refNum)"
cov <- "+ position + leagueCountry"
F <- function(y, x, extra = cov, r = re) as.formula(paste(y, "~", x, extra, r))
specs <- list(
  function() fit_or("Main", F("prop", "skin"), d),
  function() fit_or("A1 no covariates", F("prop", "skin", ""), d),
  function() fit_or("A2 + height, weight, age", F("prop", "skin", paste(cov, "+ scale(height) + scale(weight) + scale(age)")),
         d[!is.na(height) & !is.na(weight) & !is.na(age)]),
  function() fit_or("A3 rater1 only", F("prop", "rater1"), d, term = "rater1"),
  function() fit_or("A4 rater2 only", F("prop", "rater2"), d, term = "rater2"),
  function() fit_or("A5 raters agree", F("prop", "skin"), d[rater1 == rater2]),
  function() fit_or("A6 dark vs light (dichotomous)", F("prop", "dark"), d[skin <= .25 | skin >= .75][, dark := as.integer(skin >= .75)], term = "dark"),
  function() fit_or("A7 any sending-off", F("prop_so", "skin"), d),
  function() fit_or("A8 Poisson, log(games) offset", F("redCards", "skin", paste(cov, "+ offset(log(games))")), d, family = poisson, w = FALSE),
  function() fit_or("A9 GLM, no random effects", F("prop", "skin", cov, ""), d),
  function() fit_or("A10 referees with >= 22 dyads", F("prop", "skin"), d[ref_n >= 22])
)
res <- rbindlist(parallel::mclapply(specs, function(f) f(), mc.cores = 6))
# A9: replace model-based CI by player-clustered sandwich CI
X <- model.matrix(~ skin + position + leagueCountry, d)
g <- glm(prop ~ skin + position + leagueCountry, data = d, family = binomial, weights = games)
e <- d$games * (d$prop - fitted(g)); U <- rowsum(X * e, d$playerShort)
B <- vcov(g)
V <- B %*% crossprod(U) %*% B; se <- sqrt(V["skin", "skin"])
res[model == "A9 GLM, no random effects", `:=`(lo = exp(coef(g)["skin"] - 1.96 * se), hi = exp(coef(g)["skin"] + 1.96 * se))]
fwrite(res, "results_own.csv")
print(res, digits = 3)
res[, model := factor(model, rev(model))]
p <- ggplot(res, aes(OR, model)) + geom_vline(xintercept = 1, linetype = 2, colour = "grey50") +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, orientation = "y") + geom_point(size = 2) +
  labs(x = "Odds ratio, very dark vs very light (95% CI)", y = NULL) + theme_minimal(12)
ggsave("fig_robustness.png", p, width = 7, height = 4, dpi = 150)
