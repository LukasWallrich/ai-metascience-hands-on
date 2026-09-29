"""Build report.html from report.md.

Run from the project root:  python3 build_report_html.py
Needs pandoc on PATH. The figure is embedded as base64, so report.html is a
single standalone file.
"""

import base64
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MD = ROOT / "report.md"
OUT = ROOT / "report.html"
FIG = ROOT / "output" / "robustness.png"

ABSTRACT = """
<p>This report reproduces the main result of Borjas &amp; Breznau (2026) from the authors'
replication package and tests how robust it is. The paper uses the Crowdsourced Replication
Initiative (<a href="#ref-brw">Breznau et al., 2022</a>), in which 71 teams estimated 1,253 models of
the effect of immigration on public support for social programs. Its main result: teams whose members
are pro-immigration reported average marginal effects (AMEs) 0.085 higher (SE 0.031, p = 0.008) than
teams with an anti-immigration member.</p>
<ul>
  <li><strong>Reproduction.</strong> All nine columns of Table 1 reproduce exactly (largest
  difference from the Stata log: 5&nbsp;&times;&nbsp;10<sup>&minus;8</sup>).</li>
  <li><strong>Robustness.</strong> Nine alternative analysis choices were specified before any model
  was run. Under all of them the difference stays positive, but it shrinks to 0.041&ndash;0.069. It
  stays significant at 5% under 5 of the 8 alternatives that change the estimate.</li>
  <li><strong>Key dependence.</strong> Without discipline fixed effects, none of 8 specifications
  is significant at 5%. The published specification gives the largest estimate of all 24
  combinations tested.</li>
</ul>
<p><strong>Conclusion.</strong> The headline claim holds in direction. The evidence for its size and
precision is weaker than the published table suggests.</p>
"""

REFERENCES = """
<section id="references">
<h2>References</h2>
<ol class="refs">
  <li id="ref-bb">Borjas, G. J., &amp; Breznau, N. (2026). Ideological bias in the production of
  research findings. <em>Science Advances</em>, 12(1), eadz7173.
  <a href="https://doi.org/10.1126/sciadv.adz7173">https://doi.org/10.1126/sciadv.adz7173</a>.
  Full text used for the published numbers:
  <a href="https://www.ebi.ac.uk/europepmc/webservices/rest/PMC12757037/fullTextXML">Europe PMC PMC12757037</a>.</li>
  <li id="ref-brw">Breznau, N., Rinke, E. M., Wuttke, A., et al. (2022). Observing many researchers
  using the same data and hypothesis reveals a hidden universe of uncertainty. <em>Proceedings of
  the National Academy of Sciences</em>, 119(44), e2203150119.
  <a href="https://doi.org/10.1073/pnas.2203150119">https://doi.org/10.1073/pnas.2203150119</a></li>
</ol>
</section>
"""

# Hover glosses, applied to the first occurrence of each term in body text.
GLOSSES = {
    "AME": "Average marginal effect: change in the probability of supporting social programs "
           "for a one-point rise in the immigrant share of the population",
    "fixed effects": "A separate intercept for each category (here: each discipline mix)",
    "CR1": "Cluster-robust standard errors with Stata's small-sample correction G/(G-1)·(N-1)/(N-K)",
    "HC3": "Heteroskedasticity-robust standard errors that inflate residuals of high-leverage observations",
    "winsorised": "Values beyond the cut-offs are set to the cut-off values",
    "CR2": "Bias-reduced cluster-robust standard errors (Bell-McCaffrey), better with few clusters",
    "Satterthwaite": "Degrees of freedom estimated from the data; low values mean the "
                     "estimate rests on few clusters",
    "wild cluster bootstrap": "Resamples by flipping the sign/scale of whole-team residuals; "
                              "here with the null hypothesis imposed",
    "linear probability models": "Ordinary regression with a 0/1 outcome",
    "hot-deck": "Missing values filled in from similar teams",
}


def md_to_html(md_text: str) -> str:
    return subprocess.run(
        ["pandoc", "-f", "gfm", "-t", "html", "--wrap=none"],
        input=md_text, capture_output=True, text=True, check=True,
    ).stdout


def add_glosses(html: str) -> str:
    """Wrap the first occurrence of each term that sits in text (not in tags, code or headings)."""
    for term, gloss in GLOSSES.items():
        pattern = re.compile(r"(>[^<]*?)\b(" + re.escape(term) + r")\b")
        for m in pattern.finditer(html):
            before = html[: m.start()]
            last_open = before.rfind("<")
            tag = before[last_open:last_open + 4]
            if tag.startswith(("<cod", "<h1", "<h2", "<h3", "<a ", "<abb", "<th")):
                continue
            start = m.start(2)
            html = (html[:start] + f'<abbr title="{gloss}">{term}</abbr>'
                    + html[m.end(2):])
            break
    return html


def main() -> None:
    md_text = MD.read_text(encoding="utf-8")
    md_text = re.sub(r"\A# .*\n", "", md_text)          # the page header replaces the H1
    md_text = re.sub(r"\APaper: .*\n", "", md_text.lstrip("\n"))
    body = md_to_html(md_text)

    img = base64.b64encode(FIG.read_bytes()).decode()
    body = body.replace('src="output/robustness.png"', f'src="data:image/png;base64,{img}"')
    body = body.replace("<table>", '<div class="table-wrap"><table>').replace("</table>", "</table></div>")
    body = re.sub(r"<!-- generated by analysis.R -->\n?", "", body)
    body = re.sub(r"\[(-?[\d.]+), (-?[\d.]+)\]", r'<span class="nw">[\1,&nbsp;\2]</span>', body)
    body = body.replace("<td>&lt; 0.001</td>", "<td>&lt;&nbsp;0.001</td>")
    body = add_glosses(body)

    toc = "".join(
        f'<li class="lvl{lvl}"><a href="#{hid}">{re.sub("<[^>]+>", "", txt)}</a></li>'
        for lvl, hid, txt in re.findall(r'<h([23]) id="([^"]+)">(.*?)</h\1>', body)
    )

    page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Reproduction &amp; robustness: Borjas &amp; Breznau (2026) — Claude Opus 5.5</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🧭</text></svg>">
<style>
  :root {{ --ink:#1f2328; --muted:#5b6370; --line:#d8dde3; --accent:#8c2f39; --bg-soft:#f6f7f9; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; color:var(--ink); font:16px/1.6 Charter, "Bitstream Charter", Georgia, serif; background:#fff; }}
  header.page {{ background:#1f2a36; color:#fff; padding:2.2rem 1.5rem 1.8rem; }}
  header.page .inner, main, footer {{ max-width:60rem; margin:0 auto; }}
  header.page .kicker {{ font:600 .78rem/1.2 system-ui, sans-serif; letter-spacing:.08em; text-transform:uppercase; color:#c9d3de; }}
  header.page h1 {{ font-size:1.75rem; line-height:1.25; margin:.5rem 0 .6rem; }}
  header.page .meta {{ font:.92rem/1.5 system-ui, sans-serif; color:#dfe6ee; }}
  header.page .badge {{ display:inline-block; margin-top:.8rem; padding:.3rem .7rem; border:1px solid #9fb0c2; border-radius:4px;
    font:600 .85rem system-ui, sans-serif; color:#fff; }}
  header.page a {{ color:#fff; }}
  main {{ padding:0 1.5rem 3rem; }}
  .abstract {{ background:var(--bg-soft); border-left:4px solid var(--accent); padding:1rem 1.4rem; margin:2rem 0 1.5rem; }}
  .abstract h2 {{ margin-top:.2rem; border:none; font-size:1.1rem; }}
  nav.toc {{ font:.9rem/1.5 system-ui, sans-serif; margin-bottom:2rem; }}
  nav.toc ul {{ list-style:none; padding-left:0; columns:2; }}
  nav.toc li.lvl3 {{ padding-left:1.2rem; }}
  nav.toc a {{ color:var(--muted); text-decoration:none; }}
  nav.toc a:hover {{ color:var(--accent); }}
  h2 {{ font-size:1.4rem; margin-top:2.6rem; padding-bottom:.25rem; border-bottom:1px solid var(--line); }}
  h3 {{ font-size:1.15rem; margin-top:2rem; }}
  a {{ color:#1d5b8f; }}
  code {{ font:.86em/1.4 ui-monospace, SFMono-Regular, Menlo, monospace; background:var(--bg-soft); padding:.05em .3em; border-radius:3px; }}
  .nw {{ white-space:nowrap; }}
  abbr[title] {{ text-decoration:underline dotted; cursor:help; }}
  .table-wrap {{ overflow-x:auto; margin:1rem 0 1.4rem; }}
  table {{ border-collapse:collapse; font:.84rem/1.4 system-ui, sans-serif; width:100%; }}
  th, td {{ padding:.4rem .55rem; border-bottom:1px solid var(--line); text-align:left; vertical-align:top; }}
  th {{ background:var(--bg-soft); font-weight:600; }}
  tbody tr:hover {{ background:#fbf6f6; }}
  img {{ max-width:100%; height:auto; display:block; margin:1rem auto; border:1px solid var(--line); }}
  details {{ margin:1rem 0; }}
  summary {{ cursor:pointer; font:600 .92rem system-ui, sans-serif; color:var(--muted); }}
  ol.refs li {{ margin-bottom:.6rem; }}
  footer {{ font:.82rem/1.5 system-ui, sans-serif; color:var(--muted); border-top:1px solid var(--line); padding:1rem 1.5rem 2rem; }}
</style>
</head>
<body>
<header class="page"><div class="inner">
  <div class="kicker">Computational reproduction &amp; robustness report</div>
  <h1>Ideological bias in the production of research findings: reproducing and stress-testing Borjas &amp; Breznau (2026)</h1>
  <div class="meta">Target paper: Borjas, G. J., &amp; Breznau, N. (2026). <em>Science Advances</em> 12(1).
    <a href="https://doi.org/10.1126/sciadv.adz7173">doi:10.1126/sciadv.adz7173</a></div>
  <div class="badge">Analysis and report by Claude Opus 5.5 (Anthropic) &middot; 29 September 2026</div>
</div></header>
<main>
<section class="abstract">
<h2>Abstract</h2>
{ABSTRACT}
</section>
<nav class="toc"><ul>{toc}</ul></nav>
{body}
{REFERENCES}
</main>
<footer>Generated from <code>report.md</code> by <code>build_report_html.py</code>. All numbers come from
<code>analysis.R</code> (reads <code>data/df.dta</code> only). This analysis was carried out by an AI model,
Claude Opus 5.5, and has not been reviewed by the paper's authors.</footer>
</body>
</html>
"""
    OUT.write_text(page, encoding="utf-8")
    print(f"Wrote {OUT} ({OUT.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
