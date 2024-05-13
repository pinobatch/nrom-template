#!/usr/bin/make -f
#
# Makefile for NES game
# Copyright 2011-2024 Damian Yerrick
#
# Copying and distribution of this file, with or without
# modification, are permitted in any medium without royalty
# provided the copyright notice and this notice are preserved.
# This file is offered as-is, without any warranty.
#

# These are used in the title of the NES program and the zip file.
title := nrom-template
version := 0.06wip

# Space-separated list of assembly language files that make up the
# PRG ROM.  If it gets too long for one line, you can add a backslash
# (the \ character) at the end of the line and continue on the next.
objlist := \
  init main bg player \
  pads ppuclear

# Some commands differ on Windows vs. POSIX (Linux, BSD, macOS)
# systems.  Windows needs .exe suffixed to the names of executables;
# UNIX does not.  Windows starts Python via the PEP 397 launcher
# (py.exe); UNIX usually starts it via `python3`.
ifeq ($(OS), Windows_NT)
  EXE_SUFFIX := .exe
  PY := py -3
else
  EXE_SUFFIX :=
  PY := python3
endif

# cc65 build scripts detect Windows via "ECHO is on" message from
# `echo` without arguments.  This template doesn't use this method
# because its correlation with a working Python command is untested.
#    ifneq ($(shell echo),)
# It used to be common to detect Windows via the COMSPEC variable
# prior to Windows 11.

# Use cc65 conventions for variable names where practicable
CA65FLAGS := -g
CC65FLAGS := -g -Or -W error
CA65 := $(if $(wildcard $(CC65_HOME)/bin/ca65*),$(CC65_HOME)/bin/ca65,ca65)
CC65 := $(if $(wildcard $(CC65_HOME)/bin/cc65*),$(CC65_HOME)/bin/cc65,cc65)
LD65 := $(if $(wildcard $(CC65_HOME)/bin/ld65*),$(CC65_HOME)/bin/ld65,ld65)

objdir := obj/nes
srcdir := src
imgdir := tilesets

EMU := fceux
DEBUGEMU := Mesen
# other options for EMU are start "" (Windows) or xdg-open (UNIX)

# Occasionally, you need to make "build tools", or programs that run
# on a PC that convert, compress, or otherwise translate PC data
# files into the format that the NES program expects.  Some people
# write build tools in C, C++, or Rust; others prefer to write them
# in Perl, PHP, or Python.  This program doesn't use any C build
# tools, but if yours does, it might include definitions of variables
# that Make uses to call a C compiler.
CC := gcc
CFLAGS := -std=gnu17 -Wall -DNDEBUG -Og

# Windows needs .exe suffixed to the names of executables; UNIX does
# not.  COMSPEC will be set to the name of the shell on Windows and
# not defined on UNIX.  Also the Windows Python installer puts
# py.exe in the path, but not python3.exe, which confuses MSYS Make.
ifeq ($(OS), Windows_NT)
  EXE_SUFFIX:=.exe
  PY:=py
else
  EXE_SUFFIX:=
  PY:=python3
endif

# Phony targets are those not associated with an output file.
.PHONY: run debug all dist zip clean

# Running `make` without arguments builds the target of the first
# rule in a makefile.  Because some editors bind F5 to `make`,
# some people prefer to have `make` behave as `make run`.
# Rules after the first may appear in any order.

run: $(title).nes
	$(EMU) $<
debug: $(title).nes
	$(DEBUGEMU) $<

# Rules to convert graphics from PNG to the NES's 2bpp format, or
# convert or generate other data

$(objdir)/%.chr: $(imgdir)/%.png
	$(PY) tools/pilbmp2nes.py $< $@

$(objdir)/%16.chr: $(imgdir)/%.png
	$(PY) tools/pilbmp2nes.py -H 16 $< $@

# An example of how to call a lookup table generator at build time.
# mktables.py from <https://www.nesdev.org/wiki/APU_period_table>
# is not included in this template because the demo has no sound.

$(objdir)/ntscPeriods.s: tools/mktables.py
	$(PY) $< period $@

# Generic rules for assembling, or converting assembly language
# source code to object code

$(objdir)/%.o: $(srcdir)/%.s $(srcdir)/nes.inc $(srcdir)/global.inc
	$(CA65) $(CA65FLAGS) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(CA65) $(CA65FLAGS) $< -o $@

# List files that include other files.  This instructs Make to
# ensure other files are built first and to rebuild this file
# when the other files change.

$(objdir)/main.o: $(objdir)/bggfx.chr $(objdir)/spritegfx.chr

# Rules for linking, or combining several object code files into an
# executable program.  This uses a linker configuration file
# (sometimes called a linker script), which specifies in what memory
# each segment should go.

all: $(title).nes $(title)256.nes

objlist128 := $(foreach o,nrom $(objlist),$(objdir)/$(o).o)
objlist256 := $(foreach o,nrom256 $(objlist),$(objdir)/$(o).o)

map.txt $(title).nes: nrom128.cfg $(objlist128)
	$(LD65) -o $(title).nes --dbgfile $(title).dbg -m map.txt -C $^

map256.txt $(title)256.nes: nrom256.cfg $(objlist256)
	$(LD65) -o $(title)256.nes --dbgfile $(title)256.dbg -m map256.txt -C $^

# Rule to create or update the distribution zipfile by adding all
# files listed in zip.in.  Though the zipfile depends on every file
# listed in zip.in, Make can't see all dependencies.  Use changes to
# the ROMs, makefile, and README as a heuristic for when something
# was changed.  Tool changes usually imply makefile changes, and
# docs changes usually imply README or CHANGES changes.
dist: zip
zip: $(title)-$(version).zip
$(title)-$(version).zip: \
  zip.in all README.md CHANGES.txt $(objdir)/index.txt
	zip -9 -u $@ -@ < $<

# Build zip.in from the list of files in the Git tree.
zip.in:
	git ls-files | grep -e "^[^.]" > $@
	echo $(title).nes >> $@
	echo $(title)256.nes >> $@
	echo zip.in >> $@

$(objdir)/index.txt: makefile
	echo Files produced by build tools go here > $@

# When troubleshooting a build process or cleaning up a full drive,
# you can remove intermediate files.
clean:
	$(RM) $(objdir)/*.o $(objdir)/*.s $(objdir)/*.chr
