import uuid
from datetime import UTC, date, datetime, time

import pytest
from fastapi.testclient import TestClient

from app.availability import compute_availability
from app.main import create_app
from app.models import Booking, TeeSheet

TODAY = date(2026, 10, 8)
SHEET = TeeSheet(course_id=1, date=TODAY, max_players=4, times=["07:00", "07:10"])


class FakeCourses:
    def tee_sheet(self, course_id, day):
        return SHEET.model_copy(update={"date": day}) if course_id == 1 else None


class FakeRepo:
    def __init__(self):
        self.bookings: dict[uuid.UUID, Booking] = {}

    def booked_players(self, course_id, day):
        totals: dict[time, int] = {}
        for b in self.bookings.values():
            if b.course_id == course_id and b.tee_date == day and b.status == "confirmed":
                totals[b.tee_time] = totals.get(b.tee_time, 0) + b.players
        return totals

    def create(self, request, max_players):
        if self.booked_players(request.course_id, request.date).get(request.time, 0) + request.players > max_players:
            return None
        booking = Booking(
            id=uuid.uuid4(),
            course_id=request.course_id,
            tee_date=request.date,
            tee_time=request.time,
            players=request.players,
            name=request.name,
            email=request.email,
            status="confirmed",
            created_at=datetime.now(UTC),
        )
        self.bookings[booking.id] = booking
        return booking

    def get(self, booking_id):
        return self.bookings.get(booking_id)

    def cancel(self, booking_id):
        booking = self.bookings.get(booking_id)
        if booking:
            booking.status = "cancelled"
        return booking

    def ping(self):
        pass


class FakePublisher:
    def __init__(self):
        self.sent = []

    def booking_created(self, booking):
        self.sent.append(booking.id)


@pytest.fixture
def publisher():
    return FakePublisher()


@pytest.fixture
def client(publisher):
    app = create_app(FakeRepo(), FakeCourses(), publisher, today=lambda: TODAY)
    with TestClient(app) as c:
        yield c


def booking(**overrides):
    body = {
        "course_id": 1,
        "date": "2026-10-10",
        "time": "07:00",
        "players": 2,
        "name": "Mark",
        "email": "m@example.com",
    }
    return body | overrides


def test_compute_availability():
    slots = compute_availability(SHEET, {time(7, 0): 3})
    assert [(s.time, s.remaining) for s in slots] == [("07:00", 1), ("07:10", 4)]


def test_booking_is_created_and_published(client, publisher):
    response = client.post("/api/bookings", json=booking())
    assert response.status_code == 201
    assert publisher.sent == [uuid.UUID(response.json()["id"])]


def test_slot_cannot_be_overbooked(client):
    assert client.post("/api/bookings", json=booking(players=3)).status_code == 201
    assert client.post("/api/bookings", json=booking(players=2)).status_code == 409


def test_availability_reflects_bookings(client):
    client.post("/api/bookings", json=booking(players=3))
    slots = client.get("/api/bookings/availability", params={"course_id": 1, "date": "2026-10-10"}).json()
    assert slots[0] == {"time": "07:00", "remaining": 1}


def test_unknown_course(client):
    assert client.post("/api/bookings", json=booking(course_id=9)).status_code == 404


def test_time_not_on_tee_sheet(client):
    assert client.post("/api/bookings", json=booking(time="07:05")).status_code == 422


def test_past_date_rejected(client):
    assert client.post("/api/bookings", json=booking(date="2026-10-01")).status_code == 400


def test_too_many_players_rejected(client):
    assert client.post("/api/bookings", json=booking(players=5)).status_code == 422


def test_cancel_frees_the_slot(client):
    booking_id = client.post("/api/bookings", json=booking(players=4)).json()["id"]
    assert client.delete(f"/api/bookings/{booking_id}").json()["status"] == "cancelled"
    assert client.post("/api/bookings", json=booking(players=4)).status_code == 201
