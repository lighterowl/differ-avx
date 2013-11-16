NASMFLAGS=-f elf64 -F dwarf -Ox
CFLAGS=-Wall -Wextra -O2 -march=native

all : differ_mmap differ_malloc

differ_malloc : differ.c differ.o
	gcc $(CFLAGS) -DUSE_MALLOC -o differ_malloc differ.c differ.o

differ_mmap : differ.c differ.o
	gcc $(CFLAGS) -DUSE_MMAP -o differ_mmap differ.c differ.o

differ.o : differ.asm
	nasm $(NASMFLAGS) -o differ.o differ.asm

clean :
	rm -f differ_mmap differ_malloc differ.o

.PHONY : clean
