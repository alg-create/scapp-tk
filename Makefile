CFLAGS      ?=
CPPFLAGS    ?=
LDFLAGS     ?=
TARGET_ARCH ?=
LIBS        ?=

.PHONY: run clean monitor test
run: main.tcl
	./$<
monitor: main.tcl
	ls $^ | entr ./runme.sh
test:
	tclsh tests/runtests.tcl
