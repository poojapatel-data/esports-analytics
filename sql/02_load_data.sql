-- 02_load_clean.sql
USE esports_analytics_new;
SET SESSION local_infile = 1;

LOAD DATA LOCAL INFILE '/absolute/path/to/data/tournaments.csv'
INTO TABLE stg_tournaments
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE '/absolute/path/to/data/games.csv'
INTO TABLE stg_games
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE '/absolute/path/to/data/player_results.csv'
INTO TABLE stg_player_results
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 ROWS;

-- Row counts first (quick sanity check)
SELECT 'stg_tournaments' AS table_name, COUNT(*) AS ROW_COUNT FROM stg_tournaments
UNION ALL
SELECT 'stg_games', COUNT(*) FROM stg_games
UNION ALL
SELECT 'stg_player_results', COUNT(*) FROM stg_player_results;

-- Peek first 10 rows from each table
SELECT * FROM stg_tournaments     LIMIT 10;
SELECT * FROM stg_games           LIMIT 10;
SELECT * FROM stg_player_results  LIMIT 10;

DROP TABLE IF EXISTS stg_player_results;

-- 0) Ensure a surrogate PK exists (safe if already present)
ALTER TABLE stg_player_results
  ADD COLUMN IF NOT EXISTS spr_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY;

-- 1) (Optional) First, remove *exact* duplicates (identical rows across all columns)
WITH hashed AS (
  SELECT
    spr_id,
    SHA2(CONCAT_WS('|',
      TournamentId, GameId, GameName, TournamentName, EndDate,
      PlayerId, CountryCode, PrizeUSD, Teamplay, ValorantRegion, ValorantStage
    ), 256) AS h,
    ROW_NUMBER() OVER (
      PARTITION BY SHA2(CONCAT_WS('|',
        TournamentId, GameId, GameName, TournamentName, EndDate,
        PlayerId, CountryCode, PrizeUSD, Teamplay, ValorantRegion, ValorantStage
      ), 256)
      ORDER BY spr_id
    ) rn
  FROM stg_player_results
)
DELETE spr
FROM stg_player_results spr
JOIN hashed h ON h.spr_id = spr.spr_id
WHERE h.rn > 1;

-- 2) Semantic de-dupe: keep ONE row per (TournamentId, PlayerId, GameId, ValorantStage)
--    Preference order: higher PrizeUSD → non-'ZZ' country → newer EndDate → Teamplay=1 → higher spr_id
WITH ranked AS (
  SELECT
    spr_id,
    ROW_NUMBER() OVER (
      PARTITION BY TournamentId, PlayerId, GameId, ValorantStage
      ORDER BY
        COALESCE(PrizeUSD, -1) DESC,
        (CountryCode <> 'ZZ') DESC,
        EndDate DESC,
        Teamplay DESC,
        spr_id DESC
    ) AS rn
  FROM stg_player_results
)
DELETE spr
FROM stg_player_results spr
JOIN ranked r ON r.spr_id = spr.spr_id
WHERE r.rn > 1;

-- 3) Guardrail: prevent future dupes (adjust key if you drop ValorantStage)
ALTER TABLE stg_player_results
  ADD UNIQUE KEY IF NOT EXISTS uniq_pr (TournamentId, PlayerId, GameId, ValorantStage);
