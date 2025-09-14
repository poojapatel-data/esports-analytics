#!/usr/bin/env python3
"""
EsportsEarnings API → tidy CSVs for portfolio analysis (Valorant + top games)
- Pulls recent tournaments
- Maps GameId→GameName
- Fetches results (solo path vs team path)
- Computes per-player prize shares for team events
- Parses Valorant region/stage heuristically from TournamentName
- Writes tournaments.csv, games.csv, player_results.csv

Usage:
  export ESE_API_KEY="YOUR_KEY"
  python esports_pull.py --days 365 \
     --games "VALORANT,League of Legends,Counter-Strike 2,Fortnite,Overwatch,Overwatch 2" \
     --pages 3
"""

import os
import time
import argparse
import requests
import pandas as pd
from datetime import datetime, timedelta
from dateutil import parser as dtparse

BASE_URL = "https://api.esportsearnings.com/v0"
RPS_DELAY = 1.05  # seconds between calls (API limit is 1 req/sec)

# ----------------------------- API client -----------------------------

class EEClient:
    def __init__(self, api_key: str):
        self.api_key = api_key
        # TEMP insecure toggle from CLI args
        self.insecure = insecure if (insecure:=getattr(args,'insecure',False)) else False

    def _get(self, method: str, **params):
        """Call EsportsEarnings API, return JSON, raise on API error codes."""
        all_params = dict(params)
        all_params["apikey"] = self.api_key
        url = f"{BASE_URL}/{method}"
        r = requests.get(url, params=all_params, timeout=30, verify=(not self.insecure))
        try:
            data = r.json()
        except Exception:
            r.raise_for_status()
        # Error handling per API docs (e.g., {"ErrorCode":1010, "Error":"Invalid API Key"})
        if isinstance(data, dict) and "ErrorCode" in data:
            raise RuntimeError(f"API Error {data.get('ErrorCode')}: {data.get('Error')}")
        time.sleep(RPS_DELAY)  # be polite
        return data

    # --- Methods used in this script ---

    def lookup_recent_tournaments(self, offset=0, format="json"):
        return self._get("LookupRecentTournaments", offset=offset, format=format)

    def lookup_game_by_id(self, gameid: int, format="json"):
        return self._get("LookupGameById", gameid=gameid, format=format)

    def lookup_tournament_results_solo(self, tournamentid: int, format="json"):
        return self._get("LookupTournamentResultsByTournamentId", tournamentid=tournamentid, format=format)

    def lookup_tournament_team_results(self, tournamentid: int, format="json"):
        return self._get("LookupTournamentTeamResultsByTournamentId", tournamentid=tournamentid, format=format)

    def lookup_tournament_team_players(self, tournamentid: int, format="json"):
        return self._get("LookupTournamentTeamPlayersByTournamentId", tournamentid=tournamentid, format=format)

# ----------------------------- Helpers -----------------------------

VALORANT_TOKENS_REGION = ["EMEA", "Americas", "Pacific", "China"]
VALORANT_TOKENS_STAGE  = ["Kickoff", "Masters", "Champions", "Challengers", "Ascension", "Game Changers"]

def parse_valorant_region_stage(tname: str):
    """
    Very light heuristic: look for tokens in the tournament name.
    Returns (region, stage) or (None, None).
    """
    if not tname:
        return None, None
    name = tname.upper()
    is_valorant = ("VALORANT" in name) or ("VCT" in name)  # broad
    if not is_valorant:
        return None, None

    region = None
    for tok in VALORANT_TOKENS_REGION:
        if tok.upper() in name:
            region = tok
            break

    stage = None
    for tok in VALORANT_TOKENS_STAGE:
        if tok.upper() in name:
            stage = tok
            break

    return region, stage

def normalize_game_name(n: str) -> str:
    return (n or "").strip().lower()

def within_days(date_str: str, days: int) -> bool:
    try:
        d = dtparse.parse(date_str).date()
        return d >= (datetime.utcnow().date() - timedelta(days=days))
    except Exception:
        return False

# ----------------------------- Core logic -----------------------------

def fetch_recent_tournaments(client: EEClient, pages: int, page_size: int = 100):
    """
    Pull N pages of recent tournaments (page_size=100 per API).
    Returns list[dict].
    """
    all_t = []
    for i in range(pages):
        offset = i * page_size
        print(f"[tournaments] fetching offset={offset}")
        data = client.lookup_recent_tournaments(offset=offset)
        if not data:
            break
        # Ensure a list
        if isinstance(data, dict):
            data = [data]
        all_t.extend(data)
        # Stop early if less than a full page returned
        if len(data) < page_size:
            break
    print(f"[tournaments] pulled {len(all_t)} rows")
    return all_t

def map_game_ids(client: EEClient, game_ids: set):
    """
    For each GameId, fetch name once; return dict {GameId: GameName}
    """
    mapping = {}
    for gid in sorted(game_ids):
        try:
            info = client.lookup_game_by_id(gid)
            # API might return dict or list with one object; normalize
            if isinstance(info, list) and info:
                info = info[0]
            gname = info.get("GameName") or info.get("Name") or ""
            mapping[gid] = gname
            print(f"[game] {gid} → {gname}")
        except Exception as e:
            print(f"[warn] game {gid} name fetch failed: {e}")
    return mapping

def build_player_rows_for_tournament(client: EEClient, t: dict, game_name: str):
    """
    Return list of per-player rows for a given tournament t.
    Handles solo vs team paths. Each row fields:
    TournamentId, GameId, GameName, TournamentName, EndDate,
    PlayerId, CountryCode, PrizeUSD, Teamplay, ValorantRegion, ValorantStage
    """
    tid = t.get("TournamentId")
    gameid = t.get("GameId")
    tname = t.get("TournamentName")
    enddate = t.get("EndDate")
    teamplay = t.get("Teamplay")  # 0 or 1
    v_region, v_stage = parse_valorant_region_stage(tname or "")

    rows = []

    # SOLO path
    if not teamplay:
        try:
            data = client.lookup_tournament_results_solo(tid)
            if isinstance(data, dict):
                data = [data]
            for r in data or []:
                rows.append({
                    "TournamentId": tid,
                    "GameId": gameid,
                    "GameName": game_name,
                    "TournamentName": tname,
                    "EndDate": enddate,
                    "PlayerId": r.get("PlayerId"),
                    "CountryCode": r.get("CountryCode"),
                    "PrizeUSD": r.get("PrizeUSD") or r.get("Prize", 0.0),
                    "Teamplay": 0,
                    "ValorantRegion": v_region,
                    "ValorantStage": v_stage
                })
        except Exception as e:
            print(f"[warn] solo results failed for TID={tid}: {e}")
        return rows

    # TEAM path
    try:
        team_results = client.lookup_tournament_team_results(tid)
        team_players = client.lookup_tournament_team_players(tid)
        if isinstance(team_results, dict):
            team_results = [team_results]
        if isinstance(team_players, dict):
            team_players = [team_players]
        # Group players by TournamentTeamId
        players_by_team = {}
        for p in team_players or []:
            players_by_team.setdefault(p.get("TournamentTeamId"), []).append(p)

        for tr in team_results or []:
            team_id = tr.get("TournamentTeamId")
            prize = tr.get("PrizeUSD") or tr.get("Prize", 0.0)
            unknown_ct = tr.get("UnknownPlayerCount", 0) or 0
            plist = players_by_team.get(team_id, [])
            known_ct = len(plist)
            team_size = known_ct + unknown_ct if (known_ct + unknown_ct) > 0 else max(known_ct, 1)
            per_share = float(prize) / float(team_size) if team_size else 0.0

            for p in plist:
                rows.append({
                    "TournamentId": tid,
                    "GameId": gameid,
                    "GameName": game_name,
                    "TournamentName": tname,
                    "EndDate": enddate,
                    "PlayerId": p.get("PlayerId"),
                    "CountryCode": p.get("CountryCode"),
                    "PrizeUSD": per_share,
                    "Teamplay": 1,
                    "ValorantRegion": v_region,
                    "ValorantStage": v_stage
                })
            # Optionally record "unknown" players as null PlayerId + CountryCode="ZZ"
            # for complete accounting; comment out if you prefer to skip.
            for _ in range(unknown_ct):
                rows.append({
                    "TournamentId": tid,
                    "GameId": gameid,
                    "GameName": game_name,
                    "TournamentName": tname,
                    "EndDate": enddate,
                    "PlayerId": None,
                    "CountryCode": "ZZ",
                    "PrizeUSD": per_share,
                    "Teamplay": 1,
                    "ValorantRegion": v_region,
                    "ValorantStage": v_stage
                })
    except Exception as e:
        print(f"[warn] team results failed for TID={tid}: {e}")

    return rows

# ----------------------------- Main -----------------------------

def main():
    ap = argparse.ArgumentParser(description="EsportsEarnings API → tournaments/games/player_results CSVs")
    ap.add_argument("--api-key", default"", help="EsportsEarnings API key or set ESE_API_KEY")
    ap.add_argument("--days", type=int, default=365, help="How many days back from today to keep tournaments by EndDate")
    ap.add_argument("--pages", type=int, default=3, help="How many pages of recent tournaments to fetch (100 per page)")
    ap.add_argument("--games", type=str, default="VALORANT,League of Legends,Counter-Strike 2,Fortnite,Overwatch,Overwatch 2",
                    help="Comma-separated game names to include (case-insensitive)")
    ap.add_argument("--out-prefix", type=str, default="", help="Optional filename prefix (e.g., data_)")
    ap.add_argument("--insecure", action="store_true", help="TEMP: skip TLS verification (NOT RECOMMENDED)")
    global args
    args = ap.parse_args()

    if not args.api_key:
        raise SystemExit("ERROR: Provide --api-key or set ESE_API_KEY")

    target_games = [normalize_game_name(g) for g in args.games.split(",") if g.strip()]
    print(f"[config] days={args.days}, pages={args.pages}, target_games={target_games}")

    client = EEClient(args.api_key)

    # 1) Pull recent tournaments
    tournaments = fetch_recent_tournaments(client, pages=args.pages)

    # 2) Map GameId→GameName for distinct games we saw
    game_ids = {t.get("GameId") for t in tournaments if t.get("GameId") is not None}
    game_map = map_game_ids(client, game_ids)

    # 3) Attach GameName and filter by date + target games
    enriched = []
    for t in tournaments:
        gid = t.get("GameId")
        t["GameName"] = game_map.get(gid, "")
        if not t.get("EndDate"):  # some rare rows may be missing; keep them if StartDate is recent
            keep = within_days(t.get("StartDate", ""), args.days)
        else:
            keep = within_days(t["EndDate"], args.days)
        if not keep:
            continue
        if target_games and normalize_game_name(t["GameName"]) not in target_games:
            continue
        enriched.append(t)

    print(f"[filter] kept {len(enriched)} tournaments after date/game filters")

    # 4) Build player-level results for each kept tournament
    player_rows = []
    for idx, t in enumerate(enriched, 1):
        print(f"[results] {idx}/{len(enriched)} TID={t.get('TournamentId')} | {t.get('GameName')} | {t.get('TournamentName')}")
        rows = build_player_rows_for_tournament(client, t, t.get("GameName"))
        player_rows.extend(rows)

    # 5) Build frames & write CSVs
    tdf = pd.DataFrame(enriched)
    gdf = pd.DataFrame([{"GameId": gid, "GameName": gname} for gid, gname in game_map.items()])
    pdf = pd.DataFrame(player_rows)

    # Normalize date columns to ISO
    for col in ("StartDate", "EndDate"):
        if col in tdf.columns:
            tdf[col] = pd.to_datetime(tdf[col], errors="coerce").dt.date

    # Add Year for convenience
    if "EndDate" in tdf.columns:
        tdf["Year"] = pd.to_datetime(tdf["EndDate"], errors="coerce").dt.year

    # Save
    prefix = args.out_prefix
    t_out = f"{prefix}tournaments.csv"
    g_out = f"{prefix}games.csv"
    p_out = f"{prefix}player_results.csv"

    tdf.to_csv(t_out, index=False)
    gdf.to_csv(g_out, index=False)
    pdf.to_csv(p_out, index=False)

    print(f"[done] wrote {t_out} ({len(tdf)} rows), {g_out} ({len(gdf)} rows), {p_out} ({len(pdf)} rows)")

if __name__ == "__main__":
    main()
