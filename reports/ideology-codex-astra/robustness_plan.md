# Robustness plan recorded before analysis

Recorded after reading README.md and the authors' Stata main/robustness code, before loading the analysis data, fitting models, or inspecting numerical results. This is a prospective plan for this session, not a preregistration independent of the paper.

Research question: Do teams with more pro-immigration attitudes report more positive estimated effects of immigration on support for redistribution? The baseline is Table 1's adjusted pro- versus anti-immigration team contrast in AME, with inverse-number-of-model weights and team-clustered uncertainty. Reproduce all three ideology encodings and all three Table 1 outcomes as well.

Each alternative changes the baseline separately. Use two-sided 95% confidence intervals. A positive association and an interval excluding zero are distinct conclusions.

| Alternative | Rationale and exact choice | Expectation before analysis |
|---|---|---|
| No covariate adjustment | Regress AME on group1 and group3 alone. | Similar positive sign; magnitude and precision may change. |
| Adjust for prior beliefs | Add pbelief to the baseline controls. | Likely attenuation; could remove conventional statistical significance. Beliefs may also mediate the relationship. |
| Alternative education | Replace categorical mdegree with categorical degree1, keeping other controls. | Unlikely to change the positive/significant conclusion. |
| Equal model weights | Give every model equal weight, retain team clustering. | Potentially material change, including loss of significance, because prolific teams gain influence. |
| Peer-score weights | Use pscore/nmodel, retaining baseline controls and clusters. | Could attenuate or remove significance if lower-rated work drives the association. Changes the target weighting, not an identification strategy. |
| Continuous ideology | Replace group indicators with proindex; report its full-scale contrast, using the documented scale endpoints. | Positive direction expected; linearity could affect magnitude/significance. |
| Ideology shares | Replace group indicators with p12 and p56; compare wholly pro- with wholly anti-immigration teams (p56 minus p12). | Similar positive/significant conclusion expected. |
| Winsorise AME | Cap model AMEs at pooled empirical 1st and 99th percentiles (linear interpolation), retain baseline weights and controls. | Attenuation plausible; could remove significance if extremes drive the result. |
| Team-median AME | One median AME per team; equal team weights and baseline controls, HC3 uncertainty with residual-df t intervals. | Could weaken or remove significance if a team's mean reflects a few extreme models. |
| Leave one team out | Refit the baseline after dropping each team; show the estimate range and envelope of the individual 95% intervals, plus the number retaining positive/significant results. Keep original inverse-model weights. | Signs likely remain positive; a small number of teams could determine significance. |

The robustness table and figure will report every alternative, including any that contradict the expectations. Median, winsorisation, and weighting choices retain the substantive question but change its statistical summary/target. The leave-one-out envelope is a sensitivity display, not a confidence interval for a single estimator.
