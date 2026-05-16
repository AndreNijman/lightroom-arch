CC = x86_64-w64-mingw32-gcc
CFLAGS = -O2 -municode
LIBS = -lwinhttp

all: httptest.exe httptest-async.exe

httptest.exe: httptest.c
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)

httptest-async.exe: httptest-async.c
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)

clean:
	rm -f httptest.exe httptest-async.exe

.PHONY: all clean
