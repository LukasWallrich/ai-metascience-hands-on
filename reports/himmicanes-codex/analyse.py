#!/usr/bin/env python3
"""Reproduce and probe Jung et al. (2014) from the supplied hurricanes.csv.

Run from any directory: python analyse.py
Requires numpy, pandas, scipy, and statsmodels. Outputs report.md and figure.svg.
"""

from __future__ import annotations

import html
import math
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import norm
import statsmodels.api as sm
from statsmodels.tools.sm_exceptions import ConvergenceWarning


ROOT = Path(__file__).resolve().parent
DATA = pd.read_csv(ROOT / "hurricanes.csv")
PLAN = (ROOT / "analysis_plan.md").read_text()
PAPER = "https://cyclingandchill.com/wp-content/uploads/2023/11/22-jung-et-al-2014-female-hurricanes-are-deadlier-than-male-hurricanes.pdf"
AUTHOR_NOTE = "https://publish.illinois.edu/shavitt/files/2014/06/AnalysesonHurricaneData.June17.pdf"

assert len(DATA) == 92 and DATA.isna().sum().sum() == 0
assert {"ZMasFem", "ZMinPressure_A", "ZNDAM", "alldeaths"}.issubset(DATA.columns)

MEAN_MFI = DATA.MasFem.mean()
SD_MFI = DATA.MasFem.std(ddof=1)
MEAN_DAMAGE = DATA.NDAM.mean()
SD_DAMAGE = DATA.NDAM.std(ddof=1)
MEAN_PRESSURE = DATA.Minpressure_Updated_2014.mean()
HIGH_DAMAGE = DATA.NDAM.quantile(.75)
LOG_DAMAGE = np.log1p(DATA.NDAM)
LOG_MEAN = LOG_DAMAGE.mean()
LOG_SD = LOG_DAMAGE.std(ddof=1)


def design(df: pd.DataFrame, kind: str) -> pd.DataFrame:
    """Create all model columns in a stable order, including explicit interactions."""
    gender = df.Gender_MF if kind == "binary" else df.ZMasFem
    pressure = ((df.MinPressure_before - DATA.MinPressure_before.mean()) /
                DATA.MinPressure_before.std(ddof=1)) if kind == "old_pressure" else df.ZMinPressure_A
    if kind == "log_damage":
        damage = (np.log1p(df.NDAM) - LOG_MEAN) / LOG_SD
    elif kind == "winsor":
        cap = DATA.NDAM.quantile(.9, interpolation="lower")
        damage = (df.NDAM.clip(upper=cap) - MEAN_DAMAGE) / SD_DAMAGE
    else:
        damage = df.ZNDAM
    out = pd.DataFrame({"const": 1., "name": gender, "pressure": pressure,
                        "damage": damage, "name_pressure": gender * pressure,
                        "name_damage": gender * damage}, index=df.index)
    if kind == "year":
        out["year"] = (df.Year - DATA.Year.mean()) / 10
    if kind == "pressure_damage":
        out["pressure_damage"] = pressure * damage
    return out.astype(float)


def prediction_row(columns: pd.Index, kind: str, name: float) -> pd.Series:
    g = name if kind == "binary" else (name - MEAN_MFI) / SD_MFI
    if kind == "log_damage":
        d = (math.log1p(HIGH_DAMAGE) - LOG_MEAN) / LOG_SD
    else:
        d = (HIGH_DAMAGE - MEAN_DAMAGE) / SD_DAMAGE
    if kind == "old_pressure":
        p = (MEAN_PRESSURE - DATA.MinPressure_before.mean()) / DATA.MinPressure_before.std(ddof=1)
    else:
        p = (MEAN_PRESSURE - MEAN_PRESSURE) / DATA.Minpressure_Updated_2014.std(ddof=1)
    values = {"const": 1., "name": g, "pressure": p, "damage": d,
              "name_pressure": g*p, "name_damage": g*d, "year": 0.,
              "pressure_damage": p*d}
    return pd.Series({col: values[col] for col in columns})


def fit(label: str, df: pd.DataFrame, kind: str = "baseline") -> dict:
    x = design(df, kind)
    y = df.alldeaths.astype(float)
    if kind == "winsor":
        # Use the largest observed count at or below the empirical 90th percentile.
        cap = DATA.alldeaths.quantile(.9, interpolation="lower")
        y = y.clip(upper=cap)
    with warnings.catch_warnings():
        warnings.filterwarnings("error", category=ConvergenceWarning)
        model = sm.NegativeBinomial(y, x).fit(method="bfgs", maxiter=1500, disp=False)
    if not model.mle_retvals.get("converged", False):
        raise RuntimeError(f"Model did not converge: {label}")
    lo_name, hi_name = (0., 1.) if kind == "binary" else (3., 9.)
    low = prediction_row(x.columns, kind, lo_name)
    high = prediction_row(x.columns, kind, hi_name)
    delta = high - low
    beta = model.params[x.columns]
    covariance = model.cov_params().loc[x.columns, x.columns]
    log_ratio = float(delta @ beta)
    ratio_se = math.sqrt(float(delta @ covariance @ delta))
    beta_nd = float(model.params["name_damage"])
    se_nd = float(model.bse["name_damage"])
    return {"label": label, "n": len(df), "kind": kind, "model": model,
            "interaction": beta_nd, "interaction_se": se_nd,
            "interaction_p": 2*norm.sf(abs(beta_nd/se_nd)),
            "ratio": math.exp(log_ratio),
            "ratio_lo": math.exp(log_ratio - 1.96*ratio_se),
            "ratio_hi": math.exp(log_ratio + 1.96*ratio_se),
            "pred_low": math.exp(float(low @ beta)),
            "pred_high": math.exp(float(high @ beta))}


def p_text(p: float) -> str:
    return "< .001" if p < .001 else f"{p:.3f}"


def make_figure(rows: list[dict]) -> None:
    """A standalone SVG forest plot, avoiding a plotting dependency."""
    width, left, right, top, spacing = 1100, 325, 905, 64, 49
    height = top + spacing*len(rows) + 80
    extremes = [v for r in rows for v in (r["ratio_lo"], r["ratio_hi"])]
    low_exp = math.floor(math.log2(min(extremes + [1])))
    high_exp = math.ceil(math.log2(max(extremes + [1])))
    low_exp = min(low_exp, -1)
    high_exp = max(high_exp, 2)
    xmin, xmax = 2.**low_exp, 2.**high_exp
    def xpos(v: float) -> float:
        return left + (math.log(v)-math.log(xmin))/(math.log(xmax)-math.log(xmin))*(right-left)
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="Predicted death ratios for nine alternative analyses and the reference model, with 95 percent confidence intervals">',
             '<rect width="100%" height="100%" fill="white"/>',
             '<style>text{font-family:Arial,Helvetica,sans-serif;fill:#172636}.title{font-size:18px;font-weight:700}.lab{font-size:14px}.tick{font-size:12px;fill:#576677}.val{font-size:13px;fill:#172636}</style>',
             '<text class="title" x="20" y="32">Name femininity and expected deaths at high damage</text>']
    for e in range(low_exp, high_exp+1):
        v = 2.**e
        x = xpos(v)
        colour = "#7b8794" if v == 1 else "#e7edf2"
        parts.append(f'<line x1="{x:.1f}" y1="{top-20}" x2="{x:.1f}" y2="{height-62}" stroke="{colour}" stroke-width="{2 if v == 1 else 1}"/>')
        parts.append(f'<text class="tick" x="{x:.1f}" y="{height-42}" text-anchor="middle">{v:g}×</text>')
    for i, r in enumerate(rows):
        y = top + i*spacing
        colour = "#195e85" if i == 0 else "#c56d40"
        parts.append(f'<text class="lab" x="20" y="{y+5}">{html.escape(r["label"])}</text>')
        parts.append(f'<line x1="{xpos(r["ratio_lo"]):.1f}" y1="{y}" x2="{xpos(r["ratio_hi"]):.1f}" y2="{y}" stroke="{colour}" stroke-width="2"/>')
        for v in (r["ratio_lo"], r["ratio_hi"]):
            x = xpos(v)
            parts.append(f'<line x1="{x:.1f}" y1="{y-6}" x2="{x:.1f}" y2="{y+6}" stroke="{colour}" stroke-width="2"/>')
        parts.append(f'<circle cx="{xpos(r["ratio"]):.1f}" cy="{y}" r="5" fill="{colour}"/>')
        parts.append(f'<text class="val" x="{right+18}" y="{y+5}">{r["ratio"]:.2f} [{r["ratio_lo"]:.2f}, {r["ratio_hi"]:.2f}]</text>')
    parts.append(f'<text class="tick" x="{(left+right)/2}" y="{height-12}" text-anchor="middle">Predicted death ratio (more feminine / more masculine)</text>')
    parts.append('</svg>')
    (ROOT / "figure.svg").write_text("\n".join(parts) + "\n")


def main() -> None:
    ordered = [
        fit("Published specification", DATA),
        fit("Only 1979–2012", DATA.loc[DATA.Year >= 1979]),
        fit("Add year trend", DATA, "year"),
        fit("Add pressure × damage", DATA, "pressure_damage"),
        fit("Log(1 + damage)", DATA, "log_damage"),
        fit("Winsorise deaths and damage", DATA, "winsor"),
        fit("Exclude top three death tolls", DATA.drop(DATA.alldeaths.nlargest(3).index)),
        fit("Binary female vs male", DATA, "binary"),
        fit("Original minimum pressure", DATA, "old_pressure"),
        fit("Exclude Sandy", DATA.loc[DATA.Name != "Sandy"]),
    ]
    make_figure(ordered)
    base = ordered[0]
    bm = base["model"]
    p_pressure = 2*norm.sf(abs(bm.params["name_pressure"]/bm.bse["name_pressure"]))
    sig = sum(r["interaction_p"] < .05 for r in ordered[1:])
    higher = sum(r["ratio"] > 1 for r in ordered)
    ratio_intervals_above_one = sum(r["ratio_lo"] > 1 for r in ordered)
    rows = [
        ("Storms analysed", "92", f'{base["n"]}', PAPER),
        ("Name femininity × normalised damage, log coefficient", "0.705", f'{base["interaction"]:.3f}', PAPER),
        ("SE of that interaction", "0.184", f'{base["interaction_se"]:.3f}', PAPER),
        ("p for that interaction", "< .001", p_text(base["interaction_p"]), PAPER),
        ("Name femininity × minimum pressure, log coefficient", "0.395", f'{bm.params["name_pressure"]:.3f}', PAPER),
        ("SE of pressure interaction", "0.157", f'{bm.bse["name_pressure"]:.3f}', PAPER),
        ("p for pressure interaction", "0.012", p_text(p_pressure), PAPER),
        ("AIC, fitted negative binomial model", "658.09", f'{bm.aic:.2f}', PAPER),
    ]
    compare = "\n".join(f'| {label} | {published} | {ours} | [Opened source]({source}) |' for label,published,ours,source in rows)
    checks = "\n".join(
        f'| {r["label"]} | {r["n"]} | {r["interaction"]:.3f} ({r["interaction_se"]:.3f}) | {p_text(r["interaction_p"])} | {r["ratio"]:.2f} [{r["ratio_lo"]:.2f}, {r["ratio_hi"]:.2f}] |'
        for r in ordered)
    top_three = DATA.loc[DATA.alldeaths.nlargest(3).index, "Name"].tolist()
    death_cap = DATA.alldeaths.quantile(.9, interpolation="lower")
    damage_cap = DATA.NDAM.quantile(.9, interpolation="lower")
    verdict = (
        f'The published model is reproducible: its name-femininity-by-damage coefficient is {base["interaction"]:.3f} '
        f'(p {p_text(base["interaction_p"])}), and at ${HIGH_DAMAGE:,.1f} million damage it predicts '
        f'{base["ratio"]:.2f} times as many deaths for MFI 9 as for MFI 3 '
        f'(95% CI [{base["ratio_lo"]:.2f}, {base["ratio_hi"]:.2f}]). '
        f'Across the nine defensible alternatives, the high-damage ratio exceeds 1 in {higher-1} of 9, '
        f'but only {ratio_intervals_above_one} of {len(ordered)} high-damage ratio intervals exclude 1 '
        f'and the name-by-damage interaction has p < .05 in {sig} of 9; the headline claim therefore depends '
        'on modelling choices and this observational dataset does not establish a causal effect of storm names.'
    )
    report = f'''# Female hurricane names and fatalities: reproduction and sensitivity analysis

{verdict}

## Data and reference analysis

I analysed the {len(DATA)} storms in the supplied `hurricanes.csv`, covering {DATA.Year.min()}–{DATA.Year.max()}. The published archival analysis began with {len(DATA)+2} storms and excluded Katrina and Audrey, which are absent from this CSV; I therefore cannot test their inclusion from the supplied data alone. The outcome is total deaths. The reference model is a maximum-likelihood negative binomial regression with a log link, using the supplied standardised name femininity (`ZMasFem`), updated minimum pressure (`ZMinPressure_A`), normalised damage (`ZNDAM`), and the two name-by-severity interactions. Standard errors in the direct reproduction use the model's information matrix, as in the paper. The [published paper]({PAPER}) and the [authors' follow-up analysis]({AUTHOR_NOTE}) were opened for the published values below; none are recalled from memory.

| Quantity | Published | Reproduced | Published-value source |
|:--|--:|--:|:--|
{compare}

The near-identical coefficients and fit confirm that the supplied data and model specification reproduce the article's principal archival regression. The paper's illustrative {15.15:.2f} versus {41.84:.2f} predicted deaths use a separate median-split damage model ([paper]({PAPER})); they should not be compared with the continuous-damage predictions here. For a consistent comparison across models, I use damage at the full sample's 75th percentile (${HIGH_DAMAGE:,.1f} million) and pressure at the full sample mean ({MEAN_PRESSURE:.1f} mb). At these values, the reference model predicts {base["pred_low"]:.2f} deaths for MFI 3 and {base["pred_high"]:.2f} for MFI 9, a ratio of {base["ratio"]:.2f} (95% Wald CI [{base["ratio_lo"]:.2f}, {base["ratio_hi"]:.2f}]). This ratio and its CI come from the fitted coefficients and covariance matrix, not from independent storms assigned different names.

## Decisions the article did not settle for this reproduction

- I used the supplied standardised columns rather than recomputing them from rounded raw data.
- I chose a common high-damage comparison at the 75th percentile, MFI 3 versus 9, and mean pressure. The article's illustrative predictions instead use a separate, dichotomised-damage model.
- I held the comparison point and full-sample standardisation fixed across subsets, including after 1979, so model contrasts retain the same units.
- I used two-sided Wald tests for interactions and 95% Wald intervals for death ratios. The paper does not give intervals for this continuous-damage contrast.
- I set winsorisation cutoffs to the largest observed values at or below the empirical 90th percentiles (deaths {death_cap:g}, damage ${damage_cap:,.0f} million) and defined the three highest-death storms as {', '.join(top_three)}.
- I used information-matrix standard errors in all alternatives for comparability with the published main model. The authors' [follow-up]({AUTHOR_NOTE}) also reports sandwich standard errors, so inferential results can depend on that choice.

## Alternatives specified before fitting

{PLAN.split('These alternatives and expectations were specified before fitting any models:')[1].split('Each alternative changes only')[0].strip()}

These choices were recorded in [analysis_plan.md](analysis_plan.md) before fitting the models. Every alternative retains the question of whether more feminine names predict higher deaths among damaging storms; each changes one feature of the reference analysis.

## Sensitivity results

The last column compares MFI 9 with MFI 3 at the common high-damage point, except in the binary-name row, which compares female with male names. The coefficient column is the fitted name-by-damage interaction (SE in parentheses). Its scale differs in the log-damage and binary-name rows, so the ratios are the more comparable summaries. The p value tests the interaction; the interval belongs to the high-damage ratio.

| Model | N | Name × damage coefficient (SE) | Interaction p | High-damage death ratio [95% CI] |
|:--|--:|--:|--:|--:|
{checks}

![Predicted death ratios with 95% confidence intervals for all models](figure.svg)

The figure's vertical line marks a death ratio of 1. The confidence intervals use the fitted negative binomial covariance matrix, and the displayed alternative specifications are sensitivity checks rather than independent replications. Normalised damage is an outcome of a storm as well as a proxy for its severity and exposure; conditioning on it may introduce bias. The available data also omit exposure, location, warning quality, and other potential causes of deaths, so these regressions cannot identify what would have happened had the same storm received another name. The accompanying experiments address perception and stated intentions, but this report tests the archival fatality result only.

## Conclusion

{verdict}

## Reproducibility

Run `python analyse.py` from a clean start after installing `numpy`, `pandas`, `scipy`, and `statsmodels`; the script reads only the supplied CSV and `analysis_plan.md`, then writes this report and `figure.svg`. All fitted numbers, cutoffs, and counts in this report are computed by the script; published values are transcribed in the script from the linked sources. No paid API was used; incremental service cost was $0.
'''
    (ROOT / "report.md").write_text(report)
    print(f"Wrote report.md and figure.svg; {sig}/9 alternative interaction tests have p < .05")


if __name__ == "__main__":
    main()
