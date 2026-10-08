# 0003: Publish booking events after commit

**Status:** accepted, 2026-10-08

## Context
When a booking is created, bookings-api writes it to Postgres and sends a `booking.created` event to SQS. These are two systems, so they can't share one transaction.

## Decision
The booking is committed first, then the event is sent. If sending fails, the error is logged and the booking still stands.

## Consequences
- A customer never loses a booking because the queue was unavailable.
- An event can be lost, so a confirmation can be missed. That is acceptable for this project.
- If it stops being acceptable, the fix is the **transactional outbox** pattern: write the event to an `outbox` table in the same transaction, and have a relay publish and mark it sent.
- On the consuming side, the worker deletes a message only after handling it, and SQS moves repeatedly failing messages to a dead-letter queue after three attempts.
