# Robustness plan (written before any model was run)
Main model: binomial GLMM, redCards / games per dyad, skin tone = mean of two raters (0 = very light, 1 = very dark),
fixed effects position + leagueCountry, crossed random intercepts for player and referee; players without ratings dropped.

| # | Alternative | Expect conclusion to change? |
|---|---|---|
| A1 | No covariates (random intercepts only) | No |
| A2 | Add player height, weight, age | No |
| A3 | Skin tone = rater1 only | No (slightly smaller OR) |
| A4 | Skin tone = rater2 only | No |
| A5 | Keep only players where raters agree exactly | No, wider CI |
| A6 | Dichotomised: dark (mean >= 0.75) vs light (<= 0.25), middle dropped | Possibly: OR not comparable in scale, CI wider |
| A7 | Outcome = any sending-off (redCards + yellowReds) | No |
| A8 | Poisson GLMM with log(games) offset | No (rate ratio ~ OR, rare event) |
| A9 | Logistic GLM without random effects, player-clustered SEs | Point estimate similar; CI could shift |
| A10 | Drop referees with < 22 dyads in the data | Possibly: loses many referees; CI may include 1 |

Main risk to the conclusion: the main CI is likely close to 1, so any variant that widens it may cross 1.
