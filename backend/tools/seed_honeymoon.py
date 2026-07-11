"""Seed the real Japan-Korea honeymoon (16 Mar - 3 Apr 2027) with both travelers
and the actual Qatar Airways booking (PNR 8UTU58) from data/honeymoon/flights/.

Usage:
    python seed_honeymoon.py [--base http://100.76.65.1:8100]

Idempotent by trip name. FX snapshots: 1 JPY = 0.025 SAR, 1 KRW = 0.0027 SAR.
"""

import argparse
import os
import sys

import requests

JPY = {"currency": "JPY", "fx_to_base": 0.025}
KRW = {"currency": "KRW", "fx_to_base": 0.0027}
SAR = {"currency": "SAR", "fx_to_base": 1}

TRIP_NAME = "Japan & Korea — Honeymoon 2027"
REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
FLIGHT_EMAIL = os.path.join(REPO_ROOT, "data", "honeymoon", "flights", "Email.html")

LEADER = {"email": "jalalirs@gmail.com", "name": "Ridwan Jalali", "password": "zameel123"}
PARTNER = {"email": "heba.k.safi@gmail.com", "name": "Heba Safi", "password": "zameel123"}


def auth(base: str, acct: dict) -> requests.Session:
    s = requests.Session()
    r = s.post(f"{base}/auth/login", json={"email": acct["email"], "password": acct["password"]})
    if r.status_code != 200:
        r = s.post(f"{base}/auth/register", json=acct)
        r.raise_for_status()
        print(f"registered {acct['email']} (password: {acct['password']} — change it!)")
    s.headers["Authorization"] = f"Bearer {r.json()['access_token']}"
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://100.76.65.1:8100")
    args = ap.parse_args()

    s = auth(args.base, LEADER)
    auth(args.base, PARTNER)  # make sure the account exists before inviting

    if any(t["name"] == TRIP_NAME for t in s.get(f"{args.base}/trips").json()):
        print(f"trip '{TRIP_NAME}' already exists — nothing to do")
        return

    trip = s.post(
        f"{args.base}/trips",
        json={
            "name": TRIP_NAME,
            "start_date": "2027-03-16",
            "end_date": "2027-04-03",
            "base_currency": "SAR",
            "budget_total": 60000,
            "budget_enabled": True,
            "notes": "Honeymoon: Seoul buffer → Osaka → Kyoto → Fuji glamping → Tokyo climax → relaxed Seoul ending.",
        },
    ).json()
    tid = trip["id"]
    print(f"trip {tid}")

    s.post(f"{args.base}/trips/{tid}/members", json={"email": PARTNER["email"]}).raise_for_status()
    print(f"invited {PARTNER['email']}")

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

    # ---- the real booked flights (Qatar Airways, PNR 8UTU58, paid) ----
    outbound = post("legs", dict(
        kind="flight", carrier="Qatar Airways QR1179 + QR858 (via Doha)",
        from_city="Medina MED", to_city="Seoul ICN",
        depart_at="2027-03-16T12:25:00+03:00", arrive_at="2027-03-17T17:15:00+09:00",
        amount=10966.16, units=2, **SAR,
        status="paid", paid_amount=21932.32, booking_ref="8UTU58",
        notes="Round-trip First/Business for 2 (price covers the return too). "
              "MED 12:25 → DOH 14:30, layover 12h10m, DOH 02:40 → ICN 17:15.",
    ))
    print("  leg Medina → Seoul (PAID, PNR 8UTU58)")

    post("legs", dict(
        kind="flight", carrier="Qatar Airways QR863 + QR1174 (via Doha)",
        from_city="Seoul ICN", to_city="Medina MED",
        depart_at="2027-04-02T18:30:00+09:00", arrive_at="2027-04-03T03:15:00+03:00",
        amount=0, units=1, **SAR, status="paid", booking_ref="8UTU58",
        notes="Return half of PNR 8UTU58 — already paid on the outbound leg. "
              "ICN 18:30 → DOH 22:50, layover 1h45m, DOH 00:35 → MED 03:15.",
    ))
    print("  leg Seoul → Medina (return half, PAID)")

    # attach the booking confirmation email to the outbound leg
    with open(FLIGHT_EMAIL, "rb") as f:
        r = s.post(
            f"{args.base}/trips/{tid}/legs/{outbound['id']}/attachments",
            files={"file": ("QatarAirways-8UTU58.html", f, "text/html")},
        )
        r.raise_for_status()
    print("  attached QatarAirways-8UTU58.html to the outbound flight")

    # ---- remaining planned legs ----
    legs = [
        dict(kind="flight", from_city="Seoul ICN", to_city="Osaka KIX",
             depart_at="2027-03-18T09:00:00+09:00", amount=80000, units=2, **KRW, notes="per person"),
        dict(kind="train", from_city="Osaka", to_city="Kyoto",
             depart_at="2027-03-21T10:00:00+09:00", carrier="JR Special Rapid",
             amount=600, units=2, **JPY, notes="per person"),
        dict(kind="bus", from_city="Kyoto", to_city="Kawaguchiko",
             depart_at="2027-03-23T09:00:00+09:00", carrier="Shinkansen + Highway bus via Mishima",
             amount=9000, units=2, **JPY, notes="per person"),
        dict(kind="train", from_city="Kawaguchiko", to_city="Tokyo",
             depart_at="2027-03-25T11:00:00+09:00", carrier="Fuji Excursion (Shinjuku)",
             amount=4600, units=2, **JPY, notes="per person"),
        dict(kind="flight", from_city="Tokyo HND", to_city="Seoul GMP",
             depart_at="2027-03-30T10:00:00+09:00", amount=350, units=2, **SAR, notes="per person"),
    ]
    for leg in legs:
        post("legs", leg)
        print(f"  leg {leg['from_city']} → {leg['to_city']}")

    # ---- hotels (unit price per night would be nicer, but bookings are per stay) ----
    hotels = [
        dict(name="Nine Tree Premier Myeongdong", city="Seoul", check_in="2027-03-17",
             check_out="2027-03-18", amount=180000, **KRW),
        dict(name="Cross Hotel Osaka (Namba/Dotonbori)", city="Osaka", check_in="2027-03-18",
             check_out="2027-03-21", amount=25000, units=3, **JPY, notes="3 nights"),
        dict(name="Gion ryokan / machiya stay", city="Kyoto", check_in="2027-03-21",
             check_out="2027-03-23", amount=35000, units=2, **JPY, notes="2 nights"),
        dict(name="Dot Glamping Fuji — dome with Fuji view", city="Kawaguchiko",
             check_in="2027-03-23", check_out="2027-03-25", amount=60000, units=2, **JPY,
             notes="2 nights, romantic dome tent, private BBQ dinner"),
        dict(name="Shinjuku hotel", city="Tokyo", check_in="2027-03-25",
             check_out="2027-03-30", amount=35000, units=5, **JPY, notes="5 nights"),
        dict(name="Myeongdong hotel", city="Seoul (return)", check_in="2027-03-30",
             check_out="2027-04-02", amount=180000, units=3, **KRW, notes="3 nights"),
    ]
    for h in hotels:
        city = h.pop("city")
        post("hotels", {**h, "city_stop_id": cid[city]})
        print(f"  hotel {h['name']}")

    # ---- attractions (lat/lon enable photo auto-matching) ----
    attractions = [
        ("Osaka", "Dotonbori night walk & street food", "2027-03-18", "19:00", 34.6687, 135.5013, 3000, JPY),
        ("Osaka", "Universal Studios Japan + Super Nintendo World", "2027-03-19", "08:30", 34.6654, 135.4323, 21000, JPY),
        ("Osaka", "Shinsaibashi shopping & Kuromon market", "2027-03-20", "11:00", 34.6733, 135.5010, 0, JPY),
        ("Osaka", "Nara Park & Todai-ji (optional day trip)", "2027-03-20", "13:00", 34.6851, 135.8430, 1000, JPY),
        ("Kyoto", "Gion evening stroll (Hanamikoji, Yasaka)", "2027-03-21", "17:30", 35.0037, 135.7750, 0, JPY),
        ("Kyoto", "Fushimi Inari at sunrise", "2027-03-22", "07:00", 34.9671, 135.7727, 0, JPY),
        ("Kyoto", "Arashiyama bamboo grove + Togetsukyo", "2027-03-22", "10:30", 35.0094, 135.6668, 500, JPY),
        ("Kyoto", "Kinkaku-ji (Golden Pavilion)", "2027-03-22", "14:00", 35.0394, 135.7292, 500, JPY),
        ("Kawaguchiko", "Kawaguchiko ropeway + lake panorama", "2027-03-24", "10:00", 35.5171, 138.7514, 1800, JPY),
        ("Kawaguchiko", "Oishi Park Fuji viewpoint", "2027-03-24", "15:00", 35.5245, 138.7355, 0, JPY),
        ("Tokyo", "Shibuya Crossing + Hachiko", "2027-03-26", "17:00", 35.6595, 139.7005, 0, JPY),
        ("Tokyo", "teamLab Planets", "2027-03-27", "10:00", 35.6494, 139.7898, 4600, JPY),
        ("Tokyo", "Ueno Park sakura hanami", "2027-03-28", "10:00", 35.7156, 139.7745, 0, JPY),
        ("Tokyo", "Shinjuku Gyoen sakura picnic", "2027-03-28", "14:00", 35.6852, 139.7100, 500, JPY),
        ("Tokyo", "Ginza shopping + Tsukiji food crawl", "2027-03-29", "11:00", 35.6717, 139.7650, 0, JPY),
        ("Seoul (return)", "Luxury spa / jjimjilbang day", "2027-03-31", "11:00", 37.5247, 127.0475, 100000, KRW),
        ("Seoul (return)", "Myeongdong shopping", "2027-03-31", "17:00", 37.5637, 126.9838, 0, KRW),
        ("Seoul (return)", "Gyeongbokgung hanbok photoshoot", "2027-04-01", "10:00", 37.5796, 126.9770, 75000, KRW),
    ]
    for city, name, d, t, lat, lon, amount, cur in attractions:
        post("attractions", {"name": name, "city_stop_id": cid[city], "planned_date": d,
                             "planned_time": t, "lat": lat, "lon": lon,
                             "amount": amount, "units": 2 if amount else 1, **cur,
                             "notes": "tickets, per person" if amount else None})
        print(f"  attraction {name}")

    # ---- local transport ----
    transport = [
        ("Seoul", "transfer", "AREX ICN → Myeongdong", "2027-03-17", 11000, 2, KRW),
        ("Osaka", "transfer", "Nankai Rapi:t KIX → Namba", "2027-03-18", 1300, 2, JPY),
        ("Osaka", "ic_card", "ICOCA top-up (Osaka + Kyoto)", "2027-03-18", 3000, 2, JPY),
        ("Osaka", "metro", "Metro to USJ (Universal City) return", "2027-03-19", 600, 2, JPY),
        ("Kyoto", "taxi", "Taxis in Kyoto (Gion, late evenings)", "2027-03-21", 4000, 1, JPY),
        ("Kawaguchiko", "bus", "Kawaguchiko sightseeing bus 2-day pass", "2027-03-23", 1700, 2, JPY),
        ("Tokyo", "ic_card", "Suica top-up Tokyo (5 days)", "2027-03-25", 4000, 2, JPY),
        ("Tokyo", "taxi", "Taxi buffer Tokyo nights", "2027-03-26", 6000, 1, JPY),
        ("Seoul (return)", "transfer", "GMP → Myeongdong taxi", "2027-03-30", 25000, 1, KRW),
        ("Seoul (return)", "metro", "T-money top-up Seoul", "2027-03-30", 10000, 2, KRW),
        ("Seoul (return)", "transfer", "Myeongdong → ICN (AREX/taxi)", "2027-04-02", 65000, 1, KRW),
    ]
    for city, kind, desc, d, amount, units, cur in transport:
        post("transport", {"kind": kind, "description": desc, "city_stop_id": cid[city],
                           "on_date": d, "amount": amount, "units": units, **cur})
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
        print(f"  {c['category']:<12} planned {c['planned_base']:>10.0f}  paid {c['paid_base']:>10.0f}  ({c['count']} items)")
    print(f"  committed {b['committed_base']:.0f} / budget {b['budget_total']:.0f} "
          f"→ remaining {b['remaining_vs_committed']:.0f} | spent so far {b['paid_base']:.0f}")


if __name__ == "__main__":
    sys.exit(main())
