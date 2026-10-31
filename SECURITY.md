# Security policy

## Supported versions

Security fixes are currently provided for the latest source revision only.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting or a private repository security
advisory. Do not open a public issue containing exploitable details.

Never include any of the following in a report, screenshot, or log:

- browser Cookies or session tokens;
- passwords, verification codes, or Keychain data;
- private media URLs or account identifiers;
- complete home-directory paths when they are not required;
- a full copy of the Application Support directory.

## Local-only architecture

MediaDock has no account server and does not upload browsing data. The optional
aria2 RPC listener binds to `127.0.0.1`, uses a random per-task port and secret,
and is stopped after the download process ends.

The selected browser profile is copied into MediaDock's Application Support
directory for local use. File permissions and macOS sandbox/bookmark behavior
ultimately depend on the operating system.

## Scope

Reports about bypassing DRM, paid access, or platform access controls are out of
scope. MediaDock intentionally does not implement those capabilities.
