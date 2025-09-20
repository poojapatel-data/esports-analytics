# Data Dictionary

Documents fields used in model/visuals. Prefixes mirror SQL star schema.

<br>

**Star schema (Power BI):**

* Facts: `fact_player_result_clean`, `fact_tournament`
* Dims: `dim_game`, `dim_country`, `Date`


> Units: **USD**. Dates in **UTC** (as delivered by source). Country `"ZZ"` = **Unknown**.
> Country codes are normalized to **upper-case** in the BI model (source may be lower-case).

<br>

## 1) Fact Tables

### `esports_analytics fact_player_result_clean`
| Column         | Type     | Description |
|---|---|---|
| TournamentId   | INT      | Tournament key (joins to `fact_tournament`) |
| GameId         | INT      | Game key (joins to `dim_game`) |
| GameName       | TEXT     | Denormalized for convenience |
| TournamentName | TEXT     | Tournament display name |
| EndDate        | DATE     | Result date (joins to `Date[Date]`) |
| PlayerId       | INT?     | Player identifier (null for unknowns) |
| CountryCode    | CHAR(4)  | ISO-like country code; **"ZZ" = unknown** |
| PrizeUSD       | DECIMAL  | Per-player prize share (USD) |
| Teamplay       | TINYINT  | 0 = solo, 1 = team event |
| ValorantRegion | TEXT?    | Heuristic parse from tournament name (VALORANT only) |
| ValorantStage  | TEXT?    | Kickoff/Masters/Champions/… (VALORANT only) |

<br>

### `esports_analytics fact_tournament`
| Column        | Type     | Description |
|---|---|---|
| TournamentId  | INT (PK) | Tournament key |
| GameId        | INT      | Game key |
| GameName      | TEXT     | Denormalized |
| TournamentName| TEXT     | Name |
| StartDate     | DATE     | Start date |
| EndDate       | DATE     | End date |
| Location      | TEXT     | City/country/“Online” |
| Teamplay      | TINYINT  | 0/1 |
| TotalUSDPrize | DECIMAL  | Organizer-reported total prize |
| Year          | INT      | Convenience year |

<br>

## 2) Dimensions

### `esports_analytics dim_game`
| Column  | Type | Description |
|---|---|---|
| GameId  | INT (PK) | Identifier |
| GameName| TEXT     | Game name |

<br>

### `esports_analytics dim_country`
| Column    | Type | Description |
|---|---|---|
| CountryCode | CHAR(4) (PK) | Country code; **"ZZ" = unknown** |

<br>

### `Date`
| Column       | Type | Description |
|---|---|---|
| Date         | DATE | Calendar date (marked as Date table) |
| Year         | INT  | Year |
| Month        | TEXT | Month name |
| Month Number | INT  | 1–12 |
| YearMonth    | INT  | YYYYMM |

<br>

## 3) Engineered / Cleaning Rules

- Per-player **PrizeUSD** for team events splits team prize equally across known + unknown player slots (unknowns carried as `PlayerId=NULL`, `CountryCode="ZZ"`).
- **Unknown countries** normalized to `"ZZ"`, excluded from “Known” calculations.
- **Reconciliation filter:** tournaments where |Σ per-player prize − total prize| > **10%** are excluded from `fact_player_result_clean` (via view `v_prize_recon`).
* **Text normalization:** Trimmed strings, upper-case country codes, consistent title names.
* **Date alignment:** All prize rows take the **tournament EndDate** as the result date for time-series consistency.

<br>

## 4) KPI inputs (how fields are used)

* **Totals & bars:** `PrizeUSD`, `GameId`, `GameName`, `TournamentId`.
* **Geo:** `CountryCode` (excluding `"ZZ"` for **Known** metrics).
* **Concentration:** Country-level aggregation of `PrizeUSD` → **HHI** and **Top-5 Country Share %**.
* **Velocity:** Time windowing over `EndDate` with the `Date` table (e.g., **Last 180d** vs **Prev 180d**).

---

<br>

## Appendix A — Raw source columns

These reflect the CSVs produced by `esports_pull.py`. Keeping them here for traceability; not all appear in the BI model.

### `player_results.csv` 

| Column             | Example                 | Description                                                              |
| ------------------ | ----------------------- | ------------------------------------------------------------------------ |
| **TournamentId**   | `73234`                 | Unique identifier of the tournament this result belongs to.              |
| **GameId**         | `409`                   | Unique identifier of the game/title (joins to games list).               |
| **GameName**       | `Rocket League`         | Display name of the game/title.                                          |
| **TournamentName** | `Raidiant Invitational` | Official name of the tournament.                                         |
| **EndDate**        | `2025-09-07`            | Calendar date on which the tournament finished.                          |
| **PlayerId**       | `103873.0`              | Unique identifier of the player; may be missing for unknown roster slots.|
| **CountryCode**    | `us`                    | Player’s country code (lower-case here); used for geo analysis.          |
| **PrizeUSD**       | `1000.0`                | Player’s prize amount in USD (after any team prize split).               |
| **Teamplay**       | `1`                     | Event type flag: 0 = solo event, 1 = team event.                         |

<br>

### `tournaments.csv`

| Column             | Example                              |  Description                                                       |
| ------------------ | ------------------------------------ | ------------------------------------------------------------------ |
| **TournamentId**   | `73234`                              | Unique identifier of the tournament (primary key).                 |
| **GameId**         | `409`                                | Unique identifier of the game/title this tournament is for.        |
| **TournamentName** | `Champions Road 2025 - 3v3 Open: EU` | Official tournament name from the source.                          |
| **StartDate**      | `2025-09-02`                         | Date the tournament started.                                       |
| **EndDate**        | `2025-09-04`                         | Date the tournament ended.                                         |
| **Location**       | `Online`                             | Reported location (city/country) or the string `Online`.           |
| **Teamplay**       | `1`                                  | Event type flag: `0` = solo event, `1` = team event.               |
| **TotalUSDPrize**  | `54750.0`                            | Organizer-reported total prize pool in USD for the tournament.     |
| **GameName**       | `Rocket League`                      | Game/title name repeated by the source (denormalized convenience). |
| **Year**           | `2025`                               | Year extracted from dates for time slicing.                        |

<br>

### `games.csv`

| Column       | Example        |  Description                              |
| ------------ | -------------- | ----------------------------------------- |
| **GameId**   | `151`          | Unique identifier/key for the game/title. |
| **GameName** | `StarCraft II` | Canonical display name of the game/title. |

> Note: In the BI model, CountryCode is normalized to upper-case and unknowns are standardized to "ZZ" to preserve totals while allowing “Known-only” KPIs.
