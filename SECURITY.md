# Security Policy

## Supported versions

Only the latest release receives fixes. Volume Control updates itself through Sparkle, so a fix reaches users with the next release.

## Reporting a vulnerability

Report a vulnerability privately through GitHub: open the [Security tab](https://github.com/alberti42/Volume-Control/security) of this repository and choose **Report a vulnerability**. Do not open a public issue for a vulnerability.

Include the Volume Control version, the macOS version, and the steps to reproduce the problem.

## What Volume Control does that matters for security

- It needs the Accessibility permission to receive the volume keys, and the Automation permission to change the volume of Apple Music, Spotify, Doppler and Swinsian through Apple Events.
- With **Control display volume** on, it talks to BetterDisplay or Lunar on the same Mac; the connection to Lunar goes to `127.0.0.1` only.
- It connects to the internet only for updates: it downloads `Releases/VolumeControlCast.xml` from this repository and, when you install an update, `VolumeControl.zip` from GitHub Releases. Sparkle installs an update only if the ZIP's EdDSA signature matches the public key in the app.
- Each release ZIP is built by GitHub Actions from the tagged source, signed with a Developer ID, notarized by Apple, and, from 2.3.2, carries a build provenance attestation. To check where a downloaded ZIP was built:

  ```sh
  gh attestation verify VolumeControl.zip --repo alberti42/Volume-Control
  ```
