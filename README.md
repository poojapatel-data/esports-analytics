# Esports Analytics — SQL → Power BI

> Prize pools, market concentration (HHI & Top-5 share), geographic breadth, and 180-day momentum across major esports titles.

![Dashboard hero](docs/img/dashboard-overview.png)

## TL;DR (highlights)

* **Scope analyzed:** **33,813** player results, **1,086** tournaments, **13** titles, **122** countries.&#x20;
* **Market size (slice):** **\$63.67M** prize pools.&#x20;
* **Consolidation:** Top 4 titles control **\~78.8%** of prize capital.&#x20;
* **Distribution:** CS2’s HHI ≈ **0.065** → most globally distributed; some titles are highly concentrated.&#x20;
* **Momentum:** Fortnite & CS2 lead 180-day growth in this period.&#x20;

---

## Problem & Audience

**Business questions:** Which games and countries concentrate prize money? How concentrated is each market (HHI/Top-5)? Where is momentum rising or falling?&#x20;

**Who it’s for:** tournament organizers, sponsors/investors, publishers, and market researchers making portfolio and geo-expansion decisions.

---

## Data & Model

**Facts & Dims (star schema):**

* `fact_player_result_clean` (33,813 rows), `fact_tournament` (1,086) with key fields: `TournamentId, GameId, PlayerId, CountryCode, PrizeUSD, EndDate`.&#x20;
* `dim_game` (13), `dim_country` (122; handles “ZZ” unknown).&#x20;

**Analytical views:** `v_game_total`, `v_game_breadth`, `v_game_concentration` (Top-5 & HHI), `v_game_velocity`, `v_prize_recon`.&#x20;

> **Team vs Solo logic:** `Teamplay=false` → use player results (already per-player). `Teamplay=true` → split team prize equally across known players + `UnknownPlayerCount`; then **exclude** `CountryCode="ZZ"` for country views. &#x20;

![Model](docs/img/data-model-relationships.png)

---

## KPIs & Measures (Power BI)

* **Financial:** `Total Prize $`, `Known Prize $` (excludes `ZZ`), Prize by Country.&#x20;
* **Volume:** `Tournaments #`, `Countries #` (ex-ZZ).&#x20;
* **Concentration:** `Top5 Country $`, `Top5 Country Share %`, **HHI**.&#x20;
* **Velocity:** last 180d vs previous 180d + deltas; ΔCountries.&#x20;
* **Cumulative/Pareto:** `Cumulative Prize $`, `Cumulative Share %`, `Rank Country by Prize`.&#x20;

> **Example HHI DAX (excerpt in docs):** see `docs/CaseStudy.md` for a working pattern you can paste.&#x20;

![KPI cards](docs/img/kpi-cards.png)

---

## Results (selected)

* **Top-tier dominance:** CS2, Dota 2, Fortnite, LoL = **78.8%** of prize pools in this slice.&#x20;
* **Geographic breadth:** Rocket League (**95** countries), Fortnite (**83**), CS2 (**81**).&#x20;
* **Velocity:** Fortnite +123% (+\$3.62M) and CS2 +50% (+\$3.33M) in last 180d (period analyzed).&#x20;

![Pareto](docs/img/pareto-top5.png) ![Velocity](docs/img/velocity-180d.png)
![HHI](docs/img/hhi-scatter.png) ![Countries](docs/img/countries-map.png)

---

## How to Run

1. **Load data to SQL**
   Use `sql/00_schema.sql`, `01_load_clean.sql`, `02_model_views.sql`, `03_quality_checks.sql` (views listed above).&#x20;

2. **Open Power BI Template**
   Open `powerbi/Esports_Analytics.pbit`, set your SQL connection, and **Refresh**. Validate totals against screenshots.

3. **(Optional) Data sources used**
   EsportsEarnings API (`LookupRecentTournaments`, `LookupGameById`), Valorant CSV enrichment; Liquipedia for prize-tier cross-checks.&#x20;

---
## Optional: Python helper (simple API fetch)

If you want to show how the raw data was pulled (not a full pipeline), include a tiny script and keep it separate from the Power BI bits.

File: scripts/fetch_esports_api.py

**Quick start (Windows/PowerShell)**

```powershell
py -m venv .venv
.\.venv\Scripts\activate
python scripts/fetch_esports_api.py --endpoint tournaments --since 2024-01-01 --out data/raw/tournaments.json
```
---

## Repository Structure

```
.
├─ README.md
├─ docs/
│  ├─ CaseStudy.md
│  └─ img/  # add screenshots here (see names used above)
├─ sql/
│  ├─ 00_schema.sql
│  ├─ 01_load_clean.sql
│  ├─ 02_model_views.sql
│  └─ 03_quality_checks.sql
├─ powerbi/
│  ├─ Esports_Analytics.pbit
│  └─ Esports_Analytics.pbix   # optional (LFS or Release asset)
└─ data/
   ├─ games.csv
   ├─ player_results.csv
   └─ tournaments.csv
```

---

## Ethics & Limitations

* **Prize pools ≠ salaries**; interpret as **prize concentration**, not earnings power.&#x20;
* Country rollups **exclude “ZZ”** after proper team split to avoid bias.&#x20;

---

## Screenshots to include

* `docs/img/dashboard-overview.png` (hero)
* `docs/img/kpi-cards.png` (main KPIs)
* `docs/img/top-games-bar.png` (Top N by prize)
* `docs/img/pareto-top5.png` (cumulative share)
* `docs/img/countries-map.png` (breadth)
* `docs/img/velocity-180d.png` (momentum)
* `docs/img/hhi-scatter.png` (concentration vs size)
* `docs/img/prize-per-tournament.png` (efficiency)
* `docs/img/data-model-relationships.png`, `docs/img/reconciliation-view.png`, `docs/img/dax-measures-folder.png` (build quality)

---

## License

MIT (or your preference).

