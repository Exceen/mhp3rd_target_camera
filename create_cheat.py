from ModIO import CwCheatIO
from struct import pack, unpack


if __name__ == "__main__":
    with open("./bin/adds.bin", "rb") as addresses:
        load_add, hook, main, render_main, render_hook, task = unpack("6I", addresses.read(0x18))

    with CwCheatIO("./bin/CHEATS.TXT") as file:
        file.seek(load_add+4)

        file.write("Target Camera 1/3")
        with open("./bin/target_cam.bin", "rb") as bin:
            bin.read(4)
            file.write_once(bin.read())
        file.seek(hook)
        file.write(pack("I4x", 0x0A000000 | (main // 4)))

        file.write("Target Camera 2/3")
        file.write(
            "_L 0xD0000000 0x10000110\n"
            f'_L 0x{hex(load_add-0x8800000).replace("0x", ""):0>8} 0x00000001\n'
            
            "_L 0xD0000000 0x10000140\n"
            f'_L 0x{hex(load_add-0x8800000).replace("0x", ""):0>8} 0x00000000\n'
        )

        file.write("Target Camera 3/3")

        var = load_add + 1
        add = hex(var - 0x8800000).replace("0x", "")
        add2 = hex(var - 0x8800000 + 2).replace("0x", "")

        file.write(
            # left
            "_L 0xD0000003 0x10000180\n"
            f"_L 0xE1020000 0x0{add2:0>7}\n"
            f"_L 0xE0010000 0x3{add:0>7}\n"
            f"_L 0x30400004 0x0{add:0>7}\n"
            f"_L 0x0{add2:0>7} 0x00000001\n"
            
            "_L 0xD0000002 0x10000120\n"
            f"_L 0xE1010000 0x0{add2:0>7}\n"
            f"_L 0x30300004 0x0{add:0>7}\n"
            f"_L 0x0{add2:0>7} 0x00000001\n"
            
            "_L 0xD0000001 0x30000120\n"
            "_L 0xD0000000 0x30000180\n"
            f"_L 0x0{add2:0>7} 0x00000000\n"
        )

        file.write("Target Camera UI 1/2")
        file.seek(render_main)
        with open("bin/RENDER.bin", "rb") as bin:
            file.write_once(bin.read())

        file.write("Target Camera UI 2/2")
        file.seek(render_hook)
        file.write(
            f'_L 0xE0026167 0x0{hex(task-0x8800000).replace("0x", ""):0>7}\n'
        )
        file.write(pack("I4x", 0x0A000000 | (render_main // 4)))
