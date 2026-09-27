# Requirements

LabCTL is designed for Linux workstations running Ubuntu/Kubuntu or Fedora. Most integrations are optional and are detected at runtime.

## Supported platforms

- Ubuntu or Kubuntu 24.04 LTS or newer.
- Fedora Workstation 40 or newer.
- Bash 4.4 or newer.
- A systemd-based system is recommended for service controls.
- KDE Plasma is recommended for the graphical application, but the CLI does not require a particular desktop environment.

Other Linux distributions may work when equivalent commands are available, but they are not currently tested.

## CLI requirements

The base command-line interface uses common Linux utilities:

- Bash
- GNU coreutils
- `awk`, `sed`, `grep`, and `find`
- `procps`
- `iproute2`
- `util-linux`
- systemd command-line tools

Install the base dependencies on Ubuntu/Kubuntu:

```bash
sudo apt update
sudo apt install bash coreutils findutils gawk grep iproute2 procps sed systemd util-linux
```

Install them on Fedora:

```bash
sudo dnf install bash coreutils findutils gawk grep iproute procps-ng sed systemd util-linux
```

## GUI runtime requirements

- Qt 6.4 or newer: Core, GUI, and Widgets modules.
- PolicyKit and `pkexec` for privileged graphical actions.
- The `labctl` executable from the same project checkout or available in `PATH`.

When running from a source checkout, point the GUI to the CLI explicitly:

```bash
LABCTL_CLI="$PWD/labctl" ./gui/build/labctl-gui
```

## GUI build requirements

- CMake 3.21 or newer.
- A compiler with C++20 support, such as GCC 11 or newer or Clang 14 or newer.
- Qt 6.4 development packages.
- Qt Test when building the automated test suite.

Ubuntu/Kubuntu:

```bash
sudo apt install build-essential cmake ninja-build policykit-1 qt6-base-dev
```

Fedora:

```bash
sudo dnf install cmake gcc-c++ ninja-build polkit qt6-qtbase-devel
```

Build and test:

```bash
cmake -S gui -B gui/build -DBUILD_TESTING=ON
cmake --build gui/build
ctest --test-dir gui/build --output-on-failure
```

## Optional integrations

Install only the tools required by your workstation and laboratory:

| Feature | Commands or packages detected |
| --- | --- |
| NVIDIA monitoring | `nvidia-smi` and the proprietary NVIDIA driver |
| Hardware temperatures | `sensors` from `lm-sensors` |
| NVMe information | `nvme` from `nvme-cli` |
| Network and VPN details | `nmcli` from NetworkManager |
| Power profiles | `powerprofilesctl` or `tuned-adm` |
| Docker | Docker Engine and the `docker` CLI |
| QEMU/KVM | Libvirt, `virsh`, and QEMU/KVM |
| VirtualBox | `VBoxManage` |
| VMware | `vmrun` and VMware Workstation |
| Local AI services | Ollama |
| OneDrive synchronization | OneDrive Linux client |
| Ubuntu firewall | UFW |
| Fedora firewall | Firewalld |

Missing optional integrations are reported as unavailable and do not prevent the rest of LabCTL from running.

## Permissions

Read-only monitoring normally runs as the current user. Service changes, firewall operations, and profile application may require administrator authorization.

The GUI uses PolicyKit instead of requesting a password in an invisible terminal. CLI commands may use `sudo` where required by the operating system.

## Test-only dependency

The CLI JSON contract test uses Python 3 to validate structured output. Python is not required for normal LabCTL operation.
