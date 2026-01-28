.PHONY: all agent server install clean

# Top-level helper Makefile for building the Agent and Server.
# The Server depends on the Agent (Agent must be built first).

all: agent server

agent:
	$(MAKE) -C Agent

server: agent
	$(MAKE) -C Server

install:
	$(MAKE) -C Agent install
	$(MAKE) -C Server install

clean:
	$(MAKE) -C Agent clean
	$(MAKE) -C Server clean
