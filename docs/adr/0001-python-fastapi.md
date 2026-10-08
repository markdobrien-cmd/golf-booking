# 0001: Python and FastAPI for every service

**Status:** accepted, 2026-10-08

## Context
The project exists to practise platform engineering (Terraform, EKS, Helm, GitOps). Application code is a means to that end, and four services in four languages would multiply the Dockerfiles, test setups and CI templates to maintain.

## Decision
All services use Python 3.12. HTTP services use FastAPI with uvicorn; the worker is plain Python with boto3. Each service has its own `requirements.txt`, image and tests, and shares no code with the others (the small metrics module is copied, not imported).

## Consequences
- One Dockerfile pattern and one CI template cover every service.
- Services stay independently deployable, which matters more here than avoiding a few duplicated lines.
- FastAPI gives typed request validation and OpenAPI docs (`/docs`) for free.
