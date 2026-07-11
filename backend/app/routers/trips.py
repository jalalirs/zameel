from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import (
    Attraction,
    CityStop,
    Expense,
    Hotel,
    LocalTransport,
    TravelLeg,
    Trip,
    TripMember,
    User,
)
from ..schemas import (
    BudgetSummary,
    CategoryBudget,
    CityStopIn,
    CityStopOut,
    CityStopPatch,
    MemberBudget,
    MemberIn,
    MemberOut,
    MemberPatch,
    TripIn,
    TripOut,
    TripPatch,
)
from ..security import current_user, require_trip

router = APIRouter(prefix="/trips", tags=["trips"])


@router.get("", response_model=list[TripOut])
def list_trips(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return (
        db.query(Trip)
        .join(TripMember, TripMember.trip_id == Trip.id)
        .filter(TripMember.user_id == user.id)
        .order_by(Trip.start_date.desc())
        .all()
    )


@router.post("", response_model=TripOut, status_code=201)
def create_trip(body: TripIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    trip = Trip(**body.model_dump(), created_by=user.id)
    trip.members.append(TripMember(user_id=user.id, role="leader"))
    db.add(trip)
    db.commit()
    db.refresh(trip)
    return trip


@router.get("/{trip_id}", response_model=TripOut)
def get_trip(trip_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return require_trip(trip_id, user, db)


@router.patch("/{trip_id}", response_model=TripOut)
def patch_trip(
    trip_id: str, body: TripPatch, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    trip = require_trip(trip_id, user, db)
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(trip, k, v)
    db.commit()
    db.refresh(trip)
    return trip


@router.delete("/{trip_id}", status_code=204)
def delete_trip(trip_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    trip = require_trip(trip_id, user, db)
    db.delete(trip)
    db.commit()


# ---- members ----

@router.post("/{trip_id}/members", response_model=MemberOut, status_code=201)
def add_member(
    trip_id: str, body: MemberIn, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_trip(trip_id, user, db)
    invitee = db.query(User).filter(User.email == body.email.lower()).first()
    if invitee is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No user with that email")
    existing = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip_id, TripMember.user_id == invitee.id)
        .first()
    )
    if existing:
        return existing
    member = TripMember(trip_id=trip_id, user_id=invitee.id, role=body.role)
    db.add(member)
    db.commit()
    db.refresh(member)
    return member


@router.patch("/{trip_id}/members/{member_id}", response_model=MemberOut)
def patch_member(
    trip_id: str,
    member_id: str,
    body: MemberPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    """Roles are deliberately loose (any member can change them), but a
    personal budget is private — only its owner may set it."""
    require_trip(trip_id, user, db)
    member = db.get(TripMember, member_id)
    if member is None or member.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Member not found")
    changes = body.model_dump(exclude_unset=True)
    if "personal_budget" in changes and member.user_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Personal budget is personal")
    for k, v in changes.items():
        setattr(member, k, v)
    db.commit()
    db.refresh(member)
    return member


@router.delete("/{trip_id}/members/{member_id}", status_code=204)
def delete_member(
    trip_id: str, member_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_trip(trip_id, user, db)
    member = db.get(TripMember, member_id)
    if member is None or member.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Member not found")
    members = db.query(TripMember).filter(TripMember.trip_id == trip_id).count()
    if members <= 1:
        raise HTTPException(status.HTTP_409_CONFLICT, "A trip needs at least one member")
    db.delete(member)
    db.commit()


# ---- cities ----

@router.get("/{trip_id}/cities", response_model=list[CityStopOut])
def list_cities(trip_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    trip = require_trip(trip_id, user, db)
    return trip.cities


@router.post("/{trip_id}/cities", response_model=CityStopOut, status_code=201)
def create_city(
    trip_id: str, body: CityStopIn, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_trip(trip_id, user, db)
    city = CityStop(trip_id=trip_id, **body.model_dump())
    db.add(city)
    db.commit()
    db.refresh(city)
    return city


@router.patch("/{trip_id}/cities/{city_id}", response_model=CityStopOut)
def patch_city(
    trip_id: str,
    city_id: str,
    body: CityStopPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    require_trip(trip_id, user, db)
    city = db.get(CityStop, city_id)
    if city is None or city.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "City stop not found")
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(city, k, v)
    db.commit()
    db.refresh(city)
    return city


@router.delete("/{trip_id}/cities/{city_id}", status_code=204)
def delete_city(
    trip_id: str, city_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_trip(trip_id, user, db)
    city = db.get(CityStop, city_id)
    if city is None or city.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "City stop not found")
    db.delete(city)
    db.commit()


# ---- budget ----

_CATEGORIES = [
    ("travel", TravelLeg),
    ("hotels", Hotel),
    ("attractions", Attraction),
    ("transport", LocalTransport),
    ("expenses", Expense),
]


def _base_amounts(r) -> tuple[float, float]:
    """(planned_total, paid_total) in base currency. amount is a unit price;
    once paid, the actual paid_amount (a total) replaces the plan."""
    fx = float(r.fx_to_base or 1)
    planned = float(r.amount or 0) * float(r.units or 1) * fx
    if r.status == "paid":
        actual = float(r.paid_amount) * fx if r.paid_amount is not None else planned
        return actual, actual
    return planned, 0.0


@router.get("/{trip_id}/budget", response_model=BudgetSummary)
def budget(trip_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    trip = require_trip(trip_id, user, db)
    categories: list[CategoryBudget] = []
    committed = 0.0
    paid = 0.0
    pending = 0
    # per-user personal tallies: user_id -> [planned, paid]
    personal: dict[str, list[float]] = {m.user_id: [0.0, 0.0] for m in trip.members}

    def add_personal(uid: str | None, planned: float, spent: float):
        if uid in personal:
            personal[uid][0] += planned
            personal[uid][1] += spent

    for name, model in _CATEGORIES:
        rows = db.query(model).filter(model.trip_id == trip_id).all()
        cat_planned = 0.0
        cat_paid = 0.0
        for r in rows:
            planned, spent = _base_amounts(r)
            if r.scope == "group":
                if r.approval == "approved":
                    cat_planned += planned
                    cat_paid += spent
                elif r.approval == "pending":
                    pending += 1
                else:  # rejected group spend falls back to whoever paid it
                    add_personal(r.paid_by, planned, spent)
            elif r.scope == "shared":
                people = r.participant_ids or ([r.paid_by] if r.paid_by else [])
                if people:
                    share = 1 / len(people)
                    for uid in people:
                        add_personal(uid, planned * share, spent * share)
            else:  # personal
                add_personal(r.paid_by, planned, spent)
        categories.append(
            CategoryBudget(category=name, planned_base=round(cat_planned, 2),
                           paid_base=round(cat_paid, 2), count=len(rows))
        )
        committed += cat_planned
        paid += cat_paid

    total = float(trip.budget_total or 0)
    return BudgetSummary(
        base_currency=trip.base_currency,
        budget_enabled=trip.budget_enabled,
        budget_total=total,
        committed_base=round(committed, 2),
        paid_base=round(paid, 2),
        remaining_vs_committed=round(total - committed, 2),
        remaining_vs_paid=round(total - paid, 2),
        categories=categories,
        members=[
            MemberBudget(
                user=m.user,
                role=m.role,
                # personal money is private — only the owner sees their numbers
                personal_budget=m.personal_budget if m.user_id == user.id else None,
                personal_base=round(personal[m.user_id][0], 2) if m.user_id == user.id else None,
                personal_paid_base=round(personal[m.user_id][1], 2) if m.user_id == user.id else None,
            )
            for m in trip.members
        ],
        pending_count=pending,
    )
