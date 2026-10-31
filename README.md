# pricing-project

## Data pipeline

### Raw load

Loaded 678,013 policies (`policies_raw`) and 26,639 claims (`claims_raw`) from OpenML freMTPL2freq / freMTPL2sev into MySQL; row counts reconciled against the CSVs.

### Data quality and clean layer

Checks in [`sql/02_data_quality.sql`](sql/02_data_quality.sql) were run on the raw tables, then re-run on the clean layer built by [`sql/03_clean_layer.sql`](sql/03_clean_layer.sql).

| Check | Raw | Decision | Clean |
| --- | ---: | --- | ---: |
| Policies with exposure > 1 | 1,224 | Cap at 1 (exposure is in policy-years) | 0 |
| Policies with claim_nb > 4 | 9 | Cap at 4 | 0 |
| Orphan claims (no matching policy) | 195 | Exclude | 0 |
| Policies with claim_nb > 0 but no severity rows | 9,116 | Set claims to 0 | 0 |
| Zero-amount claims | 0 | Drop (none found) | 0 |

**Result:** the clean layer keeps all 678,013 policies and 26,444 claims (195 orphans removed).

**Findings:**

- 9,116 policies report claims but have no claim amounts. Setting their claims to 0 keeps frequency and severity consistent, so frequency × severity = pure premium.
- Claim severity is heavy-tailed: mean 2,278.54, max 4,075,400.56. Large claims will be capped in the severity model.
- The capped claim counts may not be errors: the 8 policies with more than 4 claims that have severity rows have exactly as many rows as claims.
- After cleaning, 9 policies have a claim_nb that differs from their number of claim rows. This is expected: 8 come from the cap at 4 (their claim rows are kept), and 1 is a policy with 2 claims but 1 severity row in the source data.

## Exploratory analysis

Queries in [`sql/04_eda.sql`](sql/04_eda.sql), run on the clean layer.

### Portfolio overview

| Policies | Claims | Exposure (years) | Frequency | Avg severity | Pure premium |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 678,013 | 26,406 | 358,360 | 0.0737 | 2,268.77 | 167.18 |

Frequency = claims / exposure; severity = claim cost / claims; pure premium = claim cost / exposure (= frequency × severity).

### By driver age band

| Age band | Exposure (years) | Frequency | Avg severity | Pure premium |
| --- | ---: | ---: | ---: | ---: |
| 18-20 | 2,585 | 0.2387 | 13,431.20 | 3,206.39 |
| 21-25 | 13,643 | 0.1310 | 2,249.70 | 294.68 |
| 26-35 | 69,238 | 0.0746 | 2,052.88 | 153.20 |
| 36-50 | 131,927 | 0.0733 | 1,895.13 | 138.94 |
| 51-65 | 96,723 | 0.0676 | 1,892.62 | 128.03 |
| 66+ | 44,246 | 0.0592 | 2,397.55 | 141.97 |

### By region

The 3 regions with the most claim cost (R24, R82, R93) account for 60% of it. The 2 highest pure premiums, R21 (399.59) and R94 (263.08), come from regions with only about 1% of total cost each.

### Large claims

The top 1% of claims make up 38% of total claim cost.

**Findings:**

- Claim frequency falls steadily with age, from 0.239 at 18-20 to 0.059 at 66+, roughly a 4× difference. Driver age is a strong frequency rating factor.
- The 18-20 band's average severity (13,431) is about 6× that of the other bands, but it rests on very little exposure (2,585 years, under 1% of the portfolio). It is probably driven by one or a few very large claims rather than a real severity effect. Bands this thin should be merged, or large claims capped, before modelling severity by age.
- Severity is roughly flat across the bands from 21 to 65 (about 1,890-2,250), so the age effect is mainly in frequency. Severity rises again at 66+ (2,398).
- Claim cost is concentrated by region: 3 of 22 regions carry 60% of it. Small regions such as R21 and R94 have the highest pure premiums, but their low volume makes those estimates unreliable. They should be credibility-weighted or grouped rather than rated on their own experience.
- Large claims dominate: the top 1% of claims make up 38% of cost. This confirms that large claims need capping, with the excess spread across the portfolio, in the severity model.
- The 26,406 claims in `policies_clean` are fewer than the 26,444 claim rows in `claims_clean` because of the cap at 4 claims per policy.
