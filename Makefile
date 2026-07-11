.PHONY: build up down logs shell collect kernels test

build:            ## Build the exam image (first build is large, ~15-40 min)
	docker compose build

up:               ## Start the exam lab at http://localhost:8888/lab
	docker compose up -d

down:             ## Stop the exam lab
	docker compose down

logs:             ## Follow container logs
	docker compose logs -f

shell:            ## Shell inside the running container
	docker compose exec examlab bash

kernels:          ## List installed Jupyter kernels
	docker compose exec examlab jupyter kernelspec list

test:             ## Smoke-test the running lab (kernels + hello notebooks)
	./scripts/smoke-test.sh

collect:          ## Archive results/ into archives/results-<timestamp>.tar.gz
	./scripts/collect-results.sh
