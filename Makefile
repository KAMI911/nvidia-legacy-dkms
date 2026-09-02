# nvidia-legacy-dkms — local build orchestration.
# The authoritative builds run on OBS; this mirrors them for development.
SHELL      := /bin/bash
ROOT       := $(CURDIR)
COMMON     := $(ROOT)/common
BUILDDIR   ?= $(ROOT)/../build
SERIES     ?= 390xx
TARGET     ?= debian13
FLAVOUR    := dkms
export SOURCE_DATE_EPOCH ?= $(shell git -C $(COMMON) log -1 --format=%ct 2>/dev/null || echo 0)

.PHONY: help regen lint source build test reprotest clean submodule

help:
	@sed -n 's/^## //p' $(MAKEFILE_LIST)

## submodule   : init/refresh the common/ submodule
submodule:
	git submodule update --init --remote common

## regen       : render every packaging/<series>/<target>
regen: ; scripts/regen.sh

## lint        : run the static gate (no build)
lint:
	.github/scripts/static-checks.sh $(SERIES) $(TARGET)

## source      : build .dsc + .orig tarballs into $(BUILDDIR)
source: regen
	mkdir -p $(BUILDDIR)
	$(COMMON)/scripts/verify-run.sh $(SERIES)
	$(COMMON)/scripts/assemble-source.sh $(SERIES) $(BUILDDIR)
	cd $(BUILDDIR) && dpkg-source -b $(ROOT)/packaging/$(SERIES)/$(TARGET)

## build       : sbuild the package for $(TARGET) (amd64 + i386 where applicable)
build: source
	.github/scripts/sbuild-wrap.sh $(SERIES) $(TARGET)

## reprotest   : build twice, diffoscope the results
reprotest: source
	reprotest --vary=-user_group --vary=-domain_host \
	  "dpkg-buildpackage -b -uc -us" \
	  $(BUILDDIR)/nvidia-legacy-$(SERIES)_*.dsc

## test        : full no-GPU test suite for $(SERIES)/$(TARGET)
test: build
	tests/run-all.sh $(SERIES) $(TARGET)

## clean       :
clean:
	rm -rf $(BUILDDIR) packaging/*/*/debian
