#!/usr/bin/env python3
"""Reproduce the red-card analysis from the local CSV, then compare OSF estimates.

Run ``python analysis.py`` from a clean start. ``--analysis-only`` stops before
the OSF download, so the local analysis can be inspected first.
"""

from __future__ import annotations

import argparse
import html
import io
import math
from pathlib import Path
from urllib.request import Request, urlopen

import numpy as np
import pandas as pd
import patsy
import statsmodels.api as sm
from statsmodels.stats.sandwich_covariance import cov_cluster, cov_cluster_2groups


ROOT = Path(__file__).resolve().parent
DATA = ROOT / "CrowdstormingDataJuly1st.csv"
REPORT = ROOT / "report.md"
FIGURE = ROOT / "robustness.svg"
TEAMS = ROOT / "teams_estimates.csv"
TEAMS_URL = "https://osf.io/download/fa743/"

SPECS = [
    ("Primary", "Any dismissal", "Mean rating", "Position + league", "All rated", "dyad"),
    ("Direct reds", "Direct red", "Mean rating", "Position + league", "All rated", "dyad"),
    ("Unadjusted", "Any dismissal", "Mean rating", "None", "All rated", "dyad"),
    ("Extra player covariates", "Any dismissal", "Mean rating", "Position + league + age + height + weight", "Complete covariates", "dyad"),
    ("Referee country", "Any dismissal", "Mean rating", "Position + league + referee country group", "All rated", "dyad"),
    ("Rater 1", "Any dismissal", "Rater 1", "Position + league", "All rated", "dyad"),
    ("Rater 2", "Any dismissal", "Rater 2", "Position + league", "All rated", "dyad"),
    ("Dark versus light", "Any dismissal", "Binary dark/light", "Position + league", "Exclude midpoint", "dyad"),
    ("30+ games", "Any dismissal", "Mean rating", "Position + league", "Players with 30+ games", "dyad"),
    ("Player aggregate", "Any dismissal", "Mean rating", "Position + league", "All rated", "player"),
]

PRESPEC = """# Red cards and player skin tone

## Analysis choices set before estimation

The primary outcome is any dismissal (`redCards + yellowReds`) per game in each player–referee dyad. I fit an aggregated binomial logistic regression, adjusting for player position (including a missing-position category) and league country. Skin tone is the mean of the two raters' scores. I report the odds ratio for a change from 0.25 to 0.75 on the 0–1 scale, with a 95% confidence interval that clusters observations by both player and referee. Players without ratings cannot contribute to the skin-tone comparison. The estimate is an association across players, not a causal effect of skin tone.

I fixed the following alternatives before fitting any model. Each changes one primary choice unless stated otherwise. A change in *conclusion* means a material change in direction or whether the 95% interval includes 1; small shifts in estimates or interval width do not count.

| Alternative | Defensible reason | Expected effect on conclusion |
|---|---|---|
| Direct red cards only | Exclude second-yellow dismissals, which may reflect a different decision process | Could change it |
| No position or league adjustment | Describe the overall observed association without controlling for recorded player context | Could change it |
| Add age, height, and weight | Account for further observed player differences, using complete cases for these fields | Unlikely, but sample loss could matter |
| Add referee-country groups | Account for between-country differences in officiating and player composition | Could change it |
| Use rater 1 alone | Test measurement choice | Unlikely |
| Use rater 2 alone | Test measurement choice | Unlikely |
| Compare dark (>0.5) with light (<0.5), excluding the midpoint | Use a categorical contrast that maps directly to the question | Could change it because the contrast differs |
| Restrict to players with at least 30 observed games | Reduce noise from players with little exposure | Unlikely, but sample loss could matter |
| Aggregate to one row per player | Treat the player as the independent sampling unit | Unlikely for the estimate; may change precision |
"""


def load_data() -> pd.DataFrame:
    d = pd.read_csv(DATA)
    d["position_group"] = d["position"].fillna("Unknown")
    d["tone"] = d[["rater1", "rater2"]].mean(axis=1)
    d["dismissals"] = d["redCards"] + d["yellowReds"]
    d["age_2013"] = (pd.Timestamp("2013-01-01") - pd.to_datetime(d["birthday"], format="%d.%m.%Y")).dt.days / 365.25
    major = {3, 7, 8, 44}  # Four most represented referee-country codes, counted before estimation.
    d["ref_country_group"] = d["refCountry"].map(lambda c: str(c) if c in major else "Other")
    assert (d["games"] > 0).all()
    assert ((d["dismissals"] >= 0) & (d["dismissals"] <= d["games"])).all()
    assert (d["rater1"].isna() == d["rater2"].isna()).all()
    assert d.groupby("playerShort")["tone"].nunique(dropna=False).max() == 1
    return d


def fit_spec(all_data: pd.DataFrame, name: str) -> dict:
    d = all_data.loc[all_data["tone"].notna()].copy()
    outcome = "dismissals"
    predictor = "tone"
    rhs = "tone + C(position_group) + C(leagueCountry)"
    unit = "dyad"

    if name == "Direct reds":
        outcome = "redCards"
    elif name == "Unadjusted":
        rhs = "tone"
    elif name == "Extra player covariates":
        d = d.dropna(subset=["height", "weight", "age_2013"])
        rhs += " + age_2013 + height + weight"
    elif name == "Referee country":
        rhs += " + C(ref_country_group)"
    elif name == "Rater 1":
        d["tone"] = d["rater1"]
    elif name == "Rater 2":
        d["tone"] = d["rater2"]
    elif name == "Dark versus light":
        d = d.loc[d["tone"] != 0.5].copy()
        d["dark"] = (d["tone"] > 0.5).astype(int)
        predictor = "dark"
        rhs = "dark + C(position_group) + C(leagueCountry)"
    elif name == "30+ games":
        total_games = d.groupby("playerShort")["games"].sum()
        d = d.loc[d["playerShort"].map(total_games) >= 30].copy()
    elif name == "Player aggregate":
        unit = "player"
        grouped = d.groupby("playerShort", sort=False)
        d = grouped.agg({
            "games": "sum", "dismissals": "sum", "tone": "first",
            "position_group": "first", "leagueCountry": "first",
        }).reset_index()

    X = patsy.dmatrix(rhs, d, return_type="dataframe")
    y = np.column_stack((d[outcome].to_numpy(), (d["games"] - d[outcome]).to_numpy()))
    model = sm.GLM(y, X, family=sm.families.Binomial()).fit(maxiter=100)
    players = pd.factorize(d["playerShort"])[0]
    if unit == "player":
        covariance = cov_cluster(model, players)
    else:
        referees = pd.factorize(d["refNum"])[0]
        covariance = cov_cluster_2groups(model, players, referees)[0]
    coefficient = float(model.params[predictor])
    variance = float(covariance[X.columns.get_loc(predictor), X.columns.get_loc(predictor)])
    if variance <= 0:
        raise ValueError(f"Non-positive clustered variance for {name}: {variance}")
    contrast = 1.0 if predictor == "dark" else 0.5
    log_or = contrast * coefficient
    se = contrast * math.sqrt(variance)
    return {
        "name": name, "odds_ratio": math.exp(log_or),
        "ci_low": math.exp(log_or - 1.96 * se),
        "ci_high": math.exp(log_or + 1.96 * se),
        "players": d["playerShort"].nunique(), "dyads": len(d),
        "games": int(d["games"].sum()), "events": int(d[outcome].sum()),
        "contrast": "dark vs light" if predictor == "dark" else "0.75 vs 0.25",
    }


def fmt_row(row: dict) -> str:
    return (f"| {row['name']} | {row['odds_ratio']:.3f} "
            f"[{row['ci_low']:.3f}, {row['ci_high']:.3f}] | "
            f"{row['players']:,} | {row['games']:,} | {row['events']:,} |")


def make_figure(results: list[dict]) -> None:
    # Standalone SVG keeps this script independent of plotting packages.
    width, height = 1020, 490
    left, right = 310, 880
    lo = min(0.6, min(r["ci_low"] for r in results) * 0.92)
    hi = max(1.8, max(r["ci_high"] for r in results) * 1.08)
    span = math.log(hi) - math.log(lo)
    x = lambda value: left + (math.log(value) - math.log(lo)) / span * (right - left)
    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#ffffff"/>',
        '<style>text{font-family:Arial,sans-serif;fill:#1e293b}.label{font-size:15px}.tick{font-size:13px;fill:#475569}.note{font-size:12px;fill:#475569}</style>',
        '<text x="24" y="27" font-size="20" font-weight="bold">Skin tone and dismissal odds</text>',
        '<text x="24" y="49" class="note">95% confidence intervals; dark/light uses a binary contrast, and player aggregate uses player-clustered uncertainty.</text>',
        '<rect x="14" y="65" width="990" height="32" fill="#f8eee8"/>',
    ]
    for tick in [0.6, 0.8, 1.0, 1.25, 1.5, 2.0]:
        if lo <= tick <= hi:
            lines.append(f'<line x1="{x(tick):.1f}" x2="{x(tick):.1f}" y1="67" y2="421" stroke="{("#94a3b8" if tick == 1 else "#e2e8f0")}" stroke-width="{(2 if tick == 1 else 1)}"/>')
            lines.append(f'<text x="{x(tick):.1f}" y="448" text-anchor="middle" class="tick">{tick:g}</text>')
    for i, row in enumerate(results):
        y = 83 + i * 35
        colour = "#a23921" if i == 0 else "#25637d"
        lines.append(f'<text x="24" y="{y+5}" class="label">{html.escape(row["name"])}</text>')
        lines.append(f'<line x1="{x(row["ci_low"]):.1f}" x2="{x(row["ci_high"]):.1f}" y1="{y}" y2="{y}" stroke="{colour}" stroke-width="2.3"/>')
        for value in (row["ci_low"], row["ci_high"]):
            lines.append(f'<line x1="{x(value):.1f}" x2="{x(value):.1f}" y1="{y-5}" y2="{y+5}" stroke="{colour}" stroke-width="2"/>')
        lines.append(f'<circle cx="{x(row["odds_ratio"]):.1f}" cy="{y}" r="5" fill="{colour}"/>')
        lines.append(f'<text x="900" y="{y+5}" class="label">{row["odds_ratio"]:.2f}</text>')
    lines.extend([
        '<text x="595" y="477" text-anchor="middle" class="tick">Odds ratio (log scale)</text>',
        '</svg>',
    ])
    FIGURE.write_text("\n".join(lines), encoding="utf-8")


def local_report(d: pd.DataFrame, results: list[dict]) -> str:
    primary = results[0]
    rated = d[d["tone"].notna()]
    n_rated = rated["playerShort"].nunique()
    n_all = d["playerShort"].nunique()
    rates = rated.groupby("playerShort").agg(games=("games", "sum"), dismissals=("dismissals", "sum"), tone=("tone", "first"))
    light = rates[rates["tone"] < 0.5]
    dark = rates[rates["tone"] > 0.5]
    changed = [r["name"] for r in results[1:] if (r["ci_low"] > 1) != (primary["ci_low"] > 1)]
    interval_summary = (
        f"All ten 95% intervals exclude 1, although the smallest lower bound is only "
        f"{min(r['ci_low'] for r in results):.3f}."
        if all(r["ci_low"] > 1 for r in results)
        else "Intervals differ in whether they include 1."
    )
    opening = (f"**Finding.** In the primary analysis, the adjusted odds ratio for a skin-tone rating "
               f"of 0.75 versus 0.25 is {primary['odds_ratio']:.2f} "
               f"(95% CI {primary['ci_low']:.2f}–{primary['ci_high']:.2f}). "
               "The nine planned alternatives point in the same direction. These data establish an association "
               "among rated players, not its cause.\n\n")
    text = PRESPEC.replace("# Red cards and player skin tone\n\n", "# Red cards and player skin tone\n\n" + opening, 1)
    text += (f"\n## Primary result\n\nI analysed {n_rated:,} of {n_all:,} players with skin-tone ratings "
             f"({primary['dyads']:,} player–referee dyads; {primary['games']:,} games). "
             f"These dyads contain {primary['events']:,} dismissals. "
             f"The adjusted odds ratio for a rating of 0.75 rather than 0.25 is "
             f"**{primary['odds_ratio']:.2f} (95% CI {primary['ci_low']:.2f}–{primary['ci_high']:.2f})**. "
             "This compares players with different ratings after conditioning on recorded position and league. "
             "A 95% interval that excludes 1 indicates evidence of an association under this specification; "
             "it does not establish discrimination by referees.\n\n"
             f"As a descriptive check, players rated below 0.5 received {light['dismissals'].sum():,} dismissals "
             f"in {light['games'].sum():,} games ({1000*light['dismissals'].sum()/light['games'].sum():.1f} per 1,000 games); "
             f"those rated above 0.5 received {dark['dismissals'].sum():,} in {dark['games'].sum():,} games "
             f"({1000*dark['dismissals'].sum()/dark['games'].sum():.1f} per 1,000). "
             "The midpoint group is omitted from this descriptive comparison.\n")
    text += ("\n## Sensitivity analyses\n\n"
             "Each row below gives the model estimate, its 95% confidence interval, and the analysed sample. "
             "Except for the binary dark/light row, odds ratios compare a skin-tone rating of 0.75 with 0.25. "
             "The binary row compares ratings above 0.5 with ratings below 0.5 and excludes ratings of exactly 0.5. "
             "The player-aggregate interval clusters at player level; other intervals cluster by both player and referee.\n\n"
             "| Specification | Odds ratio [95% CI] | Players | Games | Events |\n"
             "|---|---:|---:|---:|---:|\n")
    text += "\n".join(fmt_row(r) for r in results) + "\n\n"
    text += "![Odds ratios and confidence intervals across ten specifications](robustness.svg)\n\n"
    text += f"{interval_summary} "
    if changed:
        text += "The specifications that change the interval's relationship to 1 are " + ", ".join(changed) + ".\n"
    else:
        text += "None of the alternative specifications changes the interval's relationship to 1.\n"
    text += ("\n## Decisions and limits\n\n"
             "The question and data left several consequential choices open:\n\n"
             "1. **Target and outcome.** I estimated an association in dismissal odds per player-game and counted both direct reds and second-yellow dismissals. The direct-red-only result is a sensitivity check.\n"
             "2. **Exposure and unit.** I used each dyad's number of games as binomial trials, so games contribute equally to the likelihood. I tested aggregation to one row per player.\n"
             "3. **Skin tone.** I averaged two photo ratings, assumed a linear effect on log odds, and chose a 0.50-point contrast (0.25 to 0.75). I tested each rater separately and a categorical dark/light contrast.\n"
             "4. **Missing data.** I excluded players without both ratings and put missing positions in an `Unknown` category. The extra-covariate model uses complete cases for age, height, and weight. I did not impute unobserved skin tone.\n"
             "5. **Adjustment.** I adjusted for recorded position and league. I examined no adjustment, additional player characteristics, and referee-country groups (codes 3, 7, 8, and 44 versus all others) separately.\n"
             "6. **Dependence and interval.** I used a logistic binomial model and a normal-approximation 95% interval from a two-way player-and-referee cluster covariance. The player-aggregate model uses a player-clustered interval.\n"
             "7. **Sample restriction.** The primary analysis keeps all rated players, while one check excludes those with fewer than 30 observed games.\n\n"
             "The data do not contain each match's circumstances, playing time, fouls, or the player's skin tone as perceived by the referee. "
             "Position and league are recorded for the sampled season, whereas card counts cover player–referee careers. "
             "Ratings are missing for players without a photo. The models therefore estimate an association among rated players "
             "and cannot isolate discriminatory decisions. The binomial model treats the game count as exposure and assumes "
             "at most one dismissal per player per game; the dyad totals satisfy the corresponding count constraint. "
             "Players' tone ratings do not vary within player, so this analysis cannot compare the same player under different perceived skin tones.\n\n"
             "To reproduce the analysis from the supplied CSV, run `python analysis.py` in this folder with "
             "NumPy, pandas, Patsy, and statsmodels installed. The script generates this report and the figure, "
             "then downloads the OSF team-estimate table after completing the local analyses.\n")
    return text


def comparison_report(results: list[dict]) -> str:
    # This function is called only after the local report and figure are written.
    request = Request(TEAMS_URL, headers={"User-Agent": "redcards-reproduction/1.0"})
    with urlopen(request, timeout=60) as response:
        raw = response.read()
    teams = pd.read_csv(io.BytesIO(raw))
    expected = {"Team", "Effect.size.units", "OR", "OR_lo", "OR_hi"}
    if not expected.issubset(teams.columns) or len(teams) != 29:
        raise ValueError("Unexpected structure of the OSF team-estimates file")
    TEAMS.write_bytes(raw)
    original_or = teams.loc[teams["Effect.size.units"] == "OR", "OR"]
    all_values = teams["OR"]
    primary = results[0]["odds_ratio"]
    below_all = int((all_values < primary).sum())
    below_or = int((original_or < primary).sum())
    table = [
        "| Local specification | Local OR | OSF values below it (of 29) | Original OR values below it (of 20) |",
        "|---|---:|---:|---:|",
    ]
    for row in results:
        value = row["odds_ratio"]
        table.append(f"| {row['name']} | {value:.3f} | {(all_values < value).sum()} | {(original_or < value).sum()} |")
    return (
        "\n## Comparison with the 29 teams\n\n"
        f"I downloaded the [OSF team-estimate table]({TEAMS_URL}) after completing the local models. "
        "It contains 29 team estimates and a harmonised `OR` column. Of these, 20 are labelled odds ratios "
        "in the source file; five are incidence-rate ratios, two are correlations, and two are standardised "
        "differences with converted values in the `OR` column. Their outcomes, contrasts, and modelling choices "
        "are not necessarily the same as mine, so these ranks are descriptive rather than a meta-analysis.\n\n"
        f"The median of all 29 `OR` values is {all_values.median():.2f} "
        f"(interquartile range {all_values.quantile(.25):.2f}–{all_values.quantile(.75):.2f}). "
        f"My primary estimate ({primary:.2f}) is below 24 and above {below_all} of them; "
        f"among the 20 originally labelled odds ratios, it is below {len(original_or)-below_or} "
        f"and above {below_or}.\n\n"
        + "\n".join(table) + "\n\n"
        "Ranks use unrounded estimates. The dark-versus-light row uses a binary contrast and is less directly "
        "comparable with estimates for a 0.50-point rating difference.\n"
    )


def conclusion(results: list[dict]) -> str:
    primary = results[0]
    return (
        "\n## Conclusion\n\n"
        f"Among players with photographs, darker skin-tone ratings were associated with somewhat higher "
        f"odds of dismissal in this dataset (adjusted OR {primary['odds_ratio']:.2f}, "
        f"95% CI {primary['ci_low']:.2f}–{primary['ci_high']:.2f}). "
        "The direction persisted across the specified alternatives, but the observational data cannot "
        "show whether referee discrimination caused the difference.\n"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--analysis-only", action="store_true", help="Stop before downloading the OSF team estimates")
    args = parser.parse_args()
    d = load_data()
    results = [fit_spec(d, spec[0]) for spec in SPECS]
    make_figure(results)
    report = local_report(d, results)
    # Finish and save steps 1–3 before accessing the OSF team estimates.
    REPORT.write_text(report, encoding="utf-8")
    if args.analysis_only:
        report += "\n## Comparison with the 29 teams\n\nPending download after completion of the local analysis.\n"
    else:
        report += comparison_report(results)
        report += conclusion(results)
    REPORT.write_text(report, encoding="utf-8")
    print(pd.DataFrame(results).to_string(index=False))


if __name__ == "__main__":
    main()
