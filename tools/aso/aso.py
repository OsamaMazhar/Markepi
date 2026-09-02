#!/usr/bin/env python3
"""Markepi ASO data: App Store Connect analytics, and free rank tracking.

  analytics    App Store Connect's own numbers — impressions, product page
               views, downloads. Needs Apple to have generated instances
               (24-48h after the request is made).

  ranks        Where Markepi sits for each target phrase, from the public
               iTunes Search API. No account, no key, one row per phrase/day.

  popularity   Real Apple search-term popularity (top 500/genre) via the
               Apple Ads API — the demand side of ASO.

  suggest      Apple's own keyword-suggestion expansions for each seed phrase
               — the discovery side, finds phrasings you didn't think of.

  adstest      Connectivity check for the Apple Ads credentials.

Usage:
    python3 tools/aso/aso.py ranks
    python3 tools/aso/aso.py analytics
    python3 tools/aso/aso.py adstest
    python3 tools/aso/aso.py popularity   # -> search_term_popularity.csv
    python3 tools/aso/aso.py suggest      # -> keyword_suggestions.csv

Auth for `analytics`: ASC_ISSUER_ID in the environment and the .p8 at
~/.appstoreconnect/AuthKey_<KEY_ID>.p8.

Auth for `popularity`/`suggest`/`adstest`: SEARCHADS_CLIENT_ID,
SEARCHADS_TEAM_ID, SEARCHADS_KEY_ID, SEARCHADS_KEY_PATH in the environment
(org-wide Apple Ads credentials, already in ~/.zshrc — shared across all
apps on this account). See tools/aso/APPLE-ADS-API.md in the TripPhotoShare
repo for the full writeup.
"""
import csv, datetime, glob, gzip, io, json, os, sys, time, urllib.parse, urllib.request

APP_ID = "6782552371"
HERE = os.path.dirname(os.path.abspath(__file__))

# The phrases the metadata is aimed at. Measured against the live catalogue, so
# this list is the claim being tested: change the subtitle, watch these move.
PHRASES = [
    "watermark photos", "add watermark", "photo watermark", "watermark app",
    "video watermark", "watermark video", "logo watermark", "photo signature",
    "date stamp photos", "timestamp camera", "copyright photos",
    "content credentials", "c2pa", "photo copyright stamp", "watermark maker",
]


def ranks():
    out = os.path.join(HERE, "ranks.csv")
    new = not os.path.exists(out)
    today = datetime.date.today().isoformat()
    with open(out, "a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["date", "phrase", "rank", "results", "leader", "leader_ratings"])
        for p in PHRASES:
            u = "https://itunes.apple.com/search?" + urllib.parse.urlencode(
                {"term": p, "entity": "software", "country": "us", "limit": 200})
            try:
                res = json.load(urllib.request.urlopen(u, timeout=30)).get("results", [])
            except Exception as e:
                print(f"  {p}: {e}"); continue
            rank = next((i + 1 for i, a in enumerate(res) if str(a.get("trackId")) == APP_ID), "")
            lead = res[0] if res else {}
            w.writerow([today, p, rank, len(res), lead.get("trackName", ""), lead.get("userRatingCount", 0)])
            print(f"  {p:<26} rank={rank or '—':<5} of {len(res)}")
            time.sleep(3)
    print("→", out)


def _token():
    import jwt
    kid = os.path.basename(glob.glob(os.path.expanduser("~/.appstoreconnect/AuthKey_*.p8"))[0])[8:-3]
    iss = os.environ["ASC_ISSUER_ID"]
    key = open(os.path.expanduser(f"~/.appstoreconnect/AuthKey_{kid}.p8")).read()
    now = int(time.time())
    return jwt.encode({"iss": iss, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


def _get(path, tok):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path,
                                 headers={"Authorization": "Bearer " + tok})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


# The reports worth having. Discovery and Engagement carries impressions and
# product page views; without it there is no denominator and so no conversion
# rate, which is the number every metadata change is ultimately judged on.
WANTED = {"App Store Discovery and Engagement Detailed",
          "App Store Discovery and Engagement Standard",
          "App Downloads Detailed", "App Downloads Standard",
          "App Store Installation and Deletion Detailed"}


def analytics():
    tok = _token()
    reqs = _get(f"/v1/apps/{APP_ID}/analyticsReportRequests?limit=50", tok)["data"]
    if not reqs:
        sys.exit("No report requests exist. Create one in App Store Connect or via the API.")
    got = 0
    for rq in reqs:
        access = rq["attributes"]["accessType"]
        for rep in _get(f"/v1/analyticsReportRequests/{rq['id']}/reports?limit=200", tok)["data"]:
            name = rep["attributes"]["name"]
            if name not in WANTED:
                continue
            insts = _get(f"/v1/analyticsReports/{rep['id']}/instances?limit=200", tok)["data"]
            if not insts:
                print(f"  {access}/{name}: not generated yet")
                continue
            for inst in insts:
                segs = _get(f"/v1/analyticsReportInstances/{inst['id']}/segments", tok)["data"]
                for i, seg in enumerate(segs):
                    url = seg["attributes"]["url"]
                    safe = name.replace(" ", "_")
                    # Two instances can share a processingDate (Apple reprocessing a
                    # day), and a single instance can have multiple segments — either
                    # one collapsed onto the same filename and silently overwrote the
                    # other's data. inst['id'] and the segment index make it unique.
                    dest = os.path.join(
                        HERE,
                        f"{access}_{safe}_{inst['attributes']['processingDate']}_{inst['id']}_seg{i}.csv",
                    )
                    raw = urllib.request.urlopen(url, timeout=300).read()
                    try:
                        raw = gzip.decompress(raw)
                    except OSError:
                        pass
                    open(dest, "wb").write(raw)
                    print("  saved", os.path.basename(dest), f"({len(raw):,} bytes)")
                    got += 1
    if not got:
        print("\nNothing generated yet — Apple takes 24-48h after a request is created.")


def _searchads_token():
    import jwt
    team = os.environ["SEARCHADS_TEAM_ID"]
    client = os.environ["SEARCHADS_CLIENT_ID"]
    kid = os.environ["SEARCHADS_KEY_ID"]
    key = open(os.path.expanduser(os.environ["SEARCHADS_KEY_PATH"])).read()
    now = int(time.time())
    assertion = jwt.encode(
        {"sub": client, "aud": "https://appleid.apple.com", "iss": team,
         "iat": now, "exp": now + 3600},
        key, algorithm="ES256", headers={"kid": kid, "alg": "ES256"},
    )
    data = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "client_id": client,
        "client_secret": assertion,
        "scope": "searchadsorg",
    }).encode()
    req = urllib.request.Request("https://appleid.apple.com/auth/oauth2/token", data=data, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["access_token"]


# Markepi's App Store category is Photo & Video / Utilities. Apple Ads' genre
# enum doesn't have a Graphics & Design bucket — PRODUCTIVITY_UTILITIES is the
# closest to "Utilities", LIFESTYLE the closest adjacent general-interest one.
GENRES = ("PHOTO_VIDEO", "PRODUCTIVITY_UTILITIES", "LIFESTYLE")


def popularity():
    """Real Apple search-term popularity (top 500/genre) via the official SDK —
    not the free iTunes API's competition-density proxy. Requires SEARCHADS_*
    env vars."""
    from apple_ads_platform.builder import AppleAdsClientBuilder
    from apple_ads_platform.models.filter import Filter
    from apple_ads_platform.models.search_term_popularity_time_range import SearchTermPopularityTimeRange
    from apple_ads_platform.models.search_term_popularity_query_request import SearchTermPopularityQueryRequest
    from apple_ads_platform.models.request_pagination import RequestPagination

    api = AppleAdsClientBuilder.from_private_key_path(
        os.environ["SEARCHADS_CLIENT_ID"], os.environ["SEARCHADS_TEAM_ID"],
        os.environ["SEARCHADS_KEY_ID"], os.environ["SEARCHADS_KEY_PATH"],
    ).build()
    ctx = f"adAccountId={api.get_me().result.org_id};"

    today = datetime.date.today()
    last_sat = today - datetime.timedelta(days=(today.weekday() - 5) % 7 + 7)
    last_sun = last_sat - datetime.timedelta(days=6)
    tr = SearchTermPopularityTimeRange(start=last_sun.isoformat(), end=last_sat.isoformat(),
                                        granularity="WEEKLY_SUN_SAT")

    rows = []
    for genre in GENRES:
        req = SearchTermPopularityQueryRequest(
            filters=[Filter(field="countryOrRegion", operator="EQUALS", value="US"),
                     Filter(field="genre", operator="EQUALS", value=genre)],
            timeRange=tr, pagination=RequestPagination(pageSize=500),
        )
        resp = api.search_term_popularity_query(ctx, req)
        genre_rows = resp.result.rows if resp.result else []
        print(f"  {genre}: {len(genre_rows)} rows")
        rows.extend(genre_rows)

    out = os.path.join(HERE, "search_term_popularity.csv")
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["genre", "rank_in_genre", "search_term", "pop_in_genre", "pop_all_1to100"])
        for r in rows:
            w.writerow([r.genre, r.rank_in_genre, r.search_term, r.search_popularity_in_genre, r.search_popularity1to100])
    print(f"→ {out} ({len(rows)} rows, week {last_sun} to {last_sat})")


def suggest():
    """Real keyword-suggestion expansions from Apple, one seed phrase at a time —
    the `terms` filter only honors a single value per call despite being
    documented as list-typed."""
    from apple_ads_platform.builder import AppleAdsClientBuilder
    from apple_ads_platform.models.recommendation_query_request import RecommendationQueryRequest
    from apple_ads_platform.models.recommendation_filter_condition import RecommendationFilterCondition

    api = AppleAdsClientBuilder.from_private_key_path(
        os.environ["SEARCHADS_CLIENT_ID"], os.environ["SEARCHADS_TEAM_ID"],
        os.environ["SEARCHADS_KEY_ID"], os.environ["SEARCHADS_KEY_PATH"],
    ).build()
    ctx = f"adAccountId={api.get_me().result.org_id};"

    out = os.path.join(HERE, "keyword_suggestions.csv")
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["seed", "suggestion", "popularity"])
        for seed in PHRASES:
            req = RecommendationQueryRequest(filters=[
                RecommendationFilterCondition(field="promotedObjectId", operator="EQUALS", value=[APP_ID]),
                RecommendationFilterCondition(field="promotedObjectType", operator="EQUALS", value=["APPSTORE_APP"]),
                RecommendationFilterCondition(field="countriesOrRegions", operator="IN", value=["US"]),
                RecommendationFilterCondition(field="terms", operator="IN", value=[seed]),
            ])
            try:
                rows = api.query_keyword_suggestions(ctx, req).result or []
            except Exception as e:
                print(f"  {seed}: {e}"); continue
            rows = sorted(rows, key=lambda r: -(r.popularity or 0))
            print(f"  '{seed}' -> {len(rows)} suggestions")
            for r in rows:
                w.writerow([seed, r.text, r.popularity])
                print(f"      {r.text:<32} {r.popularity}")
            time.sleep(2)
    print("→", out)


def adstest():
    """Connectivity check: get a token, list campaigns (empty is fine — proves auth works)."""
    tok = _searchads_token()
    print("  token acquired, len", len(tok))
    req = urllib.request.Request(
        "https://api.searchads.apple.com/api/v5/campaigns",
        headers={"Authorization": "Bearer " + tok},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            print(" ", json.load(r))
    except urllib.error.HTTPError as e:
        print(f"  HTTP {e.code}: {e.read().decode()}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "ranks"
    {"ranks": ranks, "analytics": analytics, "adstest": adstest,
     "popularity": popularity, "suggest": suggest}[cmd]()
