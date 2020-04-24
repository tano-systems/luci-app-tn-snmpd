'use strict';
'require ui';
'require form';
'require network';
'require session';
'require uci';

const appVersion = '2.1.0';
const appHomeUrl = 'https://github.com/tano-systems/luci-app-tn-snmpd';

const appFooter = E('div', { 'class': 'cbi-section' }, [
	E('p', { 'class': 'cbi-section-node tano-copyright' }, [
		E('a', { 'href': appHomeUrl },
			_('SNMP LuCI application (version %s)').format(appVersion)),
		E('br', {}),
		_('© 2019–2020, Tano Systems LLC, Anton Kikin'),
		' <',
		E('a', { 'href': 'mailto:a.kikin@tano-systems.com' },
			E('nobr', {}, 'a.kikin@tano-systems.com')),
		'>'
	])
]);

function init() {
	return new Promise(function(resolveFn, rejectFn) {
		var data = session.getLocalData('luci-app-tn-snmpd');
		if ((data !== null) && data.hasOwnProperty('hideFooter')) {
			return resolveFn();
		}

		data = {};

		return uci.load('luci').then(function() {
			data.hideFooter = (uci.get('luci', 'app_tn_snmpd', 'hide_footer') == '1')
				? true : false;
			session.setLocalData('luci-app-tn-snmpd', data);
			return resolveFn();
		});
	});
}

function isNeedToHideFooter() {
	var data = session.getLocalData('luci-app-tn-snmpd');

	if (data === null)
		data = {};

	if (data.hasOwnProperty('hideFooter'))
		return data.hideFooter;
	else
		return false;
}

function renderFooter() {
	return isNeedToHideFooter() ? '' : appFooter;
}

return L.Class.extend({
	renderFooter: renderFooter,
	init: init,
});
