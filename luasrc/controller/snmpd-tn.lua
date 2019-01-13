--
-- Copyright (c) 2018-2019, Tano Systems. All Rights Reserved.
-- Anton Kikin <a.kikin@tano-systems.com>
--

module("luci.controller.snmpd-tn", package.seeall)

function index()
	entry({"admin", "services", "snmpd"}, cbi("snmpd-tn/snmpd"), _("SNMP"), 85)
	entry({"admin", "services", "snmpd", "mib_download"}, call("action_mib_download"))
end

function action_mib_download()
	local uci = require("luci.model.uci").cursor()
	local mib_file = uci:get("luci_snmpd_tn", "snmpd_tn", "download_mib")

	if mib_file and nixio.fs.access(mib_file) then
		luci.http.header('Content-Disposition', 'attachment; filename="%s"'
			%{ nixio.fs.basename(mib_file) })

		luci.http.prepare_content("text/plain")
		luci.sys.process.exec({ "/bin/cat", mib_file }, luci.http.write)
	else
		luci.http.status(404, "No such requested MIB file")
		luci.http.prepare_content("text/plain")
	end
end
