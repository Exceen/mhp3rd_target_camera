SRC_ISO := ~/Downloads/Monster\ Hunter\ Portable\ 3rd\ \(English\ Patched\ v6\)\ mod-patched.iso
DST_ISO := ~/Downloads/MHP3rd_target_cam.iso

.PHONY: all patch clean

all: bin/target_cam.bin bin/RENDER.bin

bin/target_cam.bin bin/RENDER.bin: src/no_hd.asm src/target_camera.asm src/gpu_macros.asm src/monster_icons.asm
	mkdir -p bin
	armips src/no_hd.asm

patch: all
	python3 patch_iso.py $(SRC_ISO) $(DST_ISO)

clean:
	rm -rf bin/target_cam.bin bin/RENDER.bin bin/adds.bin
