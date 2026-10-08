from datetime import date
from typing import Protocol

import httpx

from .models import TeeSheet


class CoursesClient(Protocol):
    def tee_sheet(self, course_id: int, day: date) -> TeeSheet | None: ...


class HttpCoursesClient:
    """Calls courses-api over HTTP. In Kubernetes the base URL is the service's cluster DNS name."""

    def __init__(self, base_url: str, timeout: float = 2.0):
        self.http = httpx.Client(base_url=base_url, timeout=timeout)

    def tee_sheet(self, course_id: int, day: date) -> TeeSheet | None:
        response = self.http.get(f"/api/courses/{course_id}/tee-times", params={"date": day.isoformat()})
        if response.status_code == 404:
            return None
        response.raise_for_status()
        return TeeSheet.model_validate(response.json())

    def close(self) -> None:
        self.http.close()
