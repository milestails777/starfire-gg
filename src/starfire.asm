; SAMIRIUS ARENA — top-down tactical shooter for Sega Game Gear
; Assembles to a 32KB .gg ROM (export region).

VDP_DATA  equ $be
VDP_CTRL  equ $bf
PSG_PORT  equ $7f
JOY_PORT  equ $dc
START_PORT equ $00

TILE_PLAYER equ 64
TILE_ENEMY  equ 68
TILE_BULLET equ 72
TILE_FLOOR  equ 37
TILE_COVER  equ 38

MAX_BULLETS equ 3
MAX_ENEMIES equ 3

vblank_flag equ $c000
joy         equ $c001
startb      equ $c002
state       equ $c003
player_x    equ $c004
player_y    equ $c005
fire_cd     equ $c006
lives       equ $c007
score_lo    equ $c008
score_hi    equ $c009
invuln      equ $c00c
sfx_timer   equ $c00d
frame       equ $c00e
spr_count   equ $c00f
tmp0        equ $c010
tmp1        equ $c011
tmp2        equ $c012
tmp3        equ $c013
ebul_x      equ $c014
ebul_y      equ $c015
een_x       equ $c016
een_y       equ $c017
splash_timer equ $c018
splash_note equ $c019
music_timer equ $c01a
music_index equ $c01b
facing      equ $c01c
enemy_count equ $c01d

bullets     equ $c020
enemies     equ $c030
sat_y       equ $c080
sat_xt      equ $c090

    .org $0000
    di
    im 1
    ld sp, $dff0
    jp init

    .org $0038
    push af
    in a, (VDP_CTRL)
    ld a, 1
    ld (vblank_flag), a
    pop af
    ei
    reti

    .org $0066
    retn

    .org $0100
init:
    di
    ld a, $9f
    out (PSG_PORT), a
    ld a, $bf
    out (PSG_PORT), a
    ld a, $df
    out (PSG_PORT), a
    ld a, $ff
    out (PSG_PORT), a

    xor a
    ld (sfx_timer), a
    call wait_vblank_poll
    call wait_vblank_poll
    call load_vdp_regs
    call clear_vram
    call load_tiles
    call load_palette

    xor a
    ld (vblank_flag), a
    call setup_splash
    call vdp_display_on
    ei

main_loop:
    halt
    ld a, (vblank_flag)
    or a
    jr z, main_loop
    xor a
    ld (vblank_flag), a
    ld a, (frame)
    inc a
    ld (frame), a
    call read_input
    call tick_sfx
    ld a, (state)
    cp 3
    jr nz, main_not_splash
    call update_splash
    call hide_all_sprites
    call upload_sat
    jr main_loop
main_not_splash:
    ld a, (state)
    cp 1
    jr z, main_play
    cp 2
    jr z, main_over
    cp 4
    jr z, main_over
    call tick_title_music
    call update_title
    call hide_all_sprites
    call upload_sat
    jr main_loop
main_play:
    call update_play
    call draw_sprites
    call upload_sat
    jr main_loop
main_over:
    call update_over
    call hide_all_sprites
    call upload_sat
    jr main_loop

wait_vblank_poll:
    ld bc, 0
wvp_wait:
    in a, (VDP_CTRL)
    and $80
    ret nz
    dec bc
    ld a, b
    or c
    jr nz, wvp_wait
    ret

load_vdp_regs:
    ld hl, vdp_regs
    ld b, 11
lvr_loop:
    ld a, (hl)
    out (VDP_CTRL), a
    inc hl
    ld a, (hl)
    out (VDP_CTRL), a
    inc hl
    djnz lvr_loop
    ret

vdp_display_on:
    ld a, $e2
    out (VDP_CTRL), a
    ld a, $81
    out (VDP_CTRL), a
    ret

vdp_display_off:
    ld a, $a2
    out (VDP_CTRL), a
    ld a, $81
    out (VDP_CTRL), a
    ret

set_vram_write:
    ld a, l
    out (VDP_CTRL), a
    ld a, h
    or $40
    out (VDP_CTRL), a
    ret

clear_vram:
    ld hl, $0000
    call set_vram_write
    ld de, 16384
cvr_loop:
    xor a
    out (VDP_DATA), a
    dec de
    ld a, d
    or e
    jr nz, cvr_loop
    ret

load_tiles:
    ld hl, $0000
    call set_vram_write
    ld hl, tiles
    ld c, VDP_DATA
    ld a, 10
lt_outer:
    ld b, 0
    otir
    dec a
    jr nz, lt_outer
    ret

load_palette:
    xor a
    out (VDP_CTRL), a
    ld a, $c0
    out (VDP_CTRL), a
    ld hl, palette
    ld b, 64
    ld c, VDP_DATA
    otir
    ret

read_input:
    in a, (JOY_PORT)
    cpl
    and $3f
    ld (joy), a
    in a, (START_PORT)
    cpl
    and $80
    ld (startb), a
    ret

char_to_tile:
    cp " "
    jr z, ctt_space
    cp "0"
    jr c, ctt_space
    cp $3a
    jr c, ctt_digit
    cp "A"
    jr c, ctt_space
    cp $5b
    jr nc, ctt_space
    sub "A"
    add a, 11
    ret
ctt_digit:
    sub "0"
    inc a
    ret
ctt_space:
    xor a
    ret

; B=col C=row DE=string
print_at:
    push de
    ld h, 0
    ld l, c
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld d, 0
    ld e, b
    add hl, de
    add hl, hl
    ld de, $3800
    add hl, de
    call set_vram_write
    pop de
pat_loop:
    ld a, (de)
    or a
    ret z
    call char_to_tile
    out (VDP_DATA), a
    xor a
    out (VDP_DATA), a
    inc de
    jr pat_loop

fill_nametable:
    ld hl, $3800
    call set_vram_write
    ld de, 896
fnt_loop:
    xor a
    out (VDP_DATA), a
    out (VDP_DATA), a
    dec de
    ld a, d
    or e
    jr nz, fnt_loop
    ret

draw_arena_floor:
    ld hl, $3800
    ld de, 64
    ld b, 18
daf_row:
    push bc
    call set_vram_write
    ld c, 20
daf_col:
    ld a, TILE_FLOOR
    out (VDP_DATA), a
    xor a
    out (VDP_DATA), a
    dec c
    jr nz, daf_col
    pop bc
    add hl, de
    djnz daf_row
    ret

draw_arena:
    call draw_arena_floor
    ld hl, arena_table
ps_loop:
    ld a, (hl)
    cp $ff
    ret z
    ld b, a
    inc hl
    ld c, (hl)
    inc hl
    ld a, (hl)
    inc hl
    push hl
    ld (tmp0), a
    ld h, 0
    ld l, c
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld d, 0
    ld e, b
    add hl, de
    add hl, hl
    ld de, $3800
    add hl, de
    call set_vram_write
    ld a, (tmp0)
    out (VDP_DATA), a
    xor a
    out (VDP_DATA), a
    pop hl
    jr ps_loop

setup_title:
    xor a
    ld (state), a
    ld a, $ff
    ld (music_index), a
    ld a, 1
    ld (music_timer), a
    call vdp_display_off
    call fill_nametable
    call draw_arena
    ld b, 3
    ld c, 6
    ld de, str_title
    call print_at
    ld b, 3
    ld c, 9
    ld de, str_move
    call print_at
    ld b, 5
    ld c, 12
    ld de, str_btn
    call print_at
    ld b, 4
    ld c, 15
    ld de, str_press
    call print_at
    call vdp_display_on
    ret

setup_splash:
    ld a, 3
    ld (state), a
    call vdp_display_off
    call fill_nametable
    call draw_arena
    ld b, 6
    ld c, 8
    ld de, str_splash_name
    call print_at
    ld b, 5
    ld c, 10
    ld de, str_splash_prod
    call print_at
    ld b, 6
    ld c, 14
    ld de, str_splash_presents
    call print_at
    xor a
    ld (splash_note), a
    call play_splash_note
    call vdp_display_on
    ret

update_splash:
    ld a, (splash_timer)
    dec a
    ld (splash_timer), a
    ret nz
    ld a, (splash_note)
    inc a
    cp 5
    jp nc, setup_title
    ld (splash_note), a
    call play_splash_note
    ret

play_splash_note:
    ld a, (splash_note)
    add a, a
    ld e, a
    ld d, 0
    ld hl, splash_periods
    add hl, de
    ld a, (hl)
    and $0f
    or $80
    out (PSG_PORT), a
    inc hl
    ld a, (hl)
    and $3f
    out (PSG_PORT), a
    ld a, $95
    out (PSG_PORT), a
    ld a, 16
    ld (splash_timer), a
    ret

setup_play:
    ld a, 1
    ld (state), a
    ld a, $bf
    out (PSG_PORT), a
    ld a, 3
    ld (lives), a
    xor a
    ld (score_lo), a
    ld (score_hi), a
    ld (fire_cd), a
    ld (invuln), a
    ld a, 72
    ld (player_x), a
    ld a, 72
    ld (player_y), a
    ld a, 3
    ld (enemy_count), a
    ld a, 0
    ld (facing), a
    call clear_actors
    ld hl, initial_enemies
    ld de, enemies
    ld bc, 12
    ldir
    call vdp_display_off
    call fill_nametable
    call draw_arena
    call draw_hud
    call vdp_display_on
    ret

setup_over:
    ld a, 2
    ld (state), a
    call vdp_display_off
    call fill_nametable
    call draw_arena
    ld b, 5
    ld c, 9
    ld de, str_over
    call print_at
    ld b, 8
    ld c, 12
    ld de, str_score
    call print_at
    call print_score_at
    ld b, 7
    ld c, 16
    ld de, str_retry
    call print_at
    call vdp_display_on
    ret

setup_clear:
    ld a, 4
    ld (state), a
    call vdp_display_off
    call fill_nametable
    call draw_arena
    ld b, 5
    ld c, 9
    ld de, str_clear
    call print_at
    call vdp_display_on
    ret

draw_hud:
    ld b, 1
    ld c, 1
    ld de, str_score
    call print_at
    call print_score_at
    ld b, 15
    ld c, 1
    ld de, str_lives
    call print_at
    call print_lives_at
    ret

print_score_at:
    ld b, 7
    ld c, 1
    ld a, (state)
    cp 2
    jr nz, psa_play
    ld b, 14
    ld c, 12
psa_play:
    ld h, 0
    ld l, c
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld d, 0
    ld e, b
    add hl, de
    add hl, hl
    ld de, $3800
    add hl, de
    call set_vram_write
    ld a, (score_hi)
    call emit_bcd_pair
    ld a, (score_lo)
    call emit_bcd_pair
    ret

emit_bcd_pair:
    ld b, a
    rrca
    rrca
    rrca
    rrca
    and $0f
    inc a
    out (VDP_DATA), a
    xor a
    out (VDP_DATA), a
    ld a, b
    and $0f
    inc a
    out (VDP_DATA), a
    xor a
    out (VDP_DATA), a
    ret

print_lives_at:
    ld b, 18
    ld c, 1
    ld h, 0
    ld l, c
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld d, 0
    ld e, b
    add hl, de
    add hl, hl
    ld de, $3800
    add hl, de
    call set_vram_write
    ld a, (lives)
    and $0f
    inc a
    out (VDP_DATA), a
    xor a
    out (VDP_DATA), a
    ret

clear_actors:
    ld hl, bullets
    ld b, 12
ca_b:
    ld (hl), 0
    inc hl
    djnz ca_b
    ld hl, enemies
    ld b, 12
ca_e:
    ld (hl), 0
    inc hl
    djnz ca_e
    ret

update_title:
    ld a, (joy)
    and $10
    jr nz, update_title_go
    ld a, (startb)
    or a
    ret z
update_title_go:
    jp setup_play

update_over:
    ld a, (joy)
    and $10
    jr nz, update_over_go
    ld a, (startb)
    or a
    ret z
update_over_go:
    jp setup_title

update_play:
    call move_player
    call fire_player
    call move_bullets
    call move_enemies
    call collide_all
    ld a, (enemy_count)
    or a
    jp z, setup_clear
    ld a, (invuln)
    or a
    jr z, up_noinv
    dec a
    ld (invuln), a
up_noinv:
    ld a, (fire_cd)
    or a
    jr z, up_ncd
    dec a
    ld (fire_cd), a
up_ncd:
    ld a, (lives)
    or a
    ret nz
    jp setup_over

move_player:
    ld a, (joy)
    ld b, a
    bit 2, b
    jr z, mp_right
    ld a, 2
    ld (facing), a
    ld a, (player_x)
    cp 10
    jr c, mp_right
    sub 2
    ld (tmp0), a
    ld a, (player_y)
    ld (tmp1), a
    call check_cover_collision
    or a
    jr nz, mp_right
    ld a, (tmp0)
    ld (player_x), a
mp_right:
    bit 3, b
    jr z, mp_up
    ld a, 3
    ld (facing), a
    ld a, (player_x)
    cp 134
    jr nc, mp_up
    add a, 2
    ld (tmp0), a
    ld a, (player_y)
    ld (tmp1), a
    call check_cover_collision
    or a
    jr nz, mp_up
    ld a, (tmp0)
    ld (player_x), a
mp_up:
    bit 0, b
    jr z, mp_down
    ld a, 0
    ld (facing), a
    ld a, (player_y)
    cp 26
    jr c, mp_down
    sub 2
    ld (tmp1), a
    ld a, (player_x)
    ld (tmp0), a
    call check_cover_collision
    or a
    jr nz, mp_down
    ld a, (tmp1)
    ld (player_y), a
mp_down:
    bit 1, b
    jr z, mp_done
    ld a, 1
    ld (facing), a
    ld a, (player_y)
    cp 110
    jr nc, mp_done
    add a, 2
    ld (tmp1), a
    ld a, (player_x)
    ld (tmp0), a
    call check_cover_collision
    or a
    jr nz, mp_done
    ld a, (tmp1)
    ld (player_y), a
mp_done:
    ret

check_cover_collision:
    push bc
    push de
    push hl
    ld hl, cover_pixels
    ld b, 3
cc_loop:
    ld a, (hl)
    ld d, a
    add a, 16
    ld e, a
    ld a, (tmp0)
    cp e
    jr nc, cc_next
    ld a, (tmp0)
    add a, 16
    cp d
    jr c, cc_next
    jr z, cc_next
    push hl
    inc hl
    ld a, (hl)
    ld d, a
    add a, 16
    ld e, a
    ld a, (tmp1)
    cp e
    jr nc, cc_y_clear
    ld a, (tmp1)
    add a, 16
    cp d
    jr c, cc_y_clear
    jr z, cc_y_clear
    pop hl
    ld a, 1
    jr cc_done
cc_y_clear:
    pop hl
cc_next:
    inc hl
    inc hl
    djnz cc_loop
    xor a
cc_done:
    pop hl
    pop de
    pop bc
    ret

fire_player:
    ld a, (fire_cd)
    or a
    ret nz
    ld a, (joy)
    bit 4, a
    jr nz, fp_find_start
    bit 5, a
    ret z
fp_find_start:
    ld hl, bullets
    ld b, MAX_BULLETS
fp_find:
    push hl
    inc hl
    inc hl
    ld a, (hl)
    pop hl
    or a
    jr z, fp_use
    inc hl
    inc hl
    inc hl
    inc hl
    djnz fp_find
    ret
fp_use:
    ld a, (player_x)
    add a, 4
    ld (hl), a
    inc hl
    ld a, (player_y)
    add a, 4
    ld (hl), a
    inc hl
    ld (hl), 1
    inc hl
    ld a, (facing)
    ld (hl), a
    ld a, 8
    ld (fire_cd), a
    jp sfx_shot

move_bullets:
    ld hl, bullets
    ld b, MAX_BULLETS
mb_loop:
    push bc
    push hl
    inc hl
    inc hl
    ld a, (hl)
    pop hl
    ld d, h
    ld e, l
    or a
    jr z, mb_next
    inc hl
    inc hl
    inc hl
    ld a, (hl)
    ld (tmp3), a
    or a
    jr nz, mb_not_up
    dec hl
    ld a, (hl)
    sub 4
    ld (hl), a
    cp 24
    jr nc, mb_check_cover
    jr mb_kill
mb_not_up:
    cp 1
    jr nz, mb_not_down
    dec hl
    ld a, (hl)
    add a, 4
    ld (hl), a
    cp 128
    jr c, mb_check_cover
    jr mb_kill
mb_not_down:
    cp 2
    jr nz, mb_right
    dec hl
    dec hl
    ld a, (hl)
    sub 4
    ld (hl), a
    cp 8
    jr nc, mb_check_cover
    jr mb_kill
mb_right:
    dec hl
    dec hl
    ld a, (hl)
    add a, 4
    ld (hl), a
    cp 152
    jr c, mb_check_cover
mb_check_cover:
    ld h, d
    ld l, e
    ld a, (hl)
    ld (tmp0), a
    inc hl
    ld a, (hl)
    ld (tmp1), a
    call check_cover_collision
    or a
    jr nz, mb_kill
    jr mb_next
mb_kill:
    ld a, (tmp3)
    cp 2
    jr c, mb_kill_vertical
    inc hl
    inc hl
    jr mb_mark_inactive
mb_kill_vertical:
    inc hl
mb_mark_inactive:
    ld (hl), 0
mb_next:
    ld h, d
    ld l, e
    inc hl
    inc hl
    inc hl
    inc hl
    pop bc
    djnz mb_loop
    ret

rand:
move_enemies:
    ld hl, enemies
    ld b, MAX_ENEMIES
me_loop:
    push bc
    push hl
    inc hl
    inc hl
    ld a, (hl)
    pop hl
    or a
    jr z, me_skip
    ld a, (hl)
    ld (tmp2), a
    ld a, (player_x)
    cp (hl)
    jr z, me_y
    jr c, me_left
    inc (hl)
    jr me_test_x
me_left:
    dec (hl)
me_test_x:
    ld a, (hl)
    ld (tmp0), a
    inc hl
    ld a, (hl)
    ld (tmp1), a
    dec hl
    call check_cover_collision
    or a
    jr z, me_y
    ld a, (tmp2)
    ld (hl), a
me_y:
    inc hl
    ld a, (hl)
    ld (tmp2), a
    ld a, (player_y)
    cp (hl)
    jr z, me_next
    jr c, me_up
    inc (hl)
    jr me_test_y
me_up:
    dec (hl)
me_test_y:
    ld a, (hl)
    ld (tmp1), a
    dec hl
    ld a, (hl)
    ld (tmp0), a
    inc hl
    call check_cover_collision
    or a
    jr z, me_next
    ld a, (tmp2)
    ld (hl), a
me_next:
    inc hl
    inc hl
    inc hl
    jr me_advance
me_skip:
    inc hl
    inc hl
    inc hl
    inc hl
me_advance:
    pop bc
    djnz me_loop
    ret

hit_player_life:
    ld a, (invuln)
    or a
    ret nz
    ld a, (lives)
    or a
    ret z
    dec a
    ld (lives), a
    ld a, 50
    ld (invuln), a
    call sfx_hit
    call print_lives_at
    ret

collide_all:
    ld hl, bullets
    ld b, MAX_BULLETS
col_b:
    push bc
    push hl
    inc hl
    inc hl
    ld a, (hl)
    pop hl
    or a
    jr z, col_bn
    ld a, (hl)
    ld (ebul_x), a
    inc hl
    ld a, (hl)
    ld (ebul_y), a
    dec hl
    push hl
    ld de, enemies
    ld a, MAX_ENEMIES
    ld (tmp3), a
col_e:
    push de
    inc de
    inc de
    ld a, (de)
    pop de
    or a
    jr z, col_en
    ld a, (de)
    ld (een_x), a
    inc de
    ld a, (de)
    ld (een_y), a
    dec de
    call boxes_hit
    or a
    jr z, col_en
    inc de
    inc de
    xor a
    ld (de), a
    ld a, (enemy_count)
    dec a
    ld (enemy_count), a
    pop hl
    inc hl
    inc hl
    ld (hl), 0
    dec hl
    dec hl
    push hl
    call add_score
    call sfx_kill
    pop hl
    jp col_bn
col_en:
    inc de
    inc de
    inc de
    inc de
    ld a, (tmp3)
    dec a
    ld (tmp3), a
    jr nz, col_e
    pop hl
col_bn:
    inc hl
    inc hl
    inc hl
    inc hl
    pop bc
    djnz col_b

    ld a, (invuln)
    or a
    ret nz
    ld a, (player_x)
    ld (ebul_x), a
    ld a, (player_y)
    ld (ebul_y), a
    ld de, enemies
    ld b, MAX_ENEMIES
col_p:
    push bc
    push de
    inc de
    inc de
    ld a, (de)
    pop de
    or a
    jr z, col_pn
    ld a, (de)
    ld (een_x), a
    inc de
    ld a, (de)
    ld (een_y), a
    dec de
    call boxes_hit_player
    or a
    jr z, col_pn
    push de
    call hit_player_life
    pop de
col_pn:
    inc de
    inc de
    inc de
    inc de
    pop bc
    djnz col_p
    ret
boxes_hit:
    push hl
    ld a, (een_x)
    add a, 14
    ld hl, tmp2
    ld (hl), a
    ld a, (ebul_x)
    cp (hl)
    jr nc, bh_no
    ld a, (ebul_x)
    add a, 6
    ld (hl), a
    ld a, (een_x)
    cp (hl)
    jr nc, bh_no
    ld a, (een_y)
    add a, 14
    ld (hl), a
    ld a, (ebul_y)
    cp (hl)
    jr nc, bh_no
    ld a, (ebul_y)
    add a, 8
    ld (hl), a
    ld a, (een_y)
    cp (hl)
    jr nc, bh_no
    pop hl
    ld a, 1
    ret
bh_no:
    pop hl
    xor a
    ret

boxes_hit_player:
    push hl
    ld a, (een_x)
    add a, 14
    ld hl, tmp2
    ld (hl), a
    ld a, (ebul_x)
    cp (hl)
    jr nc, bhp_no
    ld a, (ebul_x)
    add a, 14
    ld (hl), a
    ld a, (een_x)
    cp (hl)
    jr nc, bhp_no
    ld a, (een_y)
    add a, 14
    ld (hl), a
    ld a, (ebul_y)
    cp (hl)
    jr nc, bhp_no
    ld a, (ebul_y)
    add a, 14
    ld (hl), a
    ld a, (een_y)
    cp (hl)
    jr nc, bhp_no
    pop hl
    ld a, 1
    ret
bhp_no:
    pop hl
    xor a
    ret

add_score:
    ld a, (score_lo)
    add a, $10
    daa
    ld (score_lo), a
    ld a, (score_hi)
    adc a, 0
    daa
    ld (score_hi), a
    call print_score_at
    ret

hide_all_sprites:
    xor a
    ld (spr_count), a
    ret

draw_sprites:
    xor a
    ld (spr_count), a
    ld a, (invuln)
    or a
    jr z, ds_pl
    ld a, (frame)
    and 2
    jr z, ds_bul
ds_pl:
    ld a, (player_y)
    dec a
    ld b, a
    ld a, (player_x)
    ld c, a
    ld d, TILE_PLAYER
    call add_sprite
    ld a, (player_x)
    add a, 8
    ld c, a
    ld d, TILE_PLAYER+2
    call add_sprite
ds_bul:
    ld hl, bullets
    ld b, MAX_BULLETS
dsb_loop:
    push bc
    push hl
    inc hl
    inc hl
    ld a, (hl)
    pop hl
    or a
    jr z, dsb_n
    ld a, (hl)
    ld c, a
    inc hl
    ld a, (hl)
    dec a
    ld b, a
    dec hl
    ld d, TILE_BULLET
    call add_sprite
dsb_n:
    inc hl
    inc hl
    inc hl
    inc hl
    pop bc
    djnz dsb_loop

    ld hl, enemies
    ld b, MAX_ENEMIES
dse_loop:
    push bc
    push hl
    inc hl
    inc hl
    ld a, (hl)
    pop hl
    or a
    jr z, dse_n
    ld a, (hl)
    ld c, a
    inc hl
    ld a, (hl)
    dec a
    ld b, a
    dec hl
    ld d, TILE_ENEMY
    call add_sprite
    ld a, c
    add a, 8
    ld c, a
    ld d, TILE_ENEMY+2
    call add_sprite
dse_n:
    inc hl
    inc hl
    inc hl
    inc hl
    pop bc
    djnz dse_loop
    ret

; B=y C=x D=tile
add_sprite:
    ld a, (spr_count)
    cp 16
    ret nc
    push hl
    ld hl, sat_y
    add a, l
    ld l, a
    jr nc, as_1
    inc h
as_1:
    ld a, b
    ld (hl), a
    ld a, (spr_count)
    add a, a
    ld hl, sat_xt
    add a, l
    ld l, a
    jr nc, as_2
    inc h
as_2:
    ld a, c
    ld (hl), a
    inc hl
    ld a, d
    ld (hl), a
    ld a, (spr_count)
    inc a
    ld (spr_count), a
    pop hl
    ret

upload_sat:
    ld hl, $3f00
    call set_vram_write
    ld a, (spr_count)
    or a
    jr z, us_term
    ld b, a
    ld hl, sat_y
us_y:
    ld a, (hl)
    out (VDP_DATA), a
    inc hl
    djnz us_y
us_term:
    ld a, $d0
    out (VDP_DATA), a
    ld hl, $3f80
    call set_vram_write
    ld a, (spr_count)
    or a
    ret z
    ld b, a
    ld hl, sat_xt
us_x:
    ld a, (hl)
    out (VDP_DATA), a
    inc hl
    ld a, (hl)
    out (VDP_DATA), a
    inc hl
    djnz us_x
    ret

sfx_shot:
    ld a, $84
    out (PSG_PORT), a
    ld a, $00
    out (PSG_PORT), a
    ld a, $90
    out (PSG_PORT), a
    ld a, 6
    ld (sfx_timer), a
    ret

sfx_kill:
    ld a, $8c
    out (PSG_PORT), a
    ld a, $03
    out (PSG_PORT), a
    ld a, $92
    out (PSG_PORT), a
    ld a, 10
    ld (sfx_timer), a
    ret

sfx_hit:
    ld a, $8f
    out (PSG_PORT), a
    ld a, $3f
    out (PSG_PORT), a
    ld a, $91
    out (PSG_PORT), a
    ld a, $e4
    out (PSG_PORT), a
    ld a, 12
    ld (sfx_timer), a
    ret

tick_sfx:
    ld a, (sfx_timer)
    or a
    ret z
    dec a
    ld (sfx_timer), a
    ret nz
    ld a, $9f
    out (PSG_PORT), a
    ld a, $ff
    out (PSG_PORT), a
    ret

tick_title_music:
    ld a, (music_timer)
    or a
    jr z, title_music_advance
    dec a
    ld (music_timer), a
    ret nz
title_music_advance:
    ld a, (music_index)
    inc a
    cp 16
    jr c, title_music_index_ok
    xor a
title_music_index_ok:
    ld (music_index), a
    add a, a
    ld e, a
    ld d, 0
    ld hl, title_music_notes
    add hl, de
    ld a, (hl)
    and $0f
    or $a0
    out (PSG_PORT), a
    inc hl
    ld a, (hl)
    and $3f
    out (PSG_PORT), a
    ld a, $b2
    out (PSG_PORT), a
    ld a, 8
    ld (music_timer), a
    ret

vdp_regs:
    .db $06, $80
    .db $a2, $81
    .db $ff, $82
    .db $ff, $83
    .db $ff, $84
    .db $ff, $85
    .db $fb, $86
    .db $00, $87
    .db $00, $88
    .db $00, $89
    .db $ff, $8a

arena_table:
    .db 6, 6, TILE_COVER, 7, 6, TILE_COVER
    .db 6, 7, TILE_COVER, 7, 7, TILE_COVER
    .db 13, 9, TILE_COVER, 14, 9, TILE_COVER
    .db 13, 10, TILE_COVER, 14, 10, TILE_COVER
    .db 4, 11, TILE_COVER, 5, 11, TILE_COVER
    .db 4, 12, TILE_COVER, 5, 12, TILE_COVER
    .db $ff

cover_pixels:
    .db 48, 48, 104, 72, 32, 88

str_title:
    .db "SAMIRIUS ARENA", 0
str_press:
    .db "PRESS START", 0
str_move:
    .db "D-PAD: MOVE/AIM", 0
str_btn:
    .db "B1/B2: FIRE", 0
str_over:
    .db "ROUND LOST", 0
str_score:
    .db "SCORE", 0
str_lives:
    .db "HP", 0
str_retry:
    .db "PRESS START", 0
str_clear:
    .db "ROUND CLEAR", 0
str_splash_name:
    .db "SAMIRIUS", 0
str_splash_prod:
    .db "PRODUCTION", 0
str_splash_presents:
    .db "PRESENTS", 0

splash_periods:
    .dw 225, 356, 123, 126, 168, 323, 43423, 5353, 323, 233, 253, 633, 345, 232, 542, 432, 424

initial_enemies:
    .db 24, 32, 1, 1
    .db 120, 32, 1, 1
    .db 72, 104, 1, 1

title_music_notes:
    .dw 555, 444, 333, 333, 222, 222, 111, 111, 243, 553, 332, 435, 342, 242, 234, 453, 532, 422, 231, 231, 323, 231
    .dw 555, 444, 333, 333, 222, 222, 111, 111,
    
    

tiles:
    .incbin "../assets/tiles.bin"
palette:
    .incbin "../assets/palette.bin"

    .org $7ff0
    .db "TMR SEGA"
    .db 0, 0
    .dw 0
    .db $01, $70, $09, $4c
