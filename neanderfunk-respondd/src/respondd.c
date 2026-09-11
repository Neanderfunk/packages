/* SPDX-FileCopyrightText: 2026, adorfer/Neanderfunk */
/* SPDX-License-Identifier: BSD-3-Clause */

/*
 * respondd-Modul fuer Werte, die die Neanderfunk-Statusseite und nodestatus
 * zusaetzlich zu Gluons eigenem respondd zeigen. Alles unter dem Schluessel
 * "neanderfunk", Datenvertrag in der README.
 *
 * Billig bleiben: die Statusseite fragt statistics alle 3 s ab, dazu Karte und
 * Yanic. Nur sysfs, /proc, ein ioctl je Ethernet-Port und nl80211 ueber
 * libiwinfo - kein Prozessstart, kein ubus.
 *
 * Nicht hier hinein: Adressen aus dem Uplink-/WAN-Netz des Aufstellers.
 * respondd ist meshweit abfragbar und landet auf oeffentlichen Karten.
 *
 * Drei Klassen, nach wie schnell sich ein Wert aendert (Tabelle in der README):
 *
 *   statisch nach dem Boot  CPU-Modell, BIOS, Flash-Groesse, swconfig-CPU-Ports.
 *                           Einmal gelesen und im Modul gehalten - der
 *                           respondd-Prozess lebt so lange wie der Boot.
 *                           Steht in nodeinfo.
 *   mittel                  je Radio Kanal, HT-Modus, SSID, TX-Leistung, Land,
 *                           Mesh. Aendert sich durch ACS, ssid-changer,
 *                           Eingriffe. WIRELESS_TTL Sekunden gecacht.
 *                           Steht in statistics.
 *   schnell                 Ethernet je Port (Link, Speed, Duplex) und die
 *                           ssid-changer-Buchfuehrung. Bei jeder Abfrage aus
 *                           sysfs bzw. /tmp; das ioctl fuer "possible" nur,
 *                           wenn sich die Geschwindigkeit eines Ports geaendert
 *                           hat. Steht in statistics.
 *
 * preserve_channels ist Konfiguration: nodeinfo, bei jeder nodeinfo-Abfrage
 * gelesen (die kommt selten).
 */

#include <respondd.h>

#include <dirent.h>
#include <errno.h>
#include <net/if.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include <linux/ethtool.h>
#include <linux/sockios.h>

#include <iwinfo.h>
#include <json-c/json.h>
#include <uci.h>


/* --- Helfer ---------------------------------------------------------------- */

/* Erste Zeile einer Datei ohne Zeilenende und ohne Rand-Leerzeichen. */
static bool read_line(const char *path, char *buf, size_t len) {
	FILE *f = fopen(path, "r");
	if (!f)
		return false;
	bool ok = fgets(buf, len, f) != NULL;
	fclose(f);
	if (!ok)
		return false;

	char *start = buf;
	while (*start == ' ' || *start == '\t')
		start++;
	size_t l = strlen(start);
	while (l && (start[l-1] == '\n' || start[l-1] == '\r' || start[l-1] == ' ' || start[l-1] == '\t'))
		start[--l] = 0;
	if (start != buf)
		memmove(buf, start, l + 1);
	return true;
}

static bool read_ll(const char *path, long long *val) {
	char buf[64];
	if (!read_line(path, buf, sizeof(buf)))
		return false;
	char *end;
	errno = 0;
	long long v = strtoll(buf, &end, 10);
	if (errno || end == buf)
		return false;
	*val = v;
	return true;
}

static bool exists(const char *path) {
	return access(path, F_OK) == 0;
}

static time_t now_monotonic(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec;
}

static bool netdev_has(const char *ifname, const char *entry) {
	char path[128];
	snprintf(path, sizeof(path), "/sys/class/net/%s/%s", ifname, entry);
	return exists(path);
}


/* --- nodeinfo: feste Hardware-Werte -------------------------------------- */

/*
 * CPU-Modell aus /proc/cpuinfo: "model name" (x86, manche ARM), sonst
 * "cpu model" (MIPS, etwa "MIPS 1004Kc V2.15"). Die aarch64-Targets haben
 * keines von beiden, dann "".
 */
static struct json_object * get_cpu_model(void) {
	char line[256], model_name[256] = "", cpu_model[256] = "";
	FILE *f = fopen("/proc/cpuinfo", "r");
	if (f) {
		while (fgets(line, sizeof(line), f)) {
			char *colon = strchr(line, ':');
			if (!colon)
				continue;
			char *val = colon + 1;
			while (*val == ' ' || *val == '\t')
				val++;
			val[strcspn(val, "\n")] = 0;
			if (!model_name[0] && !strncmp(line, "model name", 10))
				snprintf(model_name, sizeof(model_name), "%s", val);
			else if (!cpu_model[0] && !strncmp(line, "cpu model", 9))
				snprintf(cpu_model, sizeof(cpu_model), "%s", val);
		}
		fclose(f);
	}
	return json_object_new_string(model_name[0] ? model_name : cpu_model);
}

/* BIOS aus DMI - nur auf x86, sonst leere Strings. */
static struct json_object * get_bios(void) {
	char vendor[128] = "", version[128] = "";
	if (!read_line("/sys/class/dmi/id/bios_vendor", vendor, sizeof(vendor)))
		vendor[0] = 0;
	if (!read_line("/sys/class/dmi/id/bios_version", version, sizeof(version)))
		version[0] = 0;

	struct json_object *ret = json_object_new_object();
	json_object_object_add(ret, "vendor", json_object_new_string(vendor));
	json_object_object_add(ret, "version", json_object_new_string(version));
	return ret;
}

/*
 * Groesse des Dauerspeichers in Bytes, wie statuspage-hwdetails.patch:
 * bei MTD das groesste Partitionsende (offset + size) - nicht die Summe, weil
 * Verkettungen wie "ubi" auf der COVR-X1860 bereits gezaehlte Bereiche noch
 * einmal enthalten. Ohne MTD (x86, virtio, SATA, eMMC) das groesste
 * Blockgeraet aus /proc/partitions ausser loop* und ram*. Unbekannt: 0.
 */
static long long get_flash_bytes(void) {
	long long total = 0;
	char path[64];

	for (int i = 0; ; i++) {
		long long size, offset = 0;
		snprintf(path, sizeof(path), "/sys/class/mtd/mtd%d/size", i);
		if (!read_ll(path, &size))
			break;
		snprintf(path, sizeof(path), "/sys/class/mtd/mtd%d/offset", i);
		if (!read_ll(path, &offset))
			offset = 0;
		if (offset + size > total)
			total = offset + size;
	}
	if (total > 0)
		return total;

	FILE *f = fopen("/proc/partitions", "r");
	if (!f)
		return 0;
	char line[256];
	while (fgets(line, sizeof(line), f)) {
		unsigned long long blocks;
		char name[64];
		if (sscanf(line, " %*u %*u %llu %63s", &blocks, name) != 2)
			continue;
		if (!strncmp(name, "loop", 4) || !strncmp(name, "ram", 3))
			continue;
		if ((long long)(blocks * 1024) > total)
			total = blocks * 1024;
	}
	fclose(f);
	return total;
}

static bool get_preserve_channels(void) {
	bool ret = false;
	struct uci_context *ctx = uci_alloc_context();
	if (!ctx)
		return false;
	ctx->flags &= ~UCI_FLAG_STRICT;

	struct uci_package *p;
	if (!uci_load(ctx, "gluon", &p)) {
		struct uci_section *s = uci_lookup_section(ctx, p, "wireless");
		const char *v = s ? uci_lookup_option_string(ctx, s, "preserve_channels") : NULL;
		ret = v && !strcmp(v, "1");
	}
	uci_free_context(ctx);
	return ret;
}

static struct json_object * respondd_provider_nodeinfo(void) {
	/* statisch nach dem Boot: einmal ermitteln, danach nur noch kopieren */
	static struct json_object *hardware_cache;
	if (!hardware_cache) {
		hardware_cache = json_object_new_object();
		json_object_object_add(hardware_cache, "cpu_model", get_cpu_model());
		json_object_object_add(hardware_cache, "flash", json_object_new_int64(get_flash_bytes()));
		json_object_object_add(hardware_cache, "bios", get_bios());
	}
	struct json_object *hardware = NULL;
	if (json_object_deep_copy(hardware_cache, &hardware, NULL))
		hardware = json_object_new_object();

	struct json_object *wireless = json_object_new_object();
	json_object_object_add(wireless, "preserve_channels", json_object_new_boolean(get_preserve_channels()));

	struct json_object *nf = json_object_new_object();
	json_object_object_add(nf, "hardware", hardware);
	json_object_object_add(nf, "wireless", wireless);

	struct json_object *ret = json_object_new_object();
	json_object_object_add(ret, "neanderfunk", nf);
	return ret;
}


/* --- statistics: Radios ---------------------------------------------------- */

static const char * htmode_name(int mode) {
	for (int i = 0; i < IWINFO_HTMODE_COUNT; i++) {
		if (mode == (1 << i))
			return IWINFO_HTMODE_NAMES[i];
	}
	return "";
}

static bool netdev_up(const char *ifname) {
	char path[128], buf[32];
	snprintf(path, sizeof(path), "/sys/class/net/%s/operstate", ifname);
	return read_line(path, buf, sizeof(buf)) && !strcmp(buf, "up");
}

/*
 * Je Radio, was tatsaechlich laeuft, nicht was konfiguriert ist: Kanal und
 * HT-Modus aendern sich zur Laufzeit (ACS bei channel=auto), die SSID schaltet
 * der ssid-changer auf die Offline-SSID. Gluon benennt die Interfaces nach dem
 * Radio: client<N> und mesh<N> gehoeren zu radio<N>. Ein Radio erscheint,
 * sobald eines der beiden existiert; Kanal, HT-Modus, Leistung und Land kommen
 * vom Client-AP, sonst vom Mesh-Interface.
 */
#define WIRELESS_TTL 10

static struct json_object * collect_wireless(void) {
	struct json_object *ret = json_object_new_object();

	for (int i = 0; i < 4; i++) {
		char client[IFNAMSIZ], mesh[IFNAMSIZ], radio[16];
		snprintf(client, sizeof(client), "client%d", i);
		snprintf(mesh, sizeof(mesh), "mesh%d", i);
		snprintf(radio, sizeof(radio), "radio%d", i);

		bool has_client = netdev_has(client, "");
		bool has_mesh = netdev_has(mesh, "");
		if (!has_client && !has_mesh)
			continue;

		const char *dev = has_client ? client : mesh;
		const struct iwinfo_ops *iw = iwinfo_backend(dev);

		int channel = 0, htmode = -1, txpower = 0;
		char ssid[IWINFO_ESSID_MAX_SIZE + 1] = "";
		char country[8] = "";

		if (iw) {
			if (iw->channel(dev, &channel))
				channel = 0;
			if (iw->htmode(dev, &htmode))
				htmode = -1;
			if (iw->txpower(dev, &txpower))
				txpower = 0;
			if (iw->country(dev, country))
				country[0] = 0;
			country[2] = 0;
			if (has_client && iw->ssid(client, ssid))
				ssid[0] = 0;
		}

		struct json_object *r = json_object_new_object();
		json_object_object_add(r, "channel", json_object_new_int(channel));
		json_object_object_add(r, "htmode", json_object_new_string(htmode_name(htmode)));
		json_object_object_add(r, "ssid", json_object_new_string(ssid));
		json_object_object_add(r, "txpower", json_object_new_int(txpower));
		json_object_object_add(r, "country", json_object_new_string(country));
		json_object_object_add(r, "mesh", json_object_new_boolean(has_mesh && netdev_up(mesh)));
		json_object_object_add(ret, radio, r);
	}

	iwinfo_finish();
	return ret;
}

/* mittel: hoechstens alle WIRELESS_TTL Sekunden neu ueber nl80211 */
static struct json_object * get_wireless(void) {
	static struct json_object *cache;
	static time_t stamp;
	time_t now = now_monotonic();

	if (!cache || now - stamp >= WIRELESS_TTL) {
		if (cache)
			json_object_put(cache);
		cache = collect_wireless();
		stamp = now;
	}

	struct json_object *ret = NULL;
	if (json_object_deep_copy(cache, &ret, NULL))
		ret = json_object_new_object();
	return ret;
}


/* --- statistics: ssid-changer --------------------------------------------- */

/*
 * Buchfuehrung von neanderfunk-ssid-changer in /tmp. Fehlt eine Datei, ist
 * das Paket nicht installiert oder hat seit dem Boot noch nicht gezaehlt -
 * dann fehlt das ganze Objekt.
 */
static struct json_object * get_ssid_changer(void) {
	long long offline, switches, losses;
	if (!read_ll("/tmp/ssid-changer-offline", &offline) ||
	    !read_ll("/tmp/ssid-changer-offline-switches", &switches) ||
	    !read_ll("/tmp/ssid-changer-gateway-losses", &losses))
		return NULL;

	struct json_object *ret = json_object_new_object();
	json_object_object_add(ret, "offline", json_object_new_int(offline ? 1 : 0));
	json_object_object_add(ret, "switches", json_object_new_int64(switches));
	json_object_object_add(ret, "gateway_losses", json_object_new_int64(losses));
	return ret;
}


/* --- statistics: Ethernet ------------------------------------------------- */

/*
 * Aus /etc/board.json, einmal gelesen (aendert sich zur Laufzeit nicht):
 *  - die CPU-Ports der swconfig-Switches (switch.<name>.ports[].device),
 *  - die Ports, die das Board einer Rolle zuordnet (network.<rolle>.ports[]
 *    bzw. .device).
 */
#define MAX_CPU_PORTS 8
static char cpu_ports[MAX_CPU_PORTS][IFNAMSIZ];
static int n_cpu_ports = -1;

#define MAX_BOARD_PORTS 16
static char board_ports[MAX_BOARD_PORTS][IFNAMSIZ];
static int n_board_ports;

static void add_board_port(const char *name) {
	if (name && n_board_ports < MAX_BOARD_PORTS)
		snprintf(board_ports[n_board_ports++], IFNAMSIZ, "%s", name);
}

static void load_board(void) {
	if (n_cpu_ports >= 0)
		return;
	n_cpu_ports = 0;

	struct json_object *board = json_object_from_file("/etc/board.json");
	if (!board)
		return;

	struct json_object *network;
	if (json_object_object_get_ex(board, "network", &network) && json_object_is_type(network, json_type_object)) {
		json_object_object_foreach(network, role, net) {
			(void)role;
			struct json_object *v;
			if (json_object_object_get_ex(net, "device", &v))
				add_board_port(json_object_get_string(v));
			if (json_object_object_get_ex(net, "ports", &v) && json_object_is_type(v, json_type_array)) {
				size_t n = json_object_array_length(v);
				for (size_t i = 0; i < n; i++)
					add_board_port(json_object_get_string(json_object_array_get_idx(v, i)));
			}
		}
	}

	struct json_object *switches;
	if (json_object_object_get_ex(board, "switch", &switches) && json_object_is_type(switches, json_type_object)) {
		json_object_object_foreach(switches, name, sw) {
			(void)name;
			struct json_object *ports;
			if (!json_object_object_get_ex(sw, "ports", &ports) || !json_object_is_type(ports, json_type_array))
				continue;
			size_t n = json_object_array_length(ports);
			for (size_t i = 0; i < n && n_cpu_ports < MAX_CPU_PORTS; i++) {
				struct json_object *dev;
				if (json_object_object_get_ex(json_object_array_get_idx(ports, i), "device", &dev))
					snprintf(cpu_ports[n_cpu_ports++], IFNAMSIZ, "%s", json_object_get_string(dev));
			}
		}
	}
	json_object_put(board);
}

static bool is_cpu_port(const char *ifname) {
	for (int i = 0; i < n_cpu_ports; i++) {
		if (!strcmp(cpu_ports[i], ifname))
			return true;
	}
	return false;
}

static bool is_board_port(const char *ifname) {
	for (int i = 0; i < n_board_ports; i++) {
		if (!strcmp(board_ports[i], ifname))
			return true;
	}
	return false;
}

static bool admin_up(const char *ifname) {
	char path[64 + IFNAMSIZ], buf[32];
	snprintf(path, sizeof(path), "/sys/class/net/%s/flags", ifname);
	if (!read_line(path, buf, sizeof(buf)))
		return false;
	return strtoul(buf, NULL, 16) & IFF_UP;
}

/*
 * Ein Port, an den man ein Kabel steckt (auf fuenf Knoten geprueft, siehe
 * Firmware statuspage-ethlinks.patch):
 *  - hat einen device-Link (keine VLANs, Bridges, veth local-node/-port),
 *  - ist kein WLAN (phy80211/ bzw. wireless/),
 *  - ist kein DSA-Conduit (dsa/ gibt es nur dort),
 *  - ist kein swconfig-CPU-Port,
 *  - steht in board.json unter network oder ist administrativ oben. Das
 *    laesst eine unbenutzte GMAC ohne Buchse weg (eth1 auf der COVR-X1860),
 *    behaelt aber jeden Board-Port, auch ohne Rolle und ohne Link.
 */
static bool is_port(const char *ifname) {
	return netdev_has(ifname, "device") &&
		!netdev_has(ifname, "phy80211") && !netdev_has(ifname, "wireless") &&
		!netdev_has(ifname, "dsa") &&
		!is_cpu_port(ifname) &&
		(is_board_port(ifname) || admin_up(ifname));
}

/* Geschwindigkeit je Link-Modus, nur die Modi, die an Buchsen vorkommen. */
static const struct { int bit; int speed; } link_modes[] = {
	{ ETHTOOL_LINK_MODE_10baseT_Half_BIT, 10 },
	{ ETHTOOL_LINK_MODE_10baseT_Full_BIT, 10 },
	{ ETHTOOL_LINK_MODE_100baseT_Half_BIT, 100 },
	{ ETHTOOL_LINK_MODE_100baseT_Full_BIT, 100 },
	{ ETHTOOL_LINK_MODE_1000baseT_Half_BIT, 1000 },
	{ ETHTOOL_LINK_MODE_1000baseT_Full_BIT, 1000 },
	{ ETHTOOL_LINK_MODE_1000baseX_Full_BIT, 1000 },
	{ ETHTOOL_LINK_MODE_2500baseT_Full_BIT, 2500 },
	{ ETHTOOL_LINK_MODE_2500baseX_Full_BIT, 2500 },
	{ ETHTOOL_LINK_MODE_5000baseT_Full_BIT, 5000 },
	{ ETHTOOL_LINK_MODE_10000baseT_Full_BIT, 10000 },
};

/*
 * Hoechste Rate, die BEIDE Seiten angeboten haben (advertising und
 * lp_advertising aus ETHTOOL_GLINKSETTINGS). 0, wenn nicht ermittelbar.
 */
static int best_common_speed(int sock, const char *ifname) {
	struct {
		struct ethtool_link_settings req;
		__u32 masks[3 * 127];
	} ecmd;
	struct ifreq ifr;

	memset(&ecmd, 0, sizeof(ecmd));
	memset(&ifr, 0, sizeof(ifr));
	snprintf(ifr.ifr_name, IFNAMSIZ, "%s", ifname);
	ifr.ifr_data = (void *)&ecmd;

	/* Handshake: erst fragt man nach der Maskenlaenge, der Kernel antwortet
	 * mit ihrem Negativ, dann die eigentliche Abfrage. */
	ecmd.req.cmd = ETHTOOL_GLINKSETTINGS;
	if (ioctl(sock, SIOCETHTOOL, &ifr) || ecmd.req.link_mode_masks_nwords >= 0)
		return 0;
	int nwords = -ecmd.req.link_mode_masks_nwords;
	if (nwords > 127)
		return 0;
	ecmd.req.cmd = ETHTOOL_GLINKSETTINGS;
	ecmd.req.link_mode_masks_nwords = nwords;
	if (ioctl(sock, SIOCETHTOOL, &ifr) || ecmd.req.link_mode_masks_nwords != nwords)
		return 0;

	/* masks liegt direkt hinter req, also dort, wo link_mode_masks[] beginnt:
	 * supported, advertising, lp_advertising, je nwords Worte. */
	const __u32 *adv = &ecmd.masks[nwords];
	const __u32 *lp = &ecmd.masks[2 * nwords];
	int best = 0;
	for (size_t i = 0; i < sizeof(link_modes) / sizeof(link_modes[0]); i++) {
		int b = link_modes[i].bit;
		if (b / 32 >= nwords)
			continue;
		__u32 m = 1u << (b % 32);
		if ((adv[b / 32] & m) && (lp[b / 32] & m) && link_modes[i].speed > best)
			best = link_modes[i].speed;
	}
	return best;
}

/*
 * Die Aushandlung aendert sich nur mit dem Link. Gemerkt wird je Port die
 * Geschwindigkeit, bei der zuletzt gefragt wurde; das ioctl laeuft erst
 * wieder, wenn sie sich aendert (neu ausgehandelt, Kabel gewechselt).
 */
#define MAX_PORTS 16
static struct { char ifname[IFNAMSIZ]; int speed; int best; } port_cache[MAX_PORTS];

static int possible_cached(int sock, const char *ifname, int speed) {
	int free_slot = -1;
	for (int i = 0; i < MAX_PORTS; i++) {
		if (!port_cache[i].ifname[0]) {
			if (free_slot < 0)
				free_slot = i;
			continue;
		}
		if (strcmp(port_cache[i].ifname, ifname))
			continue;
		if (port_cache[i].speed != speed) {
			port_cache[i].speed = speed;
			port_cache[i].best = best_common_speed(sock, ifname);
		}
		return port_cache[i].best;
	}

	int best = best_common_speed(sock, ifname);
	if (free_slot >= 0) {
		snprintf(port_cache[free_slot].ifname, IFNAMSIZ, "%s", ifname);
		port_cache[free_slot].speed = speed;
		port_cache[free_slot].best = best;
	}
	return best;
}

static struct json_object * get_port(int sock, const char *ifname) {
	char path[128], buf[32];
	long long v;

	snprintf(path, sizeof(path), "/sys/class/net/%s/carrier", ifname);
	/* carrier ist bei einem abgeschalteten Interface nicht lesbar (EINVAL). */
	bool carrier = read_ll(path, &v) && v == 1;

	int speed = 0;
	const char *duplex = "";
	if (carrier) {
		snprintf(path, sizeof(path), "/sys/class/net/%s/speed", ifname);
		if (read_ll(path, &v) && v > 0)
			speed = v;
		snprintf(path, sizeof(path), "/sys/class/net/%s/duplex", ifname);
		if (read_line(path, buf, sizeof(buf))) {
			if (!strcmp(buf, "full"))
				duplex = "full";
			else if (!strcmp(buf, "half"))
				duplex = "half";
		}
	}

	/* Beide Seiten koennten mehr, der Link blieb darunter: der Fingerabdruck
	 * eines beschaedigten Kabels. Ein echtes 100-MBit-Geraet an einem
	 * Gigabit-Port bietet kein Gigabit an und ergibt 0. */
	int possible = 0;
	if (carrier && speed > 0 && sock >= 0) {
		int best = possible_cached(sock, ifname, speed);
		if (best > speed)
			possible = best;
	}

	struct json_object *ret = json_object_new_object();
	json_object_object_add(ret, "carrier", json_object_new_boolean(carrier));
	json_object_object_add(ret, "speed", json_object_new_int(speed));
	json_object_object_add(ret, "duplex", json_object_new_string(duplex));
	json_object_object_add(ret, "possible", json_object_new_int(possible));
	return ret;
}

static struct json_object * get_ethernet(void) {
	struct json_object *ret = json_object_new_object();

	load_board();

	DIR *d = opendir("/sys/class/net");
	if (!d)
		return ret;

	int sock = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);

	struct dirent *e;
	while ((e = readdir(d))) {
		char name[IFNAMSIZ];
		size_t len = strlen(e->d_name);
		if (e->d_name[0] == '.' || len >= IFNAMSIZ)
			continue;
		memcpy(name, e->d_name, len + 1);
		if (!is_port(name))
			continue;
		json_object_object_add(ret, name, get_port(sock, name));
	}

	if (sock >= 0)
		close(sock);
	closedir(d);
	return ret;
}


static struct json_object * respondd_provider_statistics(void) {
	struct json_object *nf = json_object_new_object();

	json_object_object_add(nf, "wireless", get_wireless());

	struct json_object *sc = get_ssid_changer();
	if (sc)
		json_object_object_add(nf, "ssid_changer", sc);

	json_object_object_add(nf, "ethernet", get_ethernet());

	struct json_object *ret = json_object_new_object();
	json_object_object_add(ret, "neanderfunk", nf);
	return ret;
}


const struct respondd_provider_info respondd_providers[] = {
	{"nodeinfo", respondd_provider_nodeinfo},
	{"statistics", respondd_provider_statistics},
	{},
};
