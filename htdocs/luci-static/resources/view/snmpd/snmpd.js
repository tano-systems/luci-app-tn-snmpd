/*
 * Copyright (c) 2020 Tano Systems. All Rights Reserved.
 * Author: Anton Kikin <a.kikin@tano-systems.com>
 */

'use strict';
'require rpc';
'require form';
'require snmpd';
'require uci';
'require ui';
'require fs';

return L.view.extend({
	load: function() {
		return Promise.all([
			snmpd.init(),
			uci.load([ 'snmpd', 'luci_snmpd' ]).then(function() {
				var mibFile = uci.get('luci_snmpd', 'snmpd', 'download_mib');
				if (mibFile)
					return L.resolveDefault(fs.stat(mibFile), null);
				else
					return Promise.resolve(null);
			}),
		]);
	},

	__init__: function() {
		this.super('__init__', arguments);

		this.ro_community     = null;
		this.ro_community_src = null;
		this.rw_community     = null;
		this.rw_community_src = null;
		this.ip_protocol      = null;
		this.snmp_version     = null;
	},

	/** @private */
	communityGet: function(name, section, secname) {
		var com = uci.get('snmpd', section, name);
		if (!com) {
			let sections = uci.sections('snmpd', 'com2sec');
			for (let i = 0; i < sections.length; i++) {
				if (sections[i].secname == secname) {
					com = sections[i].community;
					break;
				}
			}
		}

		if (!com) {
			let sections = uci.sections('snmpd', 'com2sec6');
			for (let i = 0; i < sections.length; i++) {
				if (sections[i].secname == secname) {
					com = sections[i].community;
					break;
				}
			}
		}

		return com;
	},

	/** @private */
	communityCfgValue: function(o, section, secname) {
		var com = this.communityGet(o.alias || o.option, section, secname);
		return com || o.default;
	},

	/** @private */
	communitySrcGet: function(name, section, secname, com) {
		var src = uci.get('snmpd', section, name)
		if (!src)
			src = uci.get('snmpd', com, 'source');
		return src
	},

	/** @private */
	communitySrcCfgValue: function(o, section, secname, com) {
		var src = this.communitySrcGet(o.alias || o.option,
			section, secname, com);
		return src || o.default;
	},

	/** @private */
	communityDelete: function(community) {
		if (!community || community == '')
			return;

		// delete sections
		uci.remove('snmpd', community)              // com2sec
		uci.remove('snmpd', community + '6')        // com2sec6
		uci.remove('snmpd', community + '_v1')      // group
		uci.remove('snmpd', community + '_v2c')     // group
		uci.remove('snmpd', community + '_usm')     // group
		uci.remove('snmpd', community + '_access')  // access
	},

	/** @private */
	communityUpdate: function(community, access, src, snmp_version, ip_protocol) {
		var secname = access;
		var sname;

		if (snmp_version.match(/v1\/v2c/g)) {
			// com2sec section
			if (ip_protocol.match(/ipv4/g)) {
				sname = community;
				if (!uci.get('snmpd', sname)) {
					uci.add('snmpd', 'com2sec', sname);
				}
				uci.set('snmpd', sname, 'secname', secname);
				uci.set('snmpd', sname, 'source', src);
				uci.set('snmpd', sname, 'community', community);
			}

			// com2sec6 section
			if (ip_protocol.match(/ipv6/g)) {
				sname = community + '6';
				if (!uci.get('snmpd', sname)) {
					uci.add('snmpd', 'com2sec6', sname);
				}
				uci.set('snmpd', sname, 'secname', secname);
				uci.set('snmpd', sname, 'source', src);
				uci.set('snmpd', sname, 'community', community);
			}

			// groups
			sname = community + '_v1';
			if (!uci.get('snmpd', sname)) {
				uci.add('snmpd', 'group', sname);
			}
			uci.set('snmpd', sname, 'group', community);
			uci.set('snmpd', sname, 'version', 'v1');
			uci.set('snmpd', sname, 'secname', secname);

			sname = community + '_v2c';
			if (!uci.get('snmpd', sname)) {
				uci.add('snmpd', 'group', sname);
			}
			uci.set('snmpd', sname, 'group', community);
			uci.set('snmpd', sname, 'version', 'v2c');
			uci.set('snmpd', sname, 'secname', secname);
		}

		if (snmp_version.match(/v3/g)) {
			sname = community + '_usm';
			if (!uci.get('snmpd', sname)) {
				uci.add('snmpd', 'group', sname);
			}
			uci.set('snmpd', sname, 'group', community);
			uci.set('snmpd', sname, 'version', 'usm');
			uci.set('snmpd', sname, 'secname', secname);
		}

		// access
		sname = community + '_access';
		if (!uci.get('snmpd', sname)) {
			uci.add('snmpd', 'access', sname);
		}

		uci.set('snmpd', sname, 'group', community);
		uci.set('snmpd', sname, 'context', 'none');
		uci.set('snmpd', sname, 'version', 'any');
		uci.set('snmpd', sname, 'level', 'noauth');
		uci.set('snmpd', sname, 'prefix', 'exact');

		if (access == 'ro') {
			uci.set('snmpd', sname, 'read', 'all');
			uci.set('snmpd', sname, 'write', 'none');
			uci.set('snmpd', sname, 'notify', 'none');
		}
		else {
			uci.set('snmpd', sname, 'read', 'all');
			uci.set('snmpd', sname, 'write', 'all');
			uci.set('snmpd', sname, 'notify', 'all');
		}
	},

	/** @private */
	communitiesConfigure: function(newOpts) {
		var ro_update = false;
		var rw_update = false;

		var ro_community_prev = '';
		var ro_community_new = newOpts['ro_community'] || '';

		var ro_community_src_prev = '';
		var ro_community_src_new = newOpts['ro_community_src'] || '';

		var rw_community_prev = '';
		var rw_community_new = newOpts['rw_community'] || '';

		var rw_community_src_prev = '';
		var rw_community_src_new = newOpts['rw_community_src'] || '';

		var snmp_version_prev = '';
		var snmp_version_new = newOpts['snmp_version'] || '';

		var ip_protocol_prev = '';
		var ip_protocol_new = newOpts['ip_protocol'] || '';

		if ((ro_community_new == '') ||
		    (rw_community_new == ''))
			return false;

		snmp_version_prev = uci.get('snmpd', 'general', 'snmp_version');
		ip_protocol_prev  = uci.get('snmpd', 'general', 'ip_protocol');

		var com = 'com2sec';
		if (ip_protocol_prev && ip_protocol_prev.match(/ipv6/g))
			com = 'com2sec6';

		uci.sections('snmpd', com, function(s) {
			if (s.secname == 'ro') {
				ro_community_prev = s.community;
				ro_community_src_prev = s.source;
			}
			if (s.secname == 'rw') {
				rw_community_prev = s.community;
				rw_community_src_prev = s.source;
			}
		});

		if (ro_community_src_new !== ro_community_src_prev)
			ro_update = true;

		if (rw_community_src_new !== rw_community_src_prev)
			rw_update = true;

		if (ro_community_new !== ro_community_prev) {
			this.communityDelete(ro_community_prev)
			ro_update = true;
		}

		if (rw_community_new !== rw_community_prev) {
			this.communityDelete(rw_community_prev);
			rw_update = true;
		}

		if ((snmp_version_new !== snmp_version_prev) ||
		    (ip_protocol_new  !== ip_protocol_prev)) {
			ro_update = true;
			rw_update = true;
		}

		if (ro_update) {
			this.communityUpdate(
				ro_community_new, 'ro',
				ro_community_src_new,
				snmp_version_new, ip_protocol_new
			);
		}

		if (rw_update) {
			this.communityUpdate(
				rw_community_new, 'rw',
				rw_community_src_new,
				snmp_version_new, ip_protocol_new
			);
		}

		return true
	},

	/** @private */
	trapsConfigure: function(t_enable, t_version, t_host, t_port, t_community) {
		var traps = 0;
		uci.sections('snmpd', 'trapsink', function(s) {
			traps++;
			if ((traps > 1) || (t_enable == '0') || (t_version !== 'v1')) {
				uci.remove('snmpd', s['.name']);
			}
		});

		traps = 0;
		uci.sections('snmpd', 'trap2sink', function(s) {
			traps++;
			if ((traps > 1) || (t_enable == '0') || (t_version !== 'v2c')) {
				uci.remove('snmpd', s['.name']);
			}
		});

		if (t_enable == '1') {
			var sink;
			if (t_version == 'v1')
				sink = 'trapsink';
			else
				sink = 'trap2sink';

			var s = uci.get_first('snmpd', sink);
			var sid = s ? s['.name'] : uci.add('snmpd', sink);

			uci.set('snmpd', sid, 'community', t_community);
			uci.set('snmpd', sid, 'host', t_host);
			uci.set('snmpd', sid, 'port', t_port);
		}
	},

	/** @private */
	populateGlobalSettings: function(tab, s, data) {
		// -------------------------------------------------------------------
		// 
		// Global settings
		// 
		// -------------------------------------------------------------------
		var o;
		var mibStat = data[1];

		// Download MIB
		if (mibStat) {
			o = s.taboption(tab, form.Button, '__download', _('MIB download') );
			o.inputtitle = _('Download (%1024.2mB)', 'Download data (action)').format(mibStat.size);
			o.inputstyle = 'action';
			o.onclick = ui.createHandlerFn(this, function(ev) {
				return fs.read(mibStat.path).then(function(data) {
					var url = URL.createObjectURL(new Blob([data], {
						type: 'text/plain'
					}));

					var link = document.createElement('a');
					link.href = url;
					link.download = mibStat.path.replace(/^.*[\\\/]/, '');
					link.click();
					return Promise.resolve();
				});
			});
		}

		// Service enable/disable
		var snmp_enable = s.taboption(tab, form.Flag, 'enabled',
			_('Enable SNMP service'),
			_('Run SNMP service on system\'s startup'));

		snmp_enable.forcewrite = true;
		snmp_enable.rmempty = false;
		snmp_enable.optional = false;
		snmp_enable.default = '0';
		snmp_enable.cfgvalue = function(section_id) {
			return uci.get('snmpd', section_id, 'enabled') || '0';
		};

		snmp_enable.write = L.bind(function(o, section_id, value) {
			if (this.communitiesConfigure({
				ro_community     : this.ro_community.formvalue(section_id),
				ro_community_src : this.ro_community_src.formvalue(section_id),
				rw_community     : this.rw_community.formvalue(section_id),
				rw_community_src : this.rw_community_src.formvalue(section_id),
				snmp_version     : this.snmp_version.formvalue(section_id),
				ip_protocol      : this.ip_protocol.formvalue(section_id)
			}) == true) {
				uci.set('snmpd', section_id, o.alias || o.option, value);
			}
		}, this, snmp_enable);

		this.ip_protocol = s.taboption(tab, form.ListValue, 'ip_protocol', _('IP version'));
		this.ip_protocol.value('ipv4', _('Only IPv4'));
		this.ip_protocol.value('ipv6', _('Only IPv6'));
		this.ip_protocol.value('ipv4/ipv6', _('IPv4 and IPv6'));
		this.ip_protocol.optional = false;
		this.ip_protocol.forcewrite = true;
		this.ip_protocol.default = 'ipv4';
		this.ip_protocol.rmempty = false;

		this.ip_protocol.cfgvalue = function(section_id) {
			var ip_protocol = uci.get('snmpd', section_id, 'ip_protocol');

			if (!ip_protocol) {
				var s = uci.get_first('snmpd', 'agent');
				if (!s)
					return null;

				var addr = uci.get('snmpd', s['.name'], 'agentaddress');
				var p = [];

				if (!addr)
					return null;

				addr = addr.toUpperCase();

				if (addr.match(/UDP:\d+/g))
					p.push('ipv4');
					
				if (addr.match(/UDP6:\d+/g))
					p.push('ipv6');

				ip_protocol = p.join('/');
			}

			return ip_protocol;
		};

		// Port
		o = s.taboption(tab, form.Value, 'snmp_port', _('Port'));
		o.rmempty = false;
		o.default = '161';
		o.datatype = 'port';
		o.forcewrite = true;
		o.cfgvalue = function(section_id) {
			var port = uci.get('snmpd', section_id, 'snmp_port');
			if (!port) {
				var s = uci.get_first('snmpd', 'agent');
				var addr = uci.get('snmpd', s['.name'], 'agentaddress');

				if (!addr)
					return null;

				addr = addr.toUpperCase();
				port = addr.match(/UDP6?:(\d+)/i);

				if (Array.isArray(port) && (port.length > 1))
					port = port[1];
			}

			return port
		};

		o.write = L.bind(function(protocol, section_id, value) {
			var addr = [];
			var port = parseInt(value);
			var ip_protocol = protocol.formvalue(section_id);

			if (ip_protocol.match(/ipv4/g))
				addr.push('UDP:%d'.format(port));

			if (ip_protocol.match(/ipv6/g))
				addr.push('UDP6:%d'.format(port));

			if (addr.length > 0) {
				var s = uci.get_first('snmpd', 'agent');
				if (s)
					uci.set('snmpd', s['.name'], 'agentaddress', addr.join(','));
			}

			return form.Value.prototype.write.apply(this, [section_id, value]);
		}, o, this.ip_protocol);

		// SNMP version
		this.snmp_version = s.taboption(tab, form.ListValue, 'snmp_version',
			_('SNMP version'),
			_('SNMP version used to monitor and control the device'));
		this.snmp_version.default = 'v1/v2c';
		this.snmp_version.rmempty = false;
		this.snmp_version.forcewrite = true;
		this.snmp_version.value('v1/v2c',    _('SNMPv1 and SNMPv2c'));
		this.snmp_version.value('v1/v2c/v3', _('SNMPv1, SNMPv2c and SNMPv3'));
		this.snmp_version.value('v3',        _('Only SNMPv3'));

		// AgentX socket
		o = s.taboption(tab, form.Value, '__agentxsocket',
			_('AgentX socket path'),
			_('Empty for disable AgentX'));
		o.rmempty = true;
		o.forcewrite = true;
		o.cfgvalue = function(section_id) {
			var s = uci.get_first('snmpd', 'agentx');
			var socket = uci.get('snmpd', s['.name'], 'agentxsocket');
			if (!socket)
				socket = this.default;
			return socket;
		};

		o.remove = function(section_id) {
			var s = uci.get_first('snmpd', 'agentx');
			if (s)
				s.remove('snmpd', s['.name']);
		};

		o.write = function(section_id, value) {
			var s = uci.get_first('snmpd', 'agentx');
			var sid = s ? s['.name'] : uci.add('snmpd', 'agentx');
			uci.set('snmpd', sid, 'agentxsocket', value);
		};
	},

	/** @private */
	populateV1V2CSettings: function(tab, s, data) {
		// -------------------------------------------------------------------
		// 
		// SNMPv1/SNMPv2c options
		// 
		// -------------------------------------------------------------------
		var o, o_src;

		// SNMPv1/SNMPv2c Read only community
		this.ro_community = s.taboption(tab, form.Value, 'ro_community',
			_('Read community'));
		this.ro_community.default = 'public';
		this.ro_community.rmempty = false;

		this.ro_community_src = s.taboption(tab, form.Value, 'ro_community_src',
			_('Read community source'),
			_('Trusted source for SNMP read community access (hostname, IP/MASK, IP/BITS or IPv6 equivalents)'));
		this.ro_community_src.value('default', _('any (default)'));
		this.ro_community_src.value('localhost', 'localhost');
		this.ro_community_src.default = 'default';
		this.ro_community_src.rmempty = false;
		this.ro_community_src.datatype = 'or(host(0),ipmask)';

		this.ro_community.cfgvalue = L.bind(function(section) {
			return this.communityCfgValue(this.ro_community, section, 'ro')
		}, this);

		this.ro_community_src.cfgvalue = L.bind(function(o, section) {
			return this.communitySrcCfgValue(
				this.ro_community_src, section, 'ro', o.cfgvalue(section));
		}, this, this.ro_community);

		// SNMPv1/SNMPv2c Read/write community
		this.rw_community = s.taboption(tab, form.Value, 'rw_community',
			_('Write community'));
		this.rw_community.default = 'private';
		this.rw_community.rmempty = false;

		this.rw_community_src = s.taboption(tab, form.Value, 'rw_community_src',
			_('Write community source'),
			_('Trusted source for SNMP write community access (hostname, IP/MASK, IP/BITS or IPv6 equivalents)'));
		this.rw_community_src.value('default', _('any (default)'));
		this.rw_community_src.value('localhost', 'localhost');
		this.rw_community_src.default = 'localhost';
		this.rw_community_src.rmempty = false;
		this.rw_community_src.datatype = 'or(host(0),ipmask)';

		this.rw_community.cfgvalue = L.bind(function(section) {
			return this.communityCfgValue(
				this.rw_community, section, 'rw')
		}, this);

		this.rw_community_src.cfgvalue = L.bind(function(o, section) {
			return this.communitySrcCfgValue(
				this.rw_community_src, section, 'rw', o.cfgvalue(section));
		}, this, this.rw_community);
	},

	/** @private */
	populateV3Settings: function(tab, s, data) {
		// -------------------------------------------------------------------
		// 
		// SNMPv3 options
		// 
		// -------------------------------------------------------------------
		var o;

		// SNMPv3 user name
		o = s.taboption(tab, form.Value, 'snmp_v3_username',
			_('SNMPv3 username'),
			_('Set username to access SNMP'));
		o.rmempty = false;
		o.default = 'writeuser';

		// SNMPv3 write allow
		o = s.taboption(tab, form.Flag, 'snmp_v3_allow_write',
			_('Allow write'));
		o.rmempty = false;
		o.default = '0';

		// SNMPv3 auth type
		o = s.taboption(tab, form.ListValue, 'snmp_v3_auth_type',
			_('SNMPv3 authentication type'));
		o.value('none', _('none'));
		o.value('SHA', _('SHA'));
		o.value('MD5', _('MD5'));
		o.rmempty = false;
		o.default = 'SHA';

		// SNMPv3 auth pass
		o = s.taboption(tab, form.Value, 'snmp_v3_auth_pass',
			_('SNMPv3 authentication passphrase'));
		o.password = true;
		o.rmempty = false;
		o.default = 'passphrase';

		// SNMPv3 privacy/encryption type
		o = s.taboption(tab, form.ListValue, 'snmp_v3_privacy_type',
			_('SNMPv3 encryption type'));
		o.value('none', _('none'));
		o.value('AES', _('AES'));
		o.value('DES', _('DES'));
		o.rmempty = false;
		o.default = 'AES';

		// SNMPv3 privacy/encryption pass
		o = s.taboption(tab, form.Value, 'snmp_v3_privacy_pass',
			_('SNMPv3 encryption passphrase'));
		o.default = 'passphrase';
		o.password = true;
	},

	/** @private */
	populateTrapsSettings: function(tab, s, data) {
		// -------------------------------------------------------------------
		// 
		// Trap settings
		// 
		// -------------------------------------------------------------------
		var trap_enable;
		var trap_snmp_version;
		var trap_host;
		var trap_port;
		var trap_community;

		// Trap enable
		trap_enable = s.taboption(tab, form.Flag, 'trap_enabled',
			_('Enable SNMP traps'),
			_('Enable SNMP trap functionality'));
		trap_enable.default = '0';
		trap_enable.rmempty = false;
		trap_enable.forcewrite = true;

		trap_enable.write = L.bind(function(o, section_id, value) {
			var t_version   = trap_snmp_version.formvalue(section_id);
			var t_enable    = value;
			var t_host      = trap_host.formvalue(section_id);
			var t_port      = trap_port.formvalue(section_id);
			var t_community = trap_community.formvalue(section_id);
			this.trapsConfigure(t_enable, t_version, t_host, t_port, t_community);
			uci.set('snmpd', section_id, o.alias || o.option, value);
		}, this, trap_enable);

		// Trap SNMP version
		trap_snmp_version = s.taboption(tab, form.ListValue, 'trap_snmp_version',
			_('SNMP traps version'),
			_('SNMP version used for sending traps'));
		trap_snmp_version.value('v1', 'SNMPv1');
		trap_snmp_version.value('v2c', 'SNMPv2c');
		trap_snmp_version.default = 'v2c';

		// Trap host
		trap_host = s.taboption(tab, form.Value, 'trap_host',
			_('Host/IP'),
			_('Host to transfer SNMP trap traffic to (hostname or IP address)'));
		trap_host.datatype = 'host(0)';
		trap_host.default = 'localhost';
		trap_host.rmempty = false;

		// Trap port
		trap_port = s.taboption(tab, form.Value, 'trap_port',
			_('Port'),
			_('Port for trap\'s host'));
		trap_port.default = '162';
		trap_port.datatype = 'port';
		trap_port.rmempty = false;

		// Trap community
		trap_community = s.taboption(tab, form.Value, 'trap_community',
			_('Community'),
			_('The SNMP community for traps'));
		trap_community.value('public');
		trap_community.value('private');
		trap_community.default = 'public';
		trap_community.rmempty = false;
	},

	/** @private */
	populateSystemSettings: function(tab, s, data) {
		// -------------------------------------------------------------------
		// 
		// System settings
		// 
		// -------------------------------------------------------------------
		var o;

		function snmpd_sys_cfgvalue(section) {
			var s = uci.get_first('snmpd', 'system');
			return s && uci.get('snmpd', s['.name'], this.option) || '';
		};

		function snmpd_sys_remove(section) {
			var s = uci.get_first('snmpd', 'system');
			if (s)
				uci.unset('snmpd', s['.name'], this.option);
		};

		function snmpd_sys_write(section, value) {
			var s = uci.get_first('snmpd', 'system');
			var sid = s ? s['.name'] : uci.add('snmpd', 'system');
			uci.set('snmpd', sid, this.option, value);
		};

		o = s.taboption(tab, form.Value, 'sysName',
			_('Name'), _('System name'));
		o.cfgvalue = snmpd_sys_cfgvalue;
		o.write = snmpd_sys_write;
		o.remove = snmpd_sys_remove;

		o = s.taboption(tab, form.Value, 'sysContact',
			_('Contact'), _('System contact'));
		o.cfgvalue = snmpd_sys_cfgvalue;
		o.write = snmpd_sys_write;
		o.remove = snmpd_sys_remove;

		o = s.taboption(tab, form.Value, 'sysLocation',
			_('Location'), _('System location'));
		o.cfgvalue = snmpd_sys_cfgvalue;
		o.write = snmpd_sys_write;
		o.remove = snmpd_sys_remove;
	},

	/** @private */
	populateLogSettings: function(tab, s, data) {
		// -------------------------------------------------------------------
		// 
		// Logging
		// 
		// -------------------------------------------------------------------
		var o;

		// File logging
		o = s.taboption(tab, form.Flag, 'log_file',
			_('Enable logging to file'));
		o.default = '0';
		o.rmempty = false;
		o.optional = false;

		o = s.taboption(tab, form.Value, 'log_file_path',
			_('Path to log file'));
		o.default = '/var/log/snmpd.log';
		o.rmempty = false;
		o.placeholder = '/var/log/snmpd.log';
		o.depends('log_file', '1');

		o = s.taboption(tab, form.ListValue, 'log_file_priority',
			_('Priority for file logging'),
			_('Will log messages of selected priority and above.'));
		o.default = 'i';
		o.value('!', 'LOG_EMERG');
		o.value('a', 'LOG_ALERT');
		o.value('c', 'LOG_CRIT');
		o.value('e', 'LOG_ERR');
		o.value('w', 'LOG_WARNING');
		o.value('n', 'LOG_NOTICE');
		o.value('i', 'LOG_INFO');
		o.value('d', 'LOG_DEBUG');
		o.depends('log_file', '1');

		// Syslog
		o = s.taboption(tab, form.Flag, 'log_syslog',
			_('Enable logging to syslog'));
		o.default = '0';
		o.rmempty = false;
		o.optional = false;

		o = s.taboption(tab, form.ListValue, 'log_syslog_facility',
			_('Syslog facility'));
		o.default = 'i';
		o.value('d', 'LOG_DAEMON');
		o.value('u', 'LOG_USER');
		o.value('0', 'LOG_LOCAL0');
		o.value('1', 'LOG_LOCAL1');
		o.value('2', 'LOG_LOCAL2');
		o.value('3', 'LOG_LOCAL3');
		o.value('4', 'LOG_LOCAL4');
		o.value('5', 'LOG_LOCAL5');
		o.value('6', 'LOG_LOCAL6');
		o.value('7', 'LOG_LOCAL7');
		o.depends('log_syslog', '1');

		o = s.taboption(tab, form.ListValue, 'log_syslog_priority',
			_('Priority for syslog logging'),
			_('Will log messages of selected priority and above.'));
		o.default = 'i';
		o.value('!', 'LOG_EMERG');
		o.value('a', 'LOG_ALERT');
		o.value('c', 'LOG_CRIT');
		o.value('e', 'LOG_ERR');
		o.value('w', 'LOG_WARNING');
		o.value('n', 'LOG_NOTICE');
		o.value('i', 'LOG_INFO');
		o.value('d', 'LOG_DEBUG');
		o.depends('log_syslog', '1');
	},

	render: function(data) {
		var m, s, o;

		m = new form.Map('snmpd',
			_('SNMP Settings'),
			_('On this page you may configure SNMP agent settings.'));

		s = m.section(form.TypedSection, 'snmpd');
		s.anonymous = true;
		s.addremove = false;

		s.tab('global', _('Global'));
		s.tab('v1v2c',  _('SNMPv1/SNMPv2c'));
		s.tab('v3',     _('SNMPv3'));
		s.tab('traps',  _('Traps', 'SNMP'));
		s.tab('system', _('System'));
		s.tab('log',    _('Logging'));

		this.populateGlobalSettings ('global', s, data);
		this.populateV1V2CSettings  ('v1v2c',  s, data);
		this.populateV3Settings     ('v3',     s, data);
		this.populateTrapsSettings  ('traps',  s, data);
		this.populateSystemSettings ('system', s, data);
		this.populateLogSettings    ('log',    s, data);

		return m.render();
	},

	addFooter: function() {
		return [
			this.super('addFooter', arguments),
			snmpd.renderFooter()
		];
	},
});
