/* SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
   SPDX-License-Identifier: BSD-3-Clause

   One-page setup: counts changes per group, writes the state line of each
   collapsed group, opens groups from the side menu, refuses to submit while
   gluon-web-model marks a field invalid, and warns before leaving with
   unsaved changes. Dependencies and field checks stay gluon-web-model.js. */
(function () {
	'use strict';
	var T = window.nfText || {};
	var form = document.getElementById('nf-form');
	if (!form) return;
	var statusEl = document.getElementById('nf-status');
	var saveBtn = document.getElementById('nf-save');
	var submitting = false;

	function each(sel, root, fn) {
		Array.prototype.forEach.call((root || document).querySelectorAll(sel), fn);
	}
	function fmt(one, many, n) { return n === 1 ? one : many.replace('%d', n); }

	/* ---------- values and changes ---------- */
	function snap() {
		var o = {};
		each('input[name], select[name], textarea[name]', form, function (el) {
			var n = el.name, v;
			if (el.type === 'hidden' || el.type === 'submit') return;
			if (el.type === 'checkbox') v = el.checked ? el.value || '1' : '';
			else if (el.type === 'radio') v = el.checked ? el.value : '';
			else v = el.value;
			if (el.type === 'checkbox' || el.type === 'radio') {
				if (v) o[n] = (o[n] ? o[n] + '\n' : '') + v;
				else if (!(n in o)) o[n] = '';
			} else {
				o[n] = (n in o) ? o[n] + '\n' + v : v;
			}
		});
		return o;
	}
	function secOf(name) {
		var el = form.querySelector('[name="' + name.replace(/"/g, '\\"') + '"]');
		var s = el && el.closest('[data-sec]');
		return s ? s.getAttribute('data-sec') : null;
	}

	var initial = snap();
	var dirty = [];
	/* After a rejected save the page shows the user's input, not what is
	   stored: leaving it would lose that input just the same. */
	var rejected = !!document.getElementById('nf-problem');

	/* ---------- state line of the collapsed groups ---------- */
	function rows(g) {
		var out = [];
		each('.row', g, function (r) { out.push(r); });
		return out;
	}
	function label(r) {
		var l = r.querySelector('.lbl');
		if (!l) return '';
		var c = l.cloneNode(true);
		each('.help', c, function (h) { h.remove(); });
		return c.textContent.trim();
	}
	function value(r) {
		var sel = r.querySelector('.ctl select');
		if (sel && sel.selectedIndex >= 0) return sel.options[sel.selectedIndex].text.trim();
		var radio = r.querySelector('.ctl input[type=radio]:checked');
		if (radio) return radio.closest('label').textContent.trim();
		var multi = [];
		each('.ctl label > input[type=checkbox]:checked', r, function (c) { multi.push(c.closest('label').textContent.trim()); });
		if (multi.length) return multi.join(' + ');
		var vals = [];
		each('.ctl input[type=text]', r, function (i) { if (i.value.trim()) vals.push(i.value.trim()); });
		return vals.join(', ');
	}
	function flagOn(r) {
		var c = r.querySelector('.ctl > input[type=checkbox]');
		return c && c.checked;
	}

	var special = {
		'wifi-config': function (g) {
			var parts = [];
			each('.nf-section', g, function (s) {
				var head = s.querySelector(':scope > .subhead');
				var client = s.querySelector('input[name$="_client_enabled"]');
				var mesh = s.querySelector('input[name$="_mesh_enabled"]');
				if (!head || (!client && !mesh)) return;
				var t = client && client.checked ? T.client : T.noclient;
				if (mesh && mesh.checked) t += ' + ' + T.mesh;
				parts.push(head.textContent.trim() + ': ' + t);
			});
			return parts.join(' · ');
		},
		'remote': function (g) {
			var ta = g.querySelector('textarea');
			var n = ta ? ta.value.split('\n').filter(function (l) { return l.trim(); }).length : 0;
			return n ? fmt(T.keys1, T.keysN, n) : T.keys0;
		}
	};

	function summary(g) {
		var key = g.getAttribute('data-sec');
		if (special[key]) return special[key](g);
		var rs = rows(g);
		if (!rs.length) return '';
		/* A group that starts with an on/off switch: its state, and when on,
		   the first two values below it. */
		if (rs[0].classList.contains('flag')) {
			if (!flagOn(rs[0])) return T.off;
			var more = [T.on];
			for (var i = 1; i < rs.length && more.length < 3; i++) {
				if (rs[i].classList.contains('flag') || rs[i].querySelector('input[type=password]')) continue;
				var v = value(rs[i]);
				if (v) more.push(v);
			}
			return more.join(' · ');
		}
		/* Otherwise the first two choices with their labels. */
		var parts = [];
		for (var j = 0; j < rs.length && parts.length < 2; j++) {
			if (rs[j].classList.contains('flag')) continue;
			var val = value(rs[j]);
			if (val) parts.push((label(rs[j]) ? label(rs[j]) + ' ' : '') + val);
		}
		return parts.join(' · ');
	}

	function setStatus(text, cls) {
		statusEl.className = 'status' + (cls ? ' ' + cls : '');
		statusEl.innerHTML = '';
		if (cls === 'dirty') {
			var d = document.createElement('span');
			d.className = 'dot';
			statusEl.appendChild(d);
		}
		var s = document.createElement('span');
		s.textContent = text;
		statusEl.appendChild(s);
	}

	function update() {
		var now = snap();
		var keys = {};
		Object.keys(initial).forEach(function (k) { keys[k] = 1; });
		Object.keys(now).forEach(function (k) { keys[k] = 1; });
		dirty = Object.keys(keys).filter(function (k) { return (initial[k] || '') !== (now[k] || ''); });
		var secs = {};
		dirty.forEach(function (k) { var s = secOf(k); if (s) secs[s] = true; });
		each('[data-dot]', null, function (d) { d.hidden = !secs[d.getAttribute('data-dot')]; });
		each('details.group', form, function (g) {
			var pill = g.querySelector('.changed-pill');
			if (pill) pill.hidden = !secs[g.getAttribute('data-sec')];
			var st = g.querySelector('.sum-state');
			if (st) st.textContent = summary(g);
		});
		if (submitting) return;
		if (!dirty.length) setStatus(T.nochanges);
		else setStatus(fmt(T.change1, T.changeN, dirty.length), 'dirty');
	}
	form.addEventListener('input', function () { setTimeout(update, 0); });
	form.addEventListener('change', function () { setTimeout(update, 0); });
	form.addEventListener('click', function () { setTimeout(update, 0); });

	/* ---------- side menu opens collapsed groups ---------- */
	each('a[data-open]', null, function (a) {
		a.addEventListener('click', function () {
			var t = document.querySelector(a.getAttribute('href'));
			if (t && t.tagName === 'DETAILS') t.open = true;
		});
	});

	/* ---------- problems: open, scroll, focus ---------- */
	function reveal(el) {
		var det = el.closest('details');
		if (det) det.open = true;
		el.scrollIntoView({ block: 'center', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
		var f = el.matches('input, select, textarea') ? el : el.querySelector('input:not([type=hidden]), select, textarea');
		if (f) f.focus({ preventScroll: true });
	}

	/* Enter in a text field would press "Save & restart". */
	form.addEventListener('keydown', function (e) {
		if (e.key === 'Enter' && e.target.tagName === 'INPUT' && e.target.type !== 'submit') e.preventDefault();
	});

	form.addEventListener('submit', function (e) {
		var bad = [];
		each('.gluon-input-invalid', form, function (el) { bad.push(el); });
		if (bad.length) {
			e.preventDefault();
			each('.row.invalid', form, function (r) { r.classList.remove('invalid'); });
			bad.forEach(function (el) { var r = el.closest('.row'); if (r) r.classList.add('invalid'); });
			reveal(bad[0]);
			setStatus(fmt(T.invalid1, T.invalidN, bad.length), 'bad');
			return;
		}
		submitting = true;
		saveBtn.disabled = true;
		setStatus(T.saving);
	});

	window.addEventListener('beforeunload', function (e) {
		if ((dirty.length || rejected) && !submitting) { e.preventDefault(); e.returnValue = ''; }
	});

	update();
	var first = form.querySelector('.row.invalid, .nf-msg-error');
	if (first) reveal(first);
})();
