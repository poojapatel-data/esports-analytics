# Process & Design 

**Goal:** Recent esports prize distribution by game & geography with simple concentration/velocity diagnostics.

---

## 1) Pipeline (Raw → SQL → Power BI)

1) **Ingestion (Python)**
- Script: `esports_pull.py`  
  - Pulls recent tournaments (API pages), maps `GameId→GameName`.
  - Fetches **solo** results and **team** results (+ team players).
  - Splits team prize equally across team size (accounts for unknown players).
  - Heuristically parses VALORANT region/stage from `TournamentName`.
  - Writes CSVs: `tournaments.csv`, `games.csv`, `player_results.csv`.

2) **MySQL (Staging → Curated)**
- Load CSVs to `stg_*` tables (UTF-8). Index Date/Game/Country.
- **Cleaning**
  - Trim text, uppercase country, normalize `"ZZ"` unknowns.
  - De-dupe exact & semantic duplicates.
  - Guardrails (null/zero prize → null; date sanity).
- **Star schema**
  - `dim_game`, `dim_country`
  - `fact_tournament`, `fact_player_result`
  - **Reconciliation view** `v_prize_recon` to compare tournament prize vs player sum; drop outliers `>|10%|`.
  - Final fact for BI: `fact_player_result_clean`.

3) **Power BI (Model + DAX + Visuals)**
- Model: `fact_player_result_clean` ↔ `dim_game` (GameId), ↔ `dim_country` (CountryCode), ↔ `Date[Date]` (EndDate).  
- Measures: KPIs for **Total Prize**, **Countries**, **HHI**, **Top-5 share**, **180-day Δ**.  
- Pages: KPI Overview, Drivers by Game, Map, Country Pareto.

---

## 2) Runbook (local)

1. **Run Python** to produce CSVs (env var `ESE_API_KEY` required).  
2. **Run SQL** in order:
   - `00_create_database.sql`, `01_create_tables.sql`, `02_load_data.sql`,
   - `03_data_clean.sql`, `04_helper_views.sql`, `05_analysis_views.sql`
3. **Power BI**
   - Open `Esports_Analytics.pbix` → Data Source Settings → point to MySQL.
   - Refresh; verify `v_prize_recon` flags are empty/acceptable.

---

## 3) Design Choices & Assumptions

- **Unit:** USD. **Timezone:** UTC (as provided by API).  
- **Unknowns:** Keep `"ZZ"` for accounting, exclude from “Known” KPIs.  
- **Concentration metrics:** Country level HHI and Top-5 share.  
- **Velocity window:** 180d rolling vs prior 180d.  
- **Data freshness:** “Recent tournaments” pages from the API; adjust `--days` / `--pages` as needed.

---

## 4) Figures (suggested)
- **Model (star schema):** (See `images/model.png`).
- **Dashboard (overview):** (See `images/dashboard.png`).
- **KPI (cards only):** (See `images/kpi_strip.png`).

