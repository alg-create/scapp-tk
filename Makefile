CFLAGS      ?=
CPPFLAGS    ?=
LDFLAGS     ?=
TARGET_ARCH ?=
LIBS        ?=

.PHONY: run clean monitor
run: main.tcl
	./$<
monitor: main.tcl
	ls $^ | entr ./runme.sh
