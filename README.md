# LuCI support for SNMP

## Description
This is an alternate application for SNMP daemon configuration from LuCI web UI.

## Dependencies and Limitations
Master branch of this repository requires latest LuCI revision with client side rendering feature. Support for older LuCI releases (e.g. for version 18.06.x, 19.07.x) is left in the [v1.x](https://github.com/tano-systems/luci-app-tn-snmpd/tree/v1.x) branch of this repository.

For SNMPv3 support you need to use customized snmpd procd init script from [meta-tanowrt](https://github.com/tano-systems/meta-tanowrt.git) OpenEmbedded layer.

## Supported languages
- English
- Russian

## Supported (tested) LuCI Themes
- [luci-theme-tano](https://github.com/tano-systems/luci-theme-tano) ([screenshots](#screenshots) are taken with this theme)
- luci-theme-bootstrap
- luci-theme-openwrt-2020
- luci-theme-openwrt

## Screenshots

### Global Settings
![Global Settings](screenshots/luci-app-tn-snmpd-global.png?raw=true "Global Settings")

### SNMPv1 and SNMPv2c Settings
![SNMPv1 and SNMPv2c Settings](screenshots/luci-app-tn-snmpd-snmpv1v2c.png?raw=true "SNMPv1 and SNMPv2c Settings")

### SNMPv3 Settings
![SNMPv3 Settings](screenshots/luci-app-tn-snmpd-snmpv3.png?raw=true "SNMPv3 Settings")

### SNMP Trap Settings
![SNMP Trap Settings](screenshots/luci-app-tn-snmpd-traps.png?raw=true "SNMP Trap Settings")

### SNMP System Settings
![SNMP System Settings](screenshots/luci-app-tn-snmpd-system.png?raw=true "SNMP System Settings")

### SNMP Logging Settings
![SNMP Logging Settings](screenshots/luci-app-tn-snmpd-logging.png?raw=true "SNMP Logging Settings")
