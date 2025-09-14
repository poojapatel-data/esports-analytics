-- tournaments.csv
DROP TABLE IF EXISTS stg_tournaments;
CREATE TABLE stg_tournaments (
  TournamentId   INT PRIMARY KEY,
  GameId         INT,
  TournamentName VARCHAR(200),
  StartDate      DATE,
  EndDate        DATE,
  Location       VARCHAR(120),
  Teamplay       TINYINT,          -- 0 solo, 1 team
  TotalUSDPrize  DECIMAL(14,2),
  GameName       VARCHAR(120),
  Year           INT
);

-- games.csv
DROP TABLE IF EXISTS stg_games;
CREATE TABLE stg_games (
  GameId   INT PRIMARY KEY,
  GameName VARCHAR(120)
);

-- player_results.csv (per-player prize already computed)
DROP TABLE IF EXISTS stg_player_results;
CREATE TABLE stg_player_results (
  TournamentId    INT,
  GameId          INT,
  GameName        VARCHAR(120),
  TournamentName  VARCHAR(200),
  EndDate         DATE,
  PlayerId        INT NULL,
  CountryCode     VARCHAR(4),     -- "ZZ" used for unknowns
  PrizeUSD        DECIMAL(14,2),
  Teamplay        TINYINT,        -- 0/1
  ValorantRegion  VARCHAR(50) NULL,
  ValorantStage   VARCHAR(50) NULL
);

-- helpful indexes
CREATE INDEX idx_pr_game  ON stg_player_results(GameId);
CREATE INDEX idx_pr_date  ON stg_player_results(EndDate);
CREATE INDEX idx_pr_tour  ON stg_player_results(TournamentId);
CREATE INDEX idx_pr_cc    ON stg_player_results(CountryCode);