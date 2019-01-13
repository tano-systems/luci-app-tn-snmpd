--
-- Copyright (c) 2018-2019, Tano Systems. All Rights Reserved.
-- Anton Kikin <a.kikin@tano-systems.com>
--

local sys  = require "luci.sys"
local util = require "luci.util"
local uci  = require("luci.model.uci").cursor()

local m, s, o

m = Map("snmpd",
	translate("SNMP Settings"),
	translate("On this page you may configure SNMP agent settings.")
)

s = m:section(TypedSection, "snmpd")
s.anonymous = true
s.addremove = false

s:tab("global", translate("Global"))
s:tab("v1v2c", translate("SNMPv1/SNMPv2c"))
s:tab("v3", translate("SNMPv3"))
s:tab("traps", translate("Traps"))
s:tab("system", translate("System"))

-----------------------------------------------------------------------------------
--
-- Global settings
--
-----------------------------------------------------------------------------------

-- Download MIB
local mib_file = uci:get("luci_snmpd_tn", "snmpd_tn", "download_mib")

if mib_file and nixio.fs.access(mib_file) then
	mib = s:taboption("global", Button, "__download")
	mib.title      = translate("MIB download")
	mib.inputtitle = translate("Download")
	mib.inputstyle = "action"
	mib.template   = "snmpd-tn/button_download"
	mib.href       = luci.dispatcher.build_url("admin", "services", "snmpd", "mib_download")
end

-- Service enable/disable
local snmp_enable = s:taboption("global", Flag, "enabled",
	translate("Enable SNMP service"),
	translate("Run SNMP service on system's startup"))

snmp_enable.forcewrite = true
snmp_enable.rmempty = false

function snmp_enable.cfgvalue(self, section)
	return self.map:get(section, "enabled") or "0"
end

-- IP Protocol
local ip_protocol = s:taboption("global", ListValue, "ip_protocol", translate("IP version"))
ip_protocol:value("ipv4", translate("Only IPv4"))
ip_protocol:value("ipv6", translate("Only IPv6"))
ip_protocol:value("ipv4/ipv6", translate("IPv4 and IPv6"))
ip_protocol.default = "ipv4"
ip_protocol.rmempty = false

function ip_protocol.cfgvalue(self, section)
	local ip_protocol = ""
	if self.tag_error[section] then
		ip_protocol = self:formvalue(section)
	else
		ip_protocol = self.map:get(section, self.alias or self.option)
		if not ip_protocol then
			local s = m.uci:get_first("snmpd", "agent")
			local addr = string.upper(self.map:get(s, "agentaddress"))
			local p = { }

			if addr:match("UDP%:%d") then p[#p + 1] = "ipv4" end
			if addr:match("UDP6%:%d") then p[#p + 1] = "ipv6" end

			ip_protocol = table.concat(p, "/")
		end
	end

	return ip_protocol
end

-- Port
o = s:taboption("global", Value, "snmp_port", translate("Port"))
o.rmempty = false
o.default = "161"
o.datatype = "port"
o.forcewrite = true

function o.cfgvalue(self, section)
	local port = ""
	if self.tag_error[section] then
		port = self:formvalue(section)
	else
		port = self.map:get(section, self.alias or self.option)
		if not port then
			local sec = m.uci:get_first("snmpd", "agent")
			local addr = string.upper(self.map:get(sec, "agentaddress"))
			port = addr:match("UDP6?%:(%d+)")
		end
	end

	return port
end

function o.validate(self, value, section)
	if value then
		local netstat = luci.sys.exec("/bin/netstat -ulpn | " ..
			"grep -v snmpd | " ..
			"grep \":" .. value .. "\\s\"")

		if netstat ~= "" and tonumber(value) ~= 0 then
			return nil, translate("Specified port number is already in use")
		end
	end

	return Value.validate(self, value, section)
end

function o.write(self, section, value)
	local addr = { }
	local port = tonumber(value)
	local ip_protocol = ip_protocol:formvalue(section)

	if ip_protocol:match("ipv4") then addr[#addr + 1] = string.format("UDP:%d", port) end
	if ip_protocol:match("ipv6") then addr[#addr + 1] = string.format("UDP6:%d", port) end

	if #addr > 0 then
		local sec = m.uci:get_first("snmpd", "agent")
		self.map:set(sec, "agentaddress", table.concat(addr, ","))
	end

	Value.write(self, section, value)
end

-- SNMP version
local snmp_version = s:taboption("global", ListValue, "snmp_version",
	translate("SNMP version"),
	translate("SNMP version used to monitor and control the device"))
snmp_version.default = "v1/v2c"
snmp_version.rmempty = false
snmp_version.forcewrite = true
snmp_version:value("v1/v2c",  translate("SNMPv1 and SNMPv2c"))
snmp_version:value("v1/v2c/v3", translate("SNMPv1, SNMPv2c and SNMPv3"))
snmp_version:value("v3",  translate("Only SNMPv3"))

function snmp_version.cfgvalue(self, section)
	if self.tag_error[section] then
		return self:formvalue(section)
	else
		return AbstractValue.cfgvalue(self, section) or self.default
	end
end

-- AgentX socket
o = s:taboption("global", Value, "__agentxsocket",
	translate("AgentX socket path"),
	translate("Empty for disable AgentX"))
o.rmempty = true
o.forcewrite = true

function o.cfgvalue(self, section)
	local socket = ""
	if self.tag_error[section] then
		socket = self:formvalue(section)
	else
		local s = m.uci:get_first("snmpd", "agentx")
		socket = s and self.map:get(s, "agentxsocket") or nil
		if not socket then
			socket = self.default
		end
	end

	return socket
end

function o.remove(self, section)
	local s = m.uci:get_first("snmpd", "agentx")
	if s then return self.map:del(s) end
	return true
end

function o.write(self, section, value)
	local s = m.uci:get_first("snmpd", "agentx")
	if not s then s = self.map:add("agentx") end
	return self.map:set(s, "agentxsocket", value)
end

-----------------------------------------------------------------------------------
--
-- SNMPv1/SNMPv2c options
--
-----------------------------------------------------------------------------------

local ro_community
local ro_community_src
local rw_community
local rw_community_src

local function snmpd_get_community(self, section, secname)
	if self.tag_error[section] then
		com = self:formvalue(section)
	else
		com = self.map:get(section, self.alias or self.option)
		if not com then
			m.uci:foreach("snmpd", "com2sec", function(s)
				if s.secname == secname then
					com = s.community
					return false
				end
			end)
		end

		if not com then
			m.uci:foreach("snmpd", "com2sec6", function(s)
				if s.secname == secname then
					com = s.community
					return false
				end
			end)
		end

		if not com then
			com = self.default
		end
	end
	return com
end

local function snmpd_get_community_src(self, section, secname)
	local src = ""
	if self.tag_error[section] then
		src = self:formvalue(section)
	else
		src = self.map:get(section, self.alias or self.option)
		if not src then
			local com
			if secname == "ro" then
				com = ro_community
			else
				com = rw_community
			end
			src = m.uci:get("snmpd", com:cfgvalue(section), "source")
			if not src then
				src = self.default
			end
		end
	end

	return src
end

-- SNMPv1/SNMPv2c Read only community
ro_community = s:taboption("v1v2c", Value, "ro_community",
	translate("Read community"))
ro_community.default = "public"
ro_community.rmempty = false

function ro_community.cfgvalue(self, section)
	return snmpd_get_community(self, section, "ro")
end

ro_community_src = s:taboption("v1v2c", Value, "ro_community_src",
	translate("Read community source"),
	translate("Trusted source for SNMP read community access (hostname, IP/MASK, IP/BITS or IPv6 equivalents)"))
ro_community_src:value("default", translate("any (default)"))
ro_community_src:value("localhost", "localhost")
ro_community_src.default = "default"
ro_community_src.rmempty = false
ro_community_src.datatype = "or(host(0),ipmask)"

function ro_community_src.cfgvalue(self, section)
	return snmpd_get_community_src(self, section, "ro")
end

-- SNMPv1/SNMPv2c Read/write community
rw_community = s:taboption("v1v2c", Value, "rw_community",
	translate("Write community"))
rw_community.default = "private"
rw_community.rmempty = false

function rw_community.cfgvalue(self, section)
	return snmpd_get_community(self, section, "rw")
end

rw_community_src = s:taboption("v1v2c", Value, "rw_community_src",
	translate("Write community source"),
	translate("Trusted source for SNMP write community access (hostname, IP/MASK, IP/BITS or IPv6 equivalents)"))
rw_community_src:value("default", translate("any (default)"))
rw_community_src:value("localhost", "localhost")
rw_community_src.default = "localhost"
rw_community_src.rmempty = false
rw_community_src.datatype = "or(host(0),ipmask)"

function rw_community_src.cfgvalue(self, section)
	return snmpd_get_community_src(self, section, "rw")
end

-----------------------------------------------------------------------------------
--
-- SNMPv3 options
--
-----------------------------------------------------------------------------------

-- SNMPv3 user name
o = s:taboption("v3", Value, "snmp_v3_username", translate("SNMPv3 username"),
	translate("Set username to access SNMP"))
o.rmempty = false
o.default = "writeuser"

-- SNMPv3 write allow
o = s:taboption("v3", Flag, "snmp_v3_allow_write", translate("Allow write"))
o.rmempty = false
o.default = "0"

-- SNMPv3 auth type
o = s:taboption("v3", ListValue, "snmp_v3_auth_type", translate("SNMPv3 authentication type"))
o:value("none", translate("none"))
o:value("SHA", translate("SHA"))
o:value("MD5", translate("MD5"))
o.rmempty = false
o.default = "SHA"

-- SNMPv3 auth pass
o = s:taboption("v3", Value, "snmp_v3_auth_pass", translate("SNMPv3 authentication passphrase"))
o.password = true
o.rmempty = false
o.default = "passphrase"

-- SNMPv3 privacy/encryption type
o = s:taboption("v3", ListValue, "snmp_v3_privacy_type", translate("SNMPv3 encryption type"))
o:value("none", translate("none"))
o:value("AES", translate("AES"))
o:value("DES", translate("DES"))
o.rmempty = false
o.default = "AES"

-- SNMPv3 privacy/encryption pass
o = s:taboption("v3", Value, "snmp_v3_privacy_pass", translate("SNMPv3 encryption passphrase"))
o.default = "passphrase"
o.password = true

-----------------------------------------------------------------------------------
--
-- Trap settings
--
-----------------------------------------------------------------------------------

local trap_enable
local trap_snmp_version
local trap_host
local trap_port
local trap_community

-- Trap enable
trap_enable = s:taboption("traps", Flag, "trap_enabled", translate("Enable SNMP traps"),
	translate("Enable SNMP trap functionality"))
trap_enable.default = "0"
trap_enable.rmempty = false
trap_enable.forcewrite = true

-- Trap SNMP version
trap_snmp_version = s:taboption("traps", ListValue, "trap_snmp_version", translate("SNMP traps version"),
	translate("SNMP version used for sending traps"))
trap_snmp_version:value("v1", "SNMPv1")
trap_snmp_version:value("v2c", "SNMPv2c")
trap_snmp_version.default = "v2c"

-- Trap host
trap_host = s:taboption("traps", Value, "trap_host", translate("Host/IP"),
	translate("Host to transfer SNMP trap traffic to (hostname or IP address)"))
trap_host.datatype = "host(0)"
trap_host.default = "localhost"
trap_host.rmempty = false

-- Trap port
trap_port = s:taboption("traps", Value, "trap_port", translate("Port"),
	translate("Port for trap's host"))
trap_port.default = "162"
trap_port.datatype = "port"
trap_port.rmempty = false

-- Trap community
trap_community = s:taboption("traps", Value, "trap_community", translate("Community"),
	translate("The SNMP community for traps"))
trap_community:value("public")
trap_community:value("private")
trap_community.default = "public"
trap_community.rmempty = false

-----------------------------------------------------------------------------------

local function snmpd_community_delete(self, community)
	if not community or community == "" then return end

	-- delete sections
	self.map:del(community)               -- com2sec
	self.map:del(community .. "6")        -- com2sec6
	self.map:del(community .. "_v1")      -- group
	self.map:del(community .. "_v2c")     -- group
	self.map:del(community .. "_usm")     -- group
	self.map:del(community .. "_access")  -- access
end

local function snmpd_community_update(community, access, src, snmp_version, ip_protocol)
	local secname = access
	local sname

	if snmp_version:match("v1%/v2c") then
		-- com2sec section
		if ip_protocol:match("ipv4") then
			sname = community
			if not uci:get("snmpd", sname) then
				uci:set("snmpd", sname, "com2sec")
			end
			uci:set("snmpd", sname, "secname", secname)
			uci:set("snmpd", sname, "source", src)
			uci:set("snmpd", sname, "community", community)
		end

		-- com2sec6 section
		if ip_protocol:match("ipv6") then
			sname = community .. "6"
			if not uci:get("snmpd", sname) then
				uci:set("snmpd", sname, "com2sec6")
			end
			uci:set("snmpd", sname, "secname", secname)
			uci:set("snmpd", sname, "source", src)
			uci:set("snmpd", sname, "community", community)
		end
	end

	-- groups
	if snmp_version:match("v1%/v2c") then
		sname = community .. "_v1"
		if not uci:get("snmpd", sname) then
			uci:set("snmpd", sname, "group")
		end
		uci:set("snmpd", sname, "group", community)
		uci:set("snmpd", sname, "version", "v1")
		uci:set("snmpd", sname, "secname", secname)

		sname = community .. "_v2c"
		if not uci:get("snmpd", sname) then
			uci:set("snmpd", sname, "group")
		end
		uci:set("snmpd", sname, "group", community)
		uci:set("snmpd", sname, "version", "v2c")
		uci:set("snmpd", sname, "secname", secname)
	end

	if snmp_version:match("v3") then
		sname = community .. "_usm"
		if not uci:get("snmpd", sname) then
			uci:set("snmpd", sname, "group")
		end
		uci:set("snmpd", sname, "group", community)
		uci:set("snmpd", sname, "version", "usm")
		uci:set("snmpd", sname, "secname", secname)
	end

	-- access
	sname = community .. "_access"
	if not uci:get("snmpd", sname) then
		uci:set("snmpd", sname, "access")
	end
	uci:set("snmpd", sname, "group", community)
	uci:set("snmpd", sname, "context", "none")
	uci:set("snmpd", sname, "version", "any")
	uci:set("snmpd", sname, "level", "noauth")
	uci:set("snmpd", sname, "prefix", "exact")

	if access == "ro" then
		uci:set("snmpd", sname, "read", "all")
		uci:set("snmpd", sname, "write", "none")
		uci:set("snmpd", sname, "notify", "none")
	else
		uci:set("snmpd", sname, "read", "all")
		uci:set("snmpd", sname, "write", "all")
		uci:set("snmpd", sname, "notify", "all")
	end
end

function snmp_enable.write(self, section, value)
	local ro_update = false
	local rw_update = false

	local ro_community_prev = ""
	local ro_community_new = ro_community:formvalue(section)

	local ro_community_src_prev = ""
	local ro_community_src_new = ro_community_src:formvalue(section)

	local rw_community_prev = ""
	local rw_community_new = rw_community:formvalue(section)

	local rw_community_src_prev = ""
	local rw_community_src_new = rw_community_src:formvalue(section)

	local snmp_version_prev = ""
	local snmp_version_new = snmp_version:formvalue(section)

	local ip_protocol_prev = ""
	local ip_protocol_new = ip_protocol:formvalue(section)

	if ro_community_new == "" or rw_community_new == "" then
		return
	end

	--------

	snmp_version_prev = uci:get("snmpd", "general", "snmp_version")
	ip_protocol_prev = uci:get("snmpd", "general", "ip_protocol")

	local com = "com2sec"
	if ip_protocol_prev and ip_protocol_prev:match("ipv6") then com = "com2sec6" end
	uci:foreach("snmpd", com, function(s)
		if s.secname == "ro" then
			ro_community_prev = s.community
			ro_community_src_prev = s.source
		end
		if s.secname == "rw" then
			rw_community_prev = s.community
			rw_community_src_prev = s.source
		end
	end)

	--------

	if ro_community_src_new ~= ro_community_src_prev then ro_update = true end
	if rw_community_src_new ~= rw_community_src_prev then rw_update = true end

	if ro_community_new ~= ro_community_prev then
		snmpd_community_delete(self, ro_community_prev)
		ro_update = true
	end

	if rw_community_new ~= rw_community_prev then
		snmpd_community_delete(self, rw_community_prev)
		rw_update = true
	end

	if snmp_version_new ~= snmp_version_prev or
	   ip_protocol_new ~= ip_protocol_prev then
		ro_update = true
		rw_update = true
	end

	if ro_update then
		snmpd_community_update(ro_community_new, "ro",
			ro_community_src_new, snmp_version_new, ip_protocol_new)
	end

	if rw_update then
		snmpd_community_update(rw_community_new, "rw",
			rw_community_src_new, snmp_version_new, ip_protocol_new)
	end

	Flag.write(self, section, value)
end

function trap_enable.write(self, section, value)
	local t_version = trap_snmp_version:formvalue(section)
	local t_enable = value

	local t_host = trap_host:formvalue(section)
	local t_port = trap_port:formvalue(section)
	local t_community = trap_community:formvalue(section)

	local traps
	
	traps = 0
	m.uci:foreach("snmpd", "trapsink", function(s)
		traps = traps + 1
		if traps > 1 or t_enable == "0" or t_version ~= "v1" then
			self.map:del(s[".name"])
		end
	end)

	traps = 0
	m.uci:foreach("snmpd", "trap2sink", function(s)
		traps = traps + 1
		if traps > 1 or t_enable == "0" or t_version ~= "v2c" then
			self.map:del(s[".name"])
		end
	end)

	if t_enable == "1" then
		local sink
		if t_version == "v1" then
			sink = "trapsink"
		else
			sink = "trap2sink"
		end

		local s = m.uci:get_first("snmpd", sink)
		if not s then
			s = self.map:add(sink)
		end
		self.map:set(s, "community", t_community)
		self.map:set(s, "host", t_host)
		self.map:set(s, "port", t_port)
	end

	Flag.write(self, section, value)
end

-----------------------------------------------------------------------------------
--
-- System settings
--
-----------------------------------------------------------------------------------

function snmpd_sys_cfgvalue(self, section)
	local s = m.uci:get_first("snmpd", "system")
	return s and self.map:get(s, self.alias or self.option) or ""
end

function snmpd_sys_remove(self, section, value)
	local s = m.uci:get_first("snmpd", "system")
	if s then return self.map:del(s, self.alias or self.option) end
	return true
end

function snmpd_sys_write(self, section, value)
	local s = m.uci:get_first("snmpd", "system")
	if not s then s = self.map:add("system") end
	return self.map:set(s, self.alias or self.option, value)
end

o = s:taboption("system", Value, "sysName",
	translate("Name"),
	translate("System name for the agent"))
o.cfgvalue = snmpd_sys_cfgvalue
o.write = snmpd_sys_write
o.remove = snmpd_sys_remove

o = s:taboption("system", Value, "sysContact",
	translate("Contact"),
	translate("System contact for the agent"))
o.cfgvalue = snmpd_sys_cfgvalue
o.write = snmpd_sys_write
o.remove = snmpd_sys_remove

o = s:taboption("system", Value, "sysLocation",
	translate("Location"),
	translate("System location for the agent"))
o.cfgvalue = snmpd_sys_cfgvalue
o.write = snmpd_sys_write
o.remove = snmpd_sys_remove

-----------------------------------------------------------------------------------

m:section(SimpleSection, nil).template = "snmpd-tn/footer"

-----------------------------------------------------------------------------------

return m
