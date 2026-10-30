USE motor_pricing;

-- check if any row's exposure > 1 => invalid policy
SELECT COUNT(*) FROM policies_raw WHERE exposure > 1;
--1224

SELECT claim_nb, COUNT(*) AS n_policies
FROM policies_raw
GROUP BY claim_nb
ORDER BY claim_nb;

SELECT COUNT(*) FROM claims_raw c
LEFT JOIN policies_raw p ON c.id_pol = p.id_pol
WHERE p.id_pol IS NULL;
--195

-- Policies reporting claims but with no severity rows
SELECT COUNT(*) FROM policies_raw p
WHERE p.claim_nb > 0
  AND NOT EXISTS (SELECT 1 FROM claims_raw c WHERE c.id_pol = p.id_pol);
  --9116
-- or any option is 
-- SELECT COUo0--NT(*) from policies_raw p
-- LEFT JOIN claims_raw c ON p.id_pol=c.id_pol
-- WHERE p.claim_nb > 0 and c.id_pol IS NULL

-- Claim count in policies vs rows in claims table
WITH c AS (SELECT id_pol, COUNT(*) AS n_rows FROM claims_raw GROUP BY id_pol)
SELECT SUM(p.claim_nb <> c.n_rows) AS mismatches
FROM policies_raw p JOIN c ON p.id_pol = c.id_pol;

-- Zero-amount claims and severity percentiles (heavy tail)
SELECT COUNT(*) FROM claims_raw WHERE claim_amount = 0;
--0
SELECT MAX(claim_amount), AVG(claim_amount) FROM claims_raw;