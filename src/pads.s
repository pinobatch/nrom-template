;
; NES controller reading code
; Copyright 2009-2023 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

; Significant changes
;
; 2023-11: Damian Yerrick added a historical note about rereading
; 2011-07: Damian Yerrick added labels for the local variables and
;          copious comments and made USE_DAS a build-time option

; Historical note related to DMC DMA glitch avoidance
;
; This routine reads the controller twice and discards non-matching
; presses.  As of the second half of 2011 when nrom-template was
; first published, this method was state of the art for avoiding
; read corruption caused by DMC DMA fetches.
;
; In 2016, Rahsennor invented a way to synchronize to OAM DMA that
; even more reliably avoids read corruption in many cases.
; https://www.nesdev.org/wiki/Controller_reading_code#DPCM_Safety_using_OAM_DMA
; This technique has a couple drawbacks, such as forbidding reading
; the controller on frames when a sample is playing and OAM DMA did
; not occur.

.export read_pads
.importzp cur_keys, new_keys

JOY1      = $4016
JOY2      = $4017

; turn USE_DAS on to enable autorepeat support
.ifndef USE_DAS
USE_DAS = 0
.endif

; time until autorepeat starts making keypresses
DAS_DELAY = 15
; time between autorepeat keypresses
DAS_SPEED = 3

.segment "CODE"
.proc read_pads
thisRead = 0
firstRead = 2
lastFrameKeys = 4

  ; store the current keypress state to detect key-down later
  lda cur_keys
  sta lastFrameKeys
  lda cur_keys+1
  sta lastFrameKeys+1

  ; Read the joypads twice in case DMC DMA caused a clock glitch.
  jsr read_pads_once
  lda thisRead
  sta firstRead
  lda thisRead+1
  sta firstRead+1
  jsr read_pads_once

  ; For each player, make sure the reads agree, then find newly
  ; pressed keys.
  ldx #1
@fixupKeys:

  ; If the player's keys read out the same way both times, update.
  ; Otherwise, keep the last frame's keypresses.
  lda thisRead,x
  cmp firstRead,x
  bne @dontUpdateGlitch
  sta cur_keys,x
@dontUpdateGlitch:
  
  lda lastFrameKeys,x   ; A = keys that were down last frame
  eor #$FF              ; A = keys that were up last frame
  and cur_keys,x        ; A = keys down now and up last frame
  sta new_keys,x
  dex
  bpl @fixupKeys
  rts

read_pads_once:

  ; Bits from the controllers are shifted into thisRead and
  ; thisRead+1.  In addition, thisRead+1 serves as the loop counter:
  ; once the $01 gets shifted left eight times, the 1 bit will
  ; end up in carry, terminating the loop.
  lda #$01
  sta thisRead+1
  ; Write 1 then 0 to JOY1 to send a latch signal, telling the
  ; controllers to copy button states into a shift register
  sta JOY1
  lsr a
  sta JOY1
  loop:
    ; On NES and AV Famicom, button presses always show up in D0.
    ; On the original Famicom, presses on the hardwired controllers
    ; show up in D0 and presses on plug-in controllers show up in D1.
    ; D2-D7 consist of data from the Zapper, Power Pad, Vs. System
    ; DIP switches, and bus capacitance; ignore them.
    lda JOY1       ; read player 1's controller
    and #%00000011 ; ignore D2-D7
    cmp #1         ; CLC if A=0, SEC if A>=1
    rol thisRead   ; put one bit in the register
    lda JOY2       ; read player 2's controller the same way
    and #$03
    cmp #1
    rol thisRead+1
    bcc loop       ; once $01 has been shifted 8 times, we're done
  rts
.endproc


; Optional autorepeat handling

.if USE_DAS
.export autorepeat
.importzp das_keys, das_timer

;;
; Computes autorepeat (delayed-auto-shift) on the gamepad for one
; player, ORing result into the player's new_keys.
; @param X which player to calculate autorepeat for
.proc autorepeat
  lda cur_keys,x
  beq no_das
  lda new_keys,x
  beq no_restart_das
  sta das_keys,x
  lda #DAS_DELAY
  sta das_timer,x
  bne no_das
no_restart_das:
  dec das_timer,x
  bne no_das
  lda #DAS_SPEED
  sta das_timer,x
  lda das_keys,x
  and cur_keys,x
  ora new_keys,x
  sta new_keys,x
no_das:
  rts
.endproc

.endif
