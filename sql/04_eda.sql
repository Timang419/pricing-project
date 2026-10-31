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

-- Q5: BonusMalus bands
-- Do drivers with a worse claims history (higher bonus_malus) claim more often?
-- 50 is the best possible score, above 100 means a malus (penalty)
SELECT CASE WHEN bonus_malus = 50  THEN '50'
            WHEN bonus_malus <= 75  THEN '51-75'
            WHEN bonus_malus <= 100 THEN '76-100'
            WHEN bonus_malus <= 125 THEN '101-125'
            ELSE '126+' END AS bm_band,
       SUM(exposure) AS exposure_years,
       SUM(claim_nb) / SUM(exposure) AS frequency,
       SUM(claim_amount_total) / NULLIF(SUM(claim_nb), 0) AS avg_severity,
       SUM(claim_amount_total) / SUM(exposure) AS pure_premium
FROM policies_clean GROUP BY bm_band
ORDER BY MIN(bonus_malus);  -- sort by the band's numbers, not its text ('101-125' would come before '50')

-- Q6: Vehicle age bands
-- Are new or old cars riskier?
SELECT CASE WHEN veh_age = 0  THEN '0'
            WHEN veh_age <= 4  THEN '1-4'
            WHEN veh_age <= 10 THEN '5-10'
            WHEN veh_age <= 20 THEN '11-20'
            ELSE '21+' END AS veh_age_band,
       SUM(exposure) AS exposure_years,
       SUM(claim_nb) / SUM(exposure) AS frequency,
       SUM(claim_amount_total) / NULLIF(SUM(claim_nb), 0) AS avg_severity,
       SUM(claim_amount_total) / SUM(exposure) AS pure_premium
FROM policies_clean GROUP BY veh_age_band
ORDER BY MIN(veh_age);      -- as text, '11-20' would sort before '5-10'

-- Q7: Vehicle power
-- Do more powerful cars claim more often or cost more per claim?
-- veh_power has only a few values, so no bands are needed
SELECT veh_power,
       SUM(exposure) AS exposure_years,
       SUM(claim_nb) / SUM(exposure) AS frequency,
       SUM(claim_amount_total) / NULLIF(SUM(claim_nb), 0) AS avg_severity,
       SUM(claim_amount_total) / SUM(exposure) AS pure_premium
FROM policies_clean GROUP BY veh_power ORDER BY veh_power;

-- Q8: Area
-- How does risk change from area A to F, and does area just follow population density?
-- if avg_density rises from A to F together with frequency, area and density carry the same information
SELECT area,
       SUM(exposure) AS exposure_years,
       AVG(density) AS avg_density,
       SUM(claim_nb) / SUM(exposure) AS frequency,
       SUM(claim_amount_total) / NULLIF(SUM(claim_nb), 0) AS avg_severity,
       SUM(claim_amount_total) / SUM(exposure) AS pure_premium
FROM policies_clean GROUP BY area ORDER BY area;

-- Q9: Fuel type
-- Do diesel and regular (petrol) cars differ in risk?
SELECT veh_gas,
       SUM(exposure) AS exposure_years,
       SUM(claim_nb) / SUM(exposure) AS frequency,
       SUM(claim_amount_total) / NULLIF(SUM(claim_nb), 0) AS avg_severity,
       SUM(claim_amount_total) / SUM(exposure) AS pure_premium
FROM policies_clean GROUP BY veh_gas ORDER BY veh_gas;

-- Q9b: How many times as often do diesel cars claim compared with regular (petrol) cars?
-- CASE keeps the value for one fuel type and gives NULL for the other; SUM ignores the NULLs
-- 1.05 would mean diesel cars claim 5% more often per policy-year
SELECT
  (SUM(CASE WHEN veh_gas = 'Diesel'  THEN claim_nb END) / SUM(CASE WHEN veh_gas = 'Diesel'  THEN exposure END))
  /
  (SUM(CASE WHEN veh_gas = 'Regular' THEN claim_nb END) / SUM(CASE WHEN veh_gas = 'Regular' THEN exposure END))
  AS diesel_vs_regular_freq
FROM policies_clean;

-- Q10: Population density bands (inhabitants per km2 where the driver lives)
-- Do drivers in cities claim more than drivers in the countryside?
-- density is very skewed, so the bands get wider as density grows
SELECT CASE WHEN density < 50    THEN '<50'
            WHEN density < 200   THEN '50-199'
            WHEN density < 500   THEN '200-499'
            WHEN density < 2000  THEN '500-1999'
            WHEN density < 10000 THEN '2000-9999'
            ELSE '10000+' END AS density_band,
       SUM(exposure) AS exposure_years,
       SUM(claim_nb) / SUM(exposure) AS frequency,
       SUM(claim_amount_total) / NULLIF(SUM(claim_nb), 0) AS avg_severity,
       SUM(claim_amount_total) / SUM(exposure) AS pure_premium
FROM policies_clean GROUP BY density_band
ORDER BY MIN(density);

-- ============================================================
-- Verification checks: confirm the statements made in the README findings
-- ============================================================

-- Check 1: Are the high average severities caused by a few large claims?
-- For each group, compare the average claim with and without its largest 1 and 3 claims
-- if the average drops close to the all-claims baseline, a few large claims explain it
WITH c AS (
  SELECT 'all claims' AS seg, claim_amount FROM claims_clean
  UNION ALL
  SELECT 'driv_age 18-20', c.claim_amount FROM claims_clean c JOIN policies_clean p ON c.id_pol = p.id_pol WHERE p.driv_age < 21
  UNION ALL
  SELECT 'veh_power 9', c.claim_amount FROM claims_clean c JOIN policies_clean p ON c.id_pol = p.id_pol WHERE p.veh_power = 9
  UNION ALL
  SELECT 'bonus_malus 76-100', c.claim_amount FROM claims_clean c JOIN policies_clean p ON c.id_pol = p.id_pol WHERE p.bonus_malus BETWEEN 76 AND 100
  UNION ALL
  SELECT 'veh_age 11-20', c.claim_amount FROM claims_clean c JOIN policies_clean p ON c.id_pol = p.id_pol WHERE p.veh_age BETWEEN 11 AND 20
  UNION ALL
  SELECT 'area B', c.claim_amount FROM claims_clean c JOIN policies_clean p ON c.id_pol = p.id_pol WHERE p.area = 'B'
),
r AS (
  SELECT seg, claim_amount,
         ROW_NUMBER() OVER (PARTITION BY seg ORDER BY claim_amount DESC) AS rn  -- 1 = largest claim in each group
  FROM c
)
SELECT seg,
       COUNT(*) AS n_claims,
       AVG(claim_amount) AS avg_claim,
       MAX(claim_amount) AS largest_claim,
       SUM(CASE WHEN rn <= 3 THEN claim_amount END) / SUM(claim_amount) AS top3_cost_share,
       AVG(CASE WHEN rn > 1 THEN claim_amount END) AS avg_without_top1,
       AVG(CASE WHEN rn > 3 THEN claim_amount END) AS avg_without_top3
FROM r GROUP BY seg ORDER BY avg_claim DESC;

-- Check 2: Is the largest claim one claim on one policy, and which groups does it fall in?
SELECT c.claim_id, c.id_pol, c.claim_amount,
       p.driv_age, p.veh_power, p.area, p.bonus_malus, p.veh_age, p.claim_nb
FROM claims_clean c JOIN policies_clean p ON c.id_pol = p.id_pol
WHERE c.claim_amount = (SELECT MAX(claim_amount) FROM claims_clean);

-- Check 3: Is area just bands of density?
-- if each area covers its own density range with no overlap, area is a banded version of density
SELECT area, MIN(density) AS min_density, MAX(density) AS max_density, COUNT(*) AS policies
FROM policies_clean GROUP BY area ORDER BY area;

-- Check 4: Why does policies_clean have fewer claims (SUM(claim_nb)) than claims_clean has rows?
-- lists every policy whose claim_nb differs from its number of claim rows
WITH c AS (SELECT id_pol, COUNT(*) AS n_rows FROM claims_clean GROUP BY id_pol)
SELECT p.claim_nb, c.n_rows, COUNT(*) AS n_policies,
       SUM(c.n_rows - p.claim_nb) AS rows_minus_claim_nb
FROM policies_clean p JOIN c ON p.id_pol = c.id_pol
WHERE p.claim_nb <> c.n_rows
GROUP BY p.claim_nb, c.n_rows;

-- Check 5: Do the banded columns have NULLs, and what are their ranges?
-- a NULL would fall into the ELSE band of the CASE queries above (e.g. '66+'), so all NULL counts should be 0
SELECT MIN(driv_age) AS min_driv_age, MAX(driv_age) AS max_driv_age,
       MIN(bonus_malus) AS min_bm, MAX(bonus_malus) AS max_bm,
       MIN(veh_age) AS min_veh_age, MAX(veh_age) AS max_veh_age,
       MIN(density) AS min_density, MAX(density) AS max_density,
       SUM(driv_age IS NULL) AS null_driv_age, SUM(bonus_malus IS NULL) AS null_bm,
       SUM(veh_age IS NULL) AS null_veh_age, SUM(density IS NULL) AS null_density,
       SUM(veh_power IS NULL) AS null_veh_power, SUM(area IS NULL) AS null_area,
       SUM(veh_gas IS NULL) AS null_veh_gas, SUM(region IS NULL) AS null_region
FROM policies_clean;

-- Check 6: What share of total claim cost do the two highest pure-premium regions carry?
SELECT region, SUM(claim_amount_total) / (SELECT SUM(claim_amount_total) FROM policies_clean) AS cost_share
FROM policies_clean WHERE region IN ('R21', 'R94') GROUP BY region;