// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2017 Matthias Schiffer <mschiffer@universe-factory.net>
// SPDX-FileCopyrightText: 2017 Jan-Philipp Litza <janphilipp@litza.de>
// SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk
//
// nodeplacer-fetch: download the nodeplacer manifest from one of the
// configured mirrors, verify its signatures and header, and print the
// verified body (everything before "---") to stdout.
//
// Derived from the Gluon autoupdater (packages feed, admin/autoupdater).
// All policy lives in /usr/sbin/nodeplacer (Lua); this program never acts.
//
// Exit codes:
//   0  manifest verified, body on stdout
//   1  configuration or usage error
//   2  no manifest on any mirror (HTTP 404, connection errors)
//   3  manifest found but rejected: signatures, unsupported FORMAT,
//      missing/invalid DATE or EXPIRES, expired. No further mirror is tried.

#include "manifest.h"
#include "uclient.h"
#include "util.h"
#include "hexutil.h"

#include <libubox/uloop.h>
#include <ecdsautil/ecdsa.h>
#include <ecdsautil/sha256.h>
#include <uci.h>

#include <getopt.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>


#define MAX_LINE_LENGTH 2048
#define MAX_BODY_BYTES (256 * 1024)
#define STRINGIFY_(x) #x
#define STRINGIFY(x) STRINGIFY_(x)

static const char *const manifest_name = "nodeplacer.manifest";

enum exit_code {
	EXIT_VERIFIED = 0,
	EXIT_CONFIG = 1,
	EXIT_NO_MANIFEST = 2,
	EXIT_REJECTED = 3,
};

struct settings {
	unsigned long good_signatures;

	size_t n_mirrors;
	const char **mirrors;

	size_t n_pubkeys;
	ecc_25519_work_t *pubkeys;
};

struct recv_manifest_ctx {
	struct manifest m;
	char buf[MAX_LINE_LENGTH + 1];
	char *ptr;
	bool too_long;
	bool too_big;
};


static void usage(void) {
	fputs("\n"
		"Usage: nodeplacer-fetch [options] [<mirror> ...]\n\n"
		"Downloads <mirror>/nodeplacer.manifest, verifies signatures and header\n"
		"and prints the verified part before '---' to stdout.\n\n"
		"Possible options are:\n"
		"  -h, --help           Show this help.\n\n"
		"  <mirror> ...         Override the mirror URLs given in the configuration. If\n"
		"                       specified, these are not shuffled.\n\n"
		"Exit codes: 0 verified, 1 config error, 2 no manifest, 3 rejected.\n\n",
		stderr
	);
}


static void parse_args(int argc, char *argv[], struct settings *settings) {
	const struct option options[] = {
		{"help", no_argument, NULL, 'h'},
		{}
	};

	while (true) {
		int c = getopt_long(argc, argv, "h", options, NULL);
		if (c < 0)
			break;

		switch (c) {
		case 'h':
			usage();
			exit(0);

		default:
			usage();
			exit(EXIT_CONFIG);
		}
	}

	if (optind < argc) {
		settings->n_mirrors = argc - optind;
		settings->mirrors = safe_malloc(settings->n_mirrors * sizeof(char *));

		for (int i = optind; i < argc; i++)
			settings->mirrors[i - optind] = argv[i];
	}
}


/**** UCI ********************************************************************/

static unsigned long load_positive_number(struct uci_context *ctx, struct uci_section *s, const char *option) {
	const char *str = uci_lookup_option_string(ctx, s, option);
	if (!str) {
		fprintf(stderr, "nodeplacer-fetch: error: unable to load option '%s'\n", option);
		exit(EXIT_CONFIG);
	}

	char *end;
	unsigned long ret = strtoul(str, &end, 0);
	if (*end || !ret) {
		fprintf(stderr, "nodeplacer-fetch: error: invalid value for option '%s'\n", option);
		exit(EXIT_CONFIG);
	}

	return ret;
}

/* returns NULL (and *len = 0) if the option is missing; exits on a non-list */
static const char ** load_string_list(struct uci_context *ctx, struct uci_section *s, const char *option, size_t *len) {
	*len = 0;

	struct uci_option *o = uci_lookup_option(ctx, s, option);
	if (!o)
		return NULL;

	if (o->type != UCI_TYPE_LIST) {
		fprintf(stderr, "nodeplacer-fetch: error: invalid value for option '%s'\n", option);
		exit(EXIT_CONFIG);
	}

	size_t i = 0;
	struct uci_element *e;
	uci_foreach_element(&o->v.list, e)
		i++;

	*len = i;
	const char **ret = safe_malloc(i * sizeof(char *));

	i = 0;
	uci_foreach_element(&o->v.list, e)
		ret[i++] = e->name;

	return ret;
}

static void load_pubkeys(struct settings *settings, const char **pubkeys_str, size_t n) {
	settings->pubkeys = safe_malloc(n * sizeof(ecc_25519_work_t));
	settings->n_pubkeys = 0;

	for (size_t i = 0; i < n; i++) {
		ecc_int256_t pubkey_packed;
		if (!pubkeys_str[i] || !parsehex(pubkey_packed.p, pubkeys_str[i], 32) ||
		    !ecc_25519_load_packed_legacy(&settings->pubkeys[settings->n_pubkeys], &pubkey_packed)) {
			fprintf(stderr, "nodeplacer-fetch: warning: ignoring invalid public key '%s'\n",
				pubkeys_str[i] ? pubkeys_str[i] : "(null)");
			continue;
		}
		settings->n_pubkeys++;
	}
}

static void load_settings(struct settings *settings) {
	struct uci_context *ctx = uci_alloc_context();
	if (!ctx) {
		fputs("nodeplacer-fetch: error: failed to allocate UCI context\n", stderr);
		abort();
	}

	ctx->flags &= ~UCI_FLAG_STRICT;

	struct uci_package *p;
	struct uci_section *s;

	if (uci_load(ctx, "nodeplacer", &p) != UCI_OK) {
		fputs("nodeplacer-fetch: error: unable to load UCI package nodeplacer\n", stderr);
		exit(EXIT_CONFIG);
	}

	s = uci_lookup_section(ctx, p, "settings");
	if (!s || strcmp(s->type, "nodeplacer")) {
		fputs("nodeplacer-fetch: error: unable to load UCI settings\n", stderr);
		exit(EXIT_CONFIG);
	}

	settings->good_signatures = load_positive_number(ctx, s, "good_signatures");

	if (settings->n_mirrors == 0) {
		settings->mirrors = load_string_list(ctx, s, "mirror", &settings->n_mirrors);
		if (settings->n_mirrors == 0) {
			fputs("nodeplacer-fetch: error: no mirrors configured\n", stderr);
			exit(EXIT_CONFIG);
		}
	}

	size_t n_pubkeys_str;
	const char **pubkeys_str = load_string_list(ctx, s, "pubkey", &n_pubkeys_str);

	if (n_pubkeys_str == 0) {
		/* fall back to the pubkeys of the configured autoupdater branch */
		struct uci_package *ap;
		if (uci_load(ctx, "autoupdater", &ap) != UCI_OK) {
			fputs("nodeplacer-fetch: error: no pubkeys configured and unable to load autoupdater config\n", stderr);
			exit(EXIT_CONFIG);
		}

		struct uci_section *as = uci_lookup_section(ctx, ap, "settings");
		const char *branch = as ? uci_lookup_option_string(ctx, as, "branch") : NULL;
		struct uci_section *bs = branch ? uci_lookup_section(ctx, ap, branch) : NULL;
		if (!bs || strcmp(bs->type, "branch")) {
			fputs("nodeplacer-fetch: error: no pubkeys configured and no autoupdater branch to borrow them from\n", stderr);
			exit(EXIT_CONFIG);
		}

		pubkeys_str = load_string_list(ctx, bs, "pubkey", &n_pubkeys_str);
	}

	load_pubkeys(settings, pubkeys_str, n_pubkeys_str);
	free(pubkeys_str);

	if (settings->n_pubkeys < settings->good_signatures) {
		fprintf(stderr, "nodeplacer-fetch: error: only %zu valid public keys, but %lu signatures required\n",
			settings->n_pubkeys, settings->good_signatures);
		exit(EXIT_CONFIG);
	}

	/* the UCI strings are referenced by settings->mirrors; keep the context alive */
}


/**** Download ****************************************************************/

/** Receives data from uclient, chops it to lines and hands it to parse_line */
static void recv_manifest_cb(struct uclient *cl) {
	struct recv_manifest_ctx *ctx = uclient_get_custom(cl);
	char *newline;
	int len;

	if (ctx->too_long || ctx->too_big)
		return;

	while (true) {
		if (ctx->ptr - ctx->buf == MAX_LINE_LENGTH) {
			fputs("nodeplacer-fetch: error: encountered manifest line exceeding limit of " STRINGIFY(MAX_LINE_LENGTH) " characters\n", stderr);
			ctx->too_long = true;
			break;
		}
		len = uclient_read_account(cl, ctx->ptr, MAX_LINE_LENGTH - (ctx->ptr - ctx->buf));
		if (len <= 0)
			break;
		ctx->ptr[len] = '\0';

		char *line = ctx->buf;
		while (true) {
			newline = strchr(line, '\n');
			if (newline == NULL)
				break;
			*newline = '\0';

			if (!parse_line(line, &ctx->m, MAX_BODY_BYTES)) {
				fputs("nodeplacer-fetch: error: manifest exceeds " STRINGIFY(MAX_BODY_BYTES) " bytes\n", stderr);
				ctx->too_big = true;
				return;
			}
			line = newline + 1;
		}

		// Move the beginning of the next line to the beginning of the
		// buffer. We cannot use strcpy here because the memory areas
		// might overlap!
		int n = strlen(line);
		memmove(ctx->buf, line, n);
		ctx->ptr = ctx->buf + n;
	}
}


/* Returns an exit code; EXIT_NO_MANIFEST means "try the next mirror" */
static enum exit_code fetch(const char *mirror, const struct settings *s) {
	enum exit_code ret = EXIT_NO_MANIFEST;
	struct recv_manifest_ctx ctx = { };
	ctx.ptr = ctx.buf;
	struct manifest *m = &ctx.m;

	char url[strlen(mirror) + strlen(manifest_name) + 2];
	sprintf(url, "%s/%s", mirror, manifest_name);

	fprintf(stderr, "nodeplacer-fetch: retrieving %s ...\n", url);

	ecdsa_sha256_init(&m->hash_ctx);
	int err_code = get_url(url, recv_manifest_cb, &ctx, -1, NULL);
	if (err_code != 0) {
		fprintf(stderr, "nodeplacer-fetch: warning: error downloading manifest: %s\n", uclient_get_errmsg(err_code));
		goto out;
	}

	if (ctx.too_long || ctx.too_big)
		goto out;

	/* a trailing line without newline is still part of the manifest */
	if (ctx.ptr != ctx.buf) {
		*ctx.ptr = '\0';
		parse_line(ctx.buf, m, MAX_BODY_BYTES);
	}

	/* Check manifest signatures */
	{
		ecc_int256_t hash;
		ecdsa_sha256_final(&m->hash_ctx, hash.p);
		ecdsa_verify_context_t ctxs[m->n_signatures];
		for (size_t i = 0; i < m->n_signatures; i++)
			ecdsa_verify_prepare_legacy(&ctxs[i], &hash, m->signatures[i]);

		long unsigned int good_signatures = ecdsa_verify_list_legacy(ctxs, m->n_signatures, s->pubkeys, s->n_pubkeys);
		if (good_signatures < s->good_signatures) {
			fprintf(stderr, "nodeplacer-fetch: warning: manifest %s only carried %lu valid signatures, %lu are required\n", url, good_signatures, s->good_signatures);
			ret = EXIT_REJECTED;
			goto out;
		}
	}

	/* Check header (signed, so only now) */
	if (!m->format_ok) {
		fprintf(stderr, "nodeplacer-fetch: warning: manifest %s has no or an unsupported FORMAT (supported: " MANIFEST_FORMAT ")\n", url);
		ret = EXIT_REJECTED;
		goto out;
	}

	if (!m->date_ok || !m->expires_ok) {
		fprintf(stderr, "nodeplacer-fetch: warning: manifest %s is missing DATE or EXPIRES\n", url);
		ret = EXIT_REJECTED;
		goto out;
	}

	if (m->expires <= m->date) {
		fprintf(stderr, "nodeplacer-fetch: warning: manifest %s has EXPIRES before DATE\n", url);
		ret = EXIT_REJECTED;
		goto out;
	}

	{
		time_t now = time(NULL);

		if (now < m->date) {
			/* Either the manifest is from the future or our clock is wrong.
			 * Like the autoupdater we assume the latter; shortly after boot
			 * NTP may simply not have synced yet, so wait for the next run. */
			fputs("nodeplacer-fetch: warning: clock seems to be incorrect.\n", stderr);
			if (get_uptime() < 600) {
				ret = EXIT_NO_MANIFEST;
				goto out;
			}
		}
		else if (now > m->expires) {
			fprintf(stderr, "nodeplacer-fetch: warning: manifest %s expired\n", url);
			ret = EXIT_REJECTED;
			goto out;
		}
	}

	/* Verified: hand the body to the policy side */
	if (m->body_len) {
		fwrite(m->body, 1, m->body_len, stdout);
		fflush(stdout);
	}
	ret = EXIT_VERIFIED;

out:
	clear_manifest(m);
	return ret;
}


int main(int argc, char *argv[]) {
	struct settings s = { };
	parse_args(argc, argv, &s);

	bool external_mirrors = s.n_mirrors > 0;
	load_settings(&s);
	randomize();

	uloop_init();

	size_t mirrors_left = s.n_mirrors;
	while (mirrors_left) {
		const char **mirror = s.mirrors;
		size_t i = external_mirrors ? 0 : random() % mirrors_left;

		/* Move forward by i non-NULL entries */
		while (true) {
			while (!*mirror)
				mirror++;

			if (!i)
				break;

			mirror++;
			i--;
		}

		enum exit_code ret = fetch(*mirror, &s);
		if (ret != EXIT_NO_MANIFEST) {
			/* verified, or found and rejected: do not ask another mirror */
			uloop_done();
			return ret;
		}

		/* mirror had no usable manifest: remove it from the list */
		*mirror = NULL;
		mirrors_left--;
	}

	uloop_done();

	fputs("nodeplacer-fetch: no manifest found on any mirror\n", stderr);
	return EXIT_NO_MANIFEST;
}
