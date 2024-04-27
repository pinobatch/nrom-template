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
version := 0.05

# Space-separated list of assembly language files that make up the
# PRG ROM.  If it gets too long for one line, you can add a backslash
# (the \ character) at the end of the line and continue on the next.
objlist := \
  init main bg player \
  pads ppuclear

AS65 := ca65
LD65 := ld65
CFLAGS65 := 
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
DOTEXE:=.exe
PY:=py
else
DOTEXE:=
PY:=python3
endif

.PHONY: run debug all dist zip clean

run: $(title).nes
	$(EMU) $<
debug: $(title).nes
	$(DEBUGEMU) $<

all: $(title).nes $(title)256.nes

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

clean:
	-rm $(objdir)/*.o $(objdir)/*.s $(objdir)/*.chr

# Rules for PRG ROM

objlist128 := $(foreach o,nrom $(objlist),$(objdir)/$(o).o)
objlist256 := $(foreach o,nrom256 $(objlist),$(objdir)/$(o).o)

map.txt $(title).nes: nrom128.cfg $(objlist128)
	$(LD65) -o $(title).nes -m map.txt -C $^

map256.txt $(title)256.nes: nrom256.cfg $(objlist256)
	$(LD65) -o $(title)256.nes -m map256.txt -C $^

$(objdir)/%.o: $(srcdir)/%.s $(srcdir)/nes.inc $(srcdir)/global.inc
	$(AS65) $(CFLAGS65) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(AS65) $(CFLAGS65) $< -o $@

# Files that depend on .incbin'd files
$(objdir)/main.o: $(objdir)/bggfx.chr $(objdir)/spritegfx.chr

# This is an example of how to call a lookup table generator at
# build time.  mktables.py itself is not included because the demo
# has no music engine, but it's available online at
# http://wiki.nesdev.com/w/index.php/APU_period_table
$(objdir)/ntscPeriods.s: tools/mktables.py
	$(PY) $< period $@

# Rules for CHR ROM

$(title).chr: $(objdir)/bggfx.chr $(objdir)/spritegfx.chr
	cat $^ > $@

$(objdir)/%.chr: $(imgdir)/%.png
	$(PY) tools/pilbmp2nes.py $< $@

$(objdir)/%16.chr: $(imgdir)/%.png
	$(PY) tools/pilbmp2nes.py -H 16 $< $@
