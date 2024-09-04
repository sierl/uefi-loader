.PHONY: all clean

CC = clang
CFLAGS = -std=c23 -Wall -Wextra -Wpedantic

build: main.c
	$(CC) $(CFLAGS) $^
