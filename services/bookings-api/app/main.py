import logging
import os
from contextlib import asynccontextmanager
from datetime import date
from uuid import UUID

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

from .availability import compute_availability
from .courses_client import CoursesClient
from .metrics import instrument
from .models import Booking, BookingRequest, Slot
from .publisher import Publisher
from .repository import BookingRepository

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
log = logging.getLogger("bookings-api")


def create_app(
    repo: BookingRepository | None = None,
    courses: CoursesClient | None = None,
    publisher: Publisher | None = None,
    today=date.today,
) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if repo is not None:
            app.state.repo, app.state.courses, app.state.publisher = repo, courses, publisher
            yield
            return
        from psycopg_pool import ConnectionPool

        from .courses_client import HttpCoursesClient
        from .publisher import LogPublisher, SqsPublisher
        from .repository import PostgresBookingRepository

        pool = ConnectionPool(os.environ["DATABASE_URL"], min_size=1, max_size=5, open=True)
        postgres = PostgresBookingRepository(pool)
        postgres.init_schema()
        http_courses = HttpCoursesClient(os.environ["COURSES_API_URL"])
        queue_url = os.getenv("SQS_QUEUE_URL")
        app.state.repo = postgres
        app.state.courses = http_courses
        app.state.publisher = SqsPublisher(queue_url) if queue_url else LogPublisher()
        yield
        http_courses.close()
        pool.close()

    app = FastAPI(title="bookings-api", lifespan=lifespan)
    instrument(app)

    def get_repo(request: Request) -> BookingRepository:
        return request.app.state.repo

    def get_courses(request: Request) -> CoursesClient:
        return request.app.state.courses

    def get_publisher(request: Request) -> Publisher:
        return request.app.state.publisher

    @app.get("/healthz", include_in_schema=False)
    def healthz() -> dict:
        return {"status": "ok"}

    @app.get("/readyz", include_in_schema=False)
    def readyz(repo: BookingRepository = Depends(get_repo)):
        try:
            repo.ping()
        except Exception:
            log.exception("readiness check failed")
            return JSONResponse({"status": "database unavailable"}, status_code=503)
        return {"status": "ready"}

    @app.get("/api/bookings/availability")
    def availability(
        course_id: int,
        date: date,
        repo: BookingRepository = Depends(get_repo),
        courses: CoursesClient = Depends(get_courses),
    ) -> list[Slot]:
        sheet = courses.tee_sheet(course_id, date)
        if sheet is None:
            raise HTTPException(404, "course not found")
        return compute_availability(sheet, repo.booked_players(course_id, date))

    @app.post("/api/bookings", status_code=201)
    def create_booking(
        request: BookingRequest,
        repo: BookingRepository = Depends(get_repo),
        courses: CoursesClient = Depends(get_courses),
        publisher: Publisher = Depends(get_publisher),
    ) -> Booking:
        if request.date < today():
            raise HTTPException(400, "date is in the past")
        sheet = courses.tee_sheet(request.course_id, request.date)
        if sheet is None:
            raise HTTPException(404, "course not found")
        if request.time.strftime("%H:%M") not in sheet.times:
            raise HTTPException(422, "not a tee time on this course")
        booking = repo.create(request, sheet.max_players)
        if booking is None:
            raise HTTPException(409, "not enough places left in that slot")
        try:
            publisher.booking_created(booking)
        except Exception:
            # The booking stands even if the event is lost; docs/adr/0003 covers the outbox fix.
            log.exception("failed to publish booking %s", booking.id)
        return booking

    @app.get("/api/bookings/{booking_id}")
    def get_booking(booking_id: UUID, repo: BookingRepository = Depends(get_repo)) -> Booking:
        booking = repo.get(booking_id)
        if booking is None:
            raise HTTPException(404, "booking not found")
        return booking

    @app.delete("/api/bookings/{booking_id}")
    def cancel_booking(booking_id: UUID, repo: BookingRepository = Depends(get_repo)) -> Booking:
        booking = repo.cancel(booking_id)
        if booking is None:
            raise HTTPException(404, "booking not found")
        return booking

    return app
