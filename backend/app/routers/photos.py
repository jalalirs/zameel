import math
import os
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from PIL import ExifTags, Image
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..models import Attraction, Photo, User
from ..schemas import MatchSuggestion, PhotoOut, PhotoPatch
from ..security import current_user, require_trip

router = APIRouter(tags=["photos"])


def _photos_dir(trip_id: str) -> str:
    d = os.path.join(settings.data_dir, "photos", trip_id)
    os.makedirs(d, exist_ok=True)
    return d


def _exif_gps(path: str) -> tuple[float | None, float | None, datetime | None]:
    """Best-effort EXIF read: GPS coordinates and original capture time."""
    try:
        img = Image.open(path)
        exif = img._getexif() or {}
    except Exception:
        return None, None, None
    tags = {ExifTags.TAGS.get(k, k): v for k, v in exif.items()}
    taken_at = None
    for key in ("DateTimeOriginal", "DateTime"):
        if key in tags:
            try:
                taken_at = datetime.strptime(str(tags[key]), "%Y:%m:%d %H:%M:%S")
                break
            except ValueError:
                pass
    gps = tags.get("GPSInfo")
    if not gps:
        return None, None, taken_at
    gps = {ExifTags.GPSTAGS.get(k, k): v for k, v in gps.items()}

    def to_deg(vals, ref):
        try:
            d, m, s = (float(v) for v in vals)
            deg = d + m / 60 + s / 3600
            return -deg if ref in ("S", "W") else deg
        except Exception:
            return None

    lat = to_deg(gps.get("GPSLatitude", ()), gps.get("GPSLatitudeRef", "N"))
    lon = to_deg(gps.get("GPSLongitude", ()), gps.get("GPSLongitudeRef", "E"))
    return lat, lon, taken_at


def _haversine_m(lat1, lon1, lat2, lon2) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


@router.get("/trips/{trip_id}/photos", response_model=list[PhotoOut])
def list_photos(
    trip_id: str,
    attraction_id: str | None = None,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    require_trip(trip_id, user, db)
    q = db.query(Photo).filter(Photo.trip_id == trip_id)
    if attraction_id:
        q = q.filter(Photo.attraction_id == attraction_id)
    return q.order_by(Photo.taken_at).all()


@router.post("/trips/{trip_id}/photos", response_model=PhotoOut, status_code=201)
def upload_photo(
    trip_id: str,
    file: UploadFile = File(...),
    attraction_id: str | None = Form(None),
    lat: float | None = Form(None),
    lon: float | None = Form(None),
    taken_at: datetime | None = Form(None),
    auto_match: bool = Form(True),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    """Store the image; take GPS/time from the form fields (iOS sends PHAsset
    metadata) or fall back to EXIF. If no attraction was given and auto_match
    is on, attach to the nearest attraction within 500 m."""
    require_trip(trip_id, user, db)
    ext = os.path.splitext(file.filename or "")[1].lower() or ".jpg"
    fname = uuid.uuid4().hex + ext
    path = os.path.join(_photos_dir(trip_id), fname)
    with open(path, "wb") as f:
        f.write(file.file.read())

    if lat is None or lon is None or taken_at is None:
        exif_lat, exif_lon, exif_time = _exif_gps(path)
        lat = lat if lat is not None else exif_lat
        lon = lon if lon is not None else exif_lon
        taken_at = taken_at or exif_time

    if attraction_id is None and auto_match and lat is not None and lon is not None:
        nearest = _nearest_attractions(db, trip_id, lat, lon, limit=1)
        if nearest and nearest[0][1] <= 500:
            attraction_id = nearest[0][0].id

    photo = Photo(
        trip_id=trip_id,
        attraction_id=attraction_id,
        filename=fname,
        content_type=file.content_type or "image/jpeg",
        lat=lat,
        lon=lon,
        taken_at=taken_at,
        uploaded_by=user.id,
    )
    db.add(photo)
    db.commit()
    db.refresh(photo)
    return photo


def _nearest_attractions(db: Session, trip_id: str, lat: float, lon: float, limit: int = 3):
    rows = (
        db.query(Attraction)
        .filter(Attraction.trip_id == trip_id, Attraction.lat.isnot(None), Attraction.lon.isnot(None))
        .all()
    )
    scored = [(a, _haversine_m(lat, lon, a.lat, a.lon)) for a in rows]
    scored.sort(key=lambda t: t[1])
    return scored[:limit]


@router.get("/trips/{trip_id}/photos/{photo_id}/file")
def photo_file(
    trip_id: str, photo_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_trip(trip_id, user, db)
    photo = db.get(Photo, photo_id)
    if photo is None or photo.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo not found")
    path = os.path.join(_photos_dir(trip_id), photo.filename)
    if not os.path.exists(path):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File missing on disk")
    return FileResponse(path, media_type=photo.content_type)


@router.patch("/trips/{trip_id}/photos/{photo_id}", response_model=PhotoOut)
def patch_photo(
    trip_id: str,
    photo_id: str,
    body: PhotoPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    require_trip(trip_id, user, db)
    photo = db.get(Photo, photo_id)
    if photo is None or photo.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo not found")
    photo.attraction_id = body.attraction_id
    db.commit()
    db.refresh(photo)
    return photo


@router.delete("/trips/{trip_id}/photos/{photo_id}", status_code=204)
def delete_photo(
    trip_id: str, photo_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_trip(trip_id, user, db)
    photo = db.get(Photo, photo_id)
    if photo is None or photo.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo not found")
    path = os.path.join(_photos_dir(trip_id), photo.filename)
    if os.path.exists(path):
        os.remove(path)
    db.delete(photo)
    db.commit()


@router.get("/trips/{trip_id}/photos/{photo_id}/match", response_model=list[MatchSuggestion])
def match_photo(
    trip_id: str, photo_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    """Suggest attractions for a photo by GPS distance."""
    require_trip(trip_id, user, db)
    photo = db.get(Photo, photo_id)
    if photo is None or photo.trip_id != trip_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo not found")
    if photo.lat is None or photo.lon is None:
        return []
    return [
        MatchSuggestion(attraction=a, distance_m=round(d, 1))
        for a, d in _nearest_attractions(db, trip_id, photo.lat, photo.lon)
    ]
