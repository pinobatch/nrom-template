.include "nes.inc"
.include "global.inc"
.segment "CODE"
.proc draw_bg
  ; Start by clearing the first nametable
  ldx #$20
  lda #$00
  ldy #$AA
  jsr ppu_clear_nt

  ; Draw a floor
  lda #$23
  sta PPUADDR
  lda #$00
  sta PPUADDR
  lda #$0B
  ldx #32
floorloop1:
  sta PPUDATA
  dex
  bne floorloop1
  
  ; Draw areas buried under the floor as solid color
  ; (I learned this style from "Pinobee" for GBA.  We drink Ritalin.)
  lda #$01
  ldx #5*32
floorloop2:
  sta PPUDATA
  dex
  bne floorloop2

  ; Draw blocks on the sides, in vertical columns
  lda #VBLANK_NMI|VRAM_DOWN
  sta PPUCTRL
  
  ; At position (2, 20) (VRAM $2282) and (28, 20) (VRAM $229C),
  ; draw two columns of two blocks each, each block being 4 tiles:
  ; 0C 0D
  ; 0E 0F
  ldx #2

colloop:
  lda #$22
  sta PPUADDR
  txa
  ora #$80
  sta PPUADDR

  ; Draw $0C $0E $0C $0E or $0D $0F $0D $0F depending on column
  and #$01
  ora #$0C
  ldy #4
tileloop:
  sta PPUDATA
  eor #$02
  dey
  bne tileloop

  ; Columns 2, 3, 28, and 29 only  
  inx
  cpx #4  ; Skip columns 4 through 27
  bne not4
  ldx #28
not4:
  cpx #30
  bcc colloop

  ; The attribute table elements corresponding to these stacks are
  ; (0, 5) (VRAM $23E8) and (7, 5) (VRAM $23EF).  Set them to 0.
  ldx #$23
  lda #$E8
  ldy #$00
  stx PPUADDR
  sta PPUADDR
  sty PPUDATA
  lda #$EF
  stx PPUADDR
  sta PPUADDR
  sty PPUDATA

  rts
.endproc

