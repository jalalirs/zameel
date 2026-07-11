import uuid
from datetime import date, datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def _uuid() -> str:
    return uuid.uuid4().hex


def _now() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    password_hash: Mapped[str] = mapped_column(String(128))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class Trip(Base):
    __tablename__ = "trips"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    name: Mapped[str] = mapped_column(String(200))
    start_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date] = mapped_column(Date)
    base_currency: Mapped[str] = mapped_column(String(3), default="SAR")
    budget_total: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    # Budgeting is opt-in: a trip can be a pure itinerary. Toggleable anytime.
    budget_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    notes: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    members: Mapped[list["TripMember"]] = relationship(
        back_populates="trip", cascade="all, delete-orphan"
    )
    cities: Mapped[list["CityStop"]] = relationship(
        back_populates="trip", cascade="all, delete-orphan", order_by="CityStop.order_index"
    )


class TripMember(Base):
    __tablename__ = "trip_members"
    __table_args__ = (UniqueConstraint("trip_id", "user_id"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    role: Mapped[str] = mapped_column(String(20), default="member")  # leader | member
    # Each member may track their own budget alongside (or instead of) the group's.
    personal_budget: Mapped[float | None] = mapped_column(Numeric(12, 2))

    trip: Mapped[Trip] = relationship(back_populates="members")
    user: Mapped[User] = relationship()


class CityStop(Base):
    __tablename__ = "city_stops"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), index=True)
    city: Mapped[str] = mapped_column(String(120))
    country: Mapped[str | None] = mapped_column(String(120))
    arrive_date: Mapped[date] = mapped_column(Date)
    depart_date: Mapped[date] = mapped_column(Date)
    order_index: Mapped[int] = mapped_column(default=0)
    main_idea: Mapped[str | None] = mapped_column(Text)

    trip: Mapped[Trip] = relationship(back_populates="cities")


class CostMixin:
    """Shared money fields: planned amount in a local currency, an FX rate to
    the trip's base currency, and the lifecycle status. `paid_amount` is the
    actual amount once paid (may differ from plan)."""

    # amount is the UNIT price; units multiplies it (2 rooms, 4 tickets, ...).
    amount: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    units: Mapped[float] = mapped_column(Numeric(8, 2), default=1)
    currency: Mapped[str] = mapped_column(String(3), default="SAR")
    fx_to_base: Mapped[float] = mapped_column(Numeric(12, 6), default=1)
    status: Mapped[str] = mapped_column(String(10), default="planned")  # planned | booked | paid
    paid_amount: Mapped[float | None] = mapped_column(Numeric(12, 2))
    booking_ref: Mapped[str | None] = mapped_column(String(200))
    notes: Mapped[str | None] = mapped_column(Text)
    # Whose money: group (counts toward trip budget), personal (one member's own),
    # or shared (split equally between participant_ids).
    scope: Mapped[str] = mapped_column(String(10), default="group")  # group | personal | shared
    participant_ids: Mapped[list | None] = mapped_column(JSON)
    # Group/shared items by non-leaders wait for a leader: approved | pending | rejected.
    # Rejected items are accounted as personal.
    approval: Mapped[str] = mapped_column(String(10), default="approved")
    paid_by: Mapped[str | None] = mapped_column(String(32))  # user id of who added/paid
    # Where to buy, and when sales open (many tickets only sell ~60-90 days out).
    booking_url: Mapped[str | None] = mapped_column(String(500))
    booking_opens: Mapped[date | None] = mapped_column(Date)


class TravelLeg(Base, CostMixin):
    """Intercity travel: flights and trains between cities."""

    __tablename__ = "travel_legs"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(10), default="flight")  # flight | train | bus | ferry
    carrier: Mapped[str | None] = mapped_column(String(120))
    from_city: Mapped[str] = mapped_column(String(120))
    to_city: Mapped[str] = mapped_column(String(120))
    depart_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    arrive_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Hotel(Base, CostMixin):
    __tablename__ = "hotels"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), index=True)
    city_stop_id: Mapped[str | None] = mapped_column(
        ForeignKey("city_stops.id", ondelete="SET NULL")
    )
    name: Mapped[str] = mapped_column(String(200))
    address: Mapped[str | None] = mapped_column(Text)
    check_in: Mapped[date] = mapped_column(Date)
    check_out: Mapped[date] = mapped_column(Date)


class Attraction(Base, CostMixin):
    __tablename__ = "attractions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), index=True)
    city_stop_id: Mapped[str | None] = mapped_column(
        ForeignKey("city_stops.id", ondelete="SET NULL")
    )
    name: Mapped[str] = mapped_column(String(200))
    planned_date: Mapped[date | None] = mapped_column(Date)
    planned_time: Mapped[str | None] = mapped_column(String(20))
    lat: Mapped[float | None] = mapped_column(Float)
    lon: Mapped[float | None] = mapped_column(Float)


class LocalTransport(Base, CostMixin):
    """In-city transport: taxis, metro tickets, IC cards, airport transfers."""

    __tablename__ = "local_transport"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), index=True)
    city_stop_id: Mapped[str | None] = mapped_column(
        ForeignKey("city_stops.id", ondelete="SET NULL")
    )
    kind: Mapped[str] = mapped_column(String(20), default="taxi")  # taxi | metro | bus | ic_card | transfer
    description: Mapped[str] = mapped_column(String(300))
    on_date: Mapped[date | None] = mapped_column(Date)


class Expense(Base, CostMixin):
    """Free-form spending during execution: food, shopping, misc."""

    __tablename__ = "expenses"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), index=True)
    city_stop_id: Mapped[str | None] = mapped_column(
        ForeignKey("city_stops.id", ondelete="SET NULL")
    )
    category: Mapped[str] = mapped_column(String(30), default="misc")  # food | shopping | misc
    description: Mapped[str] = mapped_column(String(300))
    on_date: Mapped[date | None] = mapped_column(Date)


class Attachment(Base):
    """A document stuck to a cost item: ticket PDF, booking email, receipt photo."""

    __tablename__ = "attachments"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), index=True)
    item_type: Mapped[str] = mapped_column(String(20))  # legs | hotels | attractions | transport | expenses
    item_id: Mapped[str] = mapped_column(String(32), index=True)
    filename: Mapped[str] = mapped_column(String(300))  # display name
    stored_name: Mapped[str] = mapped_column(String(300))
    content_type: Mapped[str] = mapped_column(String(100))
    uploaded_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class Photo(Base):
    __tablename__ = "photos"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), index=True)
    attraction_id: Mapped[str | None] = mapped_column(
        ForeignKey("attractions.id", ondelete="SET NULL"), index=True
    )
    filename: Mapped[str] = mapped_column(String(300))
    content_type: Mapped[str] = mapped_column(String(100), default="image/jpeg")
    lat: Mapped[float | None] = mapped_column(Float)
    lon: Mapped[float | None] = mapped_column(Float)
    taken_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    uploaded_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
