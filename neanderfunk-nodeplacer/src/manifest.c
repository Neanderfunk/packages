// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2017 Jan-Philipp Litza <janphilipp@litza.de>
// SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk
// Derived from the Gluon autoupdater manifest parser (packages feed,
// admin/autoupdater/src/manifest.c).

#include "hexutil.h"
#include "manifest.h"
#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


// only frees the data inside the manifest struct, not the struct itself!
void clear_manifest(struct manifest *m) {
	free(m->body);

	for (size_t i = 0; i < m->n_signatures; i++)
		free(m->signatures[i]);
	free(m->signatures);

	memset(m, 0, sizeof(*m));
}


/* Same format and arithmetic as the autoupdater: YYYY-MM-DD HH:MM:SS+HH:MM */
static bool parse_rfc3339(const char *input, time_t *date) {
	char tzs;
	unsigned year, month, day, hour, minute, second, tzh, tzm;

	if (sscanf(input, "%04u-%02u-%02u %02u:%02u:%02u%c%02u:%02u",
		   &year, &month, &day, &hour, &minute, &second,
		   &tzs, &tzh, &tzm) != 9)
		return false;

	time_t a = (14 - month)/12;
	time_t y = year - a;
	time_t m = month + 12*a - 3;

	/* Based on a well-known formula for Julian dates */
	time_t days = day + (153*m + 2)/5 + 365*y + y/4 - y/100 + y/400 - 719469;
	time_t tim = hour*3600 + minute*60 + second;


	time_t tz = 3600 * tzh + 60 * tzm;
	if (tzs == '-')
		tz = -tz;
	else if (tzs != '+')
		return false;


	*date = 86400*days + tim - tz;
	return true;

}


static bool append_body(struct manifest *m, const char *line, size_t max_body) {
	size_t len = strlen(line);
	size_t needed = m->body_len + len + 2; /* newline and terminator */

	if (needed > max_body)
		return false;

	if (needed > m->body_size) {
		size_t size = m->body_size ? m->body_size : 4096;
		while (size < needed)
			size *= 2;
		m->body = safe_realloc(m->body, size);
		m->body_size = size;
	}

	memcpy(m->body + m->body_len, line, len);
	m->body_len += len;
	m->body[m->body_len++] = '\n';
	m->body[m->body_len] = '\0';

	return true;
}


bool parse_line(char *line, struct manifest *m, size_t max_body) {
	if (m->sep_found) {
		ecdsa_signature_t *sig = safe_malloc(sizeof(ecdsa_signature_t));

		if (!parsehex(sig, line, sizeof(*sig))) {
			free(sig);
			fprintf(stderr, "nodeplacer-fetch: warning: garbage in signature area: %s\n", line);
			return true;
		}
		m->n_signatures++;
		m->signatures = safe_realloc(m->signatures, m->n_signatures * sizeof(ecdsa_signature_t *));
		m->signatures[m->n_signatures - 1] = sig;
		return true;
	}

	if (strcmp(line, "---") == 0) {
		m->sep_found = true;
		return true;
	}

	/* everything before the separator is signed: hash it and keep it */
	ecdsa_sha256_update(&m->hash_ctx, line, strlen(line));
	ecdsa_sha256_update(&m->hash_ctx, "\n", 1);

	if (!append_body(m, line, max_body))
		return false;

	/* header fields: the first occurrence wins, like in the autoupdater */
	if (!strncmp(line, "FORMAT=", 7)) {
		if (m->format_seen)
			return true;
		m->format_seen = true;
		m->format_ok = !strcmp(&line[7], MANIFEST_FORMAT);
	}
	else if (!strncmp(line, "DATE=", 5)) {
		if (m->date_ok)
			return true;
		m->date_ok = parse_rfc3339(&line[5], &m->date);
	}
	else if (!strncmp(line, "EXPIRES=", 8)) {
		if (m->expires_ok)
			return true;
		m->expires_ok = parse_rfc3339(&line[8], &m->expires);
	}

	/* node entries are left to the Lua side */
	return true;
}
