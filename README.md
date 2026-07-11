# Zameel — زميل

Travel planning, budgeting, and on-trip tracking. Plan a multi-city trip
(flights, hotels, attractions, local transport), set a budget in SAR, then
track actual spending while traveling and attach photos to attractions by
location.

## Architecture

- **backend/** — FastAPI + Postgres. JWT auth, multi-user trips (invite a
  travel partner by email), CRUD for city stops / travel legs / hotels /
  attractions / transport / expenses, budget summary with per-item currency →
  SAR conversion, photo upload with EXIF-GPS parsing and automatic
  nearest-attraction matching (≤ 500 m).
- **ios/** — native SwiftUI app (iOS 17+, generated with `xcodegen`). Trips,
  city timeline, budget dashboard, mark-paid workflow, photo attachment via
  the system picker, and "Find photos taken here" which scans the photo
  library for shots taken near an attraction (PhotoKit + CLLocation).

## Backend

Local dev:

```sh
docker compose up            # api on 127.0.0.1:8100, postgres on 127.0.0.1:5434
```

Deploy to the GPU/Tailscale host (`100.76.65.1`, api on `:8100`):

```sh
rsync -az --exclude .git --exclude __pycache__ ./ jalalirs@100.76.65.1:~/zameel/
./tools/gpu "cd ~/zameel && docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d --build"
```

Secrets: `~/zameel/.env` on the host holds `JWT_SECRET`. Photos live in the
`zameel_data` volume under `/data/photos/<trip_id>/`.

Seed the real honeymoon trip (both travelers + the Qatar Airways booking from
`data/honeymoon/flights/`, attached to the flight):

```sh
python backend/tools/seed_honeymoon.py --base http://100.76.65.1:8100
```

Seeded accounts: `jalalirs@gmail.com` and `heba.k.safi@gmail.com`, both with
password `zameel123` — change them in Profile.

**Attachments**: any cost item (flight, hotel, attraction, transport, expense)
accepts PDF / HTML / image attachments — tickets, booking emails, receipts.
Upload from the item's edit screen (or `POST /trips/{id}/<type>/{item}/attachments`);
view in-app via QuickLook.

## iOS app

```sh
cd ios
xcodegen generate
open Zameel.xcodeproj      # or: xcodebuild -scheme Zameel -destination 'platform=iOS Simulator,name=iPhone 16e' build
```

The server base URL is editable on the login screen. It defaults to the
public Funnel URL `https://jalalirs.tailedf721.ts.net/zameel` (a path mount
on the GPU box's existing Tailscale Funnel → 127.0.0.1:8100), so phones work
anywhere without the Tailscale app. On the tailnet you can also use
`http://100.76.65.1:8100` directly.

UI tests (`ZameelUITests`) drive the seeded trip end-to-end and expect a
token injected into the app container first:

```sh
xcrun simctl spawn booted defaults write com.jalalirs.Zameel token "$JWT"
xcodebuild -project Zameel.xcodeproj -scheme Zameel \
  -destination 'platform=iOS Simulator,name=iPhone 16e' test
```

Debug hook: launching with `OPEN_TRIP=<id> OPEN_ATTRACTION=<id>` env vars
(via `SIMCTL_CHILD_…`) opens one attraction directly.

## Money model

Every cost-bearing item stores a unit price (`amount`) times `units` (2 rooms,
4 tickets…), a `currency` + `fx_to_base` rate to the trip's base currency
(SAR), and a `status` of `planned | booked | paid`; `paid_amount` records the
actual total once paid.

**People.** Trips are multi-user. Members are `leader`s or `member`s — several
leaders are fine, and roles are deliberately loose (anyone can invite or
change roles; the app trusts the group). Each item has a `scope`:

- `group` — counts toward the trip budget. Added by a non-leader it sits
  `pending` until a leader approves; rejected items are accounted as the
  payer's personal spend.
- `personal` — one member's own money, tracked against their optional
  personal budget.
- `shared` — split equally across `participant_ids` (e.g. 4 people sharing
  2 hotel rooms: units=2, four participants).

The budget summary reports the group pot (approved items only), the
pending-approval count, and your own personal totals. Personal money is
private: the API only returns personal budget/spend to their owner, and only
the owner can set their personal budget.

**Optional budgeting.** `budget_enabled` on the trip toggles all of this off,
turning Zameel into a pure itinerary keeper; flip it back anytime in trip
settings — nothing is deleted.
