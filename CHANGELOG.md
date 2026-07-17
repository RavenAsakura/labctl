# Changelog

All notable changes to LabCTL are documented in this file.

## [Unreleased]

### Added

- `doctor` module for detailed Fedora workstation diagnostics.
- Color-aware diagnostic output with `PASS`, `INFO`, `WARNING`, and `ERROR` result levels.
- System health classifications: `EXCELLENT`, `HEALTHY`, `ATTENTION NEEDED`, and `CRITICAL`.
- Separate recommendations section in diagnostic output.
- Automatic terminal detection for color output.
- `labctl about` command for project, Git, and platform information.
- `labctl info` alias for the `about` command.
- Repository, branch, commit, latest tag, module count, operating system, kernel, architecture, and license details in `about` output.

### Changed

- Development version updated to `2.3.0-dev`.
- GitHub repository remotes are displayed in `owner/repository` format instead of full SSH or HTTPS remote URLs.
- Main help output now documents `doctor`, `about`, and `info`.
- Module counting excludes the internal `utils` module.
- Module counter increment logic no longer depends on the exit status of arithmetic post-increment under strict shell settings.
- Redirected and piped output no longer contains ANSI color escape sequences.

### Fixed

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
