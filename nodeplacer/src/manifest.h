// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2017 Jan-Philipp Litza <janphilipp@litza.de>
// SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk
// Derived from the Gluon autoupdater manifest parser. The nodeplacer
// manifest keeps the framing (header lines, body, "---", signatures) but
// carries node entries instead of image lines; those are not interpreted
// here, only hashed and buffered for the Lua side.
#pragma once


#include <ecdsautil/ecdsa.h>
#include <ecdsautil/sha256.h>

#include <stdbool.h>
#include <stddef.h>
#include <time.h>


#define MANIFEST_FORMAT "1"


struct manifest {
	bool sep_found:1;
	bool format_ok:1;
	bool format_seen:1;
	bool date_ok:1;
	bool expires_ok:1;
	time_t date;
	time_t expires;

	/* everything before the separator, verbatim, newline terminated */
	char *body;
	size_t body_len;
	size_t body_size;

	size_t n_signatures;
	ecdsa_signature_t **signatures;
	ecdsa_sha256_context_t hash_ctx;
};


void clear_manifest(struct manifest *m);

/* returns false if the body would exceed max_body bytes */
bool parse_line(char *line, struct manifest *m, size_t max_body);
