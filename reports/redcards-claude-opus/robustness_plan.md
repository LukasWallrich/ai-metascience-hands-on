# Robustness plan and predictions

Written before any alternative model was fitted, and before the primary model's result was seen.

**Primary specification.** Binomial GLMM on player–referee dyads; red cards out of games; skin tone = mean of two raters (0–1); controls: position (missing = own level), league country; crossed random intercepts for player and referee. Odds ratio (OR) = very dark (1) vs very light (0).

**What counts as "changing the conclusion".** An alternative changes the conclusion if (a) its OR falls on the other side of 1 from the primary OR, or (b) its 95% CI stands in a different relation to 1 than the primary CI (excludes 1 vs includes 1).

| # | Alternative | Why a reasonable analyst could choose it | Prediction |
|---|---|---|---|
| A1 | Binary skin tone: dark (rater mean > 0.5) vs light (< 0.5); players rated exactly 0.5 dropped | Treats the ratings as categories and matches the "dark vs light" wording of the question | OR smaller than primary, because the contrast between group means is less than the full 0-to-1 scale. **May change the conclusion** (less power) |
| A2 | Only players whose two raters gave the same code | Removes players whose skin tone is ambiguous | Similar OR, wider CI. Unlikely to change |
| A3a | Skin tone from rater 1 only | The raters disagree on 379 of 1585 players (24%); each rater is one defensible measurement | Similar OR. Unlikely to change |
| A3b | Skin tone from rater 2 only | As A3a | Similar OR. Unlikely to change |
| A4 | No covariates (skin tone and random effects only) | Measures the total disparity, not a disparity conditional on position and league | Similar or slightly larger OR. Unlikely to change |
| A5 | Extended covariates: add height, weight, age (players missing these are dropped) | Physical build and age could relate to both skin tone and fouling style | Similar OR. Unlikely to change |
| A6 | Outcome = red cards + yellow-red cards (all dismissals) | A second yellow is also a dismissal; the question says "red cards" without saying which | OR a little closer to 1, because second yellows depend less on one referee judgement. Unlikely to change |
| A7 | Only referees with at least 50 dyads | Referees with few dyads mostly met these players outside the four leagues; their data are sparse | Similar OR, somewhat wider CI. Unlikely to change |
| A8 | Ordinary logistic regression, no random effects | The simplest model many analysts would fit | Similar OR, narrower CI (ignores clustering). Will not change the conclusion if the primary CI excludes 1; could change it if the primary CI includes 1 |
| A9 | Player-level aggregation: total red cards out of total games per player; quasi-binomial GLM with position and league | Skin tone varies only between players, so the player is the natural unit; removes the referee dimension | Similar OR, wider CI. **May change the conclusion** |

Overall expectation: every OR above 1, around 1.2–1.5 on the 0–1 scale. The binary split (A1) and the player-level model (A9) are the most likely to change the conclusion.
