# Hypernode Deploy

This repository contains the deployment tooling for the Arteco Hypernode video management platform. It bundles shell scripts and Docker Compose descriptors that provision the full Hypernode stack and its supporting services on a fresh Linux host.

## Repository structure

- `installer_docker/` – Turn‑key installers and Docker Compose bundles used to bootstrap Hypernode. The `installer.sh` script orchestrates the installation, while `composes/` holds the service definitions for the API server, database, storage, camera ingestion, and related workers.
- `installer_docker/install-docker-ubuntu.sh` – Convenience script that installs Docker Engine and the Compose plugin on Ubuntu-based systems.
- `ffmpeg/` – Optional ffmpeg and ffprobe binaries plus notes (`ffmpeg.md`) for sourcing compatible builds when distributing the platform without the Arteco server package.
- `hypernode_deploy.code-workspace` – Visual Studio Code workspace definition for contributors.

## Getting started

1. **Prepare the host**
   - Use a Linux server (Ubuntu is tested) with sudo privileges.
   - Ensure the system clock and DNS are correctly configured.
   - Install Docker by running `installer_docker/install-docker-ubuntu.sh` or by following the official Docker documentation.
   - Confirm that ports `80` and `443` are reachable if the node must expose public HTTPS endpoints.
   - Keep the serial number, timezone, and provider URLs ready before starting the installer so the first run can complete without manual rework.

2. **Run the Hypernode installer**
   - Execute `installer_docker/installer.sh` with the options that match your environment. Key flags include:
     - `--tag` to pick the Docker image tag (defaults to `latest`).
     - `--port` to expose the HTTPS endpoint (defaults to `443`).
     - `--mode` to select the installation profile for the node you are deploying.
     - `--serial-number`, `--internal-name`, and `--timezone` to register the device metadata.
     - `--email` and `--password` to seed the administrator credentials.
     - `--deploy-branch` to choose which Git branch to load the remote compose bundles from (defaults to `main`).
     - Provider URLs (`--certificate-provider-url`, `--dns-provider-url`, `--license-provider-url`, `--update-provider-url`) when the deployment relies on external Arteco services.
   - Run the script with `--help` to view the full list of options and examples.

3. **Review compose bundles**
   - Each folder inside `installer_docker/composes/` contains a dedicated `docker-compose.yaml` that can be used independently for advanced deployments. Services are grouped by domain—such as `server`, `database`, `storage`, `recording`, and `camera`—so you can mix and match the components required for your installation.

4. **Run a post-install validation**
   - From the deployed machine, run `installer_docker/uss_healthcheck.sh` to verify container health, DNS resolution, HTTPS reachability, and the resolved database port.
   - When troubleshooting a node that was reinstalled or moved to a different network, validate both the LAN URL (`<serial>.lan.omniaweb.cloud`) and the WAN URL (`<serial>.my.omniaweb.cloud`) before handing the system over.

## Maintenance tips

- Re-run `installer.sh` with `--force-install` to refresh an existing node or to apply updated container images.
- Monitor containers with `docker compose ps` or `docker compose logs` from the relevant compose directory.
- When distributing the platform without the Arteco server package, consult `ffmpeg/ffmpeg.md` to obtain compatible ffmpeg binaries.
- For storage-related incidents where `recording` or `snapshot` start writing to the root filesystem, use the recovery playbook in `installer_docker/README/ROOT_FULL_RECORDING_SNAPSHOT_PLAYBOOK.md`.

## Support

For assistance or licensing questions, contact Arteco Global through the usual support channels or your Arteco representative.
