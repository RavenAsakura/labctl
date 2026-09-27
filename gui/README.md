# LabCTL GUI

The Qt 6 interface provides dedicated pages for LabCTL monitoring, diagnostics, and service management.

## Pages

- **Dashboard** — system health, profile, CPU/GPU temperatures, memory, storage, connectivity, alerts, five-minute history graphs, and optional 10-second refresh.
- **Monitor** — detailed workstation resource summary.
- **Services** — status and start, stop, or restart controls for Docker, Libvirt, VMware, VirtualBox, and Ollama.
- **Workloads** — read-only inventory and current state of Docker containers and Libvirt, VMware, and VirtualBox machines.
- **Network** — network interface and traffic information.
- **Storage** — filesystem capacity and disk activity.
- **Reports** — read-only `labctl doctor` diagnostic output.
- **Settings** — LabCTL installation and platform information.

Set `LABCTL_CLI` to an executable path when the CLI cannot be discovered automatically.

Privileged service actions display a confirmation dialog and then use PolicyKit (`pkexec`) so that authentication is handled by KDE instead of an invisible terminal prompt. Read-only pages do not request elevated privileges.

The header displays command progress and provides a Cancel button for running commands.

The GUI consumes the versioned `labctl monitor dashboard --json` interface instead of parsing human-oriented terminal output. Graph history is intentionally held only in memory and is cleared when the application closes.

## Build and test

Complete runtime and build dependencies are documented in [../REQUIREMENTS.md](../REQUIREMENTS.md).

Ubuntu/Kubuntu development packages:

```bash
sudo apt install cmake ninja-build policykit-1 qt6-base-dev
```

```bash
cmake -S gui -B gui/build -DBUILD_TESTING=ON
cmake --build gui/build
ctest --test-dir gui/build --output-on-failure
```

The test suite includes CLI checks, profile safety checks, and an offscreen Qt navigation/control test.
