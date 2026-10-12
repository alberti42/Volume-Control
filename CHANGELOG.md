# Changelog

All notable changes to Volume Control are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Versions before 2.0.0 are listed in the [README](README.md#versions).

## [Unreleased]

### Added

- **Keep volume keys alive** in the menu, off by default. On some Macs the volume keys stop reaching Volume Control after a while, and unticking and re-ticking **Enable** brings them back ([#43](https://github.com/alberti42/Volume-Control/issues/43)). With this option on, Volume Control sends itself a test event every 5 s, or at an interval you set between 2 and 60 s, and reconnects to the keyboard when the test event does not arrive. Copy Diagnostics shows how many times this has happened.

### Fixed

- With Spotify, volume up changed the volume by less than volume down: at the default increment, 2 per press instead of 3.4 ([#43](https://github.com/alberti42/Volume-Control/issues/43)). Both now change it by the same amount.
- **Copy Diagnostics** could freeze Volume Control when macOS did not answer whether Volume Control may control a player, as happened with Spotify on macOS 27. The report now shows "macOS did not answer within 1 s" for that player.

## [2.4.0] - 2026-10-11

### Changed

- On macOS 26 and later, the volume HUD looks like the system volume HUD: the same Liquid Glass with its bright rim, the same slider with tick marks and speaker icons, and the same size, font and position on screen.

### Fixed

- On macOS 27, with the menu bar set to hide automatically, the HUD appeared under the menu bar icon's position while the menu bar was hidden. It is centred again.
- Includes the fixes of the 2.3.3 and 2.3.4 pre-releases.

## [2.3.4] - 2026-10-06

Pre-release; included in 2.4.0.

### Changed

- **Copy Diagnostics**: "Event tap receiving keys" is now "Event tap enabled", which is what it reports; "Event tap created" shows how long ago the event tap was created; the new line "Last media key seen by tap" updates on every volume key press.

### Fixed

- On some Macs the volume keys stopped working after a while, and only relaunching Volume Control brought them back ([#43](https://github.com/alberti42/Volume-Control/issues/43)). Waking the Mac from sleep, or unticking and re-ticking **Enable**, now brings them back.
- When macOS disables the event tap "by user input", Volume Control re-enables it.
- Volume Control turns the volume keys off only after five consecutive event tap timeouts, as intended. Before, it counted every timeout since launch.

## [2.3.3] - 2026-09-24

Pre-release; included in 2.4.0.

### Changed

- **Copy Diagnostics**: the "Last volume key press" section shows both "Command on the event" and "Command on the keyboard".

### Fixed

- On some Macs, holding Command did not switch the volume keys between the music player and the system volume, because the volume key event arrived without the Command key ([#56](https://github.com/alberti42/Volume-Control/issues/56)). Volume Control now also reads which modifier keys are held on the keyboard. A tool such as BetterTouchTool or Karabiner-Elements that sends a volume key while you hold Command is now treated as Command + volume key.

## [2.3.2] - 2026-09-23

### Added

- Support for macOS 27 Golden Gate.
- **Copy Diagnostics** includes whether Volume Control receives the volume keys, which players the volume keys target, the settings that change which volume the keys act on, and the last volume key press.

### Fixed

- A player that stopped answering Apple Events made Volume Control wait about 2 minutes for each answer; on macOS 27, an Apple Music that did not respond at launch kept the menu bar icon from appearing. Volume Control now waits at most 2 s, then skips the player and shows **(n/a)** next to it until it answers again.

## [2.3.1] - 2026-08-11

Pre-release; its changes are listed under 2.3.2.

## [2.3.0] - 2026-07-11

### Added

- **Copy Diagnostics** menu item: copies a plain-text report (app and macOS versions, permission status, and the volume controls of every audio output device) to the clipboard, for bug reports.

### Fixed

- Displays with no software volume control (USB-C, DisplayPort, HDMI monitors) are detected: the menu shows **(n/a)** for the system volume, and the volume keys are handed back to macOS ([#53](https://github.com/alberti42/Volume-Control/issues/53)).
- Devices with per-channel volume but no master volume, such as AirPods, can be controlled.
- Lowering the system volume to 0% no longer leaves the output device stuck muted.

## [2.2.2] - 2026-04-21

### Fixed

- The volume HUD appeared in the top-right corner with **Hide from Status Bar** on, and in the top-left corner when Ice or Bartender hid the menu bar icon ([#50](https://github.com/alberti42/Volume-Control/issues/50)). It is centred near the top of the screen in both cases.
- With the menu bar set to hide automatically, the HUD appeared too close to the top of the screen.

## [2.2.1] - 2026-04-07

### Fixed

- Holding a volume key changes the volume smoothly again; on macOS Tahoe it changed in uneven steps.
- The HUD's volume bar could show about 25% when the volume was near zero.

## [2.2.0] - 2026-04-06

### Added

- Support for the Swinsian music player ([#25](https://github.com/alberti42/Volume-Control/issues/25)).

## [2.1.0] - 2025-10-26

### Added

- The volume HUD is back on macOS Sequoia and Tahoe.

### Fixed

- Volume Control handles revoked permissions without freezing the keyboard.

## [2.0.2] - 2025-10-02

Tagged but not published as a release; the fix shipped in 2.1.0.

### Fixed

- When the event tap timed out, Volume Control retries enabling it 5 times, 2 s apart, before turning the volume keys off.

## [2.0.1] - 2025-09-30

### Fixed

- Volume Control could not control the music players' volume.

## [2.0.0] - 2025-09-30

### Added

- Support for macOS Tahoe (macOS Ventura and later).
- Notarized by Apple.

### Removed

- The volume HUD on macOS Tahoe (it returned in 2.1.0).

### Fixed

- The Mac could become unresponsive when Accessibility permission was revoked while Volume Control was running.
- Volume keys from the MacBook Pro Touch Bar are handled.
- The system volume can be muted completely; 0 was not silent before.

[Unreleased]: https://github.com/alberti42/Volume-Control/compare/v2.4.0...HEAD
[2.4.0]: https://github.com/alberti42/Volume-Control/compare/v2.3.2...v2.4.0
[2.3.4]: https://github.com/alberti42/Volume-Control/compare/v2.3.3...v2.3.4
[2.3.3]: https://github.com/alberti42/Volume-Control/compare/v2.3.2...v2.3.3
[2.3.2]: https://github.com/alberti42/Volume-Control/compare/v2.3.0...v2.3.2
[2.3.1]: https://github.com/alberti42/Volume-Control/compare/v2.3.0...v2.3.1
[2.3.0]: https://github.com/alberti42/Volume-Control/compare/v2.2.2...v2.3.0
[2.2.2]: https://github.com/alberti42/Volume-Control/compare/v2.2.1...v2.2.2
[2.2.1]: https://github.com/alberti42/Volume-Control/compare/v2.2.0...v2.2.1
[2.2.0]: https://github.com/alberti42/Volume-Control/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/alberti42/Volume-Control/compare/v2.0.2...v2.1.0
[2.0.2]: https://github.com/alberti42/Volume-Control/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/alberti42/Volume-Control/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/alberti42/Volume-Control/releases/tag/v2.0.0
