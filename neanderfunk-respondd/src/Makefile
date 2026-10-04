all: respondd.so

CFLAGS += -Wall -Wextra -Werror-implicit-function-declaration

respondd.so: respondd.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -shared -fPIC -D_GNU_SOURCE -o $@ $^ $(LDLIBS) -liwinfo -ljson-c
