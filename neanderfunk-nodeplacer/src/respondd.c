/* SPDX-FileCopyrightText: 2016, Matthias Schiffer <mschiffer@universe-factory.net> */
/* SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk */
/* SPDX-License-Identifier: BSD-2-Clause */
/* Derived from gluon-autoupdater/src/respondd.c */

#include <respondd.h>

#include <json-c/json.h>
#include <libgluonutil.h>

#include <uci.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


static const char *const state_file = "/tmp/nodeplacer.state";


static void add_state(struct json_object *obj) {
	FILE *f = fopen(state_file, "r");
	if (!f)
		return;

	char line[512];
	while (fgets(line, sizeof(line), f)) {
		char *nl = strchr(line, '\n');
		if (nl)
			*nl = '\0';

		char *eq = strchr(line, '=');
		if (!eq)
			continue;
		*eq = '\0';
		const char *key = line, *value = eq + 1;

		if (!strcmp(key, "target") && *value)
			json_object_object_add(obj, "target", json_object_new_string(value));
		else if (!strcmp(key, "attempts"))
			json_object_object_add(obj, "attempts", json_object_new_int(atoi(value)));
		else if (!strcmp(key, "last_date"))
			json_object_object_add(obj, "last_manifest_date", json_object_new_int64(atoll(value)));
	}

	fclose(f);
}

static struct json_object * get_nodeplacer(void) {
	struct uci_context *ctx = uci_alloc_context();
	if (!ctx)
		return NULL;
	ctx->flags &= ~UCI_FLAG_STRICT;

	struct uci_package *p;
	if (uci_load(ctx, "nodeplacer", &p))
		goto error;

	struct uci_section *s = uci_lookup_section(ctx, p, "settings");
	if (!s)
		goto error;

	struct json_object *ret = json_object_new_object();

	const char *disable = uci_lookup_option_string(ctx, s, "disable");
	json_object_object_add(ret, "enabled", json_object_new_boolean(!(disable && !strcmp(disable, "1"))));

	add_state(ret);

	uci_free_context(ctx);

	return ret;

error:
	uci_free_context(ctx);
	return NULL;
}

static struct json_object * respondd_provider_nodeinfo(void) {
	struct json_object *ret = json_object_new_object();

	struct json_object *software = json_object_new_object();
	json_object_object_add(software, "nodeplacer", get_nodeplacer());
	json_object_object_add(ret, "software", software);

	return ret;
}


const struct respondd_provider_info respondd_providers[] = {
	{"nodeinfo", respondd_provider_nodeinfo},
	{}
};
