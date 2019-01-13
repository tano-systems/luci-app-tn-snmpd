# LuCI support for SNMP

## Description
This is an alternate application for SNMP daemon configuration from LuCI web UI.

## Dependencies and Limitations
This LuCI application developed for LuCI 18.06 branch. For SNMPv3 support you need
to use customized snmpd init script from [meta-tano-openwrt](https://github.com/tano-systems/meta-tano-openwrt.git) OpenEmbedded layer.

## Supported languages
- English
- Russian

## Screenshots

### Global Settings
![Global Settings](screenshots/luci-app-snmpd-tn-global.png?raw=true "Global Settings")

### SNMPv1 and SNMPv2c Settings
![SNMPv1 and SNMPv2c Settings](screenshots/luci-app-snmpd-tn-snmpv1v2c.png?raw=true "SNMPv1 and SNMPv2c Settings")

### SNMPv3 Settings
![SNMPv3 Settings](screenshots/luci-app-snmpd-tn-snmpv3.png?raw=true "SNMPv3 Settings")

### SNMP Trap Settings
![SNMP Trap Settings](screenshots/luci-app-snmpd-tn-traps.png?raw=true "SNMP Trap Settings")

### SNMP System Settings
![SNMP System Settings](screenshots/luci-app-snmpd-tn-system.png?raw=true "SNMP System Settings")
