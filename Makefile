.NOTPARALLEL:
.PHONY: all bootstrap list inventory bash sh gpl clean

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPT := $(ROOT)/scripts/build-apple-utils.sh

all:
	"$(SCRIPT)" build all

bootstrap:
	"$(SCRIPT)" bootstrap

list:
	"$(SCRIPT)" list

inventory:
	"$(SCRIPT)" inventory

bash:
	"$(SCRIPT)" build bash

sh:
	"$(SCRIPT)" build sh

gpl:
	"$(SCRIPT)" build bash

clean:
	rm -rf "$(ROOT)/build" "$(ROOT)/out"
