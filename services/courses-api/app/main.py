import logging
import os
from contextlib import asynccontextmanager
from datetime import date

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from .metrics import instrument
from .repository import Course, CourseRepository
from .slots import generate_slots

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
log = logging.getLogger("courses-api")


class TeeSheet(BaseModel):
    course_id: int
    date: date
    max_players: int
    times: list[str]


def create_app(repo: CourseRepository | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if repo is not None:
            app.state.repo = repo
            yield
            return
        # Imported here so tests run without a database driver configured.
        from psycopg_pool import ConnectionPool

        from .repository import PostgresCourseRepository

        pool = ConnectionPool(os.environ["DATABASE_URL"], min_size=1, max_size=5, open=True)
        postgres = PostgresCourseRepository(pool)
        postgres.init_schema()
        app.state.repo = postgres
        yield
        pool.close()

    app = FastAPI(title="courses-api", lifespan=lifespan)
    instrument(app)

    def get_repo(request: Request) -> CourseRepository:
        return request.app.state.repo

    @app.get("/healthz", include_in_schema=False)
    def healthz() -> dict:
        return {"status": "ok"}

    @app.get("/readyz", include_in_schema=False)
    def readyz(repo: CourseRepository = Depends(get_repo)):
        try:
            repo.ping()
        except Exception:
            log.exception("readiness check failed")
            return JSONResponse({"status": "database unavailable"}, status_code=503)
        return {"status": "ready"}

    @app.get("/api/courses")
    def list_courses(repo: CourseRepository = Depends(get_repo)) -> list[Course]:
        return repo.list_courses()

    @app.get("/api/courses/{course_id}")
    def get_course(course_id: int, repo: CourseRepository = Depends(get_repo)) -> Course:
        course = repo.get_course(course_id)
        if course is None:
            raise HTTPException(404, "course not found")
        return course

    @app.get("/api/courses/{course_id}/tee-times")
    def tee_times(course_id: int, date: date, repo: CourseRepository = Depends(get_repo)) -> TeeSheet:
        course = repo.get_course(course_id)
        if course is None:
            raise HTTPException(404, "course not found")
        slots = generate_slots(course.first_tee, course.last_tee, course.interval_minutes)
        return TeeSheet(
            course_id=course.id,
            date=date,
            max_players=course.max_players,
            times=[t.strftime("%H:%M") for t in slots],
        )

    return app
