from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, EmailStr


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---- auth ----

class RegisterIn(BaseModel):
    email: EmailStr
    name: str
    password: str


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(ORMModel):
    id: str
    email: str
    name: str


class MePatch(BaseModel):
    name: str | None = None
    password: str | None = None


# ---- trips ----

class TripIn(BaseModel):
    name: str
    start_date: date
    end_date: date
    base_currency: str = "SAR"
    budget_total: float = 0
    budget_enabled: bool = True
    notes: str | None = None


class TripPatch(BaseModel):
    name: str | None = None
    start_date: date | None = None
    end_date: date | None = None
    base_currency: str | None = None
    budget_total: float | None = None
    budget_enabled: bool | None = None
    notes: str | None = None


class MemberOut(ORMModel):
    # personal_budget is deliberately NOT exposed here — personal money is
    # only ever returned to its owner, via the budget endpoint.
    id: str
    role: str
    user: UserOut


class TripOut(ORMModel):
    id: str
    name: str
    start_date: date
    end_date: date
    base_currency: str
    budget_total: float
    budget_enabled: bool
    notes: str | None
    created_by: str
    members: list[MemberOut] = []


class MemberIn(BaseModel):
    email: EmailStr
    role: str = "member"


class MemberPatch(BaseModel):
    role: str | None = None
    personal_budget: float | None = None


# ---- cities ----

class CityStopIn(BaseModel):
    city: str
    country: str | None = None
    arrive_date: date
    depart_date: date
    order_index: int = 0
    main_idea: str | None = None


class CityStopPatch(BaseModel):
    city: str | None = None
    country: str | None = None
    arrive_date: date | None = None
    depart_date: date | None = None
    order_index: int | None = None
    main_idea: str | None = None


class CityStopOut(ORMModel):
    id: str
    trip_id: str
    city: str
    country: str | None
    arrive_date: date
    depart_date: date
    order_index: int
    main_idea: str | None


# ---- shared cost fields ----

class CostIn(BaseModel):
    amount: float = 0
    units: float = 1
    currency: str = "SAR"
    fx_to_base: float = 1
    status: str = "planned"
    paid_amount: float | None = None
    booking_ref: str | None = None
    notes: str | None = None
    scope: str = "group"  # group | personal | shared
    participant_ids: list[str] | None = None
    booking_url: str | None = None
    booking_opens: date | None = None


class CostPatch(BaseModel):
    amount: float | None = None
    units: float | None = None
    currency: str | None = None
    fx_to_base: float | None = None
    status: str | None = None
    paid_amount: float | None = None
    booking_ref: str | None = None
    notes: str | None = None
    scope: str | None = None
    participant_ids: list[str] | None = None
    booking_url: str | None = None
    booking_opens: date | None = None


class CostOut(ORMModel):
    amount: float
    units: float
    currency: str
    fx_to_base: float
    status: str
    paid_amount: float | None
    booking_ref: str | None
    notes: str | None
    scope: str
    participant_ids: list[str] | None
    approval: str
    paid_by: str | None
    booking_url: str | None
    booking_opens: date | None


class ApprovalIn(BaseModel):
    action: str  # request | approve | reject


class AttachmentOut(ORMModel):
    id: str
    trip_id: str
    item_type: str
    item_id: str
    filename: str
    content_type: str
    created_at: datetime


# ---- travel legs ----

class TravelLegIn(CostIn):
    kind: str = "flight"
    carrier: str | None = None
    from_city: str
    to_city: str
    depart_at: datetime | None = None
    arrive_at: datetime | None = None


class TravelLegPatch(CostPatch):
    kind: str | None = None
    carrier: str | None = None
    from_city: str | None = None
    to_city: str | None = None
    depart_at: datetime | None = None
    arrive_at: datetime | None = None


class TravelLegOut(CostOut):
    id: str
    trip_id: str
    kind: str
    carrier: str | None
    from_city: str
    to_city: str
    depart_at: datetime | None
    arrive_at: datetime | None


# ---- hotels ----

class HotelIn(CostIn):
    name: str
    address: str | None = None
    city_stop_id: str | None = None
    check_in: date
    check_out: date


class HotelPatch(CostPatch):
    name: str | None = None
    address: str | None = None
    city_stop_id: str | None = None
    check_in: date | None = None
    check_out: date | None = None


class HotelOut(CostOut):
    id: str
    trip_id: str
    city_stop_id: str | None
    name: str
    address: str | None
    check_in: date
    check_out: date


# ---- attractions ----

class AttractionIn(CostIn):
    name: str
    city_stop_id: str | None = None
    planned_date: date | None = None
    planned_time: str | None = None
    lat: float | None = None
    lon: float | None = None


class AttractionPatch(CostPatch):
    name: str | None = None
    city_stop_id: str | None = None
    planned_date: date | None = None
    planned_time: str | None = None
    lat: float | None = None
    lon: float | None = None


class AttractionOut(CostOut):
    id: str
    trip_id: str
    city_stop_id: str | None
    name: str
    planned_date: date | None
    planned_time: str | None
    lat: float | None
    lon: float | None


# ---- local transport ----

class TransportIn(CostIn):
    kind: str = "taxi"
    description: str
    city_stop_id: str | None = None
    on_date: date | None = None


class TransportPatch(CostPatch):
    kind: str | None = None
    description: str | None = None
    city_stop_id: str | None = None
    on_date: date | None = None


class TransportOut(CostOut):
    id: str
    trip_id: str
    city_stop_id: str | None
    kind: str
    description: str
    on_date: date | None


# ---- expenses ----

class ExpenseIn(CostIn):
    category: str = "misc"
    description: str
    city_stop_id: str | None = None
    on_date: date | None = None


class ExpensePatch(CostPatch):
    category: str | None = None
    description: str | None = None
    city_stop_id: str | None = None
    on_date: date | None = None


class ExpenseOut(CostOut):
    id: str
    trip_id: str
    city_stop_id: str | None
    category: str
    description: str
    on_date: date | None


# ---- photos ----

class PhotoOut(ORMModel):
    id: str
    trip_id: str
    attraction_id: str | None
    filename: str
    content_type: str
    lat: float | None
    lon: float | None
    taken_at: datetime | None


class PhotoPatch(BaseModel):
    attraction_id: str | None = None


class MatchSuggestion(BaseModel):
    attraction: AttractionOut
    distance_m: float


# ---- budget ----

class CategoryBudget(BaseModel):
    category: str
    planned_base: float
    paid_base: float
    count: int


class MemberBudget(BaseModel):
    """Personal figures are private: filled only for the requesting user,
    null for everyone else."""

    user: UserOut
    role: str
    personal_budget: float | None = None
    personal_base: float | None = None       # personal items + rejected + share of shared
    personal_paid_base: float | None = None  # of those, actually paid


class BudgetSummary(BaseModel):
    base_currency: str
    budget_enabled: bool
    budget_total: float
    committed_base: float  # approved group items: planned+booked+paid, converted
    paid_base: float       # of those, actually spent
    remaining_vs_committed: float
    remaining_vs_paid: float
    categories: list[CategoryBudget]
    members: list[MemberBudget]
    pending_count: int     # items waiting for a leader's decision
