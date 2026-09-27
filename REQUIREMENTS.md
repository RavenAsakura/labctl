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

> **Important:** the command below installs only the base CLI requirements. It does not install every optional laboratory integration.

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

## Ubuntu/Kubuntu module support

For the monitoring, battery, firewall, hardware, network, power, and Libvirt modules, install the relevant open-source packages:

```bash
sudo apt install apparmor-utils iw libvirt-clients libvirt-daemon-system lm-sensors network-manager nvme-cli pciutils policykit-1 power-profiles-daemon qemu-kvm smartmontools sudo ufw upower
```

This command intentionally does not install Docker, VirtualBox, VMware, Ollama, the NVIDIA proprietary driver, or the OneDrive client. Install those products only when you need their corresponding modules.

Do not install multiple power-management frameworks without checking for conflicts. LabCTL can use either `powerprofilesctl` from `power-profiles-daemon` or `tuned-adm` from TuneD.

## Fedora module support

For equivalent Fedora functionality:

```bash
sudo dnf install firewalld iw libvirt-client libvirt-daemon-kvm lm_sensors NetworkManager nvme-cli pciutils policycoreutils polkit power-profiles-daemon qemu-kvm smartmontools sudo upower
```

As on Ubuntu, Docker, VirtualBox, VMware, Ollama, NVIDIA drivers, and OneDrive remain separate installations.

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

| Module or feature | Required command | Ubuntu/Kubuntu package or source | Fedora package or source |
| --- | --- | --- | --- |
| Battery | `upower` | `upower` | `upower` |
| Hardware inventory | `lspci` | `pciutils` | `pciutils` |
| Temperatures | `sensors` | `lm-sensors` | `lm_sensors` |
| NVMe health | `nvme`, `smartctl` | `nvme-cli`, `smartmontools` | `nvme-cli`, `smartmontools` |
| Wi-Fi and VPN details | `nmcli`, `iw` | `network-manager`, `iw` | `NetworkManager`, `iw` |
| Power profiles | `powerprofilesctl` or `tuned-adm` | `power-profiles-daemon` or TuneD | `power-profiles-daemon` or `tuned` |
| AppArmor diagnostics | `aa-status` | `apparmor-utils` | Not applicable |
| SELinux diagnostics | `getenforce` | Not applicable | `policycoreutils` |
| Ubuntu firewall | `ufw` | `ufw` | Not applicable |
| Fedora firewall | `firewall-cmd` | Optional `firewalld` | `firewalld` |
| QEMU/KVM | `virsh` | `libvirt-clients`, `libvirt-daemon-system`, `qemu-kvm` | `libvirt-client`, `libvirt-daemon-kvm`, `qemu-kvm` |
| Docker | `docker` | Docker Engine installation | Docker Engine or distribution packages |
| VirtualBox | `VBoxManage` | VirtualBox installation | VirtualBox installation |
| VMware | `vmrun` | VMware Workstation installation | VMware Workstation installation |
| NVIDIA monitoring | `nvidia-smi` | NVIDIA proprietary driver | NVIDIA proprietary driver |
| Local AI services | `ollama` | Ollama installation | Ollama installation |
| OneDrive synchronization | `onedrive` | OneDrive Linux client | OneDrive Linux client |

Missing optional integrations are reported as unavailable and do not prevent the rest of LabCTL from running.

## Permissions

Read-only monitoring normally runs as the current user. Service changes, firewall operations, and profile application may require administrator authorization.

The GUI uses PolicyKit instead of requesting a password in an invisible terminal. CLI commands may use `sudo` where required by the operating system.

## Test-only dependency

The CLI JSON contract test uses Python 3 to validate structured output. Python is not required for normal LabCTL operation.
