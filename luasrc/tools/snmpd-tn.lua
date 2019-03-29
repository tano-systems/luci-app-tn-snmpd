--
-- Copyright (c) 2018-2019, Tano Systems. All Rights Reserved.
-- Anton Kikin <a.kikin@tano-systems.com>
--

module("luci.tools.snmpd-tn", package.seeall)

local uci = require("luci.model.uci").cursor()

local app_version = "0.9.0"
local app_home = "https://github.com/tano-systems/luci-app-snmpd-tn"

function version()
	return app_version
end

function home()
	return app_home
end

function community_get(name, section, secname)
	local com = uci:get("snmpd", section, name)
	if not com then
		uci:foreach("snmpd", "com2sec", function(s)
			if s.secname == secname then
				com = s.community
				return false
			end
		end)
	end

	if not com then
		uci:foreach("snmpd", "com2sec6", function(s)
			if s.secname == secname then
				com = s.community
				return false
			end
		end)
	end
	return com
end

function community_src_get(name, section, secname, com)
	src = uci:get("snmpd", section, name)
	if not src then
		src = uci:get("snmpd", com, "source")
	end
	return src
end

function community_cfgvalue(self, section, secname)
	local com = ""
	if self.tag_error[section] then
		com = self:formvalue(section)
	else
		com = community_get(self.alias or self.option, section, secname)
	end
	return com or self.default
end

function community_src_cfgvalue(self, section, secname, com)
	local src = ""
	if self.tag_error[section] then
		src = self:formvalue(section)
	else
		src = community_src_get(self.alias or self.option,
			section, secname, com)
	end
	return src or self.default
end

function community_delete(community)
	if not community or community == "" then return end

	-- delete sections
	uci:delete("snmpd", community)               -- com2sec
	uci:delete("snmpd", community .. "6")        -- com2sec6
	uci:delete("snmpd", community .. "_v1")      -- group
	uci:delete("snmpd", community .. "_v2c")     -- group
	uci:delete("snmpd", community .. "_usm")     -- group
	uci:delete("snmpd", community .. "_access")  -- access
end

function community_update(community, access, src, snmp_version, ip_protocol)
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

function communities_config(new_opts)
	local ro_update = false
	local rw_update = false

	local ro_community_prev = ""
	local ro_community_new = new_opts["ro_community"] or ""

	local ro_community_src_prev = ""
	local ro_community_src_new = new_opts["ro_community_src"] or ""

	local rw_community_prev = ""
	local rw_community_new = new_opts["rw_community"] or ""

	local rw_community_src_prev = ""
	local rw_community_src_new = new_opts["rw_community_src"] or ""

	local snmp_version_prev = ""
	local snmp_version_new = new_opts["snmp_version"] or ""

	local ip_protocol_prev = ""
	local ip_protocol_new = new_opts["ip_protocol"] or ""

	if ro_community_new == "" or rw_community_new == "" then
		return false
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
		community_delete(ro_community_prev)
		ro_update = true
	end

	if rw_community_new ~= rw_community_prev then
		community_delete(rw_community_prev)
		rw_update = true
	end

	if snmp_version_new ~= snmp_version_prev or
	   ip_protocol_new ~= ip_protocol_prev then
		ro_update = true
		rw_update = true
	end

	if ro_update then
		community_update(ro_community_new, "ro",
			ro_community_src_new, snmp_version_new, ip_protocol_new)
	end

	if rw_update then
		community_update(rw_community_new, "rw",
			rw_community_src_new, snmp_version_new, ip_protocol_new)
	end

	return true
end

function traps_config(t_enable, t_version, t_host, t_port, t_community)
	local traps
	
	traps = 0
	uci:foreach("snmpd", "trapsink", function(s)
		traps = traps + 1
		if traps > 1 or t_enable == "0" or t_version ~= "v1" then
			uci:delete("snmpd", s[".name"])
		end
	end)

	traps = 0
	uci:foreach("snmpd", "trap2sink", function(s)
		traps = traps + 1
		if traps > 1 or t_enable == "0" or t_version ~= "v2c" then
			uci:delete("snmpd", s[".name"])
		end
	end)

	if t_enable == "1" then
		local sink
		if t_version == "v1" then
			sink = "trapsink"
		else
			sink = "trap2sink"
		end

		local s = uci:get_first("snmpd", sink)
		if not s then
			s = uci:add("snmpd", sink)
		end
		uci:set("snmpd", s, "community", t_community)
		uci:set("snmpd", s, "host", t_host)
		uci:set("snmpd", s, "port", t_port)
	end
end
