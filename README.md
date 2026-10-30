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
