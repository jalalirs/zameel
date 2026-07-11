"""Seed the Japan-Korea spring trip (17 Mar - 2 Apr 2027) through the API.

Usage:
    python seed_japan_korea.py [--base http://100.76.65.1:8100] [--email you@x.com]

Idempotent-ish: logs in (or registers) and skips creation if a trip with the
same name already exists. FX snapshots: 1 JPY = 0.025 SAR, 1 KRW = 0.0027 SAR.
"""

import argparse
import sys

import requests

JPY = {"currency": "JPY", "fx_to_base": 0.025}
KRW = {"currency": "KRW", "fx_to_base": 0.0027}
SAR = {"currency": "SAR", "fx_to_base": 1}

TRIP_NAME = "Japan & Korea — Spring 2027"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://100.76.65.1:8100")
    ap.add_argument("--email", default="jalalirs@gmail.com")
    ap.add_argument("--name", default="Jalal")
    ap.add_argument("--password", default="zameel123")
    args = ap.parse_args()
    s = requests.Session()

    r = s.post(f"{args.base}/auth/login", json={"email": args.email, "password": args.password})
    if r.status_code != 200:
        r = s.post(
            f"{args.base}/auth/register",
            json={"email": args.email, "name": args.name, "password": args.password},
        )
        r.raise_for_status()
        print(f"registered {args.email} (password: {args.password} — change it!)")
    s.headers["Authorization"] = f"Bearer {r.json()['access_token']}"

    existing = s.get(f"{args.base}/trips").json()
    if any(t["name"] == TRIP_NAME for t in existing):
        print(f"trip '{TRIP_NAME}' already exists — nothing to do")
        return

    trip = s.post(
        f"{args.base}/trips",
        json={
            "name": TRIP_NAME,
            "start_date": "2027-03-17",
            "end_date": "2027-04-02",
            "base_currency": "SAR",
            "budget_total": 40000,
            "notes": "Couple trip: Seoul buffer → Osaka → Kyoto → Fuji glamping → Tokyo climax → relaxed Seoul ending.",
        },
    ).json()
    tid = trip["id"]
    print(f"trip {tid}")

    def post(path, body):
        r = s.post(f"{args.base}/trips/{tid}/{path}", json=body)
        r.raise_for_status()
        return r.json()

    # ---- city stops ----
    cities_spec = [
        ("Seoul", "South Korea", "2027-03-17", "2027-03-18", "Arrival buffer only"),
        ("Osaka", "Japan", "2027-03-18", "2027-03-21", "Dotonbori + Universal Studios Japan"),
        ("Kyoto", "Japan", "2027-03-21", "2027-03-23", "Enough Kyoto: Gion, Arashiyama, Fushimi Inari"),
        ("Kawaguchiko", "Japan", "2027-03-23", "2027-03-25", "Romantic glamping near Mt. Fuji"),
        ("Tokyo", "Japan", "2027-03-25", "2027-03-30", "Final Japan climax: shopping, food, sakura, luxury"),
        ("Seoul (return)", "South Korea", "2027-03-30", "2027-04-02", "Relaxed ending: spa, shopping, photoshoot"),
    ]
    cid = {}
    for i, (city, country, arrive, depart, idea) in enumerate(cities_spec):
        c = post("cities", {"city": city, "country": country, "arrive_date": arrive,
                            "depart_date": depart, "order_index": i, "main_idea": idea})
        cid[city] = c["id"]
        print(f"  city {city}")

    # ---- travel legs (per couple) ----
    legs = [
        dict(kind="flight", from_city="Riyadh", to_city="Seoul ICN",
             depart_at="2027-03-16T22:00:00Z", arrive_at="2027-03-17T14:00:00Z",
             amount=5600, **SAR, notes="2 pax round-trip priced on outbound leg"),
        dict(kind="flight", from_city="Seoul ICN", to_city="Osaka KIX",
             depart_at="2027-03-18T09:00:00Z", arrive_at="2027-03-18T11:00:00Z",
             amount=160000, **KRW, notes="2 pax one-way"),
        dict(kind="train", from_city="Osaka", to_city="Kyoto",
             depart_at="2027-03-21T10:00:00Z", carrier="JR Special Rapid",
             amount=1200, **JPY, notes="2 pax"),
        dict(kind="bus", from_city="Kyoto", to_city="Kawaguchiko",
             depart_at="2027-03-23T09:00:00Z", carrier="Shinkansen + Highway bus via Mishima",
             amount=18000, **JPY, notes="2 pax"),
        dict(kind="train", from_city="Kawaguchiko", to_city="Tokyo",
             depart_at="2027-03-25T11:00:00Z", carrier="Fuji Excursion (Shinjuku)",
             amount=9200, **JPY, notes="2 pax"),
        dict(kind="flight", from_city="Tokyo HND", to_city="Seoul GMP",
             depart_at="2027-03-30T10:00:00Z", amount=700, **SAR, notes="2 pax one-way"),
        dict(kind="flight", from_city="Seoul ICN", to_city="Riyadh",
             depart_at="2027-04-02T12:00:00Z", amount=0, **SAR,
             notes="Return half of the round-trip ticket"),
    ]
    for leg in legs:
        post("legs", leg)
        print(f"  leg {leg['from_city']} → {leg['to_city']}")

    # ---- hotels ----
    hotels = [
        dict(name="Nine Tree Premier Myeongdong", city="Seoul", check_in="2027-03-17",
             check_out="2027-03-18", amount=180000, **KRW),
        dict(name="Cross Hotel Osaka (Namba/Dotonbori)", city="Osaka", check_in="2027-03-18",
             check_out="2027-03-21", amount=75000, **JPY),
        dict(name="Gion ryokan / machiya stay", city="Kyoto", check_in="2027-03-21",
             check_out="2027-03-23", amount=70000, **JPY),
        dict(name="Dot Glamping Fuji — dome with Fuji view", city="Kawaguchiko",
             check_in="2027-03-23", check_out="2027-03-25", amount=120000, **JPY,
             notes="Romantic dome tent, private BBQ dinner"),
        dict(name="Shinjuku hotel (5 nights)", city="Tokyo", check_in="2027-03-25",
             check_out="2027-03-30", amount=175000, **JPY),
        dict(name="Myeongdong hotel (3 nights)", city="Seoul (return)", check_in="2027-03-30",
             check_out="2027-04-02", amount=540000, **KRW),
    ]
    for h in hotels:
        city = h.pop("city")
        post("hotels", {**h, "city_stop_id": cid[city]})
        print(f"  hotel {h['name']}")

    # ---- attractions (lat/lon enable photo auto-matching) ----
    attractions = [
        ("Osaka", "Dotonbori night walk & street food", "2027-03-18", "19:00", 34.6687, 135.5013, 6000, JPY),
        ("Osaka", "Universal Studios Japan + Super Nintendo World", "2027-03-19", "08:30", 34.6654, 135.4323, 42000, JPY),
        ("Osaka", "Shinsaibashi shopping & Kuromon market", "2027-03-20", "11:00", 34.6733, 135.5010, 0, JPY),
        ("Osaka", "Nara Park & Todai-ji (optional day trip)", "2027-03-20", "13:00", 34.6851, 135.8430, 2000, JPY),
        ("Kyoto", "Gion evening stroll (Hanamikoji, Yasaka)", "2027-03-21", "17:30", 35.0037, 135.7750, 0, JPY),
        ("Kyoto", "Fushimi Inari at sunrise", "2027-03-22", "07:00", 34.9671, 135.7727, 0, JPY),
        ("Kyoto", "Arashiyama bamboo grove + Togetsukyo", "2027-03-22", "10:30", 35.0094, 135.6668, 1000, JPY),
        ("Kyoto", "Kinkaku-ji (Golden Pavilion)", "2027-03-22", "14:00", 35.0394, 135.7292, 1000, JPY),
        ("Kawaguchiko", "Kawaguchiko ropeway + lake panorama", "2027-03-24", "10:00", 35.5171, 138.7514, 3600, JPY),
        ("Kawaguchiko", "Oishi Park Fuji viewpoint", "2027-03-24", "15:00", 35.5245, 138.7355, 0, JPY),
        ("Tokyo", "Shibuya Crossing + Hachiko", "2027-03-26", "17:00", 35.6595, 139.7005, 0, JPY),
        ("Tokyo", "teamLab Planets", "2027-03-27", "10:00", 35.6494, 139.7898, 9200, JPY),
        ("Tokyo", "Ueno Park sakura hanami", "2027-03-28", "10:00", 35.7156, 139.7745, 0, JPY),
        ("Tokyo", "Shinjuku Gyoen sakura picnic", "2027-03-28", "14:00", 35.6852, 139.7100, 1000, JPY),
        ("Tokyo", "Ginza shopping + Tsukiji food crawl", "2027-03-29", "11:00", 35.6717, 139.7650, 0, JPY),
        ("Seoul (return)", "Luxury spa / jjimjilbang day", "2027-03-31", "11:00", 37.5247, 127.0475, 200000, KRW),
        ("Seoul (return)", "Myeongdong shopping", "2027-03-31", "17:00", 37.5637, 126.9838, 0, KRW),
        ("Seoul (return)", "Gyeongbokgung hanbok photoshoot", "2027-04-01", "10:00", 37.5796, 126.9770, 150000, KRW),
    ]
    for city, name, d, t, lat, lon, amount, cur in attractions:
        post("attractions", {"name": name, "city_stop_id": cid[city], "planned_date": d,
                             "planned_time": t, "lat": lat, "lon": lon, "amount": amount, **cur,
                             "notes": "tickets for 2" if amount else None})
        print(f"  attraction {name}")

    # ---- local transport ----
    transport = [
        ("Seoul", "transfer", "AREX ICN → Myeongdong", "2027-03-17", 22000, KRW),
        ("Osaka", "transfer", "Nankai Rapi:t KIX → Namba", "2027-03-18", 2600, JPY),
        ("Osaka", "ic_card", "Suica/ICOCA top-up for metro (Osaka+Kyoto)", "2027-03-18", 6000, JPY),
        ("Osaka", "metro", "Metro to USJ (Universal City) return", "2027-03-19", 1200, JPY),
        ("Kyoto", "taxi", "Taxis in Kyoto (Gion, late evenings)", "2027-03-21", 4000, JPY),
        ("Kawaguchiko", "bus", "Kawaguchiko sightseeing bus 2-day pass", "2027-03-23", 3400, JPY),
        ("Tokyo", "ic_card", "Suica top-up Tokyo (5 days)", "2027-03-25", 8000, JPY),
        ("Tokyo", "taxi", "Taxi buffer Tokyo nights", "2027-03-26", 6000, JPY),
        ("Seoul (return)", "transfer", "GMP → Myeongdong taxi", "2027-03-30", 25000, KRW),
        ("Seoul (return)", "metro", "T-money top-up Seoul", "2027-03-30", 20000, KRW),
        ("Seoul (return)", "transfer", "Myeongdong → ICN (AREX/taxi)", "2027-04-02", 65000, KRW),
    ]
    for city, kind, desc, d, amount, cur in transport:
        post("transport", {"kind": kind, "description": desc, "city_stop_id": cid[city],
                           "on_date": d, "amount": amount, **cur, "notes": "for 2"})
        print(f"  transport {desc}")

    # ---- daily food/shopping envelopes as planned expenses ----
    expenses = [
        ("Osaka", "food", "Food envelope Osaka (3 days)", "2027-03-18", 30000, JPY),
        ("Kyoto", "food", "Food envelope Kyoto (2 days)", "2027-03-21", 24000, JPY),
        ("Kawaguchiko", "food", "Food envelope Fuji (glamping dinner included)", "2027-03-23", 10000, JPY),
        ("Tokyo", "food", "Food envelope Tokyo (5 days, incl. one luxury dinner)", "2027-03-25", 80000, JPY),
        ("Tokyo", "shopping", "Shopping budget Tokyo", "2027-03-26", 60000, JPY),
        ("Seoul (return)", "food", "Food envelope Seoul (4 days total)", "2027-03-30", 300000, KRW),
        ("Seoul (return)", "shopping", "Shopping budget Seoul (skincare, fashion)", "2027-03-31", 500000, KRW),
    ]
    for city, cat, desc, d, amount, cur in expenses:
        post("expenses", {"category": cat, "description": desc, "city_stop_id": cid[city],
                          "on_date": d, "amount": amount, **cur})
        print(f"  expense {desc}")

    b = s.get(f"{args.base}/trips/{tid}/budget").json()
    print("\nBudget summary (SAR):")
    for c in b["categories"]:
        print(f"  {c['category']:<12} planned {c['planned_base']:>10.0f}  ({c['count']} items)")
    print(f"  committed {b['committed_base']:.0f} / budget {b['budget_total']:.0f} "
          f"→ remaining {b['remaining_vs_committed']:.0f}")


if __name__ == "__main__":
    sys.exit(main())
