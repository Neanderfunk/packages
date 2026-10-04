all: respondd.so

CFLAGS += -Wall -Wextra -Werror-implicit-function-declaration

# libnl-tiny fuer die live gesendete SSID (nl80211), wie gluon-status-page
CFLAGS_NL = $(shell pkg-config --cflags libnl-tiny)
LDLIBS_NL = $(shell pkg-config --libs libnl-tiny)

respondd.so: respondd.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(CFLAGS_NL) $(LDFLAGS) -shared -fPIC -D_GNU_SOURCE -o $@ $^ $(LDLIBS) -liwinfo -ljson-c $(LDLIBS_NL)
