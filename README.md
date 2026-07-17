# LabCTL

LabCTL is a modular workstation management and diagnostics toolkit for Fedora-based cybersecurity workstations.

It provides a single command-line interface for checking workstation health, managing laboratory services, inspecting hardware, and controlling virtualization and cloud-related tools without replacing standard Linux utilities.

## Development status

Current development version:

    2.3.0-dev

Latest stable release:

    2.2.0

## Core commands

    labctl health
    labctl doctor
    labctl about
    labctl info
    labctl modules
    labctl version
    labctl help

### Command overview

- `health` shows a quick workstation health summary.
- `doctor` runs detailed workstation diagnostics and recommendations.
- `about` shows LabCTL, Git repository, and platform information.
- `info` is an alias for `about`.
- `modules` lists the installed LabCTL modules.
- `version` prints the current LabCTL version.
- `help` displays general usage and available modules.

## Current modules

1. battery
2. docker
3. doctor
4. firewall
5. gpu
6. libvirt
7. network
8. ollama
9. onedrive
10. vm
11. vmware

The internal `utils` module provides shared output and formatting functions and is not listed as a user-facing module.

## Examples

    labctl about
    labctl doctor
    labctl battery status
    labctl docker status
    labctl firewall status
    labctl gpu status
    labctl libvirt status
    labctl network list
    labctl onedrive status
    labctl ollama status
    labctl vm list
    labctl vmware status

## Diagnostic output

The `doctor` command uses four diagnostic result levels:

- `PASS` — the check completed successfully.
- `INFO` — informational data that does not indicate a problem.
- `WARNING` — an item that may require attention.
- `ERROR` — a failed or critical check.

The final system health classification is one of:

- `EXCELLENT`
- `HEALTHY`
- `ATTENTION NEEDED`
- `CRITICAL`

Color output is enabled automatically when LabCTL is connected to an interactive terminal. ANSI color codes are omitted when output is redirected to a file or pipeline.

## Project structure

    Linux_Services/
    ├── labctl
    ├── labctl.health.backup
    ├── lab-ai
    ├── lab-docker
    ├── lab-vmware
    ├── modules/
    │   ├── battery.sh
    │   ├── docker.sh
    │   ├── doctor.sh
    │   ├── firewall.sh
    │   ├── gpu.sh
    │   ├── libvirt.sh
    │   ├── network.sh
    │   ├── ollama.sh
    │   ├── onedrive.sh
    │   ├── utils.sh
    │   ├── vm.sh
    │   └── vmware.sh
    ├── reports/
    ├── README.md
    ├── CHANGELOG.md
    ├── LICENSE
    └── .gitignore

`labctl.health.backup` is retained temporarily for the current `health` implementation and is planned for refactoring in a later development phase.

## Validation

Validate the main executable and the current health script:

    bash -n labctl
    bash -n labctl.health.backup

Validate every module:

    for file in modules/*.sh; do
        echo "Checking: $file"
        bash -n "$file" || exit 1
    done

Run basic functional checks:

    ./labctl version
    ./labctl about
    ./labctl info
    ./labctl modules
    ./labctl doctor
    ./labctl help

## Development workflow

LabCTL development uses feature branches and pull requests to keep `main` stable.

    git switch -c feat/example

    # Modify and validate complete files.

    git add <files>
    git commit -m "feat(scope): describe the change"
    git push -u origin feat/example

Create and review a pull request before merging the branch into `main`.

## Design principles

- LabCTL focuses on Fedora cybersecurity workstation administration.
- Modules should provide workflow-specific value rather than duplicate standard Linux commands.
- User-facing output and documentation are written in English.
- Modules use a common dispatch pattern and shared output functions.
- Potentially destructive operations should require clear confirmation.
- Redirected output must remain free of terminal color escape sequences.

## Roadmap

Planned development priorities include:

- Refactor the legacy health implementation.
- Add automated validation tests.
- Generate workstation reports.
- Add hardware and software inventory reporting.
- Add Fedora, firmware, Flatpak, and reboot-status update checks.

## License

LabCTL is distributed under the MIT License. See `LICENSE` for the complete license text.
