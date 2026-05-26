CFLAGS      ?=
CPPFLAGS    ?=
LDFLAGS     ?=
TARGET_ARCH ?=
LIBS        ?=

.PHONY: run clean monitor
run: main.tcl libdummy.so
	./$<
monitor: main.tcl dummy.c
	ls $^ | entr ./runme.sh
libdummy.so: dummy.c
	$(LINK.c) -shared -fPIC -o $@ $^ $(LIBS)
clean: F += libdummy.so
clean:
	$(if $(strip $(wildcard $F)),$(RM) -- $F)
