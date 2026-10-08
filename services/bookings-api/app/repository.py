from datetime import date, time
from typing import Protocol
from uuid import UUID

from psycopg.rows import class_row
from psycopg_pool import ConnectionPool

from .models import Booking, BookingRequest


class BookingRepository(Protocol):
    def booked_players(self, course_id: int, day: date) -> dict[time, int]: ...
    def create(self, request: BookingRequest, max_players: int) -> Booking | None: ...
    def get(self, booking_id: UUID) -> Booking | None: ...
    def cancel(self, booking_id: UUID) -> Booking | None: ...
    def ping(self) -> None: ...


SCHEMA = """
CREATE TABLE IF NOT EXISTS bookings (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id  INT NOT NULL,
    tee_date   DATE NOT NULL,
    tee_time   TIME NOT NULL,
    players    INT NOT NULL CHECK (players BETWEEN 1 AND 4),
    name       TEXT NOT NULL,
    email      TEXT NOT NULL,
    status     TEXT NOT NULL DEFAULT 'confirmed',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS bookings_slot ON bookings (course_id, tee_date, tee_time);
"""


class PostgresBookingRepository:
    def __init__(self, pool: ConnectionPool):
        self.pool = pool

    def init_schema(self) -> None:
        with self.pool.connection() as conn:
            conn.execute(SCHEMA)

    def booked_players(self, course_id: int, day: date) -> dict[time, int]:
        with self.pool.connection() as conn:
            rows = conn.execute(
                "SELECT tee_time, SUM(players) FROM bookings"
                " WHERE course_id = %s AND tee_date = %s AND status = 'confirmed' GROUP BY tee_time",
                (course_id, day),
            ).fetchall()
        return {tee_time: int(total) for tee_time, total in rows}

    def create(self, request: BookingRequest, max_players: int) -> Booking | None:
        """Insert the booking unless the slot would go over max_players. None means full."""
        slot_key = f"{request.course_id}:{request.date}:{request.time}"
        with self.pool.connection() as conn, conn.transaction():
            # Serialise bookings for the same slot so two requests can't both take the last places.
            conn.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (slot_key,))
            (taken,) = conn.execute(
                "SELECT COALESCE(SUM(players), 0) FROM bookings"
                " WHERE course_id = %s AND tee_date = %s AND tee_time = %s AND status = 'confirmed'",
                (request.course_id, request.date, request.time),
            ).fetchone()
            if taken + request.players > max_players:
                return None
            with conn.cursor(row_factory=class_row(Booking)) as cur:
                return cur.execute(
                    "INSERT INTO bookings (course_id, tee_date, tee_time, players, name, email)"
                    " VALUES (%s, %s, %s, %s, %s, %s) RETURNING *",
                    (request.course_id, request.date, request.time, request.players, request.name, request.email),
                ).fetchone()

    def get(self, booking_id: UUID) -> Booking | None:
        with self.pool.connection() as conn, conn.cursor(row_factory=class_row(Booking)) as cur:
            return cur.execute("SELECT * FROM bookings WHERE id = %s", (booking_id,)).fetchone()

    def cancel(self, booking_id: UUID) -> Booking | None:
        with self.pool.connection() as conn, conn.cursor(row_factory=class_row(Booking)) as cur:
            return cur.execute(
                "UPDATE bookings SET status = 'cancelled' WHERE id = %s RETURNING *", (booking_id,)
            ).fetchone()

    def ping(self) -> None:
        with self.pool.connection() as conn:
            conn.execute("SELECT 1")
