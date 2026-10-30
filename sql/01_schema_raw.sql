-- sql/01_schema_raw.sql
-- Raw tables: data exactly as received, only mechanical fixes applied in Python.
USE motor_pricing;

DROP TABLE IF EXISTS claims_raw;
DROP TABLE IF EXISTS policies_raw;

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
