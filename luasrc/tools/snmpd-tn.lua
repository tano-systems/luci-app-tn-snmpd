--
-- Copyright (c) 2018-2019, Tano Systems. All Rights Reserved.
-- Anton Kikin <a.kikin@tano-systems.com>
--

module "luci.tools.snmpd-tn"

local app_version = "0.9.0"
local app_home = "https://github.com/tano-systems/luci-app-snmpd-tn"

function version()
	return app_version
end

function home()
	return app_home
end
