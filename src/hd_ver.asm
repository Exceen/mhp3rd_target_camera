.psp

.relativeinclude on

CURRENT_TASK        equ 0x0A05E620
LOAD_ADD            equ 0x0B100000
MONSTER_POINTER     equ 0x0A1B0AE0
HOOK                equ 0x088E79EC
RENDER_HOOK         equ 0x0A16A650
ViewMatrix          equ 0x09F4F120
sceGeListEnQueue    equ 0x08965990
crosshair_tex_ptr   equ 0x0Bfff360
RENDER_LOAD         equ 0x0B100130
TEX_OFFSET          equ 0x1910
ICON_TEX_OFFSET     equ 0x3d2700
CURSOR_TEX_ADD      equ 0x3a6ea0
CURSOR_CLUT_ADD     equ 0x3af0f0

.include "target_camera.asm"
