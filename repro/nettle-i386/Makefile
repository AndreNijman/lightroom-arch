# Native (no-Wine) reproducer for the 32-bit nettle 4.0 / gnutls TLS bug.
# 64-bit build: handshake succeeds.  32-bit build: aborts in nettle.
CC = gcc

all: ntls-handshake64 ntls-handshake32

ntls-handshake64: ntls-handshake.c
	$(CC) $< -o $@ -lgnutls

# Needs gcc multilib + lib32-gnutls (Arch: multilib repo).
ntls-handshake32: ntls-handshake.c
	$(CC) -m32 $< -o $@ -L/usr/lib32 -lgnutls

clean:
	rm -f ntls-handshake64 ntls-handshake32

.PHONY: all clean
