# Motor Insurance Pricing Project Plan

Oct 28, 2026 · @ding xian ang

## Overview

Build a motor insurance pricing model on 678k French policies: SQL data layer → GLM baseline → gradient boosting → explainable premium, in about 8–9 working days.

**Headline story for the CV:** "I built a frequency–severity pricing model where an exposure-aware GBM beat the industry-standard GLM by X% on deviance, and I showed which customer segments the GLM misprices."

**Stack:** MySQL 8.0+, Python (pandas, SQLAlchemy, PyMySQL, statsmodels, scikit-learn, LightGBM or XGBoost, Optuna, SHAP, matplotlib/seaborn), Streamlit, Git/GitHub.

**Pipeline:** raw CSV → MySQL raw tables → SQL clean layer → SQL features → Python models → pricing + explanations → Streamlit app.

| Step | What | Days |
| --- | --- | --- |
| 0 | Setup and data download | 0.5 |
| 1 | Python ETL into MySQL raw tables | 0.5 |
| 2 | SQL data quality and clean layer | 1 |
| 3 | EDA (SQL aggregates + Python plots) | 1 |
| 4 | SQL features and train/test split | 0.5 |
| 5 | GLM baseline | 1 |
| 6 | GBM models | 1.5 |
| 7 | Evaluation, SHAP, mispricing, premium | 1 |
| 8 | Streamlit app, README, CV | 1.5 |

Add the project to your CV once Step 6 is done; Steps 7–8 can follow.

## Step 0 — Setup (½ day)

Goal: a GitHub repo, a working Python environment, MySQL running, and the two raw CSVs saved locally.

- [x] Install MySQL 8.0+ (window functions and CTEs need 8.0) and MySQL Workbench
- [x] Create a database: `CREATE DATABASE motor_pricing;`
- [x] Create a GitHub repo `pricing-project` and a virtual environment
- [x] `pip install pandas sqlalchemy pymysql scikit-learn statsmodels lightgbm xgboost optuna shap matplotlib seaborn streamlit python-dotenv`
- [x] Put DB credentials (`DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, `DB_NAME`) in a `.env` file and add `.env` and `data/` to `.gitignore`
- [x] Download the data and save as CSV

**Data source:** OpenML — freMTPL2freq (ID 41214, \~678k policies) and freMTPL2sev (ID 41215, one row per claim).

```python
# download.ipynb — Step 0 cell
from sklearn.datasets import fetch_openml

freq = fetch_openml(data_id=41214, as_frame=True).frame
sev = fetch_openml(data_id=41215, as_frame=True).frame
freq.to_csv("data/raw/freMTPL2freq.csv", index=False)
sev.to_csv("data/raw/freMTPL2sev.csv", index=False)
```

**Repo layout:**

```
pricing-project/
├── README.md
├── LICENSE
├── requirements.txt
├── .env                   (git-ignored: DB password)
├── data/raw/              (git-ignored: CSVs)
├── download.ipynb         (Step 0 download + Step 1 raw load)
├── 02_eda.ipynb
├── 03_glm.ipynb
├── 04_gbm.ipynb
├── 05_explain_and_price.ipynb
├── sql/
│   ├── 01_schema_raw.sql
│   ├── 02_data_quality.sql
│   ├── 03_clean_layer.sql
│   ├── 04_eda.sql
│   └── 05_features.sql
├── models/                (saved model files)
└── app/streamlit_app.py   (must be .py for streamlit run)
```

All Python work is in notebooks, run in number order. Helper code (DB connection, metrics) goes in a setup cell at the top of each notebook.

## Step 1 — Load raw data into MySQL (½ day)

Goal: both files sit in MySQL exactly as received, with only mechanical fixes. No business decisions yet.

**Python does only mechanical fixes:** strip the quote marks around category values (e.g. `'B12'` → `B12`), cast `IDpol` to integer, standardise column names to snake\_case.

```sql
-- sql/01_schema_raw.sql
CREATE TABLE policies_raw (
    id_pol       INT PRIMARY KEY,
    claim_nb     INT NOT NULL,
    exposure     DECIMAL(6,4) NOT NULL,
    area         CHAR(1),
    veh_power    INT,
    veh_age      INT,
    driv_age     INT,
    bonus_malus  INT,
    veh_brand    VARCHAR(5),
    veh_gas      VARCHAR(10),
    density      INT,
    region       VARCHAR(5)
);

CREATE TABLE claims_raw (
    claim_id      INT AUTO_INCREMENT PRIMARY KEY,  -- sev file has no claim key
    id_pol        INT NOT NULL,
    claim_amount  DECIMAL(12,2) NOT NULL
);
```

```python
# download.ipynb — Step 1 cells
import os
import pandas as pd
from sqlalchemy import create_engine, URL
from dotenv import load_dotenv

load_dotenv(".env", override=True)
url = URL.create(
    "mysql+pymysql",
    username=os.environ["DB_USER"],
    password=os.environ["DB_PASSWORD"],  # never print this
    host=os.environ["DB_HOST"],
    port=int(os.environ["DB_PORT"]),
    database=os.environ["DB_NAME"],
)
engine = create_engine(url)

freq = pd.read_csv("data/raw/freMTPL2freq.csv")
sev = pd.read_csv("data/raw/freMTPL2sev.csv")

for df in (freq, sev):
    for col in df.select_dtypes("object"):
        df[col] = df[col].str.strip("'")

freq = freq.rename(columns={"IDpol": "id_pol", "ClaimNb": "claim_nb", "Exposure": "exposure",
    "Area": "area", "VehPower": "veh_power", "VehAge": "veh_age", "DrivAge": "driv_age",
    "BonusMalus": "bonus_malus", "VehBrand": "veh_brand", "VehGas": "veh_gas",
    "Density": "density", "Region": "region"})
sev = sev.rename(columns={"IDpol": "id_pol", "ClaimAmount": "claim_amount"})
freq["id_pol"] = freq["id_pol"].astype(int)
sev["id_pol"] = sev["id_pol"].astype(int)

freq.to_sql("policies_raw", engine, if_exists="append", index=False, chunksize=50_000)
sev.to_sql("claims_raw", engine, if_exists="append", index=False, chunksize=50_000)
```

- [ ] Run the schema, then the loader
- [ ] Reconcile: `SELECT COUNT(*)` on both tables must equal the CSV row counts; `SUM(claim_amount)` must equal the CSV total
- [ ] Write the counts into the README ("Loaded 678,013 policies and N claims; reconciled")

Tip: if `to_sql` is slow, switch to `LOAD DATA LOCAL INFILE` (needs `local_infile` enabled on server and client).

## Step 2 — Data quality checks and clean layer in SQL (1 day)

Goal: every cleaning decision lives in versioned SQL, with the raw tables untouched. This is your main SQL showcase and a strong interview story.

**First, find the problems** (`02_data_quality.sql`) — record the count each query returns in the README:

```sql
-- Exposure above one policy-year
SELECT COUNT(*) FROM policies_raw WHERE exposure > 1;

-- Distribution of claim counts (look for implausible values)
SELECT claim_nb, COUNT(*) AS n_policies
FROM policies_raw GROUP BY claim_nb ORDER BY claim_nb;

-- Orphan claims: claims whose policy doesn't exist
SELECT COUNT(*) FROM claims_raw c
LEFT JOIN policies_raw p ON c.id_pol = p.id_pol
WHERE p.id_pol IS NULL;

-- Policies reporting claims but with no severity rows
SELECT COUNT(*) FROM policies_raw p
WHERE p.claim_nb > 0
  AND NOT EXISTS (SELECT 1 FROM claims_raw c WHERE c.id_pol = p.id_pol);

-- Claim count in policies vs rows in claims table
WITH c AS (SELECT id_pol, COUNT(*) AS n_rows FROM claims_raw GROUP BY id_pol)
SELECT SUM(p.claim_nb <> c.n_rows) AS mismatches
FROM policies_raw p JOIN c ON p.id_pol = c.id_pol;

-- Zero-amount claims and severity percentiles (heavy tail)
SELECT COUNT(*) FROM claims_raw WHERE claim_amount = 0;
SELECT MAX(claim_amount), AVG(claim_amount) FROM claims_raw;
```

**Then decide and document each fix:**

| Issue | Decision | Why |
| --- | --- | --- |
| exposure > 1 | Cap at 1 | Exposure is measured in policy-years |
| Very high claim\_nb | Cap at 4 | Almost certainly data errors; they distort a Poisson fit |
| Orphan claims | Exclude | No policy features to model them with |
| claim\_nb > 0 but no severity rows | Set claims to 0 for both models | Keeps frequency and severity consistent, so frequency × severity = pure premium |
| Zero-amount claims | Drop | A claim that cost nothing isn't a claim for pricing |

**Then build the clean layer** (`03_clean_layer.sql`) with keys and constraints:

```sql
CREATE TABLE claims_clean AS
SELECT c.id_pol, c.claim_amount
FROM claims_raw c
JOIN policies_raw p ON c.id_pol = p.id_pol      -- drops orphans
WHERE c.claim_amount > 0;

CREATE TABLE policies_clean AS
SELECT p.id_pol,
       LEAST(p.exposure, 1)                    AS exposure,
       CASE WHEN agg.total_amount IS NULL THEN 0
            ELSE LEAST(p.claim_nb, 4) END      AS claim_nb,
       COALESCE(agg.total_amount, 0)           AS claim_amount_total,
       p.area, p.veh_power, p.veh_age, p.driv_age, p.bonus_malus,
       p.veh_brand, p.veh_gas, p.density, p.region
FROM policies_raw p
LEFT JOIN (SELECT id_pol, SUM(claim_amount) AS total_amount
           FROM claims_clean GROUP BY id_pol) agg
       ON p.id_pol = agg.id_pol;

ALTER TABLE policies_clean ADD PRIMARY KEY (id_pol);
ALTER TABLE claims_clean ADD COLUMN claim_id INT AUTO_INCREMENT PRIMARY KEY FIRST,
    ADD FOREIGN KEY (id_pol) REFERENCES policies_clean(id_pol);
```

- [ ] Run all checks, note counts
- [ ] Build clean tables; re-run the checks against them (all should return 0)
- [ ] Optional: draw the ER diagram in MySQL Workbench and export it for the README

## Step 3 — EDA: aggregates in SQL, charts in Python (1 day)

Goal: know which rating factors drive frequency and severity before modelling. SQL computes the segment rates; Python draws them.

The key detail: always weight by exposure. Frequency = `SUM(claim_nb) / SUM(exposure)`, not an average of claim counts.

```sql
-- 04_eda.sql
-- Portfolio totals
SELECT COUNT(*) AS policies, SUM(exposure) AS exposure_years,
       SUM(claim_nb) AS claims,
       SUM(claim_nb) / SUM(exposure) AS frequency,
       SUM(claim_amount_total) / NULLIF(SUM(claim_nb), 0) AS avg_severity,
       SUM(claim_amount_total) / SUM(exposure) AS pure_premium
FROM policies_clean;

-- Frequency, severity, pure premium by driver age band
SELECT CASE WHEN driv_age < 21 THEN '18-20' WHEN driv_age < 26 THEN '21-25'
            WHEN driv_age < 36 THEN '26-35' WHEN driv_age < 51 THEN '36-50'
            WHEN driv_age < 66 THEN '51-65' ELSE '66+' END AS age_band,
       SUM(exposure) AS exposure_years,
       SUM(claim_nb) / SUM(exposure) AS frequency,
       SUM(claim_amount_total) / NULLIF(SUM(claim_nb), 0) AS avg_severity,
       SUM(claim_amount_total) / SUM(exposure) AS pure_premium
FROM policies_clean GROUP BY age_band ORDER BY age_band;

-- Rank regions by pure premium, with cumulative share of claim cost
WITH r AS (
  SELECT region, SUM(exposure) AS expo, SUM(claim_amount_total) AS cost
  FROM policies_clean GROUP BY region
)
SELECT region, cost / expo AS pure_premium,
       RANK() OVER (ORDER BY cost / expo DESC) AS risk_rank,
       SUM(cost) OVER (ORDER BY cost DESC) / SUM(cost) OVER () AS cum_cost_share
FROM r;

-- Large-claim concentration: share of total cost from the top 1% of claims
WITH ranked AS (
  SELECT claim_amount, NTILE(100) OVER (ORDER BY claim_amount DESC) AS pct
  FROM claims_clean
)
SELECT SUM(CASE WHEN pct = 1 THEN claim_amount END) / SUM(claim_amount) AS top1pct_share
FROM ranked;
```

Repeat the segment query for: BonusMalus bands, vehicle age, vehicle power, area, fuel type, density bands.

**Python charts** (`02_eda.ipynb`, using `pd.read_sql`):

1. Frequency by each rating factor (bar, with exposure shown as a secondary axis)
2. Severity distribution on a log scale
3. Lorenz-style curve of claim cost concentration
4. Correlation check between numeric factors (BonusMalus vs driver age is strongly related)

- [ ] Write 3–4 one-line findings, e.g. "drivers under 21 claim N× more often than the average" — these go in the README

## Step 4 — Feature engineering in SQL and train/test split (½ day)

Goal: one modelling-ready view that Python reads directly, with a fixed, reproducible split.

```sql
-- 05_features.sql
CREATE OR REPLACE VIEW model_features AS
SELECT id_pol, exposure, claim_nb, claim_amount_total,
       area, veh_gas, veh_brand, region,
       veh_power,
       LEAST(veh_age, 20)                   AS veh_age,        -- cap long tail
       LEAST(driv_age, 90)                  AS driv_age,
       LEAST(bonus_malus, 150)              AS bonus_malus,
       LN(density)                          AS log_density,
       CASE WHEN MOD(CRC32(id_pol), 10) < 8
            THEN 'train' ELSE 'test' END    AS split            -- deterministic 80/20
FROM policies_clean;
```

**Severity table with large-claim capping.** A few huge claims would dominate the Gamma model. Cap individual claims at roughly the 99.5th percentile and treat the excess as a flat loading spread across all policies.

```sql
-- find the cap: the claim at the 99.5th percentile
WITH r AS (
  SELECT claim_amount,
         ROW_NUMBER() OVER (ORDER BY claim_amount) AS rn,
         COUNT(*) OVER () AS n
  FROM claims_clean
)
SELECT claim_amount AS cap FROM r WHERE rn = CEIL(0.995 * n);

-- severity modelling table (replace 100000 with the cap you found)
CREATE OR REPLACE VIEW severity_features AS
SELECT f.*, s.n_claims, s.capped_total / s.n_claims AS avg_claim_capped
FROM model_features f
JOIN (SELECT id_pol, COUNT(*) AS n_claims,
             SUM(LEAST(claim_amount, 100000)) AS capped_total
      FROM claims_clean GROUP BY id_pol) s
  ON f.id_pol = s.id_pol;
```

- [ ] Large-claim loading = (total cost − capped cost) / total exposure. Record it; it's added to every premium in Step 7.
- [ ] Check the split: frequency in train and test should be close
- [ ] Python: `df = pd.read_sql("SELECT * FROM model_features", engine)`

Keep features close to the raw rating factors. GBMs don't need bands; the GLM gets bands or splines in Step 5.

## Step 5 — GLM baseline (1 day)

Goal: the industry-standard benchmark. Every GBM result is reported against it.

**Frequency:** Poisson GLM, log link, target `claim_nb`, with `log(exposure)` as an offset.

```python
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf

train = df[df.split == "train"].copy(); test = df[df.split == "test"].copy()
for d in (train, test):
    d["driv_age_band"] = pd.cut(d.driv_age, [17, 20, 25, 35, 50, 65, 100])
    d["veh_age_band"] = pd.cut(d.veh_age, [-1, 1, 4, 10, 20])

freq_glm = smf.glm(
    "claim_nb ~ C(driv_age_band) + C(veh_age_band) + bonus_malus + log_density"
    " + C(area) + C(veh_gas) + C(veh_brand) + C(region) + veh_power",
    data=train, family=sm.families.Poisson(),
    offset=np.log(train.exposure)).fit()
```

**Severity:** Gamma GLM, log link, on policies with claims. Target = average capped claim; weight = number of claims.

```python
sev_train = sev_df[sev_df.split == "train"]
sev_glm = smf.glm(
    "avg_claim_capped ~ C(driv_age_band) + C(veh_age_band) + bonus_malus + log_density + C(area)",
    data=sev_train, family=sm.families.Gamma(sm.families.links.Log()),
    var_weights=sev_train.n_claims).fit()
```

**Pure premium** per policy-year = predicted frequency × predicted severity.

**Metrics** (write these as functions in a setup cell and reuse them in the GBM notebook):

- Frequency: mean Poisson deviance on `claim_nb / exposure`, weighted by exposure (`sklearn.metrics.mean_poisson_deviance`)
- Severity: mean Gamma deviance, weighted by claim count
- Pure premium: Gini coefficient from an exposure-weighted Lorenz curve (how well the model ranks risk)
- Calibration: total predicted claim cost ÷ total actual claim cost on the test set (should be close to 1)

* [ ] Fit both GLMs, save coefficient tables (`exp(coef)` = relativities)
* [ ] Record test-set metrics in a results table
* [ ] Sanity check: young drivers and high BonusMalus should have relativities above 1

## Step 6 — Gradient boosting models (1.5 days)

Goal: beat the GLM on the same metrics, handling exposure correctly. LightGBM is faster at this size; XGBoost works the same way.

**Frequency — exposure as an offset, not a feature.** The model learns a rate per policy-year; `log(exposure)` enters as the starting score.

```python
import lightgbm as lgb

features = ["veh_power", "veh_age", "driv_age", "bonus_malus", "log_density",
            "area", "veh_gas", "veh_brand", "region"]
for c in ["area", "veh_gas", "veh_brand", "region"]:
    df[c] = df[c].astype("category")

# hold out 15% of train for early stopping / Optuna
dtrain = lgb.Dataset(tr[features], label=tr.claim_nb,
                     init_score=np.log(tr.exposure))
dvalid = lgb.Dataset(va[features], label=va.claim_nb,
                     init_score=np.log(va.exposure), reference=dtrain)

params = {"objective": "poisson", "learning_rate": 0.05,
          "num_leaves": 31, "min_data_in_leaf": 500, "verbose": -1}
freq_gbm = lgb.train(params, dtrain, 2000, valid_sets=[dvalid],
                     callbacks=[lgb.early_stopping(100)])

# predict() ignores init_score -> output is a rate per policy-year
freq_rate = freq_gbm.predict(test[features])
```

XGBoost equivalent: `objective="count:poisson"` with `base_margin=np.log(exposure)` in the `DMatrix`.

**Severity:** `objective="gamma"`, label = `avg_claim_capped`, weight = `n_claims`, trained on policies with claims only.

**Tuning with Optuna** (reuse your dissertation setup): tune `num_leaves`, `min_data_in_leaf`, `learning_rate`, `feature_fraction`, `lambda_l2`. About 50 trials is enough; optimise validation Poisson deviance. Don't chase the last 0.5%.

**Optional extra:** one Tweedie model (`objective="tweedie"`) on pure premium directly, compared against frequency × severity.

**Results table** (test set, fill in):

| Model | Freq. Poisson deviance | Sev. Gamma deviance | Pure premium Gini | Calibration (pred/actual) |
| --- | --- | --- | --- | --- |
| GLM |  |  |  |  |
| LightGBM |  |  |  |  |
| Tweedie GBM (optional) |  |  |  |  |

- [ ] Save models to `models/`
- [ ] Compute % improvement in deviance and Gini vs GLM — this is your CV number
- [ ] Add the project to your CV now

## Step 7 — Explain, find mispricing, set the premium (1 day)

Goal: turn model accuracy into a business finding. This is the section that makes the project stand out.

**1. Explain the GBM with SHAP**

- [ ] SHAP summary plot for the frequency model
- [ ] Dependence plots for `bonus_malus`, `driv_age`, `veh_age`
- [ ] Compare GBM partial dependence against GLM relativities on one chart per factor. Where they differ is what the GLM misses (e.g. non-linear age effects, BonusMalus × age interaction)

**2. Lift and mispricing analysis**

- [ ] Double lift chart: sort test policies by GBM ÷ GLM premium ratio, cut into 10 bands, plot actual loss cost vs each model's prediction per band. The model whose line tracks actual is better
- [ ] Identify segments where GLM premium is furthest from actual cost, e.g. "the GLM undercharges young drivers in dense urban areas by \~X%"
- [ ] Quantify: share of policies mispriced by more than 20%

**3. From pure premium to a quoted price**

```latex
\text{Premium} = \frac{\hat{\lambda} \cdot \hat{\mu} + L_{\text{large}}}{1 - e - p}
```

where λ̂ = predicted frequency, μ̂ = predicted capped severity, L = large-claim loading from Step 4, e = expense ratio, p = profit margin. Pick and state simple assumptions (e.g. e = 25%, p = 5%).

- [ ] Write 3 headline findings with numbers for the README

## Step 8 — Streamlit app, README, packaging (1.5 days)

Goal: a recruiter can see the result in 30 seconds without running anything.

**Streamlit quoting app** (`app/streamlit_app.py`):

- [ ] Inputs: driver age, BonusMalus, vehicle age, power, brand, fuel, area, region, density
- [ ] Outputs: predicted frequency, severity, pure premium, quoted premium, and GLM premium for comparison
- [ ] A SHAP waterfall for that single quote ("why this price")
- [ ] Load saved models from `models/`; the app doesn't need MySQL
- [ ] Deploy free on Streamlit Community Cloud and link it from the README

**README structure** (findings first, process second):

1. One-line summary + links (live app, notebooks)
2. Key findings: 3 sentences with numbers, one chart each
3. Results table (GLM vs GBM)
4. Data pipeline: ER diagram, data-quality decisions table, row-count reconciliation
5. Method: frequency–severity, exposure offset, large-claim capping
6. How to run: MySQL setup, `run sql/01, then download.ipynb, then sql/02–05, then notebooks 02–05 in number order`
7. Limitations: French data from one insurer, no time dimension, assumed expense loading

- [ ] `requirements.txt` with pinned versions
- [ ] Restart and run every notebook top to bottom before pushing, so the outputs match the code
- [ ] Optional: `docker-compose.yml` with a MySQL container so it runs in one command

## CV bullets and interview talking points

**CV entry** (fill in the numbers when done):

> **Motor Insurance Pricing — SQL, Python, LightGBM** (GitHub | Live app)
>
> - Designed a MySQL raw/clean data layer for 678k policies and claims, with SQL data-quality checks, reconciliation and feature engineering (CTEs, window functions).
> - Built frequency–severity models (Poisson/Gamma GLMs vs exposure-offset LightGBM); GBM improved Poisson deviance by \[X\]% and Gini from \[a\] to \[b\].
> - Used SHAP and double-lift analysis to find segments the GLM misprices by up to \[Z\]%; deployed a Streamlit quoting app with per-quote explanations.

**Questions you should be ready to answer:**

1. Why model frequency and severity separately instead of premium directly? (Different drivers, different distributions; Tweedie is the one-model alternative.)
2. Why is exposure an offset and not a feature? (A policy covered for half a year should expect half the claims; the offset fixes that coefficient at 1.)
3. Why Poisson and Gamma? (Counts and positive skewed amounts; log link gives multiplicative relativities.)
4. How did you handle large claims? (Capped at the 99.5th percentile, excess spread as a loading.)
5. Why does the GBM beat the GLM, and why might an insurer still use the GLM? (Interactions and non-linearity vs transparency, regulation, ease of filing rates.)
6. What would you do with more time? (Telematics or time features, monotonic constraints, GLM with GBM-discovered interactions.)
7. Walk me through one cleaning decision. (The claims-without-severity case is the best story.)

**Done checklist:**

- [ ] Repo public, README has findings + charts
- [ ] Live app link works on mobile
- [ ] CV updated with real numbers, and "PROJECT" renamed to "PROJECTS"
- [ ] SQL is now evidenced on your CV, not only listed in Skills
