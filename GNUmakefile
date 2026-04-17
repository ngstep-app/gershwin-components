# Top-level (phony) GNUmakefile for gershwin-components
# This makefile is intentionally minimal and "phony". It simply dispatches
# common targets to all first-level subdirectories that contain a Makefile.
# Use this from the top of the gershwin-components tree.

.PHONY: all build clean install distclean help $(SUBDIRS)

# Auto-detect first-level subdirectories that contain a Makefile, Makefile.in, or a configure script
SUBDIRS := $(sort $(shell for d in *; do \
	[ -d "$${d}" ] && \
	( [ -f "$${d}/GNUmakefile" ] || [ -f "$${d}/Makefile" ] || [ -f "$${d}/Makefile.in" ] || [ -x "$${d}/configure" ] || [ -f "$${d}/configure" ] ) && echo "$${d}"; \
	done))
all: build

# Build each subdirectory
build: $(SUBDIRS)
	@echo "Build completed for all components."

# For each subdir, if a Makefile.in exists and there is no Makefile (or it's older),
# prefer to run configure (use `confiture` if available, else ./configure, else autoreconf)
$(SUBDIRS):
	@echo "Entering $@";
	@if [ -f "$@/Makefile.in" ] && ( [ ! -f "$@/Makefile" ] || [ "$@/Makefile.in" -nt "$@/Makefile" ] ); then \
		echo "Preparing $@ (running configure)"; \
		( cd $@ && \
			if command -v confiture >/dev/null 2>&1; then \
				confiture || true; \
			elif [ -x configure ]; then \
				./configure || true; \
			elif [ -f configure ]; then \
				sh configure || true; \
			elif command -v autoreconf >/dev/null 2>&1; then \
				autoreconf -i && ./configure || true; \
			else \
				echo "No configure tool found in $@; skipping configure"; \
			fi ); \
	fi; \
	$(MAKE) -C $@ || true; \
	@echo "Leaving $@"; 

# Clean every subdir (non-fatal)
clean:
	@for d in $(SUBDIRS); do \
		if [ -f "$${d}/Makefile.in" ] && ( [ ! -f "$${d}/Makefile" ] || [ "$${d}/Makefile.in" -nt "$${d}/Makefile" ] ); then \
			echo "Preparing $$d (running configure)"; \
			( cd $$d && if command -v confiture >/dev/null 2>&1; then confiture || true; elif [ -x configure ]; then ./configure || true; elif [ -f configure ]; then sh configure || true; elif command -v autoreconf >/dev/null 2>&1; then autoreconf -i && ./configure || true; else echo "No configure tool found in $$d; skipping configure"; fi ); \
		fi; \
		if [ -f "$${d}/Makefile" -o -f "$${d}/GNUmakefile" ]; then \
			echo "Cleaning $$d"; $(MAKE) -C $$d clean || true; \
		fi; \
	done

# Distclean: deeper clean if subdirs provide it
distclean:
	@for d in $(SUBDIRS); do \
		if [ -f "$${d}/Makefile.in" ] && ( [ ! -f "$${d}/Makefile" ] || [ "$${d}/Makefile.in" -nt "$${d}/Makefile" ] ); then \
			echo "Preparing $$d (running configure)"; \
			( cd $$d && if command -v confiture >/dev/null 2>&1; then confiture || true; elif [ -x configure ]; then ./configure || true; elif [ -f configure ]; then sh configure || true; elif command -v autoreconf >/dev/null 2>&1; then autoreconf -i && ./configure || true; else echo "No configure tool found in $$d; skipping configure"; fi ); \
		fi; \
		if [ -f "$${d}/Makefile" -o -f "$${d}/GNUmakefile" ]; then \
			echo "Distclean $$d"; $(MAKE) -C $$d distclean || true; \
		fi; \
	done

install:
	@for d in $(SUBDIRS); do \
		if [ -f "$${d}/Makefile.in" ] && ( [ ! -f "$${d}/Makefile" ] || [ "$${d}/Makefile.in" -nt "$${d}/Makefile" ] ); then \
			echo "Preparing $$d (running configure)"; \
			( cd $$d && if command -v confiture >/dev/null 2>&1; then confiture || true; elif [ -x configure ]; then ./configure || true; elif [ -f configure ]; then sh configure || true; elif command -v autoreconf >/dev/null 2>&1; then autoreconf -i && ./configure || true; else echo "No configure tool found in $$d; skipping configure"; fi ); \
		fi; \
		if [ -f "$${d}/Makefile" -o -f "$${d}/GNUmakefile" ]; then \
			echo "Installing $$d"; $(MAKE) -C $$d install || true; \
		fi; \
	done

help:
	@echo "Top-level GNUmakefile for gershwin-components";
	@echo "Available subdirectories:"; \
	@printf '  %s\n' $(SUBDIRS);
	@echo "Targets: all (default), build, clean, distclean, install, help"
