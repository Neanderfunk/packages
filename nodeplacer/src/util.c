// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2017 Jan-Philipp Litza <janphilipp@litza.de>
// Derived from the Gluon autoupdater (packages feed, admin/autoupdater),
// reduced to what nodeplacer-fetch needs.


#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <time.h>


void randomize(void) {
	struct timespec tv;
	if (clock_gettime(CLOCK_MONOTONIC, &tv)) {
		perror("nodeplacer-fetch: error: clock_gettime");
		exit(1);
	}

	srandom(tv.tv_nsec);
}


float get_uptime(void) {
	FILE *f = fopen("/proc/uptime", "r");
	if (f) {
		float uptime;
		int match = fscanf(f, "%f", &uptime);
		fclose(f);

		if (match == 1)
			return uptime;
	}

	fputs("nodeplacer-fetch: error: unable to determine uptime\n", stderr);
	exit(1);
}

void * safe_malloc(size_t size) {
	void *ret = malloc(size);
	if (!ret) {
		fprintf(stderr, "nodeplacer-fetch: error: failed to allocate memory\n");
		abort();
	}

	return ret;
}

void * safe_realloc(void *ptr, size_t size) {
	void *ret = realloc(ptr, size);
	if (!ret) {
		fprintf(stderr, "nodeplacer-fetch: error: failed to allocate memory\n");
		abort();
	}

	return ret;
}
