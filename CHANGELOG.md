# Changelog

All notable changes to LabCTL are documented in this file.

## [Unreleased]

### Added

- Dedicated GUI pages backed by a `QStackedWidget`.
- GUI service controls for Docker, Libvirt, VMware, VirtualBox, and Ollama.
- Confirmation dialogs and PolicyKit authentication for graphical service actions.
- Command cancellation and busy-state handling in the GUI.
- Automatic hardware vendor and model reporting in `labctl about`.
- Offscreen Qt tests for GUI navigation and service controls.
- Operational dashboard with profile shortcuts, temperatures, storage, connectivity, workload counts, alerts, timestamps, and optional auto-refresh.
- Versioned `monitor dashboard --json` schema for GUI and automation clients.
- Configurable dashboard thresholds with warning/critical states and hysteresis.
- Five-minute in-memory CPU, memory, temperature, and network graphs.
- Read-only Docker, Libvirt, VMware, and VirtualBox workload inventory page.
- Caches for package-update checks and workload discovery.
- Central requirements guide for supported distributions, build dependencies, optional integrations, and permissions.
- Safe profile previews with `--dry-run`.
- Optional non-interactive profile application with `--yes` or `-y`.
- Confirmation before active components are stopped by a profile.
- Best-effort restoration of component and power state after profile failures.
- Automated CLI smoke tests integrated with CTest.
- Functional GUI navigation for monitoring, services, network, storage, diagnostics, and platform information.
- Ubuntu and Kubuntu compatibility for package, firewall, and security diagnostics.
- Automatic UFW/Firewalld and AppArmor/SELinux detection.
- Automatic discovery of mounted storage under `/mnt`, `/media`, and `/run/media`.
- `doctor` module for detailed Fedora workstation diagnostics.
- Color-aware diagnostic output with `PASS`, `INFO`, `WARNING`, and `ERROR` result levels.
- System health classifications: `EXCELLENT`, `HEALTHY`, `ATTENTION NEEDED`, and `CRITICAL`.
- Separate recommendations section in diagnostic output.
- Automatic terminal detection for color output.
- `labctl about` command for project, Git, and platform information.
- `labctl info` alias for the `about` command.
- Repository, branch, commit, latest tag, module count, operating system, kernel, architecture, and license details in `about` output.

### Changed

- LabCTL GUI version updated to `0.3.0`.
- Minimum Qt version adjusted to 6.4 for Ubuntu 24.04 LTS compatibility.
- GUI dashboard now consumes structured JSON instead of parsing terminal text.
- GUI navigation now preserves separate output for each page.
- Privileged module operations can use PolicyKit when requested by the GUI.
- Read-only doctor checks no longer invoke `sudo` for Libvirt VM queries.
- Generated GUI build output and local backup files are now ignored by Git.
- Profile application now displays its planned power mode and component state.
- Package update diagnostics now support both APT and DNF.
- Firewall commands now adapt to UFW or Firewalld.
- Storage diagnostics no longer require a fixed `/mnt/Data` mount point.
- Development version updated to `2.3.0-dev`.
- GitHub repository remotes are displayed in `owner/repository` format instead of full SSH or HTTPS remote URLs.
- Main help output now documents `doctor`, `about`, and `info`.
- Module counting excludes the internal `utils` module.
- Module counter increment logic no longer depends on the exit status of arithmetic post-increment under strict shell settings.
- Redirected and piped output no longer contains ANSI color escape sequences.

### Fixed

- Duplicate `qemu` dispatch branch that made `labctl qemu backend` unreachable.
- Repository display normalization for SSH GitHub remotes ending in `.git`.
- Diagnostic color handling when standard output is not an interactive terminal.

## [2.2.0] - 2026-07-15

### Added

- Dynamic module loading.
- Battery module.
- Docker module.
- Firewall module.
- GPU module.
- Libvirt module.
- Network module.
- OneDrive module.
- Ollama module.
- Virtual machine module.
- VMware module.
- System health command.

### Changed

- Converted all output to English.
- Standardized headers and status messages.
- Added numbered module listing.

### Fixed

- Symbolic-link path handling.
- Bash confirmation prompts.
- Silent module dispatch failure.
- OneDrive duplicate process handling.
