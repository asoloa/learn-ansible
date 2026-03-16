#!/usr/bin/env bash
# Installs Ansible on RHEL9 or compatible distros using dnf.

set -euo pipefail

# Terminal-aware ANSI color helpers for nicer output.
if [ -t 1 ]; then
	RED=$(printf '\033[31m')
	GREEN=$(printf '\033[32m')
	RESET=$(printf '\033[0m')
else
	RED=''
	GREEN=''
	RESET=''
fi

# Colored helpers: INFO to stdout, ERROR to stderr.
log() { printf '%s[INFO]%s %s\n' "$GREEN" "$RESET" "$*"; }
err() { printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*" >&2; }

# Abort early if not running as root.
require_root() {
	if [ "${EUID:-$(id -u)}" -ne 0 ]; then
		err "This script must be run as root (or with sudo)."
		exit 1
	fi
}

check_command() {
	command -v "$1" >/dev/null 2>&1
}

check_os() {
	if [ ! -r /etc/os-release ]; then
		err "/etc/os-release not found; cannot detect OS."
		exit 1
	fi
	. /etc/os-release
	ID_LOWER=$(printf "%s" "$ID" | tr '[:upper:]' '[:lower:]')
	# Accept RHEL 9 and common RHEL-derived distributions.
	case "$ID_LOWER" in
		almalinux|rhel|rocky|centos|centos-stream|ol|oraclelinux)
			;;
		*)
			err "Detected OS: $PRETTY_NAME. This script targets RHEL 9 or compatible distributions (AlmaLinux, Rocky, CentOS Stream, Oracle Linux). Aborting."
			exit 1
			;;
	esac
	case "$VERSION_ID" in
		9* ) log "Detected $PRETTY_NAME $VERSION_ID" ;;
		* ) err "Detected version $VERSION_ID — this script targets RHEL/AlmaLinux 9.x." ; exit 1 ;;
	esac
}

install_ansible() {
	log "Installing Ansible and required system packages."

	if ! check_command dnf; then
		err "dnf not found! Cannot install packages."; exit 1
	fi

	log "Enabling EPEL repository (if not already enabled)."
	dnf -y install epel-release || log "epel-release not available or already enabled."

    log "Upgrading system packages and installing Ansible prerequisites (python3, git)."
	dnf -y upgrade --refresh
	dnf -y install python3 git

	# Prefer the higher-level `ansible` meta-package where available,
	# fall back to `ansible-core` if the meta-package is not present.
	if ! dnf -y install ansible 2>/dev/null; then
		if ! dnf -y install ansible-core 2>/dev/null; then
			err "Failed to install Ansible via dnf."; exit 1
		fi
		log "Installed ansible-core (ansible meta-package unavailable)."
	else
		log "Installed ansible meta-package."
	fi
}

# Remove only Ansible packages. Do not autoremove prerequisites.
uninstall_ansible() {
	log "Uninstalling Ansible packages (will not remove prerequisites)."
	if ! check_command dnf; then
		err "dnf not found! Cannot uninstall packages."; exit 1
	fi
	pkgs=()
	if command -v rpm >/dev/null 2>&1; then
		if rpm -q ansible-core >/dev/null 2>&1; then
			pkgs+=(ansible-core)
		fi
		if rpm -q ansible >/dev/null 2>&1; then
			pkgs+=(ansible)
		fi
	else
		# conservative fallback: try to remove common names
		pkgs+=(ansible-core ansible)
	fi

	if [ ${#pkgs[@]} -eq 0 ]; then
		log "No Ansible packages found to remove."
		return 0
	fi

	for p in "${pkgs[@]}"; do
		# Prevent automatic removal of packages that were installed as dependencies.
		if dnf -y remove --setopt=clean_requirements_on_remove=0 "$p"; then
			log "Removed $p"
		else
			err "Failed to remove $p"; exit 1
		fi
	done
	log "Ansible uninstallation complete."
}

verify_install() {
	if check_command ansible; then
		log "Ansible found:"; ansible --version
	else
		err "Ansible binary not found after installation."
		exit 1
	fi
}

usage() {
	cat <<EOF
Usage: $0 [--install | --uninstall]

Installs or uninstalls Ansible on RHEL 9 or compatible distros using dnf.
Options:
	--install       Install Ansible (default if no action given)
	--uninstall     Uninstall Ansible packages only
	-h | --help     Show this help message and exit
EOF
}

ACTION=""
while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			usage; exit 0
			;;
		--install)
			if [ -n "$ACTION" ] && [ "$ACTION" != "install" ]; then
				err "Conflicting actions specified."; usage; exit 1
			fi
			ACTION=install; shift;;
		--uninstall)
			if [ -n "$ACTION" ] && [ "$ACTION" != "uninstall" ]; then
				err "Conflicting actions specified."; usage; exit 1
			fi
			ACTION=uninstall; shift;;
		--) shift; break;;
		-* ) err "Unknown option: $1"; usage; exit 1;;
		* ) break;;
	esac
done

main() {
	require_root
	check_os
	# default action: install
	if [ -z "$ACTION" ]; then
		ACTION=install
	fi

	case "$ACTION" in
		install)
			# Fail fast: if Ansible is already present (binary or installed package), skip installation.
			if check_command ansible || { command -v rpm >/dev/null 2>&1 && { rpm -q ansible >/dev/null 2>&1 || rpm -q ansible-core >/dev/null 2>&1; }; }; then
				log "Ansible already installed; nothing to do here 🛸"
				return 0
			fi
			install_ansible
			verify_install
			log "Ansible installation completed successfully."
			;;
		uninstall)
			# Quick pre-check: if no Ansible binary and no installed packages, nothing to do.
			if ! check_command ansible && ! (command -v rpm >/dev/null 2>&1 && { rpm -q ansible >/dev/null 2>&1 || rpm -q ansible-core >/dev/null 2>&1; }); then
				log "Ansible not installed; nothing to do here 🛸"
				exit 0
			fi
			uninstall_ansible
			log "Ansible uninstallation completed successfully."
			;;
		*)
			err "Unknown action: $ACTION"; usage; exit 1
			;;
	esac
}

main "$@"


