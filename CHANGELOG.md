# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

All dates in this document are in `DD.MM.YYYY` format.

## [Unreleased]

### Removed
- Removed plugin sources for [luci-app-tn-logview](https://github.com/tano-systems/luci-app-tn-logview).

## [Version 2.1.0] (24.04.2020)
### Added
- Added "Logging" tab for logging configuration.
- Added plugin for [luci-app-tn-logview](https://github.com/tano-systems/luci-app-tn-logview).

## [Version 2.0.0] (24.04.2020)
### Changed
- Converted to client side JS rendering

## [Version 1.0.0] (14.04.2020)
### Added
- Allow to hide footer by UCI option 'luci.app_tn_snmpd.hide_footer'

### Fixed
- Minor fixes for Russian translation.
- Added translation contexts for some strings.

### Changed
- Moved some functions from CBI model code to module 'luci.tools.snmpd-tn'.
- Removed useless ucitrack definitions

## [Version 0.9.0] (22.01.2019)

Initial release

[Unreleased]: https://github.com/tano-systems/luci-app-snmpd-tn/tree/master
[Version 2.1.0]: https://github.com/tano-systems/luci-app-snmpd-tn/releases/tag/v2.1.0
[Version 2.0.0]: https://github.com/tano-systems/luci-app-snmpd-tn/releases/tag/v2.0.0
[Version 1.0.0]: https://github.com/tano-systems/luci-app-snmpd-tn/releases/tag/v1.0.0
[Version 0.9.0]: https://github.com/tano-systems/luci-app-snmpd-tn/releases/tag/v0.9.0
