SERVICES := courses-api bookings-api notifications-worker

.PHONY: up down logs test lint venv

up:  ## Build and start the local stack on http://localhost:8080
	docker compose up --build -d

down:  ## Stop the local stack and delete its data
	docker compose down -v

logs:
	docker compose logs -f

venv:  ## One virtualenv per service, so each one's dependencies are tested in isolation
	@for s in $(SERVICES); do \
		python3 -m venv services/$$s/.venv && services/$$s/.venv/bin/pip install -q -r services/$$s/requirements-dev.txt; \
	done

test:
	@for s in $(SERVICES); do echo "== $$s"; (cd services/$$s && .venv/bin/pytest -q) || exit 1; done

lint:
	@for s in $(SERVICES); do (cd services/$$s && .venv/bin/ruff check . && .venv/bin/ruff format --check .) || exit 1; done
