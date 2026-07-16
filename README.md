# LabCTL

LabCTL is a modular Linux workstation management toolkit for Fedora.

## Current modules

1. battery
2. docker
3. firewall
4. gpu
5. libvirt
6. network
7. onedrive
8. ollama
9. vm
10. vmware

## General usage

    labctl help
    labctl modules
    labctl version
    labctl health

## Examples

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

## Project structure

    Linux_Services/
    ├── labctl
    ├── labctl.health.backup
    ├── lab-ai
    ├── lab-docker
    ├── lab-vmware
    ├── modules/
    ├── reports/
    ├── README.md
    ├── CHANGELOG.md
    └── .gitignore

## Validation

    bash -n labctl
    bash -n labctl.health.backup

    for file in modules/*.sh; do
        bash -n "$file" || exit 1
    done
