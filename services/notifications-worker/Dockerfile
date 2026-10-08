FROM python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY --from=build /install /usr/local
WORKDIR /srv
COPY app ./app
USER 10001
# Metrics only; the worker takes no inbound requests.
EXPOSE 8080
CMD ["python", "-m", "app.worker"]
