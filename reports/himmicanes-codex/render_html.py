#!/usr/bin/env python3
"""Render report.md as a self-contained, readable HTML report.

Requires pandoc. Run: python render_html.py
"""

from __future__ import annotations

import base64
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
markdown = (ROOT / "report.md").read_text()
body_markdown = "## Data and reference analysis\n" + markdown.split("## Data and reference analysis\n", 1)[1]
html_body = subprocess.run(
    ["pandoc", "--from=gfm", "--to=html5", "--wrap=none"],
    input=body_markdown,
    text=True,
    capture_output=True,
    check=True,
).stdout

# Preserve the figure inside the HTML file so it opens correctly on its own.
figure = base64.b64encode((ROOT / "figure.svg").read_bytes()).decode("ascii")
html_body = html_body.replace('src="figure.svg"', f'src="data:image/svg+xml;base64,{figure}"')
html_body = re.sub(r"(<table>.*?</table>)", r'<div class="table-scroll">\1</div>', html_body, flags=re.S)
html_body = re.sub(
    r'<p>(<img src="data:image/svg\+xml;base64,[^"]+" alt="[^"]+" />)</p>',
    r'<figure>\1<figcaption>Predicted death ratios and 95% confidence intervals across the reference model and nine alternatives.</figcaption></figure>',
    html_body,
)

sections = [
    ("data-and-reference-analysis", "Reproduction"),
    ("decisions-the-article-did-not-settle-for-this-reproduction", "Analysis decisions"),
    ("alternatives-specified-before-fitting", "Prespecified alternatives"),
    ("sensitivity-results", "Sensitivity results"),
    ("conclusion", "Conclusion"),
    ("reproducibility", "Reproducibility"),
]
nav = "\n".join(f'<a href="#{anchor}">{label}</a>' for anchor, label in sections)

page = f'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light">
  <title>Female hurricane names and fatalities | Codex GPT-6-Sol</title>
  <style>
    :root {{
      --ink: #172d3d;
      --muted: #516777;
      --line: #c8d6de;
      --tint: #ecf3f6;
      --sea: #195e85;
      --storm: #183f58;
      --white: #ffffff;
    }}
    * {{ box-sizing: border-box; }}
    html {{ scroll-behavior: smooth; }}
    body {{ margin: 0; background: var(--white); color: var(--ink); font-family: "Avenir Next", Avenir, "Trebuchet MS", sans-serif; font-size: 17px; line-height: 1.68; }}
    a {{ color: var(--sea); text-underline-offset: .18em; }}
    a:hover {{ text-decoration-thickness: 2px; }}
    a:focus-visible {{ outline: 3px solid #dc8a56; outline-offset: 3px; }}
    .masthead {{ background: var(--storm); color: #f8fbfd; padding: 1.15rem 1.5rem 3.8rem; }}
    .masthead-inner {{ max-width: 1160px; margin: auto; }}
    .masthead-top {{ display: flex; justify-content: space-between; gap: 1.2rem; align-items: baseline; padding-bottom: 2.8rem; border-bottom: 1px solid #7794a6; font-size: .9rem; }}
    .masthead-top strong {{ font-weight: 700; letter-spacing: .01em; }}
    .masthead-top span {{ color: #d0e0e8; text-align: right; }}
    h1, h2 {{ font-family: "Iowan Old Style", "Baskerville", Georgia, serif; font-weight: 500; letter-spacing: -.025em; }}
    h1 {{ max-width: 920px; font-size: clamp(2.5rem, 5vw, 4.6rem); line-height: 1.12; margin: 2.8rem 0 .65rem; }}
    .subtitle {{ color: #d7e6ed; font-size: 1.12rem; margin: 0; }}
    .layout {{ max-width: 1160px; margin: auto; padding: 0 1.5rem 5rem; display: grid; grid-template-columns: 205px minmax(0, 1fr); gap: 3.5rem; }}
    .contents {{ align-self: start; position: sticky; top: 2rem; padding-top: 2.6rem; font-size: .9rem; line-height: 1.4; }}
    .contents p {{ color: var(--muted); margin: 0 0 .7rem; font-weight: 700; }}
    .contents a {{ display: block; color: var(--muted); text-decoration: none; padding: .43rem 0 .43rem .75rem; border-left: 2px solid var(--line); }}
    .contents a:hover, .contents a:focus-visible {{ border-left-color: var(--sea); color: var(--ink); }}
    main {{ min-width: 0; max-width: 810px; }}
    .abstract {{ margin-top: -2rem; padding: 1.7rem 2.1rem 1.55rem; background: var(--tint); border-left: 5px solid var(--sea); position: relative; }}
    .abstract h2 {{ margin: 0 0 .45rem; font-size: 1.55rem; line-height: 1.2; }}
    .abstract p {{ max-width: 68ch; margin: 0; font-size: 1.05rem; }}
    article {{ padding-top: 1.8rem; }}
    article h2 {{ font-size: clamp(1.7rem, 2.4vw, 2.15rem); line-height: 1.18; margin: 3.5rem 0 1.05rem; padding-top: .7rem; border-top: 1px solid var(--line); scroll-margin-top: 1.4rem; }}
    article h2:first-child {{ margin-top: 1.5rem; }}
    article p {{ max-width: 76ch; margin: 0 0 1.2rem; }}
    article ul, article ol {{ max-width: 76ch; margin: .5rem 0 1.35rem; padding-left: 1.5rem; }}
    article li {{ padding-left: .2rem; margin-bottom: .6rem; }}
    article li::marker {{ color: var(--sea); font-weight: 700; }}
    article code {{ background: #eef3f5; border-radius: 3px; padding: .07rem .27rem; font-size: .88em; }}
    .table-scroll {{ overflow-x: auto; margin: 1.5rem 0; border-top: 2px solid var(--ink); border-bottom: 1px solid var(--line); }}
    table {{ border-collapse: collapse; width: 100%; min-width: 670px; font-size: .88rem; line-height: 1.45; font-variant-numeric: tabular-nums; }}
    th, td {{ padding: .7rem .62rem; border-bottom: 1px solid #d8e2e7; vertical-align: top; }}
    th {{ text-align: left; background: var(--tint); font-weight: 700; }}
    tr:last-child td {{ border-bottom: 0; }}
    tbody tr:nth-child(even) {{ background: #f8fafb; }}
    td a {{ white-space: nowrap; }}
    figure {{ margin: 1.9rem 0 1.35rem; }}
    figure img {{ display: block; max-width: 100%; width: 100%; height: auto; border: 1px solid var(--line); }}
    figcaption {{ font-size: .85rem; color: var(--muted); line-height: 1.5; margin-top: .45rem; }}
    #conclusion + p {{ font-size: 1.08rem; border-left: 3px solid var(--sea); padding-left: 1rem; }}
    footer {{ max-width: 1160px; margin: auto; padding: 1.1rem 1.5rem 2.2rem; border-top: 1px solid var(--line); color: var(--muted); font-size: .85rem; }}
    @media (max-width: 850px) {{
      .layout {{ display: block; }}
      .contents {{ position: static; padding: 1.4rem 0 0; display: flex; flex-wrap: wrap; gap: .1rem .7rem; }}
      .contents p {{ width: 100%; }}
      .contents a {{ border-left: 0; border-bottom: 2px solid var(--line); padding: .25rem 0; }}
      .abstract {{ margin-top: 1.8rem; }}
      .masthead {{ padding-bottom: 2.5rem; }}
    }}
    @media (max-width: 560px) {{
      body {{ font-size: 16px; }}
      .masthead-top {{ display: block; padding-bottom: 1.4rem; }}
      .masthead-top span {{ display: block; text-align: left; margin-top: .1rem; }}
      h1 {{ margin-top: 1.7rem; }}
      .layout {{ padding: 0 1.05rem 3rem; }}
      .abstract {{ padding: 1.25rem 1.2rem; }}
      article h2 {{ margin-top: 2.5rem; }}
    }}
    @media (prefers-reduced-motion: reduce) {{ html {{ scroll-behavior: auto; }} }}
    @media print {{
      .masthead {{ background: white; color: black; padding-bottom: 1rem; }}
      .masthead-top span, .subtitle {{ color: #333; }}
      .layout {{ display: block; }}
      .contents {{ display: none; }}
      .abstract {{ margin-top: 0; background: white; }}
      a {{ color: inherit; }}
      h2, figure, table {{ break-inside: avoid; }}
    }}
  </style>
</head>
<body>
  <header class="masthead">
    <div class="masthead-inner">
      <div class="masthead-top"><strong>Codex GPT-6-Sol</strong><span>Reproduction and sensitivity analysis · Jung et al. (2014)</span></div>
      <h1>Female hurricane names and fatalities</h1>
      <p class="subtitle">A reproduction of the archival result and nine defensible alternative analyses</p>
    </div>
  </header>
  <div class="layout">
    <nav class="contents" aria-label="Contents"><p>On this page</p>{nav}</nav>
    <main>
      <section class="abstract" aria-labelledby="abstract-title">
        <h2 id="abstract-title">Abstract</h2>
        <p>I reproduced the published negative binomial result for 92 US hurricanes: the interaction between name femininity and normalised damage matches the published coefficient (β = 0.705). Across nine prespecified alternatives, six retain a statistically significant interaction, but only one of ten predicted high-damage death-ratio intervals excludes 1. The archival data support a model-dependent association; they do not establish that a storm’s name causes deaths.</p>
      </section>
      <article>
{html_body}
      </article>
    </main>
  </div>
  <footer>Prepared by Codex GPT-6-Sol · <a href="report.md">Markdown report</a> · <a href="analyse.py">Analysis code</a> · <a href="analysis_plan.md">Prespecified choices</a></footer>
</body>
</html>
'''
(ROOT / "report.html").write_text(page)
print("Wrote report.html")
