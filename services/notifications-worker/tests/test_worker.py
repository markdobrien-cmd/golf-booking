import json

import pytest

from app.worker import confirmation_text, process

EVENT = {
    "type": "booking.created",
    "booking": {
        "id": "b1",
        "course_id": 1,
        "tee_date": "2026-10-10",
        "tee_time": "07:00:00",
        "players": 2,
        "name": "Mark",
        "email": "m@example.com",
    },
}


class FakeSqs:
    def __init__(self, bodies):
        self.messages = [{"MessageId": str(i), "ReceiptHandle": f"r{i}", "Body": b} for i, b in enumerate(bodies)]
        self.deleted = []

    def receive_message(self, **_):
        return {"Messages": self.messages}

    def delete_message(self, QueueUrl, ReceiptHandle):
        self.deleted.append(ReceiptHandle)


def test_confirmation_text():
    assert "07:00 is confirmed" in confirmation_text(json.dumps(EVENT))


def test_unknown_event_rejected():
    with pytest.raises(ValueError):
        confirmation_text(json.dumps({"type": "other"}))


def test_good_messages_deleted_bad_ones_left_for_retry():
    sqs = FakeSqs([json.dumps(EVENT), "not json"])
    assert process(sqs, "queue", wait_seconds=0) == 1
    assert sqs.deleted == ["r0"]
