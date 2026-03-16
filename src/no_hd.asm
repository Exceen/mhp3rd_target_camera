.psp

.relativeinclude on

CURRENT_TASK        equ 0x09C57CA0
LOAD_ADD            equ 0x089E0400
MONSTER_POINTER     equ 0x09DA9860
HOOK                equ 0x088e5f8c
EARLY_HOOK          equ 0x088E3B2C
RENDER_HOOK         equ 0x09D63ADC
ViewMatrix          equ 0x09B486B0
sceGeListEnQueue    equ 0x08960CF8
crosshair_tex_ptr   equ 0x09FFF360
RENDER_LOAD         equ 0x089E0600
TEX_OFFSET          equ 0xAED0
ICON_TEX_OFFSET     equ 0x2cbcc0
CURSOR_TEX_ADD      equ 0x2a0460
CURSOR_CLUT_ADD     equ 0x2A86B0

.include "target_camera.asm"
