#!/usr/bin/env bash

# Copyright (c) 2026 Grappa Helper-Script contributors
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/vjt/grappa-irc

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

GRAPPA_REPOSITORY="vjt/grappa-irc"
GRAPPA_ROOT="/opt/grappa"
GRAPPA_HELPER_ENV="${GRAPPA_ROOT}/grappa-helper.env"
GRAPPA_CONTAINER="grappa"
GRAPPA_PUBLISH="${GRAPPA_PUBLISH:-0.0.0.0:4000}"
GRAPPA_VERSION="${var_grappa_version:-v1.5.1}"

function valid_grappa_version() {
  [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z]+)*$ ]]
}

function valid_phx_host() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.:-]*$ ]]
}

function grappa_is_healthy() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$GRAPPA_CONTAINER" 2>/dev/null)" == "true" ]] || return 1
  docker exec "$GRAPPA_CONTAINER" curl -fsS -o /dev/null http://localhost:4000/healthz
}

function fail_unhealthy_grappa() {
  msg_warn "Grappa did not become healthy. Recent container logs follow:"
  docker logs --tail 100 "$GRAPPA_CONTAINER" >&2 || true
  msg_error "Grappa did not become healthy."
  exit 1
}

if ! valid_grappa_version "$GRAPPA_VERSION"; then
  msg_error "Invalid Grappa version '${GRAPPA_VERSION}'. Use a release tag such as v1.5.1."
  exit 1
fi

get_lxc_ip
PHX_HOST="${var_phx_host:-${LOCAL_IP:-}}"
if ! valid_phx_host "$PHX_HOST"; then
  msg_error "A valid public hostname or container IP is required. Set var_phx_host when the container has no IPv4 address."
  exit 1
fi

msg_info "Installing Docker"
ensure_dependencies curl
setup_docker
msg_ok "Installed Docker"

msg_info "Installing Grappa ${GRAPPA_VERSION}"
mkdir -p "$GRAPPA_ROOT"
cd "$GRAPPA_ROOT" || exit 1

bootstrap_script="$(mktemp)"
trap 'rm -f "$bootstrap_script"' EXIT

curl -fsSL \
  "https://raw.githubusercontent.com/${GRAPPA_REPOSITORY}/${GRAPPA_VERSION}/infra/docker/get.sh" \
  -o "$bootstrap_script"
chmod 700 "$bootstrap_script"

export GRAPPA_HOME="$GRAPPA_ROOT"
export GRAPPA_CONTAINER
export GRAPPA_PUBLISH
export GRAPPA_RAW_BASE="https://raw.githubusercontent.com/${GRAPPA_REPOSITORY}/${GRAPPA_VERSION}"
export GRAPPA_IMAGE="ghcr.io/vjt/grappa:${GRAPPA_VERSION}"
export PHX_HOST
bash "$bootstrap_script" install

umask 077
cat >"$GRAPPA_HELPER_ENV" <<EOF
GRAPPA_VERSION=${GRAPPA_VERSION}
GRAPPA_PUBLISH=${GRAPPA_PUBLISH}
EOF
chmod 600 "$GRAPPA_HELPER_ENV"

if ! grappa_is_healthy; then
  fail_unhealthy_grappa
fi
msg_ok "Installed Grappa ${GRAPPA_VERSION}"

motd_ssh
customize
cleanup_lxc
