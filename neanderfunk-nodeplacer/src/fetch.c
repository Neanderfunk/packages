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

/* Hard ceiling on what we will read from a mirror at all. MAX_BODY_BYTES only
 * bounds the part before "---", so this bounds the rest as well. A real
 * manifest is a few kilobytes: 320 KiB is the body cap plus generous room for
 * MAX_SIGNATURES lines, and still over in moments on any link we have. */
#define MAX_MANIFEST_BYTES (320 * 1024)
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

/* -v: report every step of the search, not just its result.
 *
 * File scope rather than a field in struct settings because the two places
 * that decide "this is not a manifest" while the body is still arriving live
 * in the uclient callback, which only gets the receive context.
 *
 * What it covers is exactly the class "this mirror has no manifest for us" -
 * unreachable, 404, an HTML page, something too large. That is the normal
 * state whenever nodeplacer is not in use, so by default it produces a single
 * summary line at the end instead of one line per mirror and step. A manifest
 * that is actually there but unusable - bad signatures, wrong FORMAT, expired
 * - is a different class and stays loud, with no -v needed. */
static bool verbose;

struct recv_manifest_ctx {
	struct manifest m;
	char buf[MAX_LINE_LENGTH + 1];
	char *ptr;
	size_t received;
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
		"  -v, --verbose        Report every mirror tried and why it had no manifest.\n"
		"                       Without it, a run that finds nothing anywhere says so in\n"
		"                       a single line: that is the normal state while nodeplacer\n"
		"                       is not in use, and this runs from cron on every node. A\n"
		"                       manifest that is there but unusable (bad signatures,\n"
		"                       unsupported FORMAT, expired) is reported either way.\n\n"
		"  <mirror> ...         Override the mirror URLs given in the configuration. If\n"
		"                       specified, these are not shuffled.\n\n"
		"Exit codes: 0 verified, 1 config error, 2 no manifest, 3 rejected.\n\n",
		stderr
	);
}


static void parse_args(int argc, char *argv[], struct settings *settings) {
	const struct option options[] = {
		{"help", no_argument, NULL, 'h'},
		{"verbose", no_argument, NULL, 'v'},
		{}
	};

	while (true) {
		int c = getopt_long(argc, argv, "hv", options, NULL);
		if (c < 0)
			break;

		switch (c) {
		case 'h':
			usage();
			exit(0);

		case 'v':
			verbose = true;
			break;

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

/* The autoupdater branch section the node is currently running, or NULL */
static struct uci_section * autoupdater_branch(struct uci_context *ctx, const char **branch_name) {
	/* May be called twice on the same context (mirrors, then keys and
	 * threshold); a second uci_load() of a loaded package fails. */
	struct uci_package *ap = uci_lookup_package(ctx, "autoupdater");
	if (!ap && uci_load(ctx, "autoupdater", &ap) != UCI_OK)
		return NULL;

	struct uci_section *as = uci_lookup_section(ctx, ap, "settings");
	const char *branch = as ? uci_lookup_option_string(ctx, as, "branch") : NULL;
	struct uci_section *bs = branch ? uci_lookup_section(ctx, ap, branch) : NULL;
	if (!bs || strcmp(bs->type, "branch"))
		return NULL;

	if (branch_name)
		*branch_name = branch;

	return bs;
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

	if (settings->n_mirrors == 0) {
		settings->mirrors = load_string_list(ctx, s, "mirror", &settings->n_mirrors);
		/* Default (D-042): without mirrors in the site configuration the
		 * manifest is looked for next to the firmware manifest, on the
		 * mirrors of the autoupdater branch this node is running - the
		 * same branch the keys and the threshold default to (D-031). */
		if (settings->n_mirrors == 0) {
			struct uci_section *bs = autoupdater_branch(ctx, NULL);
			if (bs)
				settings->mirrors = load_string_list(ctx, bs, "mirror", &settings->n_mirrors);
		}
		if (settings->n_mirrors == 0) {
			fputs("nodeplacer-fetch: error: no mirrors configured, and the autoupdater branch has none either\n", stderr);
			exit(EXIT_CONFIG);
		}
	}

	const char *own_threshold = uci_lookup_option_string(ctx, s, "good_signatures");

	size_t n_pubkeys_str;
	const char **pubkeys_str = load_string_list(ctx, s, "pubkey", &n_pubkeys_str);

	/* Trust anchor: by default the control file is verified with the keys
	 * and the threshold of the autoupdater branch this node is running.
	 * Whoever may release a firmware for this node may also move it.
	 * The site configuration can override either, but usually should not. */
	if (!own_threshold || n_pubkeys_str == 0) {
		const char *branch = NULL;
		struct uci_section *bs = autoupdater_branch(ctx, &branch);
		if (!bs) {
			fputs("nodeplacer-fetch: error: no autoupdater branch configured to take the keys "
			      "and the signature threshold from, and none given in the site configuration\n", stderr);
			exit(EXIT_CONFIG);
		}

		if (!own_threshold)
			settings->good_signatures = load_positive_number(ctx, bs, "good_signatures");

		if (n_pubkeys_str == 0)
			pubkeys_str = load_string_list(ctx, bs, "pubkey", &n_pubkeys_str);
	}

	if (own_threshold)
		settings->good_signatures = load_positive_number(ctx, s, "good_signatures");

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
			/* Quiet by default like the other "no manifest here" cases:
			 * an HTML page from a catch-all regularly arrives as one
			 * very long line, so this fires on a mirror that simply has
			 * no manifest. */
			if (verbose)
				fputs("nodeplacer-fetch: line exceeds the limit of " STRINGIFY(MAX_LINE_LENGTH) " characters, not a manifest\n", stderr);
			ctx->too_long = true;
			uclient_abort_request(cl);
			return;
		}
		len = uclient_read_account(cl, ctx->ptr, MAX_LINE_LENGTH - (ctx->ptr - ctx->buf));
		if (len <= 0)
			break;
		ctx->ptr[len] = '\0';

		ctx->received += (size_t)len;
		if (ctx->received > MAX_MANIFEST_BYTES) {
			if (verbose)
				fputs("nodeplacer-fetch: response exceeds " STRINGIFY(MAX_MANIFEST_BYTES) " bytes, not a manifest\n", stderr);
			ctx->too_big = true;
			uclient_abort_request(cl);
			return;
		}

		char *line = ctx->buf;
		while (true) {
			newline = strchr(line, '\n');
			if (newline == NULL)
				break;
			*newline = '\0';

			if (!parse_line(line, &ctx->m, MAX_BODY_BYTES)) {
				/* Body over the cap, or more signature lines than a
				 * manifest may carry. Either way this is not one of
				 * ours, so stop reading. */
				if (verbose)
					fputs("nodeplacer-fetch: body over " STRINGIFY(MAX_BODY_BYTES) " bytes or too many signatures, not a manifest\n", stderr);
				ctx->too_big = true;
				uclient_abort_request(cl);
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

	if (verbose)
		fprintf(stderr, "nodeplacer-fetch: retrieving %s ...\n", url);

	ecdsa_sha256_init(&m->hash_ctx);
	int err_code = get_url(url, recv_manifest_cb, &ctx, -1, NULL);

	/* Our own verdict first: when we hung up mid-transfer, get_url may
	 * report a size mismatch, which would only be a confusing way of saying
	 * what we already decided. */
	if (ctx.too_long || ctx.too_big)
		goto out;

	if (err_code != 0) {
		/* Unreachable or 404. Both mean "no manifest on this mirror",
		 * which is the normal state and must not cost a log line on
		 * every node every hour - the reserve mirrors carry no DNS on
		 * purpose, so one of these is guaranteed on every single run. */
		if (verbose)
			fprintf(stderr, "nodeplacer-fetch: %s: %s\n", url, uclient_get_errmsg(err_code));
		goto out;
	}

	/* a trailing line without newline is still part of the manifest */
	if (ctx.ptr != ctx.buf) {
		*ctx.ptr = '\0';
		parse_line(ctx.buf, m, MAX_BODY_BYTES);
	}

	/* No "---" at all: whatever came back is not a manifest. Some web
	 * servers answer every path with 200 and an HTML page (catch-all), so
	 * a mirror without a manifest can look like one that has a bad one.
	 * Treat it as absent - quiet, and on to the next mirror - instead of
	 * as rejected, which would be logged on every run. A real manifest
	 * without signatures still has the separator and is rejected below.
	 *
	 * The exit code already said "absent", but the warning below was
	 * printed anyway, so the case was quiet in name only: measured on
	 * 18.09.2026, every node in the fleet logged this once an hour,
	 * because firmware.ffnef.de answers that path with 200 and an HTML
	 * page. Behind -v, so a mirror that really is misconfigured can still
	 * be told apart from one that simply has no manifest - by hand, not in
	 * everyone's syslog. */
	if (!m->sep_found) {
		if (verbose)
			fprintf(stderr, "nodeplacer-fetch: %s is not a manifest (no \"---\" line)\n", url);
		goto out;
	}

	/* There is a separator, so this claims to be a manifest: unparsable
	 * lines in its signature area are worth reporting. Once, with a count -
	 * never one line per offending line, see garbage_sigs in manifest.h. */
	if (m->garbage_sigs)
		fprintf(stderr, "nodeplacer-fetch: warning: manifest %s has %zu unparsable line(s) in its signature area\n",
			url, m->garbage_sigs);

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

	/* The one line a fruitless run is allowed to cost. Everything that led
	 * here - unreachable mirrors, 404s, catch-all HTML pages - is the normal
	 * state while nodeplacer is not in use and stays behind -v; this says
	 * that the search ran and found nothing, which is worth one line an hour
	 * because it also proves the mechanism is alive. */
	fprintf(stderr, "nodeplacer-fetch: no manifest on any of the %zu mirrors (-v says which and why)\n",
		s.n_mirrors);
	return EXIT_NO_MANIFEST;
}
