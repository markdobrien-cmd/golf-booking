from datetime import date, datetime, time, timedelta


def generate_slots(first_tee: time, last_tee: time, interval_minutes: int) -> list[time]:
    """Every tee time from first_tee to last_tee inclusive, interval_minutes apart."""
    if interval_minutes <= 0:
        raise ValueError("interval_minutes must be positive")
    current = datetime.combine(date.min, first_tee)
    end = datetime.combine(date.min, last_tee)
    slots = []
    while current <= end:
        slots.append(current.time())
        current += timedelta(minutes=interval_minutes)
    return slots
