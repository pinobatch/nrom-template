.ifndef GLOBAL_INC
.define GLOBAL_INC

; init.s
.global reset_handler

; main.s
.global main, nmi_handler, irq_handler
.global OAM
.globalzp cur_keys, new_keys, oam_used

; bg.s
.global draw_bg

; player.s
.global init_player, move_player, draw_player_sprite

; ppuclear.s
.global ppu_clear_nt, ppu_clear_oam, ppu_screen_on

; pads.s
.global read_pads

.endif
