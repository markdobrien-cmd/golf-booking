"""Prometheus metrics shared by every route: request count and latency.

Each service carries its own copy of this file so images stay independent.
"""

import time

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "route", "status"])
LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency", ["method", "route"])


def instrument(app: FastAPI) -> None:
    @app.middleware("http")
    async def record(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        # Label by route template (/api/courses/{course_id}), not raw path, to keep cardinality low.
        route = request.scope.get("route")
        path = route.path if route else "unmatched"
        REQUESTS.labels(request.method, path, response.status_code).inc()
        LATENCY.labels(request.method, path).observe(time.perf_counter() - start)
        return response

    @app.get("/metrics", include_in_schema=False)
    def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
