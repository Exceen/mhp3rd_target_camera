#!/usr/bin/env python3
"""Patch EBOOT.BIN inside a MHP3rd ISO with target camera binaries."""

import struct
import shutil
import sys
import os

SECTOR_SIZE = 2048
EBOOT_BASE = 0x0880134C  # vaddr 0x08804000, file_offset 0x2CB4

CW_BASE = 0x08800000


def find_file_in_iso(iso_path, target_path_parts):
    """Parse ISO 9660 to find a file's byte offset and size."""
    with open(iso_path, 'rb') as f:
        f.seek(16 * SECTOR_SIZE)
        pvd = f.read(SECTOR_SIZE)
        assert pvd[0:1] == b'\x01' and pvd[1:6] == b'CD001', "Not a valid ISO 9660"
        root_record = pvd[156:156+34]
        dir_lba = struct.unpack_from('<I', root_record, 2)[0]
        dir_size = struct.unpack_from('<I', root_record, 10)[0]
        for part in target_path_parts:
            f.seek(dir_lba * SECTOR_SIZE)
            dir_data = f.read(dir_size)
            found = False
            pos = 0
            while pos < len(dir_data):
                rec_len = dir_data[pos]
                if rec_len == 0:
                    pos = (pos // SECTOR_SIZE + 1) * SECTOR_SIZE
                    continue
                name_len = dir_data[pos + 32]
                name = dir_data[pos + 33:pos + 33 + name_len].decode('ascii', errors='replace')
                name = name.split(';')[0]
                lba = struct.unpack_from('<I', dir_data, pos + 2)[0]
                size = struct.unpack_from('<I', dir_data, pos + 10)[0]
                if name.upper() == part.upper():
                    dir_lba = lba
                    dir_size = size
                    found = True
                    break
                pos += rec_len
            if not found:
                raise FileNotFoundError(f"'{part}' not found in ISO directory")
    return dir_lba * SECTOR_SIZE, dir_size


def patch_iso(iso_path, eboot_offset):
    """Apply target camera patches to EBOOT.BIN inside the ISO."""
    with open("bin/adds.bin", "rb") as f:
        adds_data = f.read()
    load_add, hook, main_addr, render_addr, render_hook, task, early_main, early_hook = struct.unpack("8I", adds_data[:32])
    btn_suppress = btn_hook = None
    if len(adds_data) > 32:
        btn_suppress, btn_hook = struct.unpack("2I", adds_data[32:40])

    # Check binary overlap
    with open("bin/target_cam.bin", "rb") as f:
        cam_data = f.read()
    with open("bin/RENDER.bin", "rb") as f:
        render_data = f.read()

    cam_end = load_add + len(cam_data)
    if cam_end > render_addr:
        raise RuntimeError(
            f"BINARY OVERLAP: target_cam.bin ends at 0x{cam_end:08X} "
            f"but RENDER.bin starts at 0x{render_addr:08X}. "
            f"Increase RENDER_LOAD in no_hd.asm to at least 0x{(cam_end + 0xFF) & ~0xFF:08X}")

    render_end = render_addr + len(render_data)
    free_end = 0x089E21E0
    if render_end > free_end:
        raise RuntimeError(
            f"OUT OF SPACE: RENDER.bin ends at 0x{render_end:08X} "
            f"but free space ends at 0x{free_end:08X}. "
            f"Need {render_end - free_end} more bytes.")

    patches = []
    patches.append((load_add - EBOOT_BASE, cam_data))
    patches.append((render_addr - EBOOT_BASE, render_data))

    j_main = struct.pack('<II', 0x08000000 | (main_addr >> 2), 0x00000000)
    patches.append((hook - EBOOT_BASE, j_main))

    j_early = struct.pack('<II', 0x08000000 | (early_main >> 2), 0x00000000)
    patches.append((early_hook - EBOOT_BASE, j_early))

    # Button processing return hook
    if btn_suppress and btn_hook:
        j_btn = struct.pack('<II', 0x08000000 | (btn_suppress >> 2), 0x00000000)
        patches.append((btn_hook - EBOOT_BASE, j_btn))

    print(f"  target_cam.bin: 0x{load_add:08X}-0x{cam_end:08X} ({len(cam_data)} bytes)")
    print(f"  RENDER.bin:     0x{render_addr:08X}-0x{render_end:08X} ({len(render_data)} bytes)")
    print(f"  Free remaining: {free_end - render_end} bytes")
    print(f"  HOOK:           0x{hook:08X} -> 0x{main_addr:08X}")
    print(f"  EARLY_HOOK:     0x{early_hook:08X} -> 0x{early_main:08X}")
    if btn_suppress:
        print(f"  BTN_SUPPRESS:   0x{btn_hook:08X} -> 0x{btn_suppress:08X}")

    with open(iso_path, 'r+b') as f:
        for file_offset, data in patches:
            iso_offset = eboot_offset + file_offset
            f.seek(iso_offset)
            f.write(data)

    return load_add, render_addr, cam_data, render_data


def generate_cheats(load_add):
    """Generate CWCheat codes from binary addresses."""
    enabled_cw = f"0x{load_add - CW_BASE:08X}"

    # MONSTER_POINTER upper halfwords for auto-activate
    mp_base = 0x09DA9860
    mp0_hi = f"0x{mp_base + 2 - CW_BASE:08X}"

    cheats = f"""
_C0 ==== Target Camera =========
_L 0x00000000 0x00000000
_C1  TC Reset disabled flag (not in quest)
_L 0xE1016167 0x01457CA0
_L 0x{load_add + 1 - CW_BASE:08X} 0x00000000
_C1  TC Auto-activate (on quest entry)
_L 0xE0020000 {enabled_cw}
_L 0xE1010000 {mp0_hi}
_L {enabled_cw} 0x00000001
_C1  TC Enable (L+DpadUp)
_L 0xD0000001 0x10000110
_L {enabled_cw} 0x00000001
_L 0x{load_add + 1 - CW_BASE:08X} 0x00000000
_C1  TC Disable (L+DpadDown)
_L 0xD0000001 0x10000140
_L {enabled_cw} 0x00000000
_L 0x{load_add + 1 - CW_BASE:08X} 0x00000001
"""
    return cheats.strip() + "\n"


def patch_title(iso_path, new_title, max_len=128):
    """Patch the game title in PARAM.SFO inside the ISO."""
    sfo_offset, _ = find_file_in_iso(iso_path, ["PSP_GAME", "PARAM.SFO"])
    title_bytes = new_title.encode('utf-8') + b'\x00'
    if len(title_bytes) > max_len:
        raise ValueError(f"Title too long: {len(title_bytes)} > {max_len}")
    title_bytes = title_bytes.ljust(max_len, b'\x00')
    with open(iso_path, 'r+b') as f:
        f.seek(sfo_offset + 0x1AC)
        f.write(title_bytes)
    print(f"  Set title to: {new_title}")


def main():
    src_iso = os.path.expanduser(
        "~/Downloads/Monster Hunter Portable 3rd (English Patched v6) mod-patched.iso")
    dst_iso = os.path.expanduser("~/Downloads/MHP3rd_target_cam.iso")

    if len(sys.argv) >= 3:
        src_iso = sys.argv[1]
        dst_iso = sys.argv[2]
    elif len(sys.argv) == 2:
        src_iso = sys.argv[1]

    print("Copying ISO...")
    shutil.copy2(src_iso, dst_iso)
    print(f"  -> {dst_iso}")

    print("Finding EBOOT.BIN...")
    eboot_offset, eboot_size = find_file_in_iso(dst_iso, ["PSP_GAME", "SYSDIR", "EBOOT.BIN"])
    print(f"  Found at 0x{eboot_offset:08X}, {eboot_size} bytes")

    print("Applying patches...")
    load_add, render_addr, cam_data, render_data = patch_iso(dst_iso, eboot_offset)

    print("Patching title...")
    title = "MONSTER HUNTER PORTABLE 3rd"
    version_file = os.path.join(os.path.dirname(__file__) or '.', "version.txt")
    if os.path.exists(version_file):
        version = open(version_file).read().strip()
        if version:
            title += f" ({version})"
    patch_title(dst_iso, title)

    print("Generating cheats...")
    cheats = generate_cheats(load_add)
    cheats_file = os.path.join(os.path.dirname(__file__) or '.', "cheats.txt")
    with open(cheats_file, 'w') as f:
        f.write(cheats)
    print(f"  Written to {cheats_file}")

    print("Done!")


if __name__ == "__main__":
    main()
