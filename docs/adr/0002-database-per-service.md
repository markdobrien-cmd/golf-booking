# 0002: A database per service on one Postgres instance

**Status:** accepted, 2026-10-08

## Context
In a microservice design each service owns its data, and no service reads another's tables. Running a separate RDS instance per service would double the database cost of an environment that is meant to be cheap to run.

## Decision
One Postgres instance (RDS `db.t4g.micro` on AWS, a container locally) holds two databases, `courses` and `bookings`, each with its own login. bookings-api learns about courses only through the courses-api HTTP API.

## Consequences
- The ownership boundary is enforced by credentials, not just convention.
- The services share one failure domain and one instance's capacity. Splitting them later is a Terraform change plus a data migration, with no code changes.
- Schemas are created at startup for now; a migration tool will replace that once the schema starts changing.
