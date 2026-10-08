"""Consumes booking-created events from SQS and sends a confirmation.

Phase 0 "sends" by logging. A message is deleted only after it is handled, so a
failure leaves it on the queue to be retried and, after maxReceiveCount, moved to
the dead-letter queue.
"""

import json
import logging
import os
import signal
import time

from prometheus_client import Counter, Gauge, start_http_server

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
log = logging.getLogger("notifications-worker")

HANDLED = Counter("notifications_handled_total", "Messages handled", ["outcome"])
LAST_POLL = Gauge("notifications_last_poll_timestamp_seconds", "When the worker last polled SQS")


def confirmation_text(body: str) -> str:
    event = json.loads(body)
    if event.get("type") != "booking.created":
        raise ValueError(f"unexpected event type {event.get('type')!r}")
    b = event["booking"]
    return (
        f"Hi {b['name']}, your tee time for {b['players']} player(s) at course {b['course_id']} "
        f"on {b['tee_date']} at {b['tee_time'][:5]} is confirmed. Booking reference {b['id']}."
    )


def process(sqs, queue_url: str, wait_seconds: int = 20) -> int:
    """One long-poll of the queue. Returns how many messages were handled successfully."""
    response = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10, WaitTimeSeconds=wait_seconds)
    LAST_POLL.set_to_current_time()
    handled = 0
    for message in response.get("Messages", []):
        try:
            log.info("confirmation sent: %s", confirmation_text(message["Body"]))
        except Exception:
            HANDLED.labels("failed").inc()
            log.exception("could not handle message %s; leaving it for retry", message["MessageId"])
            continue
        sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=message["ReceiptHandle"])
        HANDLED.labels("sent").inc()
        handled += 1
    return handled


def main() -> None:
    import boto3

    queue_url = os.environ["SQS_QUEUE_URL"]
    sqs = boto3.client("sqs")
    start_http_server(int(os.getenv("METRICS_PORT", "8080")))

    # Kubernetes sends SIGTERM before killing a pod; finish the current poll and exit cleanly.
    stopping = False

    def stop(*_):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    log.info("polling %s", queue_url)
    while not stopping:
        try:
            process(sqs, queue_url)
        except Exception:
            log.exception("poll failed; backing off")
            time.sleep(5)
    log.info("stopped")


if __name__ == "__main__":
    main()
