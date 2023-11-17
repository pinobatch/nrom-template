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
; 2023-11: Damian Yerrick replaced the controller reading routine
;          with a different routine from NESdev Wiki that both
;          performs OAM DMA and reads the controller on advice from
;          Fiskbit that rereading is misleadingly inadequate
; 2023-11: Damian Yerrick added a historical note about rereading
; 2011-07: Damian Yerrick added labels for the local variables and
;          copious comments and made USE_DAS a build-time option

; In 2016, Rahsennor invented a way to synchronize to OAM DMA that
; more reliably avoids read corruption than the rereading technique
; used by many licensed games.
; https://www.nesdev.org/wiki/Controller_reading_code#DPCM_Safety_using_OAM_DMA
; This technique has a couple drawbacks, such as forbidding reading
; the controller on frames when a sample is playing and OAM DMA did
; not occur.  These drawbacks mostly affect advanced methods of
; mitigating lag frames.

.export read_pads, run_dma_and_read_pads
.importzp cur_keys, new_keys
.import OAM

OAM_DMA   = $4014
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
;;
; Starts OAM DMA and then reads all 8 buttons of both controllers.
; Performing OAM DMA first aligns the controller reading routine to
; the APU's get-put cycle to avoid a conflict glitch in which the
; DMC DMA can cause bits to be deleted from the input stream that
; the CPU reads.
.proc run_dma_and_read_pads
  lda #>OAM
  sta OAM_DMA
  .assert * = read_pads, error, "fallthrough expected"
.endproc
.proc read_pads
controller1 = $0000
controller2 = $0001
  ; Bits from the controllers are shifted into controller1 and
  ; controller2.  In addition, controller1 serves as the loop counter:
  ; once the $01 gets shifted left eight times, the 1 bit will
  ; end up in carry, terminating the loop.
  ;
  ; NES, FamicomBox, and AV Famicom report all button presses in D0.
  ; The original Famicom and Twin Famicom report presses on the
  ; hardwired controllers in D0 and presses on plug-in controllers
  ; in D1.  D2-D7 consist of data from other peripherals (such as
  ; the Zapper and Power Pad) and bus capacitance.
  ; The AND #$03 CMP #1 idiom sets the carry flag if D0 or D1
  ; or both are true and disregards D2-D7.

  ldx #1             ; get put          <- strobe code must take an odd number of cycles total
  stx controller1    ; get put get      <- controller1 and controller2 must be in the zeropage
  stx $4016          ; put get put get
  dex                ; put get
  stx $4016          ; put get put get
@read_loop:
  lda $4017          ; put get put GET  <- loop code must take an even number of cycles total
  and #%00000011     ; put get
  cmp #1             ; put get
  rol controller2, x ; put get put get put get (X = 0; waste 1 cycle and 0 bytes for alignment)
  lda $4016          ; put get put GET
  and #%00000011     ; put get
  cmp #1             ; put get
  rol controller1    ; put get put get put
  bcc @read_loop     ; get put [get]    <- this branch must not be allowed to cross a page
  .assert >* = >@read_loop, error, "read_pads: read_loop crosses a page boundary"
  
  ; For each player, find newly pressed keys.
  inx
@calcNewKeys:
  lda cur_keys,x
  eor #$FF
  and controller1,x
  sta new_keys,x
  lda controller1,x
  sta cur_keys,x
  beq :+
    sta $4444
  :
  dex
  bpl @calcNewKeys
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
