from datetime import date, datetime, time
from uuid import UUID

from pydantic import BaseModel, Field


class BookingRequest(BaseModel):
    course_id: int
    date: date
    time: time
    players: int = Field(ge=1, le=4)
    name: str = Field(min_length=1, max_length=100)
    email: str = Field(pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$", max_length=254)


class Booking(BaseModel):
    id: UUID
    course_id: int
    tee_date: date
    tee_time: time
    players: int
    name: str
    email: str
    status: str
    created_at: datetime


class TeeSheet(BaseModel):
    course_id: int
    date: date
    max_players: int
    times: list[str]


class Slot(BaseModel):
    time: str
    remaining: int
