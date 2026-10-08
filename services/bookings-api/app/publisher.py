import json
import logging
from typing import Protocol

from .models import Booking

log = logging.getLogger("bookings-api")


class Publisher(Protocol):
    def booking_created(self, booking: Booking) -> None: ...


class SqsPublisher:
    """Sends booking-created events to SQS.

    Locally AWS_ENDPOINT_URL points boto3 at ElasticMQ; on EKS it is unset and
    credentials come from the pod's IAM role, so the code is identical in both places.
    """

    def __init__(self, queue_url: str):
        import boto3

        self.queue_url = queue_url
        self.sqs = boto3.client("sqs")

    def booking_created(self, booking: Booking) -> None:
        body = {"type": "booking.created", "booking": booking.model_dump(mode="json")}
        self.sqs.send_message(QueueUrl=self.queue_url, MessageBody=json.dumps(body))


class LogPublisher:
    """Used when no queue is configured."""

    def booking_created(self, booking: Booking) -> None:
        log.info("no queue configured; booking %s not published", booking.id)
