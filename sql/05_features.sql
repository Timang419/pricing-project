-- sql/05_features.sql
-- Step 4: modelling views and a fixed train/test split, built on the clean layer.
-- Features stay close to the raw rating factors: banding and grouping happen in the Step 5 GLM,
-- so the Step 6 GBM can still use the raw values.
USE motor_pricing;


-- 1. One row per policy, with the train/test split
CREATE OR REPLACE VIEW model_features AS
SELECT id_pol, exposure, claim_nb, claim_amount_total,
       area,             -- same information as density (EDA): use only one of them in the GLM
       veh_gas, veh_brand, region, veh_power,
       LEAST(veh_age, 20)       AS veh_age,      -- above 20 is thin and includes implausible ages up to 100
       LEAST(driv_age, 90)      AS driv_age,
       LEAST(bonus_malus, 150)  AS bonus_malus,
       LN(density)              AS log_density,  -- density is very skewed
       -- deterministic 80/20 split: the same policy always lands on the same side
       CASE WHEN MOD(CRC32(id_pol), 10) < 8 THEN 'train' ELSE 'test' END AS split
FROM policies_clean;


-- 2. Large-claim cap: the 99.5th-percentile claim, from train claims only so the test set
--    has no influence on the model
-- replace the claim that larger than the cap in test using the train cap 
CREATE OR REPLACE VIEW large_claim_cap AS
WITH train_claims AS (
  SELECT c.claim_amount,
         ROW_NUMBER() OVER (ORDER BY c.claim_amount) AS rn,
         COUNT(*) OVER () AS n
  FROM claims_clean c
  JOIN model_features f ON c.id_pol = f.id_pol
  WHERE f.split = 'train'
)
SELECT claim_amount AS cap
FROM train_claims
WHERE rn = CEIL(0.995 * n);


-- 3. Severity: one row per policy with claims. Built on model_features, so all of a policy's
--    claims are on the same side of the split.
--    n_claims counts claim rows, which can differ from claim_nb (capped at 4 in the clean layer).
-- avg_claim_capped is the target severity
CREATE OR REPLACE VIEW severity_features AS
SELECT f.*, s.n_claims, s.capped_total / s.n_claims AS avg_claim_capped
FROM model_features f
JOIN (SELECT c.id_pol,
             COUNT(*)                          AS n_claims,
             SUM(LEAST(c.claim_amount, k.cap)) AS capped_total
      FROM claims_clean c
      CROSS JOIN large_claim_cap k             -- one row, so every claim gets the same cap
      GROUP BY c.id_pol) s
  ON f.id_pol = s.id_pol;


-- 4. Large-claim loading: cost above the cap per train claim.
--    Added to predicted severity in Step 7, so it scales with predicted frequency
--    (large-claim counts rise with claim frequency, so a flat amount per year overcharges low-risk policies).
--    Divided by SUM(claim_nb), the frequency target, so the loading collects all of the excess on train.
CREATE OR REPLACE VIEW large_claim_loading AS
SELECT k.cap,
       SUM(GREATEST(c.claim_amount - k.cap, 0))                            AS excess_cost,
       (SELECT SUM(claim_nb) FROM model_features WHERE split = 'train')    AS train_claims,
       SUM(GREATEST(c.claim_amount - k.cap, 0))
         / (SELECT SUM(claim_nb) FROM model_features WHERE split = 'train') AS loading_per_claim
FROM claims_clean c
JOIN model_features f ON c.id_pol = f.id_pol
CROSS JOIN large_claim_cap k
WHERE f.split = 'train'
GROUP BY k.cap;


-- Checks

-- 1. All four views exist
SHOW FULL TABLES FROM motor_pricing WHERE Table_type = 'VIEW';

-- 2. Nothing lost: expect 678,013 policies; severity should hold every claim row (26,444)
--    and every policy with a claim amount
SELECT (SELECT COUNT(*) FROM model_features)                        AS policies,
       (SELECT COUNT(*) FROM severity_features)                     AS policies_with_claims,
       (SELECT COUNT(*) FROM policies_clean WHERE claim_amount_total > 0) AS expected_with_claims,
       (SELECT SUM(n_claims) FROM severity_features)                AS claim_rows,
       (SELECT COUNT(*) FROM claims_clean)                          AS expected_claim_rows;

-- 3. The split is about 80/20, and train and test look alike
SELECT split,
       COUNT(*)                                   AS policies,
       COUNT(*) / SUM(COUNT(*)) OVER ()           AS share,
       SUM(exposure)                              AS exposure_years,
       SUM(claim_nb) / SUM(exposure)              AS frequency,
       SUM(claim_amount_total) / NULLIF(SUM(claim_nb), 0) AS avg_severity  -- uncapped, so noisier
FROM model_features
GROUP BY split;

-- capped severity by split should be closer than the uncapped one above
SELECT split,
       SUM(n_claims)                                         AS claims,
       SUM(avg_claim_capped * n_claims) / SUM(n_claims)      AS avg_claim_capped
FROM severity_features
GROUP BY split;

-- 4. Feature ranges after capping: veh_age <= 20, driv_age <= 90, bonus_malus <= 150, no NULLs
SELECT MIN(veh_age), MAX(veh_age), MIN(driv_age), MAX(driv_age),
       MIN(bonus_malus), MAX(bonus_malus), MIN(log_density), MAX(log_density),
       SUM(veh_age IS NULL OR driv_age IS NULL OR bonus_malus IS NULL OR log_density IS NULL) AS rows_with_nulls
FROM model_features;

-- 5. Cap and loading: the cap should be close to the 34,377 found on all claims in the EDA
SELECT * FROM large_claim_loading;

-- how many train claims the cap touches (about 0.5%)
SELECT SUM(c.claim_amount > k.cap) AS claims_above_cap,
       AVG(c.claim_amount > k.cap) AS share_above_cap
FROM claims_clean c
JOIN model_features f ON c.id_pol = f.id_pol
CROSS JOIN large_claim_cap k
WHERE f.split = 'train';
