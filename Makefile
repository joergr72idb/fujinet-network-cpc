# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 joergr72idb - see LICENSE
# fujinet-network for the CPC + M4 (SDCC): the network part of FujiNet's fujinet-lib on the M4.
# Uses the CPC development kit (../development-kit-cpc-and-m4: SDCC, lib/cpc, lib/m4, iDSK,
# CPCSyntaxError); `make DEV=/path/to/kit` for another place.
#
#   make                  build/fujinet-network.rel + build/m4.rel (link both into your program)
#   make test             builds FNTEST.BIN (TCP), FNHTTP.BIN (HTTP) and FNJSON.BIN (JSON) - one
#                         program with everything does not fit in the CPC's memory - and runs each
#                         headless in the kit's emulator against test/testserver.py: PASS or FAIL
#   make fntest           only the programs + fntest.dsk (SERVER=, PORT= for a real CPC)
#   NO_HTTP=1             with any of them: without HTTP (-DFN_NO_HTTP, about 3 KB smaller)
#
# Your program: -I include -I $(DEV)/lib/m4, link build/fujinet-network.rel build/m4.rel.

DEV     ?= $(abspath ../development-kit-cpc-and-m4)
# SDCC: Homebrew's on macOS, the one on PATH (apt) on Linux - as in the kit
SDCC    := $(if $(filter Darwin,$(shell uname -s)),$(shell brew --prefix sdcc 2>/dev/null)/bin/sdcc,$(shell command -v sdcc 2>/dev/null))
SDASZ80 := $(dir $(SDCC))sdasz80
IDSK    := $(DEV)/opt/idsk/iDSK
CPCSE   := $(DEV)/opt/cpcse

SERVER  ?= 127.0.0.1
PORT    ?= 6510
FRAMES  ?= 5000
NO_HTTP ?=

CFLAGS  := -mz80 --opt-code-size -I include -I $(DEV)/lib/cpc -I $(DEV)/lib/m4 $(if $(NO_HTTP),-DFN_NO_HTTP)
LDFLAGS := -mz80 --no-std-crt0 --code-loc 0x4010 --data-loc 0
OBJ     := build

.PHONY: all lib fntest test clean

all: lib
lib: $(OBJ)/fujinet-network.rel $(OBJ)/m4.rel

$(OBJ)/fujinet-network.rel: src/fujinet-network.c include/fujinet-network.h $(OBJ)/fntest.id | $(OBJ)
	$(SDCC) $(CFLAGS) -c -o $@ $<

$(OBJ)/m4.rel: $(DEV)/lib/m4/m4.c | $(OBJ)
	$(SDCC) $(CFLAGS) -c -o $@ $<

$(OBJ)/cpc.rel: $(DEV)/lib/cpc/cpc.c | $(OBJ)
	$(SDCC) $(CFLAGS) -c -o $@ $<

$(OBJ)/crt0.rel: $(DEV)/lib/cpc/crt0.s | $(OBJ)
	$(SDASZ80) -o $@ $<

# the server and NO_HTTP are compiled in: build/fntest.id changes (and the objects are rebuilt)
# when SERVER/PORT/NO_HTTP do
TEST_ID := $(SERVER) $(PORT) $(NO_HTTP)
ifneq ($(shell cat $(OBJ)/fntest.id 2>/dev/null),$(TEST_ID))
$(shell mkdir -p $(OBJ) && echo "$(TEST_ID)" > $(OBJ)/fntest.id)
endif

$(OBJ)/fntest.rel: test/fntest.c include/fujinet-network.h $(OBJ)/fntest.id | $(OBJ)
	$(SDCC) $(CFLAGS) -DSERVER_HOST='"$(SERVER)"' -DSERVER_PORT=$(PORT) -c -o $@ $<

$(OBJ)/fnhttp.rel: test/fntest.c include/fujinet-network.h $(OBJ)/fntest.id | $(OBJ)
	$(SDCC) $(CFLAGS) -DTEST_HTTP -DSERVER_HOST='"$(SERVER)"' -DSERVER_PORT=$(PORT) -c -o $@ $<

$(OBJ)/fnjson.rel: test/fntest.c include/fujinet-network.h $(OBJ)/fntest.id | $(OBJ)
	$(SDCC) $(CFLAGS) -DTEST_JSON -DSERVER_HOST='"$(SERVER)"' -DSERVER_PORT=$(PORT) -c -o $@ $<

# the library without JSON, for FNTEST and FNHTTP (they don't use it; it would not fit)
$(OBJ)/fujinet-network-nojson.rel: src/fujinet-network.c include/fujinet-network.h $(OBJ)/fntest.id | $(OBJ)
	$(SDCC) $(CFLAGS) -DFN_NO_JSON -c -o $@ $<

# program end (data and the crt0's stack included) must stay below HIMEM: &A5F7 with the M4 ROM
HIMEM   := 0xA5F7
define link
	$(SDCC) $(LDFLAGS) -o $(OBJ)/$(1).ihx $(2)
	@python3 -I -c 'import re,sys; m=open(sys.argv[1]).read(); s=int(re.search(r"(\w+)\s+s__STACK",m).group(1),16); l=int(re.search(r"(\w+)\s+l__STACK",m).group(1),16); e=s+l; print("$(1): ends at &%04X (HIMEM &%04X)" % (e, $(HIMEM))); sys.exit(e > $(HIMEM))' $(OBJ)/$(1).map || { echo "$(1) is too big for the CPC"; rm -f $(OBJ)/$(1).ihx; exit 1; }
	python3 -I $(DEV)/tools/cpcbin.py $(OBJ)/$(1).ihx $(3)
endef

# crt0 first: its JP at &4000 is the entry. NO_HTTP: FNTEST with the TCP-only library
LIBTCP  := $(OBJ)/$(if $(NO_HTTP),fujinet-network,fujinet-network-nojson).rel
FNTEST.BIN: $(OBJ)/crt0.rel $(OBJ)/fntest.rel $(LIBTCP) $(OBJ)/m4.rel $(OBJ)/cpc.rel
	$(call link,fntest,$^,$@)

FNHTTP.BIN: $(OBJ)/crt0.rel $(OBJ)/fnhttp.rel $(OBJ)/fujinet-network-nojson.rel $(OBJ)/m4.rel $(OBJ)/cpc.rel
	$(call link,fnhttp,$^,$@)

FNJSON.BIN: $(OBJ)/crt0.rel $(OBJ)/fnjson.rel $(OBJ)/fujinet-network.rel $(OBJ)/m4.rel $(OBJ)/cpc.rel
	$(call link,fnjson,$^,$@)

PROGS   := FNTEST.BIN $(if $(NO_HTTP),,FNHTTP.BIN FNJSON.BIN)

fntest.dsk: $(PROGS)
	rm -f $@
	$(IDSK) $@ -n > /dev/null
	for f in $(PROGS); do $(IDSK) $@ -i $$f > /dev/null; done

fntest: $(PROGS) fntest.dsk

# headless, for each program: the test server in the background, the program in the emulator, the
# server's verdict (build/server-NAME.log, build/shot-NAME.png)
test: $(PROGS)
	mkdir -p $(DEV)/m4sd && cp $(PROGS) $(DEV)/m4sd/
	$(MAKE) -C $(DEV) build/cpcse-home/cpcse.ini
	@rc=0; for f in $(basename $(PROGS)); do \
	  echo "=== $$f"; \
	  python3 -I test/testserver.py $(PORT) 180 > $(OBJ)/server-$$f.log 2>&1 & \
	  sleep 1; \
	  ( cd $(CPCSE) && CPCSE_HOME=$(DEV)/build/cpcse-home ./cpcse --shot $(CURDIR)/$(OBJ)/shot.bmp \
	    --model cpc6128 --m4 $(DEV)/m4sd --type "RUN\"$$f\"\n" --frames $(FRAMES) \
	    > $(CURDIR)/$(OBJ)/emu-$$f.log 2>&1 ); \
	  wait $$! || rc=1; \
	  $(if $(filter Darwin,$(shell uname -s)),sips -s format png $(OBJ)/shot.bmp --out $(OBJ)/shot-$$f.png > /dev/null,python3 -I $(DEV)/tools/bmp2png.py $(OBJ)/shot.bmp $(OBJ)/shot-$$f.png); \
	  cat $(OBJ)/server-$$f.log; \
	done; echo "screenshots: $(OBJ)/shot-*.png"; \
	if [ $$rc = 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi; exit $$rc

$(OBJ):
	mkdir -p $@

clean:
	rm -rf $(OBJ) FNTEST.BIN FNHTTP.BIN FNJSON.BIN fntest.dsk
