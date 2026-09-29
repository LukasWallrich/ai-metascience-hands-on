# Analysis choices recorded before model fitting

The question throughout is whether storms with more feminine names have higher expected death counts, particularly among damaging storms. The reference analysis is the paper's negative binomial log-link model on all 92 supplied storms, with standardised name femininity, updated minimum pressure, normalised damage, and the femininity-by-pressure and femininity-by-damage interactions. The comparable summary is the predicted death ratio for MFI 9 versus MFI 3 at the sample's 75th percentile of damage and mean updated pressure. The binary-name analysis substitutes female versus male naming for that contrast. Wald confidence intervals use the model covariance matrix. The interaction test concerns the femininity-by-damage coefficient; it is not a test of the predicted ratio at one damage value.

These alternatives and expectations were specified before fitting any models:

1. **Only 1979–2012 storms.** This is the era of alternating male and female names. Expect weaker evidence because historical naming is confounded with time and the sample shrinks.
2. **Add a linear year term.** Fatality prevention may change over decades. Expect little change if the published association is not driven by a simple time trend.
3. **Add pressure-by-damage interaction.** Storm strength may alter the relation between damage and deaths. Expect the name-by-damage evidence to weaken if the published model omitted this relevant interaction.
4. **Use log(1 + damage), with its name interaction.** Damage is highly skewed, so a nonlinear scale is reasonable. Expect the name-by-damage evidence to weaken if a few costly storms drive it.
5. **Winsorise deaths and damage at their 90th percentiles.** Limit the influence of extreme storms without deleting them. Expect a weaker association if the largest storms dominate.
6. **Exclude the three storms with the most deaths in the supplied data.** This is a simple influence check. Expect weaker evidence because these extreme fatalities are all associated with feminine names.
7. **Use binary female versus male name, with the same interactions.** The headline uses this distinction rather than the continuous rating. Expect a similar direction but less precision because the rating contains more information.
8. **Use the original rather than updated minimum-pressure values.** Both versions are supplied. Expect little change because the measures are close.
9. **Exclude Sandy.** Its unusually costly impact and potentially ambiguous name make it an influential case. Expect a similar or stronger association, as the authors' later analysis suggested.

Each alternative changes only the stated feature of the reference model. The fixed high-damage prediction point is computed from the full 92-storm sample for every model, even when a model uses a subset or transforms damage.
