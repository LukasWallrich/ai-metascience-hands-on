# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy==2.5.3", "pandas==3.0.6", "scipy==1.18.1", "patsy==1.0.3", "statsmodels==0.15.0", "matplotlib==3.11.2"]
# ///
"""Run `uv run reproduce.py` from any directory; no pre-existing Python state needed.
All reported estimates, tables, figure, and report.md are generated here.
The authors' supplied df.dta is the starting data, not reconstructed raw surveys.
"""
from pathlib import Path
import hashlib
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
import importlib.metadata
import numpy as np
import pandas as pd
import patsy
from scipy import stats
import statsmodels.api as sm
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'analysis_output'
OUT.mkdir(exist_ok=True)
URL = 'https://www.ebi.ac.uk/europepmc/webservices/rest/PMC12757037/fullTextXML'
ARTICLE = ROOT / 'sources/article.xml'
ARTICLE.parent.mkdir(exist_ok=True)
if not ARTICLE.exists():
    with urllib.request.urlopen(URL, timeout=60) as response:
        ARTICLE.write_bytes(response.read())
article = ET.parse(ARTICLE).getroot()
raw = pd.read_stata(ROOT / 'data/df.dta', convert_categoricals=False)
df = raw.dropna(subset=['ame', 'teamid']).copy()
# Convert Stata floats before reciprocal weights; Stata evaluates 1/nmodel in double precision.
for c in df.select_dtypes(include='number').columns:
    df[c] = df[c].astype(float)
assert not df.id.duplicated().any()
assert np.all(df.groupby('teamid').size().reindex(df.teamid).to_numpy() == df.nmodel)
assert np.allclose(df.group1 + df.group2 + df.group3, 1)
assert np.allclose(df.p12 + df.p34 + df.p56, 1)
# Stata treats numeric missing as larger than a finite number. Preserve its stored
# tail indicators; separately audit whether that convention changes any outcomes.
zstata = df.z.fillna(np.inf)
assert np.array_equal(df.neg10s, ((df.ame < -.071) & (zstata > 1.645)).astype(float))
assert np.array_equal(df.pos10s, ((df.ame > .052) & (zstata > 1.645)).astype(float))
missing_z_tail = int((df.z.isna() & ((df.ame < -.071) | (df.ame > .052))).sum())
BASE = 'stats_brw + topic_brw + t2 + t3 + C(mdegree)'
GROUP = 'group1 + group3'
CONTRAST = {'group3': 1, 'group1': -1}
teamvars = ['group1', 'group2', 'group3', 'proindex', 'p12', 'p56', 'stats_brw',
            'topic_brw', 't2', 't3', 'mdegree', 'degree1', 'pbelief']
assert (df.groupby('teamid')[teamvars].nunique().max() <= 1).all()


def fit(data, y='ame', ideology=GROUP, controls=BASE, weights='team', covariance='cluster'):
    work = data.copy()
    if weights == 'team':
        work['_weight'] = 1 / work.nmodel
    elif weights == 'peer':
        work['_weight'] = work.pscore / work.nmodel
    else:
        work['_weight'] = 1.
    work = work.loc[work._weight.notna() & (work._weight > 0)]
    formula = f'{y} ~ {ideology}' + (f' + {controls}' if controls else '')
    ym, xm = patsy.dmatrices(formula, work, return_type='dataframe')
    sample = work.loc[xm.index]
    x, yy, w = xm.to_numpy(), ym.to_numpy().ravel(), sample._weight.to_numpy()
    xw, yw = x * np.sqrt(w)[:, None], yy * np.sqrt(w)
    pinv = np.linalg.pinv(xw)
    beta = pinv @ yw
    rank = np.linalg.matrix_rank(xw)
    bread = pinv @ pinv.T
    residual = yy - x @ beta
    n = len(yy)
    g = sample.teamid.nunique()
    hc3_removed = 0
    if covariance == 'cluster':
        scores = x * (w * residual)[:, None]
        sums = pd.DataFrame(scores).groupby(sample.teamid.to_numpy()).sum().to_numpy()
        cov = bread @ (sums.T @ sums) @ bread * g/(g-1) * (n-1)/(n-rank)
        dof = g - 1
    else:
        h = np.einsum('ij,ji->i', xw, pinv)
        # Saturated singleton discipline cells contain no information about the
        # ideology contrast. Drop them before fitting HC3 instead of dividing by 0.
        singleton = h > 1 - 1e-10
        if singleton.any():
            reduced = sample.loc[~singleton].copy()
            result = fit(reduced, y, ideology, controls, weights, covariance)
            result['hc3_removed'] += int(singleton.sum())
            return result
        scores = x * (w * residual / (1-h))[:, None]
        cov = bread @ (scores.T @ scores) @ bread
        dof = n - rank
    r2 = 1 - np.sum(w * residual**2) / np.sum(w * (yy-np.average(yy, weights=w))**2)
    return dict(beta=beta, cov=cov, names=list(xm.columns), n=n, teams=int(g),
                df=int(dof), rank=int(rank), r2=r2, formula=formula,
                hc3_removed=hc3_removed, x=x, y=yy, weights=w,
                clusters=sample.teamid.to_numpy())


def contrast(model, terms):
    c = np.array([terms.get(name, 0) for name in model['names']])
    b = float(c @ model['beta'])
    se = float(np.sqrt(max(0, c @ model['cov'] @ c)))
    crit = stats.t.ppf(.975, model['df'])
    p = float(2 * stats.t.sf(abs(b/se), model['df']))
    return dict(estimate=b, se=se, lo=b-crit*se, hi=b+crit*se, p=p,
                n=model['n'], teams=model['teams'], df=model['df'], rank=model['rank'])


# Parse the journal table independently of the reconstructed estimates.
published = {}
for ri, row in enumerate(article.findall('.//table-wrap[@id="T1"]/table/tbody/tr')):
    cells = row.findall('td')
    label = ' '.join(''.join(cells[0].itertext()).split())
    for col, cell in enumerate(cells[1:], 1):
        text = ''.join(cell.itertext()).replace('−', '-')
        numbers = re.findall(r'-?\d+\.\d+', text)
        if numbers:
            published[(ri, col)] = dict(label=label, text=text,
                b=float(numbers[0]), se=float(numbers[1]) if len(numbers)>1 else None)
logpath = ROOT / 'code/Log Files/02_Main_Regs.log'
log = logpath.read_text()
models, mainrows, fullrows = {}, [], []
outcomes = [('ame','AME'), ('neg10s','Extreme negative'), ('pos10s','Extreme positive')]
encodings = [('proindex', {'proindex':1}, 'Mean sentiment: one point'),
             ('p12 + p56', {'p56':1,'p12':-1}, 'All-pro minus all-anti shares'),
             (GROUP, CONTRAST, 'Pro minus anti team')]
for oi,(y,outcome) in enumerate(outcomes):
    for ei,(ideology,terms,label) in enumerate(encodings):
        col=oi*3+ei+1
        model=fit(df,y,ideology)
        models[col]=model
        result=contrast(model,terms)
        ri=0 if ei==0 else 5
        pub=published[(ri,col)]
        # Extract exact supporting values from the authors' labelled log blocks.
        marker=f'. *Table 1, Model {col} &'
        start=log.index(marker)
        if ei==0:
            pattern=r'^\s*proindex\s*\|\s+([^\n]+)'
        else:
            pattern=r'^\s*\(1\)\s*\|\s+([^\n]+)'
        match=re.search(pattern,log[start:],re.M)
        nums=[float(v) for v in match.group(1).split()]
        line=log[:start+match.start()].count('\n')+1
        assert abs(result['estimate']-nums[0]) < 1e-6, (col,result,nums)
        assert abs(result['se']-nums[1]) < 1e-6, (col,result,nums)
        result.update(column=col, outcome=outcome, contrast=label,
                      published_estimate=pub['b'], published_se=pub['se'],
                      log_estimate=nums[0], log_se=nums[1], log_line=line,
                      source=f'{URL} (Table 1, column {col}); code/Log Files/02_Main_Regs.log:{line}')
        mainrows.append(result)
        # Independent package check of weighted clustered covariance.
        smfit=sm.WLS(model['y'],model['x'],weights=model['weights']).fit(
            cov_type='cluster',cov_kwds={'groups':model['clusters'],'use_correction':True})
        np.testing.assert_allclose(model['beta'],smfit.params,atol=1e-10)
        np.testing.assert_allclose(model['cov'],smfit.cov_params(),atol=1e-10)
        for (rowindex,c),p in published.items():
            if c != col:
                continue
            mapping={0:{'proindex':1},1:{'p12':1},2:{'p56':1},
                     3:{'group1':1},4:{'group3':1},5:terms}
            if rowindex==6:
                fullrows.append(dict(column=col,term='R squared',estimate=model['r2'],published_estimate=p['b'],
                                     source=f'{URL} (Table 1, column {col})'))
            else:
                entry=contrast(model,mapping[rowindex])
                entry.update(column=col,term=p['label'],published_estimate=p['b'],published_se=p['se'],
                             source=f'{URL} (Table 1, column {col})')
                fullrows.append(entry)
main=pd.DataFrame(mainrows)
main.to_csv(OUT/'main_comparison.csv',index=False)
pd.DataFrame(fullrows).to_csv(OUT/'full_table1_comparison.csv',index=False)

# Post-plan data-integrity audit: significance is unknown when z is missing.
# Exclude that model for the affected negative-tail outcome and re-equalise
# total weights within retained teams. This does not affect the AME analyses.
tail_complete=df.loc[df.z.notna()].copy()
tail_complete['nmodel']=tail_complete.groupby('teamid').ame.transform('size')
tail_audit=contrast(fit(tail_complete,y='neg10s'),CONTRAST)
pd.DataFrame([tail_audit]).to_csv(OUT/'negative_tail_missing_z_audit.csv',index=False)
missing_z_ids=', '.join(df.loc[df.z.isna(),'id'])

# Run all prospectively listed alternatives, without selecting on results.
rob=[]
def add(name, model, terms=CONTRAST, note=''):
    row=contrast(model,terms)
    row.update(choice=name,note=note)
    rob.append(row)
    return row
add('Baseline',models[3])
add('No covariate adjustment',fit(df,controls=''))
add('Adjust for prior beliefs',fit(df,controls=BASE+' + pbelief'))
add('Alternative education',fit(df,controls=BASE.replace('C(mdegree)','C(degree1)')))
add('Equal model weights',fit(df,weights='equal'))
add('Peer-score weights',fit(df,weights='peer'))
add('Continuous ideology (1 to 6)',models[1],{'proindex':5},'Full-scale linear contrast')
add('Ideology shares',models[2],{'p56':1,'p12':-1},'All-pro versus all-anti composition')
cutlow,cuthigh=df.ame.quantile([.01,.99],interpolation='linear')
win=df.copy()
win['ame']=win.ame.clip(cutlow,cuthigh)
add('Winsorise AME (1%, 99%)',fit(win))
teams=df.groupby('teamid',as_index=False)[teamvars].first()
teams=teams.merge(df.groupby('teamid').ame.agg(['mean','median']).reset_index(),on='teamid')
teams['ame']=teams['median']
median_model=fit(teams,weights='equal',covariance='HC3')
add('Team-median AME (HC3)',median_model,note='Singleton discipline cells dropped for HC3')
# The same contrast using all team medians must have the same point estimate.
median_all=fit(teams,weights='equal')
np.testing.assert_allclose(contrast(median_model,CONTRAST)['estimate'],
                           contrast(median_all,CONTRAST)['estimate'],atol=1e-10)
# Check the documented point-estimate equivalence of weighted models and team means.
means=teams.copy(); means['ame']=means['mean']
np.testing.assert_allclose(contrast(fit(means,weights='equal'),CONTRAST)['estimate'],
                           rob[0]['estimate'],atol=1e-10)
loo=[]
for team in sorted(df.teamid.unique()):
    r=contrast(fit(df.loc[df.teamid!=team]),CONTRAST)
    r['omitted_team']=int(team)
    loo.append(r)
loo=pd.DataFrame(loo)
loo.to_csv(OUT/'leave_one_team_out.csv',index=False)
robust=pd.DataFrame(rob)
robust.to_csv(OUT/'robustness.csv',index=False)

# Compact forest plot; leave-one-out uses a range and an interval envelope.
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10})
fig,ax=plt.subplots(figsize=(10.5,7.2),layout='constrained')
for i,r in robust.iterrows():
    color='#135f75' if r['lo']>0 else '#955326'
    ax.errorbar(r.estimate,i,xerr=[[r.estimate-r.lo],[r.hi-r.estimate]],
                fmt='o',color=color,capsize=3,lw=1.8,markersize=6)
li=len(robust)
ax.plot([loo.lo.min(),loo.hi.max()],[li,li],color='#888888',lw=1.5,label='Leave-one-out interval envelope')
ax.plot([loo.estimate.min(),loo.estimate.max()],[li,li],color='#252525',lw=6,solid_capstyle='butt',label='Leave-one-out estimate range')
ax.set_yticks(range(li+1),list(robust.choice)+['Leave one team out'])
ax.invert_yaxis()
ax.axvline(0,color='#555555',lw=1,ls='--')
ax.set_xlabel('Difference in reported AME (more pro-immigration minus more anti-immigration)')
ax.set_title('Positive estimates throughout; precision depends on analysis choices',loc='left',weight='bold',pad=14)
ax.spines[['top','right','left']].set_visible(False)
ax.grid(axis='x',alpha=.15)
ax.legend(loc='upper center',bbox_to_anchor=(.5,-.14),fontsize=8,frameon=False,ncol=2)
fig.savefig(OUT/'robustness.png',dpi=200)
fig.savefig(OUT/'robustness.svg')
plt.close(fig)

versions={p:importlib.metadata.version(p) for p in ['numpy','pandas','scipy','patsy','statsmodels','matplotlib']}
manifest={'python':sys.version,'packages':versions,'article_source':URL,
          'sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in [ROOT/'data/df.dta',logpath,ARTICLE,ROOT/'robustness_plan.md']}}
(OUT/'run_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')

def f(x): return f'{x:.4f}'
def pv(x): return '<0.001' if x<.001 else f'{x:.3f}'
def ci(r): return f'[{f(r["lo"])}, {f(r["hi"])}]'
def table(headers,rows):
    return '| '+' | '.join(headers)+' |\n| '+' | '.join(['---']*len(headers))+' |\n'+ '\n'.join('| '+' | '.join(map(str,row))+' |' for row in rows)
base=rob[0]
counts=teams[['group1','group2','group3']].sum().astype(int)
n_sig=int((robust.lo>0).sum())
alt_sig=int((robust.iloc[1:].lo>0).sum())
unsig=', '.join(robust.loc[robust.lo<=0,'choice'])
minloo=loo.loc[loo.estimate.idxmin()]
maxloo=loo.loc[loo.estimate.idxmax()]
maxp=loo.loc[loo.p.idxmax()]
plan=(ROOT/'robustness_plan.md').read_text()
plan_table=plan[plan.index('| Alternative'):plan.index('\n\nThe robustness table')]
main_table=table(['Table 1 column; outcome','Ideology contrast','Published b (SE)','Reproduced b (SE)','Reproduced 95% CI; p','Source for published b and SE'],[
    [f'{int(r.column)}; {r.outcome}',r.contrast,f'{r.published_estimate:.3f} ({r.published_se:.3f})',
     f'{f(r.estimate)} ({f(r.se)})',f'{ci(r)}; {pv(r.p)}',
     f'[Article, Table 1, col. {int(r.column)}]({URL}); [local log, line {int(r.log_line)}](code/Log%20Files/02_Main_Regs.log)']
    for _,r in main.iterrows()])
rob_table=table(['Choice','Estimate (SE)','95% interval','p','Models / teams'],[
    [r.choice,f'{f(r.estimate)} ({f(r.se)})',ci(r),pv(r.p),f'{int(r.n)} / {int(r.teams)}'] for _,r in robust.iterrows()]+[
    ['Leave one team out',f'{f(loo.estimate.min())} to {f(loo.estimate.max())} (range)',
     f'[{f(loo.lo.min())}, {f(loo.hi.max())}] (envelope)',f'{pv(loo.p.min())} to {pv(loo.p.max())}',
     f'{int(loo.n.min())}–{int(loo.n.max())} / {int(loo.teams.min())}']])
summary={
    'rows_in_file':len(raw),'models':len(df),'teams':len(teams),'group_counts':counts.to_dict(),
    'winsor_cutoffs':[cutlow,cuthigh],'missing_z':int(df.z.isna().sum()),
    'missing_z_tail':missing_z_tail,'median_singletons_removed':median_model['hc3_removed'],
    'baseline':base,'negative_tail_missing_z_audit':tail_audit,'positive_regular_fits':int((robust.estimate>0).sum()),
    'significant_regular_fits':n_sig,'positive_loo_fits':int((loo.estimate>0).sum()),
    'significant_loo_fits':int((loo.lo>0).sum()),'max_b_log_difference':float(abs(main.estimate-main.log_estimate).max()),
    'max_se_log_difference':float(abs(main.se-main.log_se).max())}
(OUT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
report=f'''# Reproduction of Borjas and Breznau: ideology and research findings

The main adjusted association reproduces: pro-immigration teams report AMEs {f(base['estimate'])} higher than anti-immigration teams (SE = {f(base['se'])}, 95% CI {ci(base)}, p = {pv(base['p'])}). Every planned analysis retains a positive point estimate, but the evidence against a zero association depends on the specification. These are associations between teams' attitudes and their reported results; they do not by themselves identify a causal effect of ideology or establish which estimates are biased.

The research question is whether teams with more pro-immigration attitudes report more positive estimates of immigration's effect on support for social welfare programmes. I reproduce all nine specifications in Table 1, then examine the AME association under the ten choices recorded in [robustness_plan.md](robustness_plan.md) before loading the data or fitting models. The checks concern this association; they do not reproduce the paper's separate decomposition of research-design mechanisms.

## Published estimates and reproduction

The primary outcome, `ame`, is the team's reported average marginal effect, in the units supplied in the package. A positive value means more immigration predicts more support for social programmes. The sample contains {len(df):,} models from {len(teams)} teams: {counts['group1']} anti-immigration, {counts['group2']} moderate, and {counts['group3']} pro-immigration. I excluded {len(raw)-len(df)} empty merge-only row from `data/df.dta`; no observed AMEs were removed from the baseline.

I followed `code/Stata Main Results/02_Main_Regs.do`: weighted least squares with weight `1/nmodel`, team-clustered standard errors, and controls for statistical skills, topic experience, team size, and categorical disciplinary composition (`mdegree`). All covariates are constant within teams, so the point estimates equal a regression of team means with equal team weights; the script verifies that equivalence. Team categories follow the supplied coding, including its priority for a pro-immigration majority when a team also includes an anti-immigration respondent. Moderate teams are the reference group; the main contrast subtracts the anti-team coefficient from the pro-team coefficient.

{main_table}

The published numbers in every row come directly from the original article's XML, opened in this session at the linked Europe PMC API URL and saved as [sources/article.xml](sources/article.xml). The script parses them, rather than using remembered values. The accompanying log locations give the authors' unrounded supporting output. All reproduced coefficients and standard errors agree with those log entries within {max(summary['max_b_log_difference'],summary['max_se_log_difference']):.2g}. The printed standard error for the positive-tail shares contrast is {main.iloc[7].published_se:.3f}; the local log gives {main.iloc[7].log_se:.7f}, reproduced as {main.iloc[7].se:.7f}, which rounds to {main.iloc[7].se:.3f}. This is a small printed-table discrepancy. I report calculated p values rather than reproducing significance stars. The [full table comparison](analysis_output/full_table1_comparison.csv) also includes every individual ideology coefficient and the R² values.

The tail outcomes use the supplied definitions: `ame < −0.071` or `ame > 0.052`, combined with `|z| > 1.645`. These cut-offs come from `code/Stata Main Results/01_Data_Prep.do`; the article's “Baseline evidence” section explicitly identifies the significance test as one-sided. Tail-outcome coefficients are probability differences, so multiplying them by 100 gives percentage-point differences.

**Data-integrity finding:** {int(df.z.isna().sum())} usable model lacks a z statistic (`{missing_z_ids}`), and its AME lies in the negative tail. Stata treats missing numeric values as larger than finite values, so the supplied code incorrectly marks this estimate as significant. The reproduction table preserves that coding to match the publication. In a separate, unplanned audit, excluding this model and restoring equal total weight per retained team gives a pro-minus-anti negative-tail contrast of {f(tail_audit['estimate'])} (SE = {f(tail_audit['se'])}, 95% CI {ci(tail_audit)}, p = {pv(tail_audit['p'])}; {tail_audit['n']} models, {tail_audit['teams']} teams). This does not change the negative-tail conclusion or any AME analysis. The audit is saved in [negative_tail_missing_z_audit.csv](analysis_output/negative_tail_missing_z_audit.csv).

## Choices and expectations recorded before analysis

The following list was saved after reading the authors' code, before loading the analysis data, inspecting numerical results, or fitting models. It is a prospective plan for this session, not a preregistration made independently of the paper. Each alternative changes the baseline separately; the leave-one-out choice entails one fit per team.

{plan_table}

## Sensitivity results

All contrasts below point from more anti-immigration to more pro-immigration. Except where labelled, the contrast compares the supplied pro and anti team categories. The continuous-index contrast uses the paper's 1-to-6 comparison; the shares contrast compares hypothetical all-pro and all-anti compositions. These retain the research question but are not identical interventions or effect sizes. Winsorisation and team medians also change the outcome summary, while weighting changes whose results count most.

{rob_table}

![AME association across all planned analysis choices](analysis_output/robustness.png)

Points and bars show estimates and two-sided 95% confidence intervals. The last row instead shows the range of leave-one-out estimates (thick segment) and the envelope of their individual intervals (thin segment); that envelope is not a confidence interval for one estimator. The team-median row uses team observations, so its first sample count is teams rather than model submissions. That choice combines a different outcome summary with HC3 uncertainty; its wider interval cannot be attributed solely to using medians.

Of the {len(robust)-1} individually estimated alternatives, {alt_sig} have intervals wholly above zero; {unsig} have intervals that include zero. The baseline is also above zero. Across the {len(loo)} leave-one-team-out fits, {int((loo.estimate>0).sum())} estimates are positive and {int((loo.lo>0).sum())} intervals exclude zero. The smallest estimate follows omission of team {int(minloo.omitted_team)} ({f(minloo.estimate)}); the largest follows omission of team {int(maxloo.omitted_team)} ({f(maxloo.estimate)}). The largest leave-one-out p value is {pv(maxp.p)}, after omitting team {int(maxp.omitted_team)}.

Contrary to my expectations, prior-belief adjustment and peer-score weighting preserve conventional statistical significance. The continuous linear ideology measure does not meet the two-sided 5% threshold even in the published baseline specification; expressing it as a full-scale contrast does not change that p value. These correlated checks are a sensitivity exercise, not independent replications or a vote count establishing a probability that the claim is true.

## Analysis decisions and implementation limits

The paper and supplied code settle the baseline weights, controls, outcomes, and clustering. I made the following additional decisions for this reproduction and sensitivity exercise:

- **Scope and target.** Treat Table 1 as the main result and use the adjusted pro-minus-anti AME contrast as the principal sensitivity target. Keep the two tail outcomes in the reproduction table, without claiming the AME sensitivity checks establish their robustness or verify the mechanism analysis.
- **Data boundary.** Start from the requested processed `df.dta`, retain the authors' imputations and category construction, and remove the merge-only row. Preserve the missing-z classification for reproduction, then exclude that observation and recompute inverse retained-model counts in the separate negative-tail audit. This verifies downstream analysis, not the correctness of every raw-survey transformation or imputation. The derivations and imputation rules are in `01_Data_Prep.do`.
- **Numerical reference.** Parse the journal table and use the explicitly labelled Stata log to check precision. The CSV table filenames do not consistently identify the published tables; the README's table-to-code mapping takes precedence. No published number is taken from memory.
- **Inference.** Use two-sided 95% intervals and p < .05 for the sensitivity summaries. Reproduce Stata's clustered covariance correction, G/(G−1) × (N−1)/(N−k), and t reference with G−1 degrees of freedom; k is design-matrix rank. This avoids treating model submissions as independent teams. No multiplicity correction is used, and the checks do not provide confirmatory familywise inference.
- **Alternative education and missingness.** Treat `degree1` as categorical and use complete cases for that specification; do not invent an education category or impute it. It uses {int(rob[3]['n'])} models from {int(rob[3]['teams'])} teams, so its change combines education coding with a sample change. Other model-level alternatives retain the full sample.
- **Weights.** Give teams equal total weight in the baseline, models equal weight in the corresponding alternative, and use the supplied positive `pscore/nmodel` for the peer-score alternative without further normalising within teams. Peer scores are partly imputed in the supplied file. They are not sampling probabilities, and quality weighting does not establish absence of bias.
- **Functional form.** Compare the two category coefficients explicitly, including their covariance. For continuous ideology, multiply the coefficient and its standard error by the endpoint distance, rather than comparing an unscaled one-point slope with a group contrast. The shares variables are proportions, despite their percentage labels in the paper.
- **Outlier treatment.** Winsorise at the unweighted pooled model-level empirical 1st and 99th percentiles, using linear interpolation: {f(cutlow)} and {f(cuthigh)}. Keep all models and baseline weights. For the median alternative, use the ordinary within-team median and equal weight per team.
- **Median uncertainty.** Use HC3 with residual-df t intervals. The categorical controls create {median_model['hc3_removed']} singleton discipline cells with unit leverage, where HC3 is undefined. Exclude these cells for this fit, leaving {median_model['n']} teams; they contribute no information to the ideology contrast. The script verifies that excluding them leaves its point estimate unchanged. This numerical handling was decided after inspecting the design, not in the original plan.
- **Influence and presentation.** Drop each team once, recompute the estimable design and finite-sample correction, retain the remaining original inverse-model weights, and publish every omission in a CSV. Show the estimate range and interval envelope without labelling the envelope as a single confidence interval. Report all planned alternatives, regardless of direction or significance.

The anti-immigration group contains only {counts['group1']} teams, and the baseline design has {base['rank']} fitted parameters. This makes uncertainty and control specification consequential even though there are many submitted models. No regression here randomises immigration attitudes or supplies a known true AME against which ideological bias can be measured.

## Reproducibility

Run the single analysis script from a clean process:

```sh
uv run reproduce.py
```

Alternatively install NumPy, pandas, SciPy, Patsy, statsmodels, and Matplotlib and run `python reproduce.py`. Paths resolve relative to the script, so the working directory is immaterial. The saved article XML makes subsequent runs independent of web access; the script downloads it from the original-article API if absent. It regenerates this report, both tables' CSVs, the full Table 1 comparison, every leave-one-out result, and the PNG/SVG figure under `analysis_output/`. [run_manifest.json](analysis_output/run_manifest.json) records software versions and input hashes, including the pre-analysis plan. All numerical results in this report are computed or parsed by the script. Assertions check the data structure, outcome definitions, agreement with the authors' unrounded log, equality with team-mean point estimates, and agreement of all main-model covariance matrices with statsmodels. No paid API was used; incremental API cost was US$0.

## Does the headline claim hold up?

The published adjusted association reproduces, and its direction survives every planned alternative and every single-team omission. Its statistical strength depends on defensible analysis choices, so the evidence supports an association between immigration attitudes and reported findings more clearly than a specification-insensitive result. A causal claim that ideology produces biased findings remains unestablished by these observational comparisons.
'''
(ROOT/'report.md').write_text(report)
print(main[['column','estimate','se','p']].to_string(index=False))
print(robust[['choice','estimate','lo','hi','p','n','teams']].to_string(index=False))
print('LOO:',loo[['estimate','p','lo','hi']].agg(['min','max']).to_string())
print('Wrote report.md and analysis_output/; all checks passed.')
