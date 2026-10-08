from datetime import time
from typing import Protocol

from psycopg.rows import class_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel


class Course(BaseModel):
    id: int
    name: str
    location: str
    holes: int
    first_tee: time
    last_tee: time
    interval_minutes: int
    max_players: int


class CourseRepository(Protocol):
    def list_courses(self) -> list[Course]: ...
    def get_course(self, course_id: int) -> Course | None: ...
    def ping(self) -> None: ...


# Schema is created on startup to keep Phase 0 simple; a migration tool replaces this later.
SCHEMA = """
CREATE TABLE IF NOT EXISTS courses (
    id               SERIAL PRIMARY KEY,
    name             TEXT UNIQUE NOT NULL,
    location         TEXT NOT NULL,
    holes            INT NOT NULL,
    first_tee        TIME NOT NULL,
    last_tee         TIME NOT NULL,
    interval_minutes INT NOT NULL,
    max_players      INT NOT NULL DEFAULT 4
);
INSERT INTO courses (name, location, holes, first_tee, last_tee, interval_minutes) VALUES
    ('Oakmere Links', 'Coastal', 18, '07:00', '17:00', 10),
    ('Hollybrook Park', 'Parkland', 18, '07:30', '16:30', 12),
    ('Silverstrand Nine', 'Heathland', 9, '08:00', '18:00', 15)
ON CONFLICT (name) DO NOTHING;
"""


class PostgresCourseRepository:
    def __init__(self, pool: ConnectionPool):
        self.pool = pool

    def init_schema(self) -> None:
        with self.pool.connection() as conn:
            conn.execute(SCHEMA)

    def list_courses(self) -> list[Course]:
        with self.pool.connection() as conn, conn.cursor(row_factory=class_row(Course)) as cur:
            return cur.execute("SELECT * FROM courses ORDER BY name").fetchall()

    def get_course(self, course_id: int) -> Course | None:
        with self.pool.connection() as conn, conn.cursor(row_factory=class_row(Course)) as cur:
            return cur.execute("SELECT * FROM courses WHERE id = %s", (course_id,)).fetchone()

    def ping(self) -> None:
        with self.pool.connection() as conn:
            conn.execute("SELECT 1")
