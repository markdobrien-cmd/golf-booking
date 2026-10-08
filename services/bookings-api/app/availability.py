from datetime import time

from .models import Slot, TeeSheet


def compute_availability(sheet: TeeSheet, booked: dict[time, int]) -> list[Slot]:
    """Places left in each slot of the tee sheet, given players already booked per slot."""
    slots = []
    for label in sheet.times:
        taken = booked.get(time.fromisoformat(label), 0)
        slots.append(Slot(time=label, remaining=max(sheet.max_players - taken, 0)))
    return slots
