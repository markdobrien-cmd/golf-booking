from datetime import time

import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.repository import Course
from app.slots import generate_slots

OAKMERE = Course(
    id=1,
    name="Oakmere Links",
    location="Coastal",
    holes=18,
    first_tee=time(7, 0),
    last_tee=time(8, 0),
    interval_minutes=20,
    max_players=4,
)


class FakeRepo:
    def __init__(self, courses, healthy=True):
        self.courses = {c.id: c for c in courses}
        self.healthy = healthy

    def list_courses(self):
        return list(self.courses.values())

    def get_course(self, course_id):
        return self.courses.get(course_id)

    def ping(self):
        if not self.healthy:
            raise RuntimeError("down")


@pytest.fixture
def client():
    with TestClient(create_app(FakeRepo([OAKMERE]))) as c:
        yield c


def test_generate_slots_includes_last_tee():
    assert generate_slots(time(7, 0), time(7, 30), 10) == [time(7, 0), time(7, 10), time(7, 20), time(7, 30)]


def test_generate_slots_rejects_bad_interval():
    with pytest.raises(ValueError):
        generate_slots(time(7, 0), time(8, 0), 0)


def test_list_courses(client):
    assert [c["name"] for c in client.get("/api/courses").json()] == ["Oakmere Links"]


def test_unknown_course_is_404(client):
    assert client.get("/api/courses/99").status_code == 404


def test_tee_sheet(client):
    body = client.get("/api/courses/1/tee-times", params={"date": "2026-10-10"}).json()
    assert body["times"] == ["07:00", "07:20", "07:40", "08:00"]
    assert body["max_players"] == 4


def test_readyz_reports_database_down():
    with TestClient(create_app(FakeRepo([], healthy=False))) as c:
        assert c.get("/readyz").status_code == 503


def test_metrics_exposed(client):
    client.get("/api/courses")
    assert "http_requests_total" in client.get("/metrics").text
