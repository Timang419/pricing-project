USE motor_pricing;


CREATE TABLE claims_clean AS
SELECT c.id_pol, c.claim_amount
FROM claims_raw c
-- only keep row where claim and policy both exist
JOIN policies_raw p ON c.id_pol = p.id_pol 
-- filter out claim where claim =0
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
-- use group by to get the sum of claim amount 
-- select total amount and id pool as a new table agg,then left join
LEFT JOIN (SELECT id_pol, SUM(claim_amount) AS total_amount
           FROM claims_clean GROUP BY id_pol) agg
       ON p.id_pol = agg.id_pol;

ALTER TABLE policies_clean ADD PRIMARY KEY (id_pol);
ALTER TABLE claims_clean 
    ADD COLUMN claim_id INT AUTO_INCREMENT PRIMARY KEY FIRST,
    ADD FOREIGN KEY (id_pol) REFERENCES policies_clean(id_pol);

-- 1. Both tables exist
SHOW TABLES FROM motor_pricing;

-- 2. Row counts
SELECT COUNT(*) FROM motor_pricing.policies_clean;   -- expect 678,013
SELECT COUNT(*) FROM motor_pricing.claims_clean;     -- expect a bit fewer than claims_raw

-- 3. The ALTERs worked: shows PRIMARY KEY on id_pol and the FOREIGN KEY
SHOW CREATE TABLE motor_pricing.claims_clean;
SHOW CREATE TABLE motor_pricing.policies_clean;
