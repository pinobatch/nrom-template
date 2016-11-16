.include "nes.inc"
.include "global.inc"

.segment "ZEROPAGE"
; Game variables
player_xlo:       .res 1  ; horizontal position is xhi + xlo/256 px
player_xhi:       .res 1
player_dxlo:      .res 1  ; speed in pixels per 256 s
player_yhi:       .res 1
player_facing:    .res 1
player_frame:     .res 1
player_frame_sub: .res 1

; constants used by move_player
; PAL frames are about 20% longer than NTSC frames.  So if you make
; dual NTSC and PAL versions, or you auto-adapt to the TV system,
; you'll want PAL velocity values to be 1.2 times the corresponding
; NTSC values, and PAL accelerations should be 1.44 times NTSC.
WALK_SPD = 105  ; speed limit in 1/256 px/frame
WALK_ACCEL = 4  ; movement acceleration in 1/256 px/frame^2
WALK_BRAKE = 8  ; stopping acceleration in 1/256 px/frame^2

LEFT_WALL = 32
RIGHT_WALL = 224

.segment "CODE"

.proc init_player
  lda #0
  sta player_xlo
  sta player_dxlo
  sta player_facing
  sta player_frame
  lda #48
  sta player_xhi
  lda #192
  sta player_yhi
  rts
.endproc

;;
; Moves the player character in response to controller 1.
.proc move_player

  ; Acceleration to right: Do it only if the player is holding right
  ; on the Control Pad and has a nonnegative velocity.
  lda cur_keys
  and #KEY_RIGHT
  beq notRight
  lda player_dxlo
  bmi notRight
  
    ; Right is pressed.  Add to velocity, but don't allow velocity
    ; to be greater than the maximum.
    clc
    adc #WALK_ACCEL
    cmp #WALK_SPD
    bcc :+
      lda #WALK_SPD
    :
    sta player_dxlo
    lda player_facing  ; Set the facing direction to not flipped 
    and #<~$40         ; turn off bit 6, leave all others on
    sta player_facing
    jmp doneRight
  notRight:

    ; Right is not pressed.  Brake if headed right.
    lda player_dxlo
    bmi doneRight
    cmp #WALK_BRAKE
    bcs notRightStop
    lda #WALK_BRAKE+1  ; add 1 to compensate for the carry being clear
  notRightStop:
    sbc #WALK_BRAKE
    sta player_dxlo
  doneRight:

  ; Acceleration to left: Do it only if the player is holding left
  ; on the Control Pad and has a nonpositive velocity.
  lda cur_keys
  and #KEY_LEFT
  beq notLeft
  lda player_dxlo
  beq isLeft
    bpl notLeft
  isLeft:

    ; Left is pressed.  Add to velocity.
    lda player_dxlo
    sec
    sbc #WALK_ACCEL
    cmp #256-WALK_SPD
    bcs :+
      lda #256-WALK_SPD
    :
    sta player_dxlo
    lda player_facing  ; Set the facing direction to flipped
    ora #$40
    sta player_facing
    jmp doneLeft

    ; Left is not pressed.  Brake if headed left.
  notLeft:
    lda player_dxlo
    bpl doneLeft
    cmp #256-WALK_BRAKE
    bcc notLeftStop
    lda #256-WALK_BRAKE
  notLeftStop:
    adc #8-1
    sta player_dxlo
  doneLeft:

  ; In a real game, you'd respond to A, B, Up, Down, etc. here.

  ; Move the player by adding the velocity to the 16-bit X position.
  lda player_dxlo
  bpl player_dxlo_pos
    ; if velocity is negative, subtract 1 from high byte to sign extend
    dec player_xhi
  player_dxlo_pos:
  clc
  adc player_xlo
  sta player_xlo
  lda #0          ; add high byte
  adc player_xhi
  sta player_xhi

  ; Test for collision with side walls
  cmp #LEFT_WALL-4
  bcs notHitLeft
    lda #LEFT_WALL-4
    sta player_xhi
    lda #0
    sta player_dxlo
    beq doneWallCollision
  notHitLeft:

  cmp #RIGHT_WALL-12
  bcc notHitRight
    lda #RIGHT_WALL-13
    sta player_xhi
    lda #0
    sta player_dxlo
  notHitRight:

  ; Additional checks for collision, if needed, would go here.
doneWallCollision:

  ; Animate the player
  ; If stopped, freeze the animation on frame 0
  lda player_dxlo
  bne notStop1
    lda #$C0
    sta player_frame_sub
    lda #0
    beq have_player_frame
  notStop1:

  ; Take absolute value of velocity (negate it if it's negative)
  bpl player_animate_noneg
    eor #$FF
    clc
    adc #1
  player_animate_noneg:

  lsr a  ; Multiply abs(velocity) by 5/16
  lsr a
  sta 0
  lsr a
  lsr a
  adc 0

  ; And 16-bit add it to player_frame, mod $600  
  adc player_frame_sub
  sta player_frame_sub
  lda player_frame
  adc #0  ; add only the carry

  ; Wrap from $800 (after last frame of walk cycle)
  ; to $100 (first frame of walk cycle)
  cmp #8  ; frame 0: still; 1-7: scooting
  bcc have_player_frame
    lda #1
  have_player_frame:

  sta player_frame
  rts
.endproc


;;
; Draws the player's character to the display list as six sprites.
; In the template, we don't need to handle half-offscreen actors,
; but a scrolling game will need to "clip" sprites (skip drawing the
; parts that are offscreen).
.proc draw_player_sprite
draw_y = 0
cur_tile = 1
x_add = 2         ; +8 when not flipped; -8 when flipped
draw_x = 3
rows_left = 4
row_first_tile = 5
draw_x_left = 7

  lda #3
  sta rows_left
  
  ; In platform games, the Y position is often understood as the
  ; bottom of a character because that makes certain things related
  ; to platform collision easier to reason about.  Here, the
  ; character is 24 pixels tall, and player_yhi is the bottom.
  ; On the NES, sprites are drawn one scanline lower than the Y
  ; coordinate in the OAM entry (e.g. the top row of pixels of a
  ; sprite with Y=8 is on scanline 9).  But in a platformer, it's
  ; also common practice to overlap the bottom row of a sprite's
  ; pixels with the top pixel of the background platform that they
  ; walk on to suggest depth in the background.
  lda player_yhi
  sec
  sbc #24
  sta draw_y

  ; set up increment amounts based on flip value
  ; A: actual X coordinate of first sprite
  ; X: distance to move (either 8 or -8)
  lda player_xhi
  ldx #8
  bit player_facing
  bvc not_flipped
  clc
  adc #8
  ldx #(256-8)
not_flipped:
  sta draw_x_left
  stx x_add

  ; the eight frames start at $10, $12, ..., $1E
  ; 0: still; 1-7: scooting
  lda player_frame
  asl a
  ora #$10
  sta row_first_tile
  
  ; frame 7 is special: the player needs to be drawn 1 unit forward
  ; because of how far he's leaned forward
  lda player_frame
  cmp #7
  bcc not_frame_7
  
  ; here, carry is set, so anything you add will get another 1
  ; added to it, so subtract 1 when constructing the value to add
  ; to the player's X position
  lda #1 - 1  ; facing right: move forward by 1
  bit player_facing
  bvc f7_not_flipped
  lda #<(-1 - 1)  ; facing left: move left by 1
f7_not_flipped:
  adc draw_x_left
  sta draw_x_left
not_frame_7:

  ldx oam_used
rowloop:
  ldy #2              ; Y: remaining width on this row in 8px units
  lda row_first_tile
  sta cur_tile
  lda draw_x_left
  sta draw_x
tileloop:

  ; draw an 8x8 pixel chunk of the character using one entry in the
  ; display list
  lda draw_y
  sta OAM,x
  lda cur_tile
  inc cur_tile
  sta OAM+1,x
  lda player_facing
  sta OAM+2,x
  lda draw_x
  sta OAM+3,x
  clc
  adc x_add
  sta draw_x
  
  ; move to the next entry of the display list
  inx
  inx
  inx
  inx
  dey
  bne tileloop

  ; move to the next row, which is 8 scanlines down and on the next
  ; row of tiles in the pattern table
  lda draw_y
  clc
  adc #8
  sta draw_y
  lda row_first_tile
  clc
  adc #16
  sta row_first_tile
  dec rows_left
  bne rowloop

  stx oam_used
  rts
.endproc

