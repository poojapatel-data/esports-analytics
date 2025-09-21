# KPIs & Measures 

**Scope:** Business definitions + all DAX used in the report.  

**Model**:<br>
Fact tables: `esports_analytics fact_player_result_clean`, `esports_analytics fact_tournament`  
Dims: `Date`, `esports_analytics dim_game`, `esports_analytics dim_country`  

>**Notes.** Country `"ZZ"` = unknown (excluded from “Known” metrics).

---

## 1) KPI Definitions

- **Total Prize $** — Sum of per-player prize USD across selected filters.
- **Known Prize $** — Total Prize excluding unknown countries (`CountryCode <> "ZZ"`).
- **Tournaments #** — Distinct count of tournaments in context.
- **Countries #** — Count of distinct (known) countries represented by prize.
- **Top5 Country Share %** — Share of prize captured by top-5 countries.
- **HHI** — Herfindahl–Hirschman Index of country concentration (0–1).
- **ΔPrize** — Last 180d prize − previous 180d prize.
- **ΔCountries** — Last 180d countries − previous 180d countries.

---

## 2) Measures (DAX)
### Core

#### Total Prize $ 
```
Total Prize $ :=
SUM ( 'esports_analytics fact_player_result_clean'[PrizeUSD] )
```

#### Known Prize $
```
Known Prize $ :=
CALCULATE ( [Total Prize $],
  'esports_analytics fact_player_result_clean'[CountryCode] <> "ZZ"
)
```

#### Tournaments #
```
Tournaments # :=
DISTINCTCOUNT ( 'esports_analytics fact_player_result_clean'[TournamentId] )
```

#### Countries #
```
Countries # :=
CALCULATE (
  DISTINCTCOUNT ( 'esports_analytics fact_player_result_clean'[CountryCode] ),
  'esports_analytics fact_player_result_clean'[CountryCode] <> "ZZ"
)
```

<br>

### Top-5 share & HHI (country concentration)

#### Top5 Country Share %
```
Top5 Country $ :=
VAR T =
    TOPN (
        5,
        SUMMARIZE (
            'esports_analytics fact_player_result_clean',
            'esports_analytics fact_player_result_clean'[CountryCode],
            "P", CALCULATE (
                    SUM ( 'esports_analytics fact_player_result_clean'[PrizeUSD] ),
                    'esports_analytics fact_player_result_clean'[CountryCode] <> "ZZ"
            )
        ),
        [P], DESC
    )
RETURN
    SUMX ( T, [P] )
```

#### Top5 Country Share %
```
Top5 Country Share % :=
DIVIDE ( [Top5 Country $], [Known Prize $] )
```

#### HHI
```
HHI :=
VAR Total = [Known Prize $]
RETURN
SUMX (
    SUMMARIZE (
        'esports_analytics fact_player_result_clean',
        'esports_analytics fact_player_result_clean'[CountryCode],
        "P",
            CALCULATE (
                SUM ( 'esports_analytics fact_player_result_clean'[PrizeUSD] ),
                'esports_analytics fact_player_result_clean'[CountryCode] <> "ZZ"
            )
    ),
    VAR p = [P]
    RETURN POWER ( DIVIDE ( p, Total ), 2 )
)
```

### Velocity (180d vs previous 180d)

#### Prize (Last 180d)
```
Prize (Last 180d) :=
CALCULATE ( [Known Prize $],
  DATESINPERIOD ( 'Date'[Date], MAX ( 'Date'[Date] ), -180, DAY )
)
```

#### Prize (Prev 180d
```
Prize (Prev 180d) :=
CALCULATE (
  [Known Prize $],
  DATEADD (
    DATESINPERIOD ( 'Date'[Date], MAX ( 'Date'[Date] ), -180, DAY ),
    -180, DAY
  )
)
```

#### ΔPrize
```
ΔPrize := [Prize (Last 180d)] - [Prize (Prev 180d)]
```

#### Countries #(Last 180d)
```
Countries #(Last 180d) :=
CALCULATE ( [Countries #],
  DATESINPERIOD ( 'Date'[Date], MAX ( 'Date'[Date] ), -180, DAY )
)
```

#### Countries #(Prev 180d)
```
Countries #(Prev 180d) :=
CALCULATE (
  [Countries #],
  DATEADD (
    DATESINPERIOD ( 'Date'[Date], MAX ( 'Date'[Date] ), -180, DAY ),
    -180, DAY
  )
)
```

#### ΔCountries
```
ΔCountries := [Countries #(Last 180d)] - [Countries #(Prev 180d)]
```

<br>

### Pareto (Country ranking & cumulative share)

#### Prize by Country $
```
Prize by Country $ :=
VAR CurrentCountry =
    SELECTEDVALUE ( 'esports_analytics fact_player_result_clean'[CountryCode] )
RETURN
IF (
    NOT ISBLANK ( CurrentCountry ) && CurrentCountry <> "ZZ",
    CALCULATE (
        SUM ( 'esports_analytics fact_player_result_clean'[PrizeUSD] ),
        'esports_analytics fact_player_result_clean'[CountryCode] = CurrentCountry
    ),
    BLANK()
)
```

#### Rank Country by Prize
```
Rank Country by Prize :=
RANKX (
    FILTER (
        ALL ( 'esports_analytics fact_player_result_clean'[CountryCode] ),
        [Prize by Country $] > 0
    ),
    [Prize by Country $],
    ,
    DESC,
    DENSE
)
```

#### Cumulative Prize $
```
Cumulative Prize $ :=
VAR r = [Rank Country by Prize]
RETURN
IF (
    ISBLANK ( r ),
    BLANK (),
    SUMX (
        TOPN (
            r,
            ADDCOLUMNS (
                ALLSELECTED ( 'esports_analytics fact_player_result_clean'[CountryCode] ),
                "__p", [Prize by Country $]
            ),
            [__p], DESC
        ),
        [__p]
    )
)
```

#### Cumulative Share %
```
Cumulative Share % :=
DIVIDE (
    [Cumulative Prize $],
    CALCULATE(
        SUM('esports_analytics fact_player_result_clean'[PrizeUSD]),
        'esports_analytics fact_player_result_clean'[CountryCode] <> "ZZ"
    )
)

```
