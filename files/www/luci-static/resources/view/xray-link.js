'use strict';
'require view';
'require fs';
'require ui';

function exec(cmd, args) {
	return fs.exec(cmd, args).then(function(res) {
		var out = [ res.stdout || '', res.stderr || '' ].join('\n').trim();
		ui.addNotification(null, E('pre', { 'style': 'white-space:pre-wrap' }, out || _('Done')),
			res.code === 0 ? 'info' : 'danger');
		return res;
	}).catch(function(err) {
		ui.addNotification(null, E('p', {}, err.message), 'danger');
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.read('/etc/xray/link'), ''),
			L.resolveDefault(fs.exec('/etc/init.d/xray', [ 'status' ]), {}),
			L.resolveDefault(fs.exec('/sbin/logread', [ '-e', 'xray', '-l', '50' ]), {})
		]);
	},

	render: function(data) {
		var link = (data[0] || '').trim(),
		    status = ((data[1] && data[1].stdout) || '').trim() || 'unknown',
		    log = (data[2] && data[2].stdout) || '';

		var ta = E('textarea', {
			'class': 'cbi-input-textarea',
			'style': 'width:100%;font-family:monospace',
			'rows': 4,
			'spellcheck': 'false',
			'placeholder': 'vless://UUID@server:443?type=tcp&security=reality&pbk=...&sid=...&sni=...&fp=chrome&flow=xtls-rprx-vision#name'
		}, [ link ]);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ 'Xray' ]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Paste a VLESS share link (REALITY/TLS, tcp/xhttp/ws/httpupgrade). ' +
				  'Traffic is sent to Xray by policies in Services → Policy Routing (pbr), ' +
				  'the default policies use the itdoginfo "Russia inside" lists.')
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, [ E('strong', {}, [ _('Status') + ': ' ]), status ]),
				ta,
				E('div', { 'style': 'margin-top:1em;display:flex;flex-wrap:wrap;gap:.5em' }, [
					E('button', {
						'class': 'cbi-button cbi-button-apply',
						'click': ui.createHandlerFn(this, function() {
							return exec('/usr/bin/xray-link', [ ta.value.trim() ]);
						})
					}, [ _('Save & Apply') ]),
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, function() {
							return exec('/etc/init.d/xray', [ 'restart' ]);
						})
					}, [ _('Restart') ]),
					E('button', {
						'class': 'cbi-button cbi-button-reset',
						'click': ui.createHandlerFn(this, function() {
							return exec('/etc/init.d/xray', [ 'stop' ]);
						})
					}, [ _('Stop') ]),
					E('button', {
						'class': 'cbi-button',
						'click': ui.createHandlerFn(this, function() {
							return exec('/etc/init.d/pbr', [ 'restart' ]);
						})
					}, [ _('Update lists (restart pbr)') ])
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ _('Log') ]),
				E('pre', { 'style': 'max-height:30em;overflow:auto;white-space:pre-wrap' }, [ log ])
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
