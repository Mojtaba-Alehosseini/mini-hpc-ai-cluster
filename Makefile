COMPOSE ?= docker compose
PLAYBOOK ?= ansible-playbook

.PHONY: up down reset check build logs ps configure idempotent bench

## up: build and start the containers, then configure them with Ansible
up: secrets/munge.key
	@date +%s > .up_started
	$(COMPOSE) up -d --build
	$(MAKE) configure
	./scripts/wait_ready.sh
	$(COMPOSE) exec -T head sinfo
	@echo "make up took $$(( $$(date +%s) - $$(cat .up_started) )) s"

## configure: run the Ansible site playbook (idempotent)
configure:
	cd ansible && $(PLAYBOOK) site.yml

## idempotent: a second Ansible run in check mode must report no change (test 13)
idempotent:
	cd ansible && $(PLAYBOOK) site.yml --check --diff

## check: the acceptance tests in tests/
check:
	./tests/run.sh

## bench: run the IO benchmarks and write CSVs under bench/results/
## Override the size for real numbers, e.g. make bench SIZE=2g NFILES=200000
bench:
	SIZE=$(SIZE) TRIALS=$(TRIALS) ./bench/io/run.sh bench/results/fio.csv
	NFILES=$(NFILES) TRIALS=$(TRIALS) ./bench/io/smallfiles_run.sh bench/results/smallfiles.csv

SIZE ?= 512m
NFILES ?= 20000
TRIALS ?= 3

## down: stop the containers, keep the volumes (accounting, shared files)
down:
	$(COMPOSE) down

## reset: stop and delete everything, including the volumes and the munge key
reset:
	$(COMPOSE) down -v --remove-orphans
	rm -rf secrets .up_started

build:
	$(COMPOSE) build

logs:
	$(COMPOSE) logs --tail=50

ps:
	$(COMPOSE) ps

# The munge key is generated once per checkout and never committed.
secrets/munge.key:
	mkdir -p secrets
	dd if=/dev/urandom of=$@ bs=1024 count=1 status=none
	chmod 600 $@
