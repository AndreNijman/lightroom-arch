CC64 = x86_64-w64-mingw32-gcc
CC32 = i686-w64-mingw32-gcc
CFLAGS = -O2 -municode
LIBS = -lwinhttp

# 64-bit builds pass; 32-bit builds reproduce the Wine secur32 TLS failure.
all: httptest.exe httptest-async.exe httptest32.exe httptest-async32.exe

httptest.exe: httptest.c
	$(CC64) $(CFLAGS) $< -o $@ $(LIBS)

httptest-async.exe: httptest-async.c
	$(CC64) $(CFLAGS) $< -o $@ $(LIBS)

httptest32.exe: httptest.c
	$(CC32) $(CFLAGS) $< -o $@ $(LIBS)

httptest-async32.exe: httptest-async.c
	$(CC32) $(CFLAGS) $< -o $@ $(LIBS)

clean:
	rm -f httptest.exe httptest-async.exe httptest32.exe httptest-async32.exe

.PHONY: all clean
