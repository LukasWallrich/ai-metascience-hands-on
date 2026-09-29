#!/usr/bin/env python3
"""Render report.md as a self-contained styled report.html; requires Pandoc."""
from pathlib import Path
import base64
import html
import re
import subprocess

ROOT = Path(__file__).resolve().parent
source = (ROOT / 'report.md').read_text()
blocks = source.split('\n\n', 2)
assert blocks[0].startswith('# ') and blocks[1].startswith('The main adjusted association')
abstract = blocks[1].replace('report AMEs', 'report average marginal effects (AMEs)')
body_md = blocks[2]

def convert(markdown):
    return subprocess.run(['pandoc', '--from=markdown', '--to=html5', '--section-divs', '--wrap=none'],
                          input=markdown, text=True, capture_output=True, check=True).stdout

body = convert(body_md)
abstract_html = convert(abstract)
headings = re.findall(r'<section id="([^"]+)"[^>]*>\s*<h2>(.*?)</h2>', body, re.S)
nav = '\n'.join(f'<a href="#{anchor}">{title}</a>' for anchor, title in headings)
# Contain wide tables on small screens without shrinking the prose or whole page.
labels = ['Published and reproduced estimates', 'Planned alternatives and expectations', 'Sensitivity estimates']
index = 0

def wrap_table(match):
    global index
    label = labels[index]
    index += 1
    table = re.sub(r'<table\b[^>]*>', f'<table><caption>{label}</caption>', match.group(0), count=1)
    table = re.sub(r'<colgroup>.*?</colgroup>', '', table, flags=re.S)
    table = table.replace('<th>', '<th scope="col">')
    return f'<div class="table-scroll table-{index}" tabindex="0" role="region" aria-label="{label}; scroll horizontally if needed">{table}</div>'

body = re.sub(r'<table\b[^>]*>.*?</table>', wrap_table, body, flags=re.S)
assert index == len(labels)
figure_data = base64.b64encode((ROOT / 'analysis_output/robustness.png').read_bytes()).decode()
body = body.replace('src="analysis_output/robustness.png"', f'src="data:image/png;base64,{figure_data}"')
body = body.replace('<p><strong>Data-integrity finding:</strong>', '<p class="audit"><strong>Data-integrity finding:</strong>')
css = '''
:root { --ink:#20313b; --muted:#526773; --accent:#135f75; --paper:#fff; --wash:#f0f5f8; --line:#cbd9e1; }
* { box-sizing:border-box; }
html { scroll-padding-top:1.5rem; }
body { margin:0; background:var(--paper); color:var(--ink); font-family:Charter,"Bitstream Charter",Georgia,serif; font-size:18px; line-height:1.7; }
a { color:var(--accent); text-decoration-thickness:1px; text-underline-offset:.18em; overflow-wrap:anywhere; }
a:hover { text-decoration-thickness:2px; }
a:focus-visible, button:focus-visible, [tabindex]:focus-visible { outline:3px solid #a45318; outline-offset:4px; }
.skip { position:absolute; left:1rem; top:-5rem; background:white; padding:.5rem 1rem; z-index:10; }
.skip:focus { top:1rem; }
.masthead { border-top:7px solid var(--accent); background:var(--wash); padding:3.2rem 1.5rem 2.8rem; }
.header-inner { max-width:780px; margin:auto; }
.byline { font-family:"Avenir Next",Avenir,"Segoe UI",sans-serif; color:var(--accent); font-size:1.05rem; font-weight:650; margin:0 0 1.1rem; }
h1,h2,h3,nav,.actions,caption,th,footer { font-family:"Avenir Next",Avenir,"Segoe UI",sans-serif; }
h1 { font-size:clamp(2.3rem,5vw,3.65rem); font-weight:650; letter-spacing:-.045em; line-height:1.1; margin:0 0 1.3rem; max-width:18ch; }
.subtitle { font-size:1.22rem; margin:0 0 .9rem; }
.paper { font-size:.94rem; color:var(--muted); margin:0; line-height:1.55; }
.actions { display:flex; gap:1.1rem; flex-wrap:wrap; align-items:center; font-size:.86rem; margin-top:1.6rem; }
.actions button { font:inherit; color:var(--accent); background:transparent; border:1px solid #9eb7c2; padding:.35rem .75rem; border-radius:4px; cursor:pointer; }
main { width:min(1160px,calc(100% - 3rem)); margin:0 auto; padding:2.6rem 0 4rem; }
.abstract { max-width:780px; margin:0 auto 2.6rem; padding:0 0 0 1.6rem; border-left:4px solid var(--accent); }
.abstract h2 { font-size:1.15rem; margin:0 0 .7rem; color:var(--accent); }
.abstract p { font-size:1.07rem; margin:.75rem 0; }
nav { max-width:780px; margin:0 auto 2.9rem; border-block:1px solid var(--line); padding:1.1rem 0 1.3rem; }
nav h2 { font-size:.98rem; margin:0 0 .8rem; }
.nav-links { display:grid; grid-template-columns:1fr 1fr; gap:.55rem 1.5rem; font-size:.88rem; line-height:1.45; }
article > p, section > p, section > ul, section > pre, section > h2 { max-width:780px; margin-left:auto; margin-right:auto; }
article p { margin-top:1rem; margin-bottom:1.25rem; }
section { margin-top:3.5rem; }
section > h2 { font-size:1.72rem; line-height:1.25; letter-spacing:-.025em; font-weight:650; margin-top:0; margin-bottom:1.4rem; }
section > ul { padding-left:1.4rem; }
li { padding-left:.25rem; margin-bottom:1rem; }
code { font-family:"SFMono-Regular",Consolas,monospace; font-size:.83em; background:#f0f4f6; border-radius:3px; padding:.12rem .28rem; overflow-wrap:anywhere; }
pre { padding:1.2rem 1.4rem; background:var(--wash); overflow:auto; border-left:3px solid var(--line); }
pre code { background:none; padding:0; }
.table-scroll { margin:2rem 0; overflow-x:auto; border-block:1px solid var(--line); border-radius:2px; }
table { width:100%; border-collapse:collapse; font-family:"Avenir Next",Avenir,"Segoe UI",sans-serif; font-size:.88rem; line-height:1.55; font-variant-numeric:tabular-nums; }
caption { caption-side:top; text-align:left; color:var(--muted); font-size:.83rem; padding:.75rem .85rem; background:#f6f9fa; }
th { text-align:left; font-weight:650; vertical-align:bottom; background:#e9f1f5; color:#1f4c5c; }
th,td { padding:.85rem .8rem; border-bottom:1px solid #dae3e8; vertical-align:top; }
tr:last-child td { border-bottom:0; }
tbody tr:nth-child(even) { background:#f7fafb; }
table p { margin:0 !important; }
.table-1 table { min-width:980px; }
.table-1 th:nth-child(1) { width:12%; }
.table-1 th:nth-child(2) { width:18%; }
.table-1 th:nth-child(3),.table-1 th:nth-child(4) { width:15%; }
.table-1 th:nth-child(5) { width:18%; }
.table-1 td:nth-child(3),.table-1 td:nth-child(4) { white-space:nowrap; }
.table-1 td:last-child { font-size:.81rem; }
.table-2 table { min-width:690px; }
.table-2 th:first-child { width:20%; }
.table-2 th:nth-child(2) { width:44%; }
.table-3 table { min-width:810px; }
.table-3 td:nth-child(2),.table-3 td:nth-child(3) { white-space:nowrap; }
.table-3 tbody tr:first-child { font-weight:650; background:#eaf3f6; }
figure { margin:2.4rem 0 1rem; }
figure img { width:100%; height:auto; display:block; }
figcaption { font-size:.9rem; color:var(--muted); text-align:center; margin-top:.7rem; }
.audit { background:#f0f5f8; padding:1.2rem 1.4rem; border-left:3px solid #688796; font-size:.98rem; }
#does-the-headline-claim-hold-up { border-top:2px solid var(--accent); padding-top:2rem; max-width:780px; margin-left:auto; margin-right:auto; }
footer { background:var(--wash); padding:1.3rem 1.5rem; color:var(--muted); font-size:.82rem; }
footer p { max-width:780px; margin:0 auto; }
@media (max-width:650px) {
 body { font-size:17px; }
 .masthead { padding:2.2rem 1.15rem 2rem; }
 main { width:calc(100% - 2.3rem); padding-top:2rem; }
 .abstract { padding-left:1rem; }
 .nav-links { grid-template-columns:1fr; gap:.7rem; }
 section > h2 { font-size:1.48rem; }
 .table-scroll::before { content:'Scroll horizontally to read the full table'; display:block; font: .76rem/1.4 "Avenir Next",sans-serif; padding:.6rem .7rem; color:var(--muted); background:var(--wash); }
 .audit { padding:1rem; }
}
@media print {
 @page { margin:15mm; }
 body { font-size:10.5pt; line-height:1.5; color:#000; }
 .masthead { background:white; padding:0 0 1rem; border-top:3px solid var(--accent); }
 h1 { font-size:28pt; max-width:none; }
 main { width:100%; padding-top:1rem; }
 .abstract { margin-bottom:1.5rem; }
 .abstract p { font-size:10.5pt; }
 .actions,nav,.skip,footer { display:none; }
 section { margin-top:1.5rem; }
 section > h2 { font-size:16pt; break-after:avoid; }
 .table-scroll { overflow:visible; break-inside:auto; }
 .table-scroll::before { display:none; }
 .table-scroll table { min-width:0; font-size:8pt; line-height:1.35; table-layout:fixed; }
 th,td { padding:.35rem; overflow-wrap:anywhere; }
 .table-scroll td { white-space:normal !important; }
 .table-1 td:last-child { font-size:7pt; }
 thead { display:table-header-group; }
 tr,figure { break-inside:avoid; }
 a { color:inherit; }
}
'''
page = f'''<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="author" content="Codex GPT-6-Astra">
<meta name="description" content="Reproduction and sensitivity analysis of Borjas and Breznau (2026), prepared by Codex GPT-6-Astra.">
<title>Ideology and research findings | Codex GPT-6-Astra</title>
<style>{css}</style>
</head>
<body>
<a class="skip" href="#report">Skip to report</a>
<header class="masthead">
<div class="header-inner">
<p class="byline">Analysis and report by Codex GPT-6-Astra</p>
<h1>Ideology and research findings</h1>
<p class="subtitle">Reproduction and sensitivity analysis of Borjas &amp; Breznau (2026)</p>
<p class="paper">Original paper: “Ideological bias in the production of research findings”, <em>Science Advances</em>.<br><a href="https://doi.org/10.1126/sciadv.adz7173">doi:10.1126/sciadv.adz7173</a></p>
<div class="actions"><a href="report.md">Markdown source</a><a href="reproduce.py">Analysis script</a><button type="button" onclick="window.print()">Print or save as PDF</button></div>
</div>
</header>
<main id="report">
<section class="abstract" aria-labelledby="abstract-heading">
<h2 id="abstract-heading">Abstract</h2>
<p>I examine whether researchers’ immigration attitudes predict their reported estimates of immigration’s effect on support for social welfare programmes. The reproduction uses 1,253 model estimates from 71 teams, follows the published weighted regressions, and checks ten alternative analysis choices recorded before fitting models.</p>
{abstract_html}
<p>The unadjusted, continuous-ideology, and team-median analyses have confidence intervals that include zero. Every single-team omission retains a positive estimate with an interval above zero.</p>
</section>
<nav aria-label="Report sections"><h2>In this report</h2><div class="nav-links">{nav}</div></nav>
<article>{body}</article>
</main>
<footer><p>Codex GPT-6-Astra · Reproduction report. The tables, figure, and source links accompany the complete analysis in this folder.</p></footer>
</body></html>
'''
(ROOT / 'report.html').write_text(page)
print(f'Wrote report.html ({len(page):,} characters); {index} tables and {len(headings)} section links.')
