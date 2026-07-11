from fastapi import FastAPI
from sqlalchemy import text

from .db import Base, engine
from .routers import auth, items, photos, trips

app = FastAPI(title="Zameel", description="Travel planning, budgeting and tracking")

# Idempotent column additions for databases created before these fields existed.
# create_all only creates missing tables; it never alters existing ones.
_MIGRATIONS = [
    "ALTER TABLE trips ADD COLUMN IF NOT EXISTS budget_enabled BOOLEAN NOT NULL DEFAULT TRUE",
    "ALTER TABLE trip_members ADD COLUMN IF NOT EXISTS personal_budget NUMERIC(12,2)",
    "UPDATE trip_members SET role = 'leader' WHERE role = 'owner'",
] + [
    stmt
    for table in ("travel_legs", "hotels", "attractions", "local_transport", "expenses")
    for stmt in (
        f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS units NUMERIC(8,2) NOT NULL DEFAULT 1",
        f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS scope VARCHAR(10) NOT NULL DEFAULT 'group'",
        f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS participant_ids JSON",
        f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS approval VARCHAR(10) NOT NULL DEFAULT 'approved'",
        f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS paid_by VARCHAR(32)",
        f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS booking_url VARCHAR(500)",
        f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS booking_opens DATE",
    )
]


@app.on_event("startup")
def init_db():
    Base.metadata.create_all(engine)
    with engine.begin() as conn:
        for stmt in _MIGRATIONS:
            conn.execute(text(stmt))


@app.get("/health")
def health():
    return {"status": "ok"}


app.include_router(auth.router)
app.include_router(trips.router)
app.include_router(items.router)
app.include_router(photos.router)
