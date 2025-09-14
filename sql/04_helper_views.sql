-- Helper Views

-- ──────────────────────────────────────────────────────────────────────────────
-- 3) BUILD CURATED STAR TABLES (DROP+CREATE FROM CLEANED STAGING)
-- ──────────────────────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS dim_game;
CREATE TABLE dim_game AS
SELECT DISTINCT
  t.GameId,
  g.GameName
FROM stg_tournaments t
JOIN stg_games g
  ON g.GameId = t.GameId;

ALTER TABLE dim_game
  ADD PRIMARY KEY (GameId);

DROP TABLE IF EXISTS dim_country;
CREATE TABLE dim_country AS
SELECT DISTINCT CountryCode
FROM stg_player_results;

ALTER TABLE dim_country
  ADD PRIMARY KEY (CountryCode);

DROP TABLE IF EXISTS fact_tournament;
CREATE TABLE fact_tournament AS
SELECT
  t.TournamentId,
  t.GameId,
  t.GameName,
  t.TournamentName,
  t.StartDate,
  t.EndDate,
  t.Location,
  t.Teamplay,
  t.TotalUSDPrize,
  t.Year
FROM stg_tournaments t
WHERE t.TournamentId IS NOT NULL;

ALTER TABLE fact_tournament
  ADD PRIMARY KEY (TournamentId),
  ADD KEY idx_ft_game (GameId),
  ADD KEY idx_ft_date (EndDate);

DROP TABLE IF EXISTS fact_player_result;
CREATE TABLE fact_player_result AS
SELECT
  pr.TournamentId,
  pr.GameId,
  pr.GameName,
  pr.TournamentName,
  pr.EndDate,
  pr.PlayerId,
  pr.CountryCode,
  pr.PrizeUSD,
  pr.Teamplay,
  pr.ValorantRegion,
  pr.ValorantStage
FROM stg_player_results pr
WHERE pr.TournamentId IS NOT NULL;

ALTER TABLE fact_player_result
  ADD KEY idx_fpr_tour (TournamentId),
  ADD KEY idx_fpr_game (GameId),
  ADD KEY idx_fpr_date (EndDate),
  ADD KEY idx_fpr_cc   (CountryCode);

-- Foreign keys 
ALTER TABLE fact_tournament
ADD CONSTRAINT fk_ft_game FOREIGN KEY (GameId) REFERENCES dim_game(GameId);
ALTER TABLE fact_player_result
ADD CONSTRAINT fk_fpr_game FOREIGN KEY (GameId) REFERENCES dim_game(GameId),
ADD CONSTRAINT fk_fpr_cc   FOREIGN KEY (CountryCode) REFERENCES dim_country(CountryCode);

-- ──────────────────────────────────────────────────────────────────────────────
-- 4) RECONCILIATION VIEW: tournament prize vs sum of players
--    (Flags events where sums differ materially; team/split logic might cause tiny diffs)
-- ──────────────────────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS v_prize_recon;
CREATE VIEW v_prize_recon AS
SELECT
  ft.TournamentId,
  ft.GameName,
  ft.TournamentName,
  ft.TotalUSDPrize AS prize_tournament,
  ROUND(SUM(fpr.PrizeUSD), 2) AS prize_players,
  ROUND(SUM(fpr.PrizeUSD), 2) - ft.TotalUSDPrize AS delta_abs,
  CASE
    WHEN ft.TotalUSDPrize IS NULL OR ft.TotalUSDPrize = 0 THEN NULL
    ELSE (ROUND(SUM(fpr.PrizeUSD), 2) - ft.TotalUSDPrize) / ft.TotalUSDPrize
  END AS delta_pct
FROM fact_tournament ft
LEFT JOIN fact_player_result fpr USING (TournamentId)
GROUP BY ft.TournamentId, ft.GameName, ft.TournamentName, ft.TotalUSDPrize;

-- For easy triage:
SELECT * FROM v_prize_recon WHERE ABS(delta_pct) > 0.05 ORDER BY ABS(delta_pct) DESC;

-- drop tournaments where |player_sum − tournament_prize| > 10%
CREATE OR REPLACE VIEW fact_player_result_clean AS
SELECT fpr.*
FROM fact_player_result fpr
WHERE fpr.TournamentId NOT IN (
  SELECT TournamentId
  FROM v_prize_recon
  WHERE delta_pct IS NOT NULL
    AND ABS(delta_pct) > 0.05
);

