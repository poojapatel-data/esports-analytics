-- Analysis Views

-- A) Game × Country prize
CREATE OR REPLACE VIEW v_game_country AS
SELECT
  GameId, GameName, CountryCode,
  SUM(PrizeUSD) AS prize_usd
FROM fact_player_result_clean
WHERE EndDate >= (CURDATE() - INTERVAL 365 DAY)
  AND CountryCode IS NOT NULL
  AND CountryCode <> 'ZZ'
GROUP BY GameId, GameName, CountryCode;

-- B) Game totals (market size) + tournament count
CREATE OR REPLACE VIEW v_game_total AS
SELECT
  GameId, GameName,
  SUM(PrizeUSD) AS prize_usd,
  COUNT(DISTINCT TournamentId) AS tourneys
FROM fact_player_result_clean
WHERE EndDate >= (CURDATE() - INTERVAL 365 DAY)
GROUP BY GameId, GameName;

-- C) Concentration (Top-5 country share & HHI) by game
CREATE OR REPLACE VIEW v_game_concentration AS
WITH ranked AS (
  SELECT
    gc.*,
    ROW_NUMBER() OVER (PARTITION BY GameId ORDER BY prize_usd DESC) AS rn,
    SUM(prize_usd) OVER (PARTITION BY GameId) AS game_total
  FROM v_game_country gc
)
SELECT
  GameId,
  GameName,
  SUM(CASE WHEN rn <= 5 THEN prize_usd ELSE 0 END) / MAX(game_total) AS top5_country_share,
  SUM(POWER(prize_usd / NULLIF(game_total,0), 2))                   AS hhi
FROM ranked
GROUP BY GameId, GameName;

-- D) Breadth: how many countries per game
CREATE OR REPLACE VIEW v_game_breadth AS
SELECT GameId, GameName, COUNT(*) AS countries
FROM v_game_country
GROUP BY GameId, GameName;

-- E) Velocity: last 180d vs previous 180d

-- your data spans 2025-06-21 → 2025-08-05 and there are 0 rows in the prior 180-day window, so the original velocity view (which JOINed P1 to P0) will return nothing. 
CREATE OR REPLACE VIEW v_game_velocity AS
WITH p AS (
  SELECT 'P1' AS period, CURDATE() - INTERVAL 180 DAY AS start_dt, CURDATE() AS end_dt
  UNION ALL
  SELECT 'P0', CURDATE() - INTERVAL 360 DAY, CURDATE() - INTERVAL 180 DAY
),
agg AS (
  SELECT
    p.period, f.GameId, f.GameName,
    SUM(f.PrizeUSD) AS prize,
    COUNT(DISTINCT f.TournamentId) AS tourneys,
    COUNT(DISTINCT CASE WHEN f.CountryCode <> 'ZZ' THEN f.CountryCode END) AS countries
  FROM fact_player_result_clean f
  JOIN p ON f.EndDate >= p.start_dt AND f.EndDate < p.end_dt
  GROUP BY p.period, f.GameId, f.GameName
)
SELECT
  cur.GameId, cur.GameName,
  cur.prize AS prize_P1, prev.prize AS prize_P0, (cur.prize - prev.prize) AS d_prize,
  cur.tourneys AS t_P1, prev.tourneys AS t_P0, (cur.tourneys - prev.tourneys) AS d_tourneys,
  cur.countries AS c_P1, prev.countries AS c_P0, (cur.countries - prev.countries) AS d_countries
FROM agg cur
JOIN agg prev USING (GameId, GameName)
WHERE cur.period='P1' AND prev.period='P0';


select * from v_game_velocity;
-- changed view for above 

CREATE OR REPLACE VIEW v_game_velocity AS
WITH p AS (
  SELECT 'P1' AS period, CURDATE() - INTERVAL 180 DAY AS start_dt, CURDATE() AS end_dt
  UNION ALL
  SELECT 'P0', CURDATE() - INTERVAL 360 DAY, CURDATE() - INTERVAL 180 DAY
),
agg AS (
  SELECT
    p.period, f.GameId, f.GameName,
    SUM(f.PrizeUSD) AS prize,
    COUNT(DISTINCT f.TournamentId) AS tourneys,
    COUNT(DISTINCT CASE WHEN f.CountryCode <> 'ZZ' THEN f.CountryCode END) AS countries
  FROM fact_player_result_clean f
  JOIN p
    ON f.EndDate >= p.start_dt AND f.EndDate < p.end_dt
  GROUP BY p.period, f.GameId, f.GameName
)
SELECT
  GameId, GameName,
  SUM(CASE WHEN period='P1' THEN prize    ELSE 0 END) AS prize_P1,
  SUM(CASE WHEN period='P0' THEN prize    ELSE 0 END) AS prize_P0,
  SUM(CASE WHEN period='P1' THEN tourneys ELSE 0 END) AS t_P1,
  SUM(CASE WHEN period='P0' THEN tourneys ELSE 0 END) AS t_P0,
  SUM(CASE WHEN period='P1' THEN countries ELSE 0 END) AS c_P1,
  SUM(CASE WHEN period='P0' THEN countries ELSE 0 END) AS c_P0,
  (SUM(CASE WHEN period='P1' THEN prize ELSE 0 END)
 - SUM(CASE WHEN period='P0' THEN prize ELSE 0 END)) AS d_prize,
  (SUM(CASE WHEN period='P1' THEN tourneys ELSE 0 END)
 - SUM(CASE WHEN period='P0' THEN tourneys ELSE 0 END)) AS d_tourneys,
  (SUM(CASE WHEN period='P1' THEN countries ELSE 0 END)
 - SUM(CASE WHEN period='P0' THEN countries ELSE 0 END)) AS d_countries
FROM agg
GROUP BY GameId, GameName
HAVING prize_P1 > 0 OR prize_P0 > 0;
SELECT * FROM v_game_total ORDER BY prize_usd DESC LIMIT 10;
SELECT * FROM v_game_concentration ORDER BY hhi DESC LIMIT 10;
SELECT * FROM v_game_breadth ORDER BY countries DESC LIMIT 10;
SELECT * FROM v_game_velocity ORDER BY d_countries DESC, d_prize DESC LIMIT 10;


