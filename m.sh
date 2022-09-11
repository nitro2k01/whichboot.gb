mkdir -p obj
mkdir -p bin
rgbasm -oobj/whichboot.o -Wno-obsolete -p 0xFF -isrc/ -ires/ -i./common/ src/whichboot.asm  &&
rgblink -t -w -p0xFF -o bin/whichboot.gb -m bin/whichboot.map -n bin/whichboot.sym obj/whichboot.o &&
rgbfix -v -s -l 0x33 -c -n 1 -p0xFF -t "WHICHBOOT" bin/whichboot.gb
