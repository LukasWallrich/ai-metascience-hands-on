"""Build report.html from report.md: header, abstract, contents, embedded figures, references.

Run from this folder: python3 build_report_html.py  (needs pandoc on PATH)
"""
import base64
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).parent

ABSTRACT = """
<p><strong>Question.</strong> Are soccer referees more likely to give red cards to dark-skin-toned
players than to light-skin-toned players?</p>
<p><strong>Data.</strong> The <em>many analysts, one dataset</em> data (Silberzahn et al., 2018):
146,028 player&ndash;referee pairs, covering 2,053 players from the 2012&ndash;13 first divisions of
England, France, Germany and Spain and the 3,147 referees they played under. Two raters coded skin
tone from photos for 1,585 players.</p>
<p><strong>Method.</strong> A binomial <abbr title="generalised linear mixed model">GLMM</abbr> of red
cards out of games in each pair, with crossed random intercepts for player and referee, controlling
for position and league.</p>
<p><strong>Result.</strong> A player rated very dark had higher odds of a red card than a player rated
very light: <strong><abbr title="odds ratio">OR</abbr> = 1.38, 95%
<abbr title="confidence interval">CI</abbr> [1.12, 1.70]</strong>.</p>
<p><strong>Robustness.</strong> Ten alternative specifications, listed with predictions before they
were run, changed the skin-tone measure, covariates, outcome, sample and model. They gave ORs of
1.20&ndash;1.40, and every CI excluded 1.</p>
<p><strong>Comparison.</strong> The estimate lies near the middle of the 29 original teams&rsquo;
estimates (median 1.31) and close to those of the teams that fitted similar mixed models.</p>
<p><strong>Conclusion.</strong> The data show a consistent disparity in red cards. They cannot show
that referee bias causes it, because player behaviour is not measured.</p>
"""

REFERENCES = """
<h2 id="references">References</h2>
<ul class="refs">
<li>Brooks, M. E., Kristensen, K., van Benthem, K. J., Magnusson, A., Berg, C. W., Nielsen, A.,
Skaug, H. J., M&auml;chler, M., &amp; Bolker, B. M. (2017). glmmTMB balances speed and flexibility
among packages for zero-inflated generalized linear mixed modeling. <em>The R Journal, 9</em>(2), 378.
<a href="https://doi.org/10.32614/RJ-2017-066">https://doi.org/10.32614/RJ-2017-066</a></li>
<li>Silberzahn, R., Uhlmann, E. L., Martin, D. P., et al. (2018). Many analysts, one data set: Making
transparent how variations in analytic choices affect results. <em>Advances in Methods and Practices
in Psychological Science, 1</em>(3), 337&ndash;356.
<a href="https://doi.org/10.1177/2515245917747646">https://doi.org/10.1177/2515245917747646</a></li>
<li>Crowdstorming project data and materials, OSF:
<a href="https://osf.io/gvm2z/">https://osf.io/gvm2z/</a>. Team estimates:
<a href="https://osf.io/download/fa743/">https://osf.io/download/fa743/</a></li>
</ul>
"""

CSS = """
:root { --ink:#1c1c1a; --muted:#5b5a55; --line:#e3e1da; --accent:#2a78d6; --bg:#fcfcfb; --panel:#f3f6fb; }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--ink);
  font: 17px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; }
main { max-width: 860px; margin: 0 auto; padding: 0 24px 64px; }
header.top { border-bottom: 1px solid var(--line); padding: 36px 0 20px; margin-bottom: 28px; }
.byline { display:flex; flex-wrap:wrap; gap:10px; align-items:center; margin-bottom:14px; font-size:14px; color:var(--muted); }
.badge { background:var(--accent); color:#fff; font-weight:600; padding:4px 10px; border-radius:4px; letter-spacing:.01em; }
h1 { font-size: 30px; line-height:1.25; margin: 0 0 8px; }
.subtitle { color:var(--muted); margin:0; }
.abstract { background:var(--panel); border-left:4px solid var(--accent); padding:18px 22px; border-radius:4px; margin: 0 0 28px; }
.abstract h2 { margin:0 0 8px; font-size:15px; text-transform:uppercase; letter-spacing:.06em; color:var(--muted); border:0; padding:0; }
.abstract p { margin: 6px 0; }
nav.toc { font-size:15px; margin-bottom: 32px; }
nav.toc ol { padding-left: 20px; margin: 6px 0; columns: 2; }
h2 { font-size: 23px; margin-top: 44px; padding-bottom: 6px; border-bottom: 1px solid var(--line); }
h3 { font-size: 18px; margin-top: 28px; }
.table-wrap { overflow-x:auto; margin: 14px 0 20px; }
table { border-collapse: collapse; width: 100%; font-size: 14.5px; }
th, td { border-bottom: 1px solid var(--line); padding: 6px 10px; text-align: left; vertical-align: top; }
th { background:#f1f0ec; font-weight:600; }
tbody tr:hover { background:#f7f7f4; }
code { font-size: 90%; background:#f1f0ec; padding: 1px 4px; border-radius:3px; }
figure { margin: 22px 0; }
figure img { width:100%; border:1px solid var(--line); border-radius:4px; background:#fff; }
figcaption { font-size:14px; color:var(--muted); margin-top:6px; }
.nw { white-space: nowrap; }
abbr[title] { text-decoration: underline dotted; cursor: help; }
.refs li { margin-bottom: 8px; font-size: 15px; }
footer { margin-top:48px; padding-top:16px; border-top:1px solid var(--line); font-size:13.5px; color:var(--muted); }
"""

FAVICON = ("<link rel=\"icon\" href=\"data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' "
           "viewBox='0 0 100 100'><text y='.9em' font-size='90'>⚽</text></svg>\">")


def body_from_markdown() -> str:
    html = subprocess.run(
        ["pandoc", "report.md", "-f", "markdown+autolink_bare_uris", "-t", "html5", "--wrap=none"],
        cwd=HERE, check=True, capture_output=True, text=True).stdout
    # Title and one-paragraph answer are replaced by the header and abstract
    html = re.sub(r"<h1[^>]*>.*?</h1>\s*", "", html, count=1, flags=re.S)
    html = re.sub(r"<p><strong>Answer\.</strong>.*?</p>\s*", "", html, count=1, flags=re.S)
    # Move the file list and reproduction note to an appendix before the references
    files = re.search(r"<p>Files in this folder:</p>.*?(?=<h2)", html, flags=re.S).group(0)
    html = html.replace(files, "")
    files = files.replace("<p>Files in this folder:</p>", "")
    html += '<h2 id="files-and-reproduction">Files and reproduction</h2>\n' + files
    # Figures: embed PNGs and use alt text as caption
    def embed(m):
        src, alt = m.group("src"), m.group("alt")
        data = base64.b64encode((HERE / src).read_bytes()).decode()
        return (f'<figure><img src="data:image/png;base64,{data}" alt="{alt}">'
                f"<figcaption>{alt}. Source file: <code>{src}</code>.</figcaption></figure>")
    html = re.sub(r'<figure>\s*<img src="(?P<src>[^"]+)" alt="(?P<alt>[^"]*)"\s*/?>.*?</figure>',
                  embed, html, flags=re.S)
    html = html.replace("<code>https://osf.io/download/fa743/</code>",
                        '<a href="https://osf.io/download/fa743/">https://osf.io/download/fa743/</a>')
    # Hover glosses on first use of cited methods in the body
    for term, gloss in [("Wald", "CI from estimate ± 1.96 standard errors on the log-odds scale"),
                        ("Laplace approximation", "standard fast approximation to the mixed-model likelihood"),
                        ("quasi-binomial", "binomial model with an estimated dispersion factor that rescales the SEs"),
                        ("incidence-rate ratios", "ratio of event rates from a count (Poisson-type) model")]:
        html = html.replace(term, f'<abbr title="{gloss}">{term}</abbr>', 1)
    # Keep CIs and "< .001" on one line
    html = re.sub(r"(\[\d+\.\d+, \d+\.\d+\]|&lt; \.001)", r'<span class="nw">\1</span>', html)
    html = re.sub(r"<colgroup>.*?</colgroup>\s*", "", html, flags=re.S)  # let columns size to content
    html = re.sub(r"<table>.*?</table>", lambda m: f'<div class="table-wrap">{m.group(0)}</div>', html, flags=re.S)
    return html


def toc(html: str) -> str:
    items = re.findall(r'<h2 id="([^"]+)">(.*?)</h2>', html)
    lis = "".join(f'<li><a href="#{i}">{re.sub(r"^\\d+\\.\\s*", "", t)}</a></li>' for i, t in items)
    return f'<nav class="toc"><strong>Contents</strong><ol>{lis}</ol></nav>'


def main():
    body = body_from_markdown() + REFERENCES
    page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Skin tone and red cards: re-analysis by Claude Opus 5.5</title>
{FAVICON}
<style>{CSS}</style>
</head>
<body>
<main>
<header class="top">
  <div class="byline"><span class="badge">Analysis and report by Claude Opus 5.5</span>
    <span>Anthropic AI model <code>claude-opus-5-5</code>, working in Claude Code &middot; 29 September 2026</span></div>
  <h1>Skin tone and red cards: a re-analysis of the Silberzahn et al. (2018) dataset</h1>
  <p class="subtitle">Primary analysis, analysis decisions, robustness checks, and comparison with the
  29 original analysis teams</p>
</header>
<section class="abstract"><h2>Abstract</h2>{ABSTRACT}</section>
{toc(body)}
{body}
<footer>Written by Claude Opus 5.5 (Anthropic). &ldquo;I&rdquo; in this report refers to the model.
Built from <code>report.md</code> by <code>build_report_html.py</code>.</footer>
</main>
</body>
</html>
"""
    (HERE / "report.html").write_text(page, encoding="utf-8")
    print("wrote report.html")


if __name__ == "__main__":
    main()
