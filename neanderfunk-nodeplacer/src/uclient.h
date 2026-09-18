// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2017 Jan-Philipp Litza <janphilipp@litza.de>
#pragma once


#include <libubox/uclient.h>
#include <sys/types.h>


struct uclient_data {
	/* data that can be passed in by caller and used in custom callbacks */
	void *custom;
	/* data used by uclient callbacks */
	int retries;
	int err_code;
	ssize_t downloaded;
	ssize_t length;
};

inline struct uclient_data * uclient_data(struct uclient *cl) {
	return (struct uclient_data *)cl->priv;
}

inline void * uclient_get_custom(struct uclient *cl) {
	return uclient_data(cl)->custom;
}


ssize_t uclient_read_account(struct uclient *cl, char *buf, int len);

/* Stop the running request from inside a read callback.
 *
 * The manifest parser can often tell well before the end of a transfer that
 * what is arriving cannot be a manifest. It should then hang up rather than
 * read on, so that the far side never decides how long a run takes.
 *
 * get_url() returns 0 afterwards; the caller knows from its own state why it
 * aborted. */
void uclient_abort_request(struct uclient *cl);

int get_url(const char *url, void (*read_cb)(struct uclient *cl), void *cb_data, ssize_t len, const char *firmware_version);
const char *uclient_get_errmsg(int code);
int uclient_interrupted_signal(int code);
