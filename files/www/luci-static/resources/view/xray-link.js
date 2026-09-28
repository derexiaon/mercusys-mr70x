'use strict';
'require view';
'require fs';
'require uci';
'require ui';

function exec(cmd, args) {
	return fs.exec(cmd, args).then(function(res) {
		var out = [ res.stdout || '', res.stderr || '' ].join('\n').trim();
		ui.addNotification(null, E('pre', { 'style': 'white-space:pre-wrap' }, out || 'Готово'),
			res.code === 0 ? 'info' : 'danger');
		return res;
	}).catch(function(err) {
		ui.addNotification(null, E('p', {}, err.message), 'danger');
	});
}

function parseServers(text) {
	return (text || '').split('\n').filter(function(l) { return l.length; }).map(function(l) {
		var f = l.split('\t');
		return { idx: f[0], proto: f[1], addr: f[2], name: f[3] };
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.read('/etc/xray/links'), ''),
			L.resolveDefault(fs.read('/etc/xray/servers'), ''),
			L.resolveDefault(fs.exec('/etc/init.d/xray', [ 'status' ]), {}),
			L.resolveDefault(fs.exec('/sbin/logread', [ '-e', 'xray', '-l', '50' ]), {}),
			uci.load('xray')
		]);
	},

	render: function(data) {
		var links = (data[0] || '').trim(),
		    servers = parseServers(data[1]),
		    status = ((data[2] && data[2].stdout) || '').trim() || 'unknown',
		    log = (data[3] && data[3].stdout) || '',
		    sub = uci.get('xray', 'main', 'subscription') || '',
		    selected = uci.get('xray', 'main', 'server') || 'auto';

		var ta = E('textarea', {
			'class': 'cbi-input-textarea',
			'style': 'width:100%;font-family:monospace',
			'rows': 5,
			'spellcheck': 'false',
			'placeholder': 'vless://...\nhysteria2://...\ntrojan://...\nss://...'
		}, [ links ]);

		var subInput = E('input', {
			'class': 'cbi-input-text',
			'style': 'width:100%',
			'type': 'text',
			'spellcheck': 'false',
			'placeholder': 'https://panel.example.com/sub/...',
			'value': sub
		});

		var sel = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': 'auto' }, [ 'Автоматически (самый быстрый живой сервер)' ])
		]);
		servers.forEach(function(s) {
			sel.appendChild(E('option', { 'value': s.name }, [ s.name + ' (' + s.proto + ')' ]));
		});
		sel.value = servers.some(function(s) { return s.name === selected; }) ? selected : 'auto';

		var table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, [ '#' ]),
				E('th', { 'class': 'th' }, [ 'Название' ]),
				E('th', { 'class': 'th' }, [ 'Протокол' ]),
				E('th', { 'class': 'th' }, [ 'Адрес' ])
			])
		].concat(servers.map(function(s) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, [ s.idx ]),
				E('td', { 'class': 'td' }, [ s.name ]),
				E('td', { 'class': 'td' }, [ s.proto ]),
				E('td', { 'class': 'td' }, [ s.addr ])
			]);
		})));

		function field(label, widget, descr) {
			return E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, [ label ]),
				E('div', { 'class': 'cbi-value-field' }, [
					widget,
					descr ? E('div', { 'class': 'cbi-value-description' }, [ descr ]) : ''
				])
			]);
		}

		function button(cls, label, cmd, args) {
			return E('button', {
				'class': 'cbi-button ' + cls,
				'click': ui.createHandlerFn(null, function() {
					return exec(cmd, typeof args === 'function' ? args() : args);
				})
			}, [ label ]);
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ 'Xray' ]),
			E('div', { 'class': 'cbi-map-descr' }, [
				'Ссылки VLESS, Hysteria2, Trojan, Shadowsocks и/или подписка на VPN. ',
				'Какие сайты идут через VPN, настраивается в «Службы → Маршрутизация по политикам» (pbr). ',
				'Подписка обновляется каждый день в 05:20.'
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, [ E('strong', {}, [ 'Статус: ' ]), status ]),
				field('Подписка', subInput, 'URL подписки из панели VPN (3x-ui, Marzban, Remnawave…). Можно оставить пустым.'),
				field('Ссылки', ta, 'Свои серверы, по одной ссылке на строку. Используются вместе с подпиской.'),
				field('Сервер', sel, 'При нескольких серверах Xray раз в 2 минуты проверяет их и переключается на живой.'),
				E('div', { 'style': 'margin-top:1em;display:flex;flex-wrap:wrap;gap:.5em' }, [
					button('cbi-button-apply', 'Сохранить и применить', '/usr/bin/xray-link', function() {
						return [ '--set', ta.value.trim(), subInput.value.trim(), sel.value ];
					}),
					button('cbi-button-action', 'Обновить подписку', '/usr/bin/xray-link', [ '--update' ]),
					button('cbi-button-action', 'Перезапустить', '/etc/init.d/xray', [ 'restart' ]),
					button('cbi-button-reset', 'Остановить', '/etc/init.d/xray', [ 'stop' ]),
					button('', 'Обновить списки сайтов (pbr)', '/etc/init.d/pbr', [ 'restart' ])
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ 'Серверы' ]),
				servers.length ? table : E('p', {}, [ 'Пока нет — добавьте ссылку или подписку.' ])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ 'Журнал' ]),
				E('pre', { 'style': 'max-height:30em;overflow:auto;white-space:pre-wrap' }, [ log ])
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
