.psp

icon_size           equ 24
icon_stride         equ 25            ; icon_size + 1px spacing
icon_x              equ 3
icon_y              equ 244

.include "gpu_macros.asm"

.macro lih,dest,value
	lui			at, value / 0x10000
	lh			dest, value & 0xFFFF(at)
.endmacro

.macro lib,dest,value
	lui			at, value / 0x10000
	lb			dest, value & 0xFFFF(at)
.endmacro

.macro sih,orig,value
	lui			at, value / 0x10000
	sh			orig, value & 0xFFFF(at)
.endmacro

.macro sib,orig,value
	lui			at, value / 0x10000
	sb			orig, value & 0xFFFF(at)
.endmacro

.createfile "../bin/adds.bin", 0x0
    .word   LOAD_ADD
    .word   HOOK
    .word   main
    .word   render
    .word   RENDER_HOOK
    .word   CURRENT_TASK
    .word   early_main
    .word   EARLY_HOOK
.close

.createfile "../bin/target_cam.bin", LOAD_ADD

enabled:
    .byte   0              ; +0 (CWCheat: 0x001E0400)
selected_monster:
    .byte   0              ; +1 (CWCheat: 0x001E0401)
.align 4


.func main
    lw      v0, 0x74(s5)
    lbu     a2, 0x8F(s1)

    ; Save player entity pointer (a0 = player entity at hook point)
    ; Pointer stays valid for the entire quest
    lui     t0, 0x0880
    sltu    at, a0, t0
    bnez    at, @@skip_save
    nop
    lui     t0, 0x0A00
    sltu    at, a0, t0
    beqz    at, @@skip_save
    nop
    li      t1, PLAYER_ENTITY_ADDR
    sw      a0, 0(t1)
@@skip_save:

    lib     t0, enabled
    bne     t0, zero, find_angle
    nop

return:
    li      a1, 0
    li      a2, 0
    j       HOOK+8
    li      a3, 0
.endfunc

.func find_angle
    addiu   sp, sp, -0x4
    sw      ra, 0x0(sp)

    ; Try selected monster first
    li      a1, SELECTED_MON_ADDR
    lb      a1, 0(a1)
    li      a2, MONSTER_POINTER
    addu    a1, a1, a2
    lw      a1, 0x0(a1)
    beq     a1, zero, @@scan
    nop
    lh      t0, 0x246(a1)
    bgtz    t0, @@try_lock          ; alive, try to lock
    nop

@@scan:
    ; Selected monster dead/null — find first alive large monster
    li      t1, 0                   ; slot offset (0, 4, 8)
@@scan_loop:
    li      a2, MONSTER_POINTER
    addu    a2, a2, t1
    lw      a1, 0(a2)
    beq     a1, zero, @@scan_next
    nop
    lh      t0, 0x246(a1)
    bgtz    t0, @@try_lock          ; found alive monster
    nop
@@scan_next:
    addiu   t1, t1, 4
    slti    at, t1, 12
    bnez    at, @@scan_loop
    nop
    j       @@ret                   ; no alive monsters found
    nop

@@try_lock:
    ; a1 = alive monster entity
    jal     monster_in_area
    nop
    beq     t0, zero, @@ret
    nop
    jal     get_angle
    nop

@@ret:
    lw      ra, 0x0(sp)
    j       return
    addiu   sp, sp, 0x4
.endfunc

.func get_angle
    lv.s    s000, 0x80(a0)
    lv.s    s001, 0x88(a0)
    lv.s    s002, 0x80(a1)
    lv.s    s003, 0x88(a1)

    vsub.p  c000, c002, c000
    vmul.p  c002, c000, c000
    vfad.p  r020, c002
    vsqrt.s s003, s003
    vdiv.s  s003, s000, s003
    vasin.s s003, s003

    vsgn.s  s001, s001
	vmul.s  s003, s003, s001

    vzero.s s002
    vsge.s  s000, s001, s002

    lui     a1, 0x4000
    mtv     a1, s002
    vadd.s  s003, s003, s002

    vmul.s  s002, s000, s002
    vadd.s  s003, s003, s002

    li      a1, 0x467fff00
    mtv     a1, s002
    vmul.s  s000, s002, s003

    vf2in.s s000, s000, 0
    mfv     a1, s000

    slti    at, a1, 0x0
    beq     at, zero, no_flip
    li      a2, 0xffff
    addu    a1, a1, a2

no_flip:
    andi    v0, a1, 0xFFFF
    jr      ra
    nop
.endfunc

.func monster_in_area
    lb      t0, 0xD6(a0)
    lb      t1, 0xD6(a1)
    xor     t0, t0, t1
    jr      ra
    slti    t0, t0, 0x1
.endfunc

; Large monster bitmap (duplicate for early hook cycling)
.align 4
cycle_large_bitmap:
    .word 0x81CEE9FF  ; IDs 1-32
    .word 0x3FFC7F80  ; IDs 33-64

; Early hook — runs unconditionally every frame
; Replaces: sw s1, 0xB4(sp) / swc1 f22, 0xE8(sp)
.func early_main
    sw      s1, 0xB4(sp)
    swc1    f22, 0xE8(sp)

    ; Install render hook if overlay loaded
    li      t0, CURRENT_TASK
    lhu     t0, 0(t0)
    li      t1, 0x6167
    bne     t0, t1, @@skip
    nop
    li      t0, RENDER_HOOK
    li      t1, 0x08000000 | (render >> 2)
    sw      t1, 0(t0)
    sw      zero, 4(t0)
    ; === Button handling (MHFU-style with trigger debounce) ===
    ; Read buttons
    lw      t0, 0x7A7C(s0)         ; controller state pointer (s0=0x09BB0000)
    beq     t0, zero, @@btn_done
    nop
    ; Validate pointer is in PSP user memory range (0x08800000-0x0A000000)
    lui     t2, 0x0880
    sltu    at, t0, t2
    bnez    at, @@btn_done          ; below 0x08800000, invalid
    nop
    lui     t2, 0x0A00
    sltu    at, t0, t2
    beqz    at, @@btn_done          ; above 0x0A000000, invalid
    nop
    lhu     t1, 0(t0)              ; t1 = held buttons

    ; If neither L+DpadLeft nor L+DpadRight: clear trigger
    li      t2, BUTTON_L | BUTTON_DPAD_RIGHT
    and     t3, t1, t2
    beq     t3, t2, @@btn_check_trigger
    nop
    li      t2, BUTTON_L | BUTTON_DPAD_LEFT
    and     t3, t1, t2
    beq     t3, t2, @@btn_check_trigger
    nop
    ; Neither direction held — clear trigger
    li      t0, TRIGGER_ADDR
    sh      zero, 0(t0)
    j       @@btn_done
    nop

@@btn_check_trigger:
    ; If trigger == 0xFAFA, already processed this press
    li      t0, TRIGGER_ADDR
    lhu     t2, 0(t0)
    li      t3, 0xFAFA
    beq     t2, t3, @@btn_done
    nop

    ; L+DpadUp → enable
    li      t2, BUTTON_L | BUTTON_DPAD_UP
    and     t3, t1, t2
    bne     t3, t2, @@btn_not_enable
    nop
    li      t0, 1
    sib     t0, enabled
    j       @@btn_done
    nop
@@btn_not_enable:

    ; L+DpadDown → disable
    li      t2, BUTTON_L | BUTTON_DPAD_DOWN
    and     t3, t1, t2
    bne     t3, t2, @@btn_not_disable
    nop
    sib     zero, enabled
    j       @@btn_done
    nop
@@btn_not_disable:

    ; L+DpadRight (not R) → cycle right
    li      t2, BUTTON_L | BUTTON_R | BUTTON_DPAD_RIGHT
    and     t3, t1, t2
    li      t2, BUTTON_L | BUTTON_DPAD_RIGHT
    bne     t3, t2, @@btn_not_right
    nop
    ; Set trigger
    li      t0, TRIGGER_ADDR
    li      t2, 0xFAFA
    sh      t2, 0(t0)
    ; If not enabled, just enable
    lib     t0, enabled
    bnez    t0, @@do_cycle_right
    nop
    li      t0, 1
    sib     t0, enabled
    j       @@btn_done
    nop
@@do_cycle_right:
    ; Scan forward from current selected for next alive large monster
    li      t5, SELECTED_MON_ADDR
    lbu     t0, 0(t5)              ; current selected (0, 4, 8)
    li      t4, 3                  ; check up to 3 slots
@@sr_next:
    beqz    t4, @@btn_done
    addiu   t4, t4, -1
    addiu   t0, t0, 4
    slti    at, t0, 12
    bnez    at, @@sr_check
    nop
    li      t0, 0                  ; wrap to slot 0
@@sr_check:
    li      t2, MONSTER_POINTER
    addu    t2, t2, t0
    lw      t2, 0(t2)
    beq     t2, zero, @@sr_next   ; null pointer, skip
    nop
    lh      t3, 0x246(t2)
    blez    t3, @@sr_next          ; dead, skip
    nop
    ; Check large monster bitmap
    lb      t3, 0x62(t2)          ; icon ID
    beqz    t3, @@sr_next
    nop
    slti    at, t3, 65
    beqz    at, @@sr_next
    nop
    addiu   t3, t3, -1
    srl     t6, t3, 3
    li      t7, cycle_large_bitmap
    addu    t6, t7, t6
    lbu     t6, 0(t6)
    andi    t3, t3, 7
    li      t7, 1
    sllv    t7, t7, t3
    and     t6, t6, t7
    beqz    t6, @@sr_next          ; not a large monster, skip
    nop
    ; Found alive large monster — store selection
    sb      t0, 0(t5)
    j       @@btn_done
    nop

@@btn_not_right:
    ; L+DpadLeft (not R) → cycle left
    li      t2, BUTTON_L | BUTTON_R | BUTTON_DPAD_LEFT
    and     t3, t1, t2
    li      t2, BUTTON_L | BUTTON_DPAD_LEFT
    bne     t3, t2, @@btn_done
    nop
    ; Set trigger
    li      t0, TRIGGER_ADDR
    li      t2, 0xFAFA
    sh      t2, 0(t0)
    ; If not enabled, just enable
    lib     t0, enabled
    bnez    t0, @@do_cycle_left
    nop
    li      t0, 1
    sib     t0, enabled
    j       @@btn_done
    nop
@@do_cycle_left:
    ; Scan backward from current selected
    li      t5, SELECTED_MON_ADDR
    lbu     t0, 0(t5)
    li      t4, 3
@@sl_next:
    beqz    t4, @@btn_done
    addiu   t4, t4, -1
    addiu   t0, t0, -4
    bgez    t0, @@sl_check
    nop
    li      t0, 8                  ; wrap to slot 2
@@sl_check:
    li      t2, MONSTER_POINTER
    addu    t2, t2, t0
    lw      t2, 0(t2)
    beq     t2, zero, @@sl_next
    nop
    lh      t3, 0x246(t2)
    blez    t3, @@sl_next
    nop
    ; Check large monster bitmap
    lb      t3, 0x62(t2)
    beqz    t3, @@sl_next
    nop
    slti    at, t3, 65
    beqz    at, @@sl_next
    nop
    addiu   t3, t3, -1
    srl     t6, t3, 3
    li      t7, cycle_large_bitmap
    addu    t6, t7, t6
    lbu     t6, 0(t6)
    andi    t3, t3, 7
    li      t7, 1
    sllv    t7, t7, t3
    and     t6, t6, t7
    beqz    t6, @@sl_next
    nop
    sb      t0, 0(t5)
    j       @@btn_done
    nop

@@btn_done:
    ; === D-pad camera suppression when L is held ===
    ; Button state is inverted (1=not pressed, 0=pressed)
    ; SET d-pad bits to force "not pressed"
    lw      t0, 0x7A7C(s0)
    beq     t0, zero, @@no_suppress
    nop
    lhu     t1, 0(t0)
    andi    t2, t1, BUTTON_L
    beq     t2, zero, @@no_suppress
    nop
    ; Suppress vertical d-pad (Up+Down) when L held
    lw      t1, 0x7A64(s0)
    ori     t1, t1, 0x0050         ; DpadUp(0x10) + DpadDown(0x40)
    sw      t1, 0x7A64(s0)
    lw      t1, 0x7A68(s0)
    ori     t1, t1, 0x0050
    sw      t1, 0x7A68(s0)
@@no_suppress:
    ; === Area check for icon brightness ===
    ; Read player area from saved entity pointer (set by cam_main on first L press)
    li      t5, PLAYER_ENTITY_ADDR
    lw      t5, 0(t5)             ; player entity pointer
    beqz    t5, @@skip            ; not initialized yet (no L press yet)
    nop
    lb      t5, 0xD6(t5)          ; player's current area byte
    ; Save to PLAYER_AREA_ADDR for reference
    li      t0, PLAYER_AREA_ADDR
    sb      t5, 0(t0)
    li      t4, 0                  ; area_mask = 0
    li      t1, 0
@@area_loop:
    li      t2, MONSTER_POINTER
    addu    t2, t2, t1
    lw      t2, 0(t2)
    beq     t2, zero, @@area_next
    nop
    lb      t3, 0xD6(t2)
    bne     t3, t5, @@area_next
    nop
    srl     t3, t1, 2
    li      t2, 1
    sllv    t2, t2, t3
    or      t4, t4, t2
@@area_next:
    addiu   t1, t1, 4
    slti    at, t1, 12
    bnez    at, @@area_loop
    nop
    li      t0, AREA_MASK_ADDR
    sb      t4, 0(t0)

@@skip:
    j       EARLY_HOOK + 8
    nop
.endfunc

.close


.createfile "../bin/RENDER.bin", RENDER_LOAD

.func render
    lib     t0, enabled
    beqz    t0, @render_skip
    nop

    addiu       sp, sp, -0x10
    sw          ra, 0x0C(sp)
    sw          zero, 0x08(sp)     ; cursor_pos = -1 (not found yet)
    addiu       at, zero, -1
    sw          at, 0x08(sp)

    ; Load icons compacted: only alive monsters get positions
    li          t1, 0x0            ; slot offset (0, 4, 8)
    li          t0, 0x0            ; vertex offset (advances only for alive)
    li          t5, 0x0            ; alive count
@loop:
    jal         get_id
    move        a0, t1
    beqz        v0, @@skip_slot
    nop

    ; Alive monster: render at compacted position t0
    jal         load_texture
    move        a0, v0

    ; Icon brightness: check area_mask for this slot
    li          a0, AREA_MASK_ADDR
    lbu         a0, 0(a0)
    srl         a1, t1, 2             ; slot index (0,1,2)
    li          a2, 1
    sllv        a2, a2, a1
    and         a2, a0, a2
    bnez        a2, @@bright
    nop
    ; Not in area — dim
    li          a3, 0xFF666666
    j           @@set_color
    nop
@@bright:
    li          a3, 0xFFFFFFFF
@@set_color:
    li          a2, vertices
    addu        a2, a2, t0
    addu        a2, a2, t0             ; a2 = vertices + t0*2 (each vertex pair = 32 bytes)
    sw          a3, 0x04(a2)           ; vertex 1 color
    sw          a3, 0x14(a2)           ; vertex 2 color

    ; Check if this is the selected monster
    li          a0, SELECTED_MON_ADDR
    lbu         a0, 0(a0)
    beq         a0, t1, @@is_selected
    nop
    ; Not selected — check if this is the first alive (fallback cursor)
    lw          a0, 0x08(sp)
    bgez        a0, @@not_first    ; already found a cursor target
    nop
    ; First alive monster — save as fallback cursor position
    sw          t0, 0x08(sp)
@@not_first:
    j           @@advance_pos
    nop
@@is_selected:
    ; Selected and alive — cursor goes here
    sw          t0, 0x08(sp)
@@advance_pos:
    addiu       t0, t0, 0x10
    addiu       t5, t5, 1
    j           @@next_slot
    nop

@@skip_slot:
    ; Dead/empty: zero out vertex at current position t0
    ; (only if we haven't used all 3 vertex pairs yet)
    slti        at, t0, 0x30
    beqz        at, @@next_slot
    nop
@@next_slot:
    addiu       t1, t1, 4
    slti        at, t1, 12
    bnez        at, @loop
    nop

    ; Zero remaining vertex positions
@@zero_remaining:
    slti        at, t0, 0x30
    beqz        at, @@zero_done
    nop
    li          a0, 0
    jal         load_texture
    move        a0, zero           ; icon_id=0 zeros the vertex
    addiu       t0, t0, 0x10
    j           @@zero_remaining
    nop
@@zero_done:

    ; Store alive count to scratch space
    li          at, ALIVE_COUNT_ADDR
    sb          t5, 0(at)

    ; Check if any alive
    beqz        t5, @render_return
    nop

    ; Position cursor
    lw          a0, 0x08(sp)       ; cursor vertex offset
    bltz        a0, @render_return ; shouldn't happen but safety
    nop
    jal         set_cursor_pos
    nop

    li          a0, gpu_code
    li          a2, 0
    li          a3, 0
    jal         sceGeListEnQueue
    li          a1, 0x0

@render_return:
    lw          ra, 0x0C(sp)
    addiu       sp, sp, 0x10

@render_skip:
    lw          a0, 0x8(sp)
    lw          v0, 0x4(sp)
    j           RENDER_HOOK+8
    nop

.endfunc

; a0 = vertex offset (0x00, 0x10, 0x20) = compacted position * 16
.func set_cursor_pos
    srl         a0, a0, 4          ; position index (0, 1, 2)
    li          at, select_vertices
    li          a2, icon_stride
    mult        a0, a2
    mflo        a0
    addiu       a0, a0, icon_x+(11*icon_size/42)
    sh          a0, 0x08(at)
    addiu       a0, a0, (22*icon_size/42)
    sh          a0, 0x18(at)
    jr          ra
    nop
.endfunc

.func get_id
    li          a1, MONSTER_POINTER
    addu        a1, a1, a0
    lw          a0, 0x0(a1)
    beql        a0, zero, @@fail
    li          v0, 0x0
    ; Check HP > 0 (entity+0x246 = current HP, signed halfword)
    lh          a1, 0x246(a0)
    blez        a1, @@fail
    nop
    ; Get icon ID
    lb          v0, 0x62(a0)
    slti        at, v0, 65
    beql        at, zero, @@fail
    li          v0, 0x0
    ; Check large monster bitmap
    addiu       a1, v0, -1
    srl         a2, a1, 3
    li          a3, large_bitmap
    addu        a3, a3, a2
    lbu         a3, 0(a3)
    andi        a2, a1, 7
    li          a1, 1
    sllv        a1, a1, a2
    and         a1, a3, a1
    bnez        a1, @@ret
    nop
@@fail:
    li          v0, 0x0
@@ret:
    jr          ra
    nop
.endfunc

.func load_texture
    bne         a0, zero, normal_tex_load
    nop
    li          at, vertices
    addu        at, at, t0
    addu        at, at, t0
    sw          zero, 0x00(at)
    sw          zero, 0x10(at)
    li          at, TEX_OFFSET
    li          a1, clut_add
    addu        a1, a1, t0
    sh          at, 0x0(a1)
    jr          ra
    nop
normal_tex_load:
    addiu       a0, a0, -1
    li          at, icons
    sll         a0, a0, 1
    add         a1, at, a0
    lb          a0, 0x0(a1)
    lb          a1, 0x1(a1)
    sll         a1, a1, 6
    li          at, TEX_OFFSET
    add         at, at, a1
    li          a1, clut_add
    addu        a1, a1, t0
    sh          at, 0x0(a1)
    li          at, vertices
    addu        at, at, t0
    addu        at, at, t0
    srl         a1, a0, 0x3
    li          a2, 42
    mult        a1, a2
    mflo        a1
    sh          a1, 0x02(at)
    addiu       a1, a1, 42
    sh          a1, 0x12(at)
    srl         a1, a0, 0x3
    sll         a1, a1, 0x3
    subu        a1, a0, a1
    li          a2, 42
    mult        a1, a2
    mflo        a1
    sh          a1, 0x00(at)
    addiu       a1, a1, 42
    sh          a1, 0x10(at)
    jr          ra
    nop
.endfunc

.area 65*2, 0x0
icons:
.include "monster_icons.asm"
.endarea
.align 4

; Large monster bitmap (1=large, 0=small) for icon IDs 1-64
; Large: Rathian(1)-Uragaan(9), Great Jaggi(12), Great Baggi(14),
;   Gold Rathian(15), Royal Ludroth(16), Silver Rathalos(18)-Black Diablos(20),
;   Black Tigrex(23)-Jhen Mohran(25), Green Nargacuga(32),
;   Zinogre(40)-Nibelsnarf(47), Crimson Qurupeco(51)-Bulldrome(62)
large_bitmap:
    .word 0x81CEE9FF  ; IDs 1-32
    .word 0x3FFC7F80  ; IDs 33-64

gpu_code:
    offset      0
    base        RENDER_LOAD >> 24
    vtype       1, 2, 7, 0, 2, 0, 0, 0
    tfilter     0, 0
    tmode       1, 0, 0
    tpf         4
    tbp0        ICON_TEX_OFFSET
    tbw0        0x160, 9
    tsize0      9, 9
    clutf       3, 0xff
    clutaddhi   0x09
    vaddr       vertices-(RENDER_LOAD & 0xFF000000)
    tme         1
    tfunc       0, 1
clut_add:
    clutaddlo   ((ICON_TEX_OFFSET & 0xFF0000) + 0x10000)
    load_clut   2
    tflush
    prim        2, 6
    clutaddlo   ((ICON_TEX_OFFSET & 0xFF0000) + 0x10000)
    load_clut   2
    tflush
    prim        2, 6
    clutaddlo   ((ICON_TEX_OFFSET & 0xFF0000) + 0x10000)
    load_clut   2
    tflush
    prim        2, 6
    tbp0        CURSOR_TEX_ADD
    tbw0        256, 9
    tsize0      8, 8
    clutaddlo   CURSOR_CLUT_ADD
    load_clut   2
    tflush
    prim        2, 6
    finish
    end

.align 0x10
vertices:
    vertex      42, 0, 0xFFFFFFFF, icon_x, icon_y, 0
    vertex      42+42, 42, 0xFFFFFFFF, icon_x+icon_size, icon_y+icon_size, 0
    vertex      42, 0, 0xFFFFFFFF, icon_x+icon_stride, icon_y, 0
    vertex      42+42, 42, 0xFFFFFFFF, icon_x+icon_stride+icon_size, icon_y+icon_size, 0
    vertex      42, 0, 0xFFFFFFFF, icon_x+icon_stride*2, icon_y, 0
    vertex      42+42, 42, 0xFFFFFFFF, icon_x+icon_stride*2+icon_size, icon_y+icon_size, 0
select_vertices:
    vertex      129, 56, 0xFFFFFFFF, icon_x+(11*icon_size/42), icon_y+(32*icon_size/42), 0
    vertex      140, 63, 0xFFFFFFFF, icon_x+((11+22)*icon_size/42), icon_y+((32+14)*icon_size/42), 0

.close
