CC = i686-w64-mingw32-gcc
CFLAGS = -O2
LDFLAGS = -lole32 -loleaut32 -luuid -lgdi32 -luser32
TARGET = wbhost.exe
SRC = wbhost.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC) $(LDFLAGS)

clean:
	rm -f $(TARGET) *.o

.PHONY: all clean
