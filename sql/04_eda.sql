USE motor_pricing;

DESCRIBE motor_pricing.policies_clean;
DESCRIBE motor_pricing.claims_clean;

-- overview
SELECT COUNT(*)                     AS policies,
       SUM(claim_nb)                AS claims_count,
       SUM(exposure)                AS exposure_years,
       SUM(claim_nb) / SUM(exposure) AS claims_frequency,
       SUM(claim_amount_total)/SUM(claim_nb) AS avg_severity,
       SUM(claim_amount_total)/SUM(exposure) AS pure_premium
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
       -- first descending order by (cost / expo)  then rank the new order as risk rank
       SUM(cost) OVER (ORDER BY cost DESC) / SUM(cost) OVER () AS cum_cost_share
       -- first calculate the running total(descending order by cost then sum all row before it)
FROM r
ORDER BY cost DESC;  -- display rows in the same order the running total is built

-- Large-claim concentration: share of total cost from the top 1% of claims
WITH ranked AS (
  SELECT claim_amount, NTILE(100) OVER (ORDER BY claim_amount DESC) AS pct
  FROM claims_clean
)
SELECT SUM(CASE WHEN pct = 1 THEN claim_amount END) / SUM(claim_amount) AS top1pct_share
FROM ranked;