

all: crt0.slf main.slf library.slf

%.slf: %.asm
	nasm $< -o $@ -p slf.asm 