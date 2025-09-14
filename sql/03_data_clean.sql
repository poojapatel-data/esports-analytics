-- Data Cleaning

USE esports_analytics_new;

-- ──────────────────────────────────────────────────────────────────────────────
-- 1) LIGHT NORMALIZATION IN STAGING (idempotent)
-- ──────────────────────────────────────────────────────────────────────────────

-- Trim text
UPDATE stg_tournaments
  SET TournamentName = TRIM(TournamentName),
      Location       = TRIM(Location),
      GameName       = TRIM(GameName);

UPDATE stg_player_results
  SET GameName      = TRIM(GameName),
      TournamentName= TRIM(TournamentName),
      CountryCode   = UPPER(TRIM(CountryCode));
      
UPDATE stg_games
  SET GameName      = TRIM(GameName);
   
-- Normalize "unknown" countries
UPDATE stg_player_results
  SET CountryCode = 'ZZ'
WHERE CountryCode IS NULL OR CountryCode IN ('', 'NA', 'UNK', 'XX');

-- Normalize Teamplay to 0/1

UPDATE stg_tournaments
SET Teamplay =
  CASE
    WHEN LOWER(TRIM(CAST(Teamplay AS CHAR))) IN ('1','true','yes','y') THEN 1
    WHEN LOWER(TRIM(CAST(Teamplay AS CHAR))) IN ('0','false','no','n') THEN 0
    ELSE NULL
  END;

UPDATE stg_player_results
SET Teamplay =
  CASE
    WHEN LOWER(TRIM(CAST(Teamplay AS CHAR))) IN ('1','true','yes','y') THEN 1
    WHEN LOWER(TRIM(CAST(Teamplay AS CHAR))) IN ('0','false','no','n') THEN 0
    ELSE NULL
  END;

-- Derive Year from EndDate when missing/wrong
UPDATE stg_tournaments
  SET Year = YEAR(EndDate)
WHERE (Year IS NULL OR Year <> YEAR(EndDate)) AND EndDate IS NOT NULL;

-- Standardize "online" locations
UPDATE stg_tournaments
SET Location = 'Online'
WHERE Location IS NOT NULL
  AND TRIM(LOWER(Location)) = 'online';
  
-- ──────────────────────────────────────────────────────────────────────────────
-- 2) INTEGRITY CHECKS (soft, before building curated)
-- ──────────────────────────────────────────────────────────────────────────────

-- A) EndDate must be present and >= StartDate (when StartDate exists)
--    (We don't UPDATE here; we just mark bad rows for review)
DROP TEMPORARY TABLE IF EXISTS tmp_bad_dates;
CREATE TEMPORARY TABLE tmp_bad_dates AS
SELECT t.*
FROM stg_tournaments t
WHERE (EndDate IS NULL)
   OR (StartDate IS NOT NULL AND EndDate < StartDate);

-- B) GameId ↔ GameName consistency (by majority vote from stg_games)
--    If GameName is missing in tournaments, fill from stg_games.
UPDATE stg_tournaments t
JOIN stg_games g USING (GameId)
SET t.GameName = g.GameName
WHERE (t.GameName IS NULL OR t.GameName = '');

-- C) Ensure TournamentId uniqueness
--    (If duplicates exist, keep the latest EndDate row)
DROP TEMPORARY TABLE IF EXISTS tmp_dupe_tournaments;
CREATE TEMPORARY TABLE tmp_dupe_tournaments AS
SELECT TournamentId, COUNT(*) cnt
FROM stg_tournaments GROUP BY TournamentId HAVING cnt > 1;

-- D) Negative/zero prizes (set to NULL for zero; negative flagged)
UPDATE stg_player_results SET PrizeUSD = NULL WHERE PrizeUSD = 0;
-- Keep negatives for QA; we won't delete them, but they won't affect most sums.
