"""CRUD for the trip's cost-bearing items. All five item types share the same
shape (list / create / patch / delete scoped to a trip), so the routers are
stamped out from one factory."""

import os
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..models import Attachment, Attraction, Expense, Hotel, LocalTransport, TravelLeg, User
from ..schemas import (
    ApprovalIn,
    AttachmentOut,
    AttractionIn,
    AttractionOut,
    AttractionPatch,
    ExpenseIn,
    ExpenseOut,
    ExpensePatch,
    HotelIn,
    HotelOut,
    HotelPatch,
    TransportIn,
    TransportOut,
    TransportPatch,
    TravelLegIn,
    TravelLegOut,
    TravelLegPatch,
)
from ..security import current_user, is_leader, require_trip

router = APIRouter(tags=["items"])


_ALLOWED_ATTACHMENT_TYPES = ("application/pdf", "text/html", "image/")


def _attachments_dir(trip_id: str) -> str:
    d = os.path.join(settings.data_dir, "attachments", trip_id)
    os.makedirs(d, exist_ok=True)
    return d


def _initial_approval(scope: str, leader: bool) -> str:
    """Only group spend needs a leader's sign-off; personal and shared money
    never touches the group pot."""
    if scope == "group" and not leader:
        return "pending"
    return "approved"


def _make_crud(path: str, model, in_schema, patch_schema, out_schema, order_by):
    @router.get(f"/trips/{{trip_id}}/{path}", response_model=list[out_schema], name=f"list_{path}")
    def list_items(trip_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
        require_trip(trip_id, user, db)
        return db.query(model).filter(model.trip_id == trip_id).order_by(order_by).all()

    @router.post(
        f"/trips/{{trip_id}}/{path}", response_model=out_schema, status_code=201,
        name=f"create_{path}",
    )
    def create_item(
        trip_id: str, body: in_schema, user: User = Depends(current_user), db: Session = Depends(get_db)
    ):
        require_trip(trip_id, user, db)
        item = model(trip_id=trip_id, **body.model_dump())
        item.paid_by = user.id
        item.approval = _initial_approval(item.scope, is_leader(trip_id, user, db))
        db.add(item)
        db.commit()
        db.refresh(item)
        return item

    @router.patch(
        f"/trips/{{trip_id}}/{path}/{{item_id}}", response_model=out_schema, name=f"patch_{path}"
    )
    def patch_item(
        trip_id: str,
        item_id: str,
        body: patch_schema,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        require_trip(trip_id, user, db)
        item = db.get(model, item_id)
        if item is None or item.trip_id != trip_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
        changes = body.model_dump(exclude_unset=True)
        for k, v in changes.items():
            setattr(item, k, v)
        if "scope" in changes:
            item.approval = _initial_approval(item.scope, is_leader(trip_id, user, db))
        db.commit()
        db.refresh(item)
        return item

    @router.delete(
        f"/trips/{{trip_id}}/{path}/{{item_id}}", status_code=204, name=f"delete_{path}"
    )
    def delete_item(
        trip_id: str, item_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
    ):
        require_trip(trip_id, user, db)
        item = db.get(model, item_id)
        if item is None or item.trip_id != trip_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
        db.delete(item)
        db.commit()

    @router.post(
        f"/trips/{{trip_id}}/{path}/{{item_id}}/approval", response_model=out_schema,
        name=f"approval_{path}",
    )
    def decide_approval(
        trip_id: str,
        item_id: str,
        body: ApprovalIn,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        """`request` re-submits a personal/rejected item for the group pot;
        `approve`/`reject` are leader decisions."""
        require_trip(trip_id, user, db)
        item = db.get(model, item_id)
        if item is None or item.trip_id != trip_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
        if body.action == "request":
            item.scope = "group"
            item.approval = "approved" if is_leader(trip_id, user, db) else "pending"
        elif body.action in ("approve", "reject"):
            if not is_leader(trip_id, user, db):
                raise HTTPException(status.HTTP_403_FORBIDDEN, "Only a trip leader can decide")
            item.approval = "approved" if body.action == "approve" else "rejected"
        else:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Unknown action")
        db.commit()
        db.refresh(item)
        return item

    @router.get(
        f"/trips/{{trip_id}}/{path}/{{item_id}}/attachments",
        response_model=list[AttachmentOut], name=f"attachments_{path}",
    )
    def list_attachments(
        trip_id: str, item_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
    ):
        require_trip(trip_id, user, db)
        return (
            db.query(Attachment)
            .filter(Attachment.trip_id == trip_id, Attachment.item_type == path,
                    Attachment.item_id == item_id)
            .order_by(Attachment.created_at)
            .all()
        )

    @router.post(
        f"/trips/{{trip_id}}/{path}/{{item_id}}/attachments",
        response_model=AttachmentOut, status_code=201, name=f"attach_{path}",
    )
    def upload_attachment(
        trip_id: str,
        item_id: str,
        file: UploadFile = File(...),
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        require_trip(trip_id, user, db)
        item = db.get(model, item_id)
        if item is None or item.trip_id != trip_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
        ctype = file.content_type or "application/octet-stream"
        if not ctype.startswith(_ALLOWED_ATTACHMENT_TYPES):
            raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                                "Only PDF, HTML and images are allowed")
        ext = os.path.splitext(file.filename or "")[1].lower() or ""
        stored = uuid.uuid4().hex + ext
        with open(os.path.join(_attachments_dir(trip_id), stored), "wb") as f:
            f.write(file.file.read())
        att = Attachment(
            trip_id=trip_id, item_type=path, item_id=item_id,
            filename=file.filename or stored, stored_name=stored,
            content_type=ctype, uploaded_by=user.id,
        )
        db.add(att)
        db.commit()
        db.refresh(att)
        return att


@router.get("/trips/{trip_id}/attachments/{attachment_id}/file")
def attachment_file(
    trip_id: str, attachment_id: str,
    user: User = Depends(current_user), db: Session = Depends(get_db),
):
    require_trip(trip_id, user, db)
    att = db.get(Attachment, attachment_id)
    if att is None or att.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Attachment not found")
    fpath = os.path.join(_attachments_dir(trip_id), att.stored_name)
    if not os.path.exists(fpath):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File missing on disk")
    return FileResponse(fpath, media_type=att.content_type, filename=att.filename)


@router.delete("/trips/{trip_id}/attachments/{attachment_id}", status_code=204)
def delete_attachment(
    trip_id: str, attachment_id: str,
    user: User = Depends(current_user), db: Session = Depends(get_db),
):
    require_trip(trip_id, user, db)
    att = db.get(Attachment, attachment_id)
    if att is None or att.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Attachment not found")
    fpath = os.path.join(_attachments_dir(trip_id), att.stored_name)
    if os.path.exists(fpath):
        os.remove(fpath)
    db.delete(att)
    db.commit()


_make_crud("legs", TravelLeg, TravelLegIn, TravelLegPatch, TravelLegOut, TravelLeg.depart_at)
_make_crud("hotels", Hotel, HotelIn, HotelPatch, HotelOut, Hotel.check_in)
_make_crud(
    "attractions", Attraction, AttractionIn, AttractionPatch, AttractionOut, Attraction.planned_date
)
_make_crud(
    "transport", LocalTransport, TransportIn, TransportPatch, TransportOut, LocalTransport.on_date
)
_make_crud("expenses", Expense, ExpenseIn, ExpensePatch, ExpenseOut, Expense.on_date)
