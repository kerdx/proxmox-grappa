#!/usr/bin/env bash

# Copyright (c) 2026 Grappa Helper-Script contributors
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/vjt/grappa-irc
#
# Development entry point: this script targets ProxmoxVED until it is accepted
# and promoted by the community-scripts maintainers.

GRAPPA_SCRIPT_URL="${GRAPPA_SCRIPT_URL:-https://raw.githubusercontent.com/kerdx/proxmox-grappa/main}"
PROXMOXVE_URL="${PROXMOXVE_URL:-${PROXMOXVED_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main}}"
GRAPPA_SCRIPT_ROOT="$(mktemp -d)"
mkdir -p "${GRAPPA_SCRIPT_ROOT}/misc"

if ! curl -fsSL "${PROXMOXVE_URL}/misc/build.func" \
  -o "${GRAPPA_SCRIPT_ROOT}/misc/build.func"; then
  echo "Unable to download the Proxmox VE Community Scripts framework." >&2
  exit 1
fi

# The legacy ProxmoxVE build helper hard-codes its installer origin. Redirect
# only that path so the shared framework still comes from the official source.
sed -i \
  's|https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/|${GRAPPA_SCRIPT_URL}/install/|g' \
  "${GRAPPA_SCRIPT_ROOT}/misc/build.func"

trap 'rm -rf "$GRAPPA_SCRIPT_ROOT"' EXIT 

export GRAPPA_SCRIPT_URL
export COMMUNITY_SCRIPTS_URL="$PROXMOXVE_URL"
source "${GRAPPA_SCRIPT_ROOT}/misc/build.func"

APP="Grappa"
GRAPPA_REPOSITORY="vjt/grappa-irc"
GRAPPA_DEFAULT_VERSION="latest"
GRAPPA_HOME="/opt/grappa"
GRAPPA_HELPER_ENV="${GRAPPA_HOME}/grappa-helper.env"

var_tags="${var_tags:-irc;chat;docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"
var_mknod="${var_mknod:-1}"
var_fuse="${var_fuse:-no}"
var_arm64="${var_arm64:-no}" # Docker-in-LXC deployment is not yet verified on PVE arm64.
var_install="${var_install:-grappa}"
var_phx_host="${var_phx_host:-}"
var_grappa_version="${var_grappa_version:-$GRAPPA_DEFAULT_VERSION}"

export var_phx_host
export var_grappa_version

header_info "$APP"
variables
color
catch_errors

function valid_grappa_version() {
  [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z]+)*$ ]]
}

function get_helper_value() {
  local key="$1"
  sed -n "s/^${key}=//p" "$GRAPPA_HELPER_ENV" | tail -n 1
}

function download_grappa_bootstrap() {
  local release="$1"
  local destination="$2"

  curl -fsSL \
    "https://raw.githubusercontent.com/${GRAPPA_REPOSITORY}/${release}/infra/docker/get.sh" \
    -o "$destination"
  chmod 700 "$destination"
}

function grappa_is_healthy() {
  [[ "$(docker inspect -f '{{.State.Running}}' grappa 2>/dev/null)" == "true" ]] || return 1
  docker exec grappa curl -fsS -o /dev/null http://localhost:4000/healthz
}

function fail_unhealthy_grappa() {
  msg_warn "Grappa is not healthy. Recent container logs follow:"
  docker logs --tail 100 grappa >&2 || true
  msg_error "Grappa is not healthy."
  exit 1
}

function latest_grappa_version() {
  curl -fsSL "https://api.github.com/repos/${GRAPPA_REPOSITORY}/releases/latest" \
    | sed -n 's/^[[:space:]]*"tag_name": "\([^"]*\)".*/\1/p' \
    | head -n 1
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f "$GRAPPA_HELPER_ENV" ]]; then
    msg_error "No managed ${APP} installation found at ${GRAPPA_HOME}!"
    exit 1
  fi

  local current_version latest_version grappa_publish bootstrap_script
  current_version="$(get_helper_value GRAPPA_VERSION)"
  grappa_publish="$(get_helper_value GRAPPA_PUBLISH)"

  if ! valid_grappa_version "$current_version"; then
    msg_error "The recorded Grappa version is invalid: '${current_version:-missing}'."
    exit 1
  fi

  grappa_publish="${grappa_publish:-0.0.0.0:4000}"
  latest_version="$(latest_grappa_version)"
  if ! valid_grappa_version "$latest_version"; then
    msg_error "Could not determine a valid latest Grappa release."
    exit 1
  fi

  if [[ "$current_version" == "$latest_version" ]]; then
    if ! grappa_is_healthy; then
      fail_unhealthy_grappa
    fi
    msg_ok "Grappa is already at ${current_version} and healthy."
    exit 0
  fi

  bootstrap_script="$(mktemp)"
  trap 'rm -f "$bootstrap_script"' EXIT

  msg_info "Updating Grappa from ${current_version} to ${latest_version}"
  download_grappa_bootstrap "$latest_version" "$bootstrap_script"

  export GRAPPA_HOME
  export GRAPPA_CONTAINER="grappa"
  export GRAPPA_PUBLISH="$grappa_publish"
  export GRAPPA_RAW_BASE="https://raw.githubusercontent.com/${GRAPPA_REPOSITORY}/${latest_version}"
  export GRAPPA_IMAGE="ghcr.io/vjt/grappa:${latest_version}"

  cd "$GRAPPA_HOME" || exit 1
  bash "$bootstrap_script" -s -- update

  if ! grappa_is_healthy; then
    fail_unhealthy_grappa
  fi

  sed -i "s/^GRAPPA_VERSION=.*/GRAPPA_VERSION=${latest_version}/" "$GRAPPA_HELPER_ENV"
  msg_ok "Updated Grappa to ${latest_version}"
  exit 0
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using:${CL}"
echo -e "${TAB}${GATEWAY}http://${IP}:4000${CL}"
echo -e "${INFO}${YW} Create the first admin user with: docker exec -it grappa bin/grappa create-user admin --admin${CL}"
