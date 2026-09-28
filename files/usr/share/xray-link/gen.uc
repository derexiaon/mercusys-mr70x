// Build Xray configs from share links (vless://, trojan://, ss://,
// hysteria2:// / hy2://) and subscriptions (plain or base64 lists).
//
//   ucode gen.uc out=DIR [dns_port=5353] [upstream_dns=1.1.1.1] [server=auto]
//                [max=10] [exclude=1,3] SOURCE_FILE...
//
// Writes into DIR:
//   config.json   config with the TUN inbound (for /etc/xray/config.json)
//   test.json     same without TUN ("xray run -test" really opens the device)
//   test-N.json   only server N, to find the one xray rejects
//   servers       "N<TAB>protocol<TAB>host:port<TAB>name" per server
//   hosts         server addresses, one per line
//   errors        skipped links and why
//   count         number of servers in config.json

'use strict';

import { readfile, writefile } from 'fs';

const opts = {
	out: null, dns_port: 5353, upstream_dns: '1.1.1.1', server: 'auto', max: 10, exclude: {}
};
const sources = [];

for (let arg in ARGV) {
	let m = match(arg, /^([a-z_]+)=(.*)$/s);
	if (!m) {
		push(sources, arg);
	}
	else if (m[1] == 'exclude') {
		for (let i in split(m[2], ','))
			if (length(i))
				opts.exclude[int(i)] = true;
	}
	else if (m[1] in ['dns_port', 'max']) {
		opts[m[1]] = int(m[2]);
	}
	else {
		opts[m[1]] = m[2];
	}
}

if (!opts.out)
	die('out=DIR is required\n');

let errors = [];

function urldecode(s) {
	return replace(s ?? '', /%([0-9A-Fa-f]{2})/g, (all, h) => chr(hex(h)));
}

function b64(s) {
	s = replace(s ?? '', /[\r\n\t ]/g, '');
	s = replace(replace(s, /-/g, '+'), /_/g, '/');
	s = replace(s, /=+$/, '');
	while (length(s) % 4)
		s += '=';
	return b64dec(s);
}

function parse_query(q) {
	let r = {};
	for (let kv in split(q ?? '', '&')) {
		if (!length(kv))
			continue;
		let i = index(kv, '=');
		if (i < 0)
			r[urldecode(kv)] = '';
		else
			r[urldecode(substr(kv, 0, i))] = urldecode(substr(kv, i + 1));
	}
	return r;
}

// scheme://user@host:port[,ports][/path][?query][#name]
function parse_uri(link) {
	let m = match(link, /^([A-Za-z0-9]+):\/\/([^#]*)(#(.*))?$/s);
	if (!m)
		return null;

	let r = { scheme: lc(m[1]), name: trim(urldecode(m[4] ?? '')), query: {}, user: null, path: '' };
	let rest = m[2];

	let qi = index(rest, '?');
	if (qi >= 0) {
		r.query = parse_query(substr(rest, qi + 1));
		rest = substr(rest, 0, qi);
	}

	let at = rindex(rest, '@');
	if (at >= 0) {
		r.user = substr(rest, 0, at);
		rest = substr(rest, at + 1);
	}

	let si = index(rest, '/');
	if (si >= 0) {
		r.path = substr(rest, si);
		rest = substr(rest, 0, si);
	}

	let hm = match(rest, /^\[([0-9A-Fa-f:.]+)\]:(.+)$/) ?? match(rest, /^([^:]+):(.+)$/);
	if (!hm)
		return null;

	r.host = hm[1];
	r.portspec = hm[2];

	let pm = match(r.portspec, /^([0-9]+)/);
	if (!pm)
		return null;

	r.port = int(pm[1]);
	if (r.port < 1 || r.port > 65535)
		return null;

	return r;
}

// Reject a link: caught in the main loop and reported in "errors".
function fail(msg) {
	die(`SKIP:${msg}`);
}

function csv(s) {
	return filter(map(split(s ?? '', ','), trim), length);
}

// Xray 26 dropped "allowInsecure": self-signed servers need a pinned
// certificate hash (pinSHA256 in hysteria2 links, pcs in Xray links).
function tls_verify(tls, q) {
	let pin = q.pinSHA256 || q.pcs;

	if (pin)
		tls.pinnedPeerCertSha256 = pin;
	else if (q.insecure == '1' || q.allowInsecure == '1')
		fail('insecure=1 без pinSHA256/pcs: Xray 26 больше не разрешает отключать проверку сертификата, попросите у провайдера хеш сертификата');

	if (q.vcn)
		tls.verifyPeerCertByName = q.vcn;
}

// TLS / REALITY + transport settings shared by vless and trojan
function stream_settings(u, default_security) {
	let q = u.query;
	let type = lc(q.type || 'tcp');
	let network = { tcp: 'raw', raw: 'raw', xhttp: 'xhttp', splithttp: 'xhttp', ws: 'ws', httpupgrade: 'httpupgrade' }[type];

	if (!network)
		fail(`транспорт "${type}" не включён в облегчённую сборку Xray`);

	if (network == 'raw' && q.headerType && q.headerType != 'none')
		fail(`headerType=${q.headerType} не поддерживается`);

	let security = lc(q.security || default_security);
	let s = { network, security };

	if (security == 'reality') {
		if (!q.pbk)
			fail('в ссылке reality нет pbk');

		s.realitySettings = {
			serverName: q.sni || q.peer || '',
			fingerprint: q.fp || 'chrome',
			publicKey: q.pbk,
			shortId: q.sid || ''
		};

		if (q.spx)
			s.realitySettings.spiderX = q.spx;

		if (q.pqv)
			s.realitySettings.mldsa65Verify = q.pqv;
	}
	else if (security == 'tls') {
		s.tlsSettings = { fingerprint: q.fp || 'chrome' };

		if (q.sni || q.peer)
			s.tlsSettings.serverName = q.sni || q.peer;

		if (q.alpn)
			s.tlsSettings.alpn = csv(q.alpn);

		tls_verify(s.tlsSettings, q);
	}
	else if (security != 'none') {
		fail(`security "${security}" не поддерживается`);
	}

	if (network == 'ws' || network == 'httpupgrade' || network == 'xhttp') {
		let t = { path: q.path || '/' };

		if (q.host)
			t.host = q.host;

		if (network == 'xhttp') {
			t.mode = q.mode || 'auto';

			if (q.extra) {
				let extra = json(q.extra);

				if (type(extra) == 'object')
					t.extra = extra;
			}
		}

		s[network + 'Settings'] = t;
	}

	return s;
}

function vless(u) {
	if (!u.user)
		fail('нет UUID');

	let settings = {
		address: u.host,
		port: u.port,
		id: urldecode(u.user),
		encryption: u.query.encryption || 'none'
	};

	if (u.query.flow)
		settings.flow = u.query.flow;

	return { protocol: 'vless', settings, streamSettings: stream_settings(u, 'none') };
}

function trojan(u) {
	if (!u.user)
		fail('нет пароля');

	return {
		protocol: 'trojan',
		settings: { address: u.host, port: u.port, password: urldecode(u.user) },
		streamSettings: stream_settings(u, 'tls')
	};
}

const ss_methods = [
	'aes-128-gcm', 'aes-256-gcm', 'chacha20-poly1305', 'chacha20-ietf-poly1305',
	'xchacha20-poly1305', 'xchacha20-ietf-poly1305', 'none', 'plain',
	'2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305'
];

function shadowsocks(link) {
	let u = parse_uri(link);
	let userinfo;

	if (u && u.user != null) {
		// SIP002: ss://base64(method:password)@host:port or ss://method:password@host:port
		userinfo = urldecode(u.user);
		if (index(userinfo, ':') < 0)
			userinfo = b64(u.user);
	}
	else {
		// legacy: ss://base64(method:password@host:port)#name
		let m = match(link, /^ss:\/\/([^#?\/]*)[^#]*(#(.*))?$/s);
		let plain = m ? b64(m[1]) : null;

		if (!plain)
			fail('не удалось декодировать ss://');

		u = parse_uri(`ss://${plain}${m[2] ?? ''}`);
		if (!u || u.user == null)
			fail('не удалось разобрать ss://');

		userinfo = u.user;
	}

	if (u.query.plugin)
		fail(`плагин ss "${u.query.plugin}" не поддерживается`);

	let ci = index(userinfo ?? '', ':');
	if (ci < 0)
		fail('в ss:// нет method:password');

	let method = lc(substr(userinfo, 0, ci));
	if (!(method in ss_methods))
		fail(`шифр ss "${method}" не поддерживается`);

	u.parsed = {
		protocol: 'shadowsocks',
		settings: { address: u.host, port: u.port, method, password: substr(userinfo, ci + 1) },
		streamSettings: { network: 'raw', security: 'none' }
	};

	return u;
}

function hysteria2(u) {
	let q = u.query;

	if (u.user == null)
		fail('нет пароля (auth)');

	let tls = { serverName: q.sni || q.peer || u.host, alpn: q.alpn ? csv(q.alpn) : [ 'h3' ] };

	tls_verify(tls, q);

	let s = {
		network: 'hysteria',
		security: 'tls',
		tlsSettings: tls,
		hysteriaSettings: { version: 2, auth: urldecode(u.user) }
	};

	let finalmask = {};

	if (q.obfs && q.obfs != 'none') {
		if (q.obfs != 'salamander')
			fail(`obfs "${q.obfs}" не поддерживается`);

		finalmask.udp = [ { type: 'salamander', settings: { password: q['obfs-password'] ?? '' } } ];
	}

	// port hopping: host:443,20000-30000 or ?mport=20000-30000
	let hop = q.mport || (match(u.portspec, /[,-]/) ? u.portspec : null);
	if (hop)
		finalmask.quicParams = { udpHop: { ports: hop, interval: '30' } };

	if (length(finalmask))
		s.finalmask = finalmask;

	return {
		protocol: 'hysteria',
		settings: { version: 2, address: u.host, port: u.port },
		streamSettings: s
	};
}

function parse_link(link) {
	let scheme = lc(match(link, /^([A-Za-z0-9]+):\/\//)?.[1] ?? '');
	let u, ob;

	if (!(scheme in [ 'vless', 'trojan', 'ss', 'hysteria2', 'hy2' ]))
		fail(`протокол "${scheme}" не поддерживается (есть: vless, hysteria2, trojan, ss)`);

	if (scheme == 'ss') {
		u = shadowsocks(link);
		ob = u.parsed;
	}
	else {
		u = parse_uri(link);
		if (!u)
			fail('не удалось разобрать ссылку');

		switch (scheme) {
		case 'vless':     ob = vless(u); break;
		case 'trojan':    ob = trojan(u); break;
		case 'hysteria2':
		case 'hy2':       ob = hysteria2(u); break;
		}
	}

	return {
		outbound: ob,
		host: u.host,
		label: `${ob.protocol} ${u.host}:${u.port}`,
		name: u.name || `${ob.protocol} ${u.host}:${u.port}`
	};
}

// Collect links from all sources; a source may be a base64 subscription.
let links = [], seen = {};

for (let file in sources) {
	let text = readfile(file);

	if (!text)
		continue;

	if (index(text, '://') < 0) {
		let decoded = b64(text);

		if (decoded && index(decoded, '://') >= 0)
			text = decoded;
		else
			push(errors, `${file}: ссылки не найдены (неподдерживаемый формат подписки?)`);
	}

	for (let line in split(text, /\r?\n/)) {
		line = trim(line);

		if (!match(line, /^[A-Za-z0-9]+:\/\//) || seen[line])
			continue;

		seen[line] = true;
		push(links, line);
	}
}

let candidates = [];

for (let link in links) {
	let r;

	try {
		r = parse_link(link);
	}
	catch (e) {
		let why = replace(type(e) == 'object' ? e.message : `${e}`, /^SKIP:/, '');
		push(errors, `${substr(link, 0, 50)}...: ${why}`);
		continue;
	}

	if (length(candidates) >= opts.max) {
		push(errors, `${r.name}: больше ${opts.max} серверов (опция max_servers)`);
		continue;
	}

	push(candidates, r);
}

let servers = [];

for (let i, r in candidates)
	if (!opts.exclude[i + 1])
		push(servers, r);

for (let i, r in servers)
	r.outbound.tag = `proxy-${i + 1}`;

function build(with_tun) {
	let inbounds = [];

	if (with_tun)
		push(inbounds, { tag: 'tun-in', protocol: 'tun', settings: { name: 'xray0', MTU: 1500 } });

	push(inbounds, {
		tag: 'dns-in',
		listen: '127.0.0.1',
		port: opts.dns_port,
		protocol: 'dokodemo-door',
		settings: { address: opts.upstream_dns, port: 53, network: 'tcp,udp' }
	});

	let outbounds = map(servers, r => r.outbound);
	push(outbounds, { tag: 'direct', protocol: 'freedom' });
	push(outbounds, { tag: 'block', protocol: 'blackhole' });

	let cfg = { log: { loglevel: 'warning' }, inbounds, outbounds };
	let rule = { type: 'field', inboundTag: [ 'tun-in', 'dns-in' ] };
	let fixed = null;

	for (let r in servers)
		if (opts.server != 'auto' && r.name == opts.server)
			fixed = r.outbound.tag;

	if (fixed || length(servers) == 1) {
		rule.outboundTag = fixed ?? 'proxy-1';
		cfg.routing = { rules: [ rule ] };
	}
	else {
		// Several servers: pick the fastest alive one, switch when it fails.
		rule.balancerTag = 'auto';
		cfg.observatory = {
			subjectSelector: [ 'proxy-' ],
			probeURL: 'https://www.gstatic.com/generate_204',
			probeInterval: '2m',
			enableConcurrency: true
		};
		cfg.routing = {
			balancers: [ {
				tag: 'auto',
				selector: [ 'proxy-' ],
				strategy: { type: 'leastPing' },
				fallbackTag: 'proxy-1'
			} ],
			rules: [ rule ]
		};
	}

	return cfg;
}

const out = opts.out;

writefile(`${out}/config.json`, sprintf('%.J\n', build(true)));
writefile(`${out}/test.json`, sprintf('%.J\n', build(false)));

for (let i, r in candidates)
	writefile(`${out}/test-${i + 1}.json`, sprintf('%.J\n', { outbounds: [ r.outbound ] }));

let hosts = {};
let lines = [];

for (let i, r in servers) {
	hosts[r.host] = true;
	push(lines, join('\t', [ i + 1, r.outbound.protocol, replace(r.label, /^[a-z0-9]+ /, ''), replace(r.name, /[\t\n]/g, ' ') ]));
}

writefile(`${out}/servers`, length(lines) ? join('\n', lines) + '\n' : '');
writefile(`${out}/hosts`, length(hosts) ? join('\n', keys(hosts)) + '\n' : '');
writefile(`${out}/errors`, length(errors) ? join('\n', errors) + '\n' : '');
writefile(`${out}/count`, `${length(servers)} ${length(candidates)}\n`);
