#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_FILE="${SCRIPT_DIR}/hermes-profiles.yaml"
ENV_FILE="${SCRIPT_DIR}/hermes.env"
SECRET_FILE="${SCRIPT_DIR}/.secret"
IMAGE_NAME="hermes-custom"
BASE_IMAGE="nousresearch/hermes-agent:latest"
DEFAULT_DATA_BASE="${HOME}/dockered-hermes"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }

TEMP_FILES=()
cleanup_temp_files() { rm -f "${TEMP_FILES[@]}"; }
trap cleanup_temp_files EXIT

check_deps() {
  for cmd in yq podman; do
    command -v "$cmd" &>/dev/null || die "'$cmd' is required but not found in PATH"
  done
}

profile_exists() {
  local result
  result=$(yq eval ".profiles.${1}" "$PROFILES_FILE" 2>/dev/null)
  [[ -n "$result" && "$result" != "null" ]]
}

profile_field() {
  local profile="$1" field="$2" default="${3:-}"
  local val
  val=$(yq eval ".profiles.${profile}.${field} // \"\"" "$PROFILES_FILE" 2>/dev/null)
  if [[ -z "$val" || "$val" == "null" ]]; then
    echo "$default"
  else
    echo "$val"
  fi
}

default_field() {
  local field="$1" default="${2:-}"
  local val
  val=$(yq eval ".defaults.${field} // \"\"" "$PROFILES_FILE" 2>/dev/null)
  if [[ -z "$val" || "$val" == "null" ]]; then
    echo "$default"
  else
    echo "$val"
  fi
}

resolve_profile() {
  local name="$1"
  PROFILE="$name"
  GATEWAY_PORT=$(profile_field "$name" "gateway_port")
  DASHBOARD_PORT=$(profile_field "$name" "dashboard_port")
  DATA_DIR=$(profile_field "$name" "data_dir" "${DEFAULT_DATA_BASE}/.${name}")
  CPU=$(profile_field "$name" "cpu" "$(default_field "cpu" "1")")
  MEMORY=$(profile_field "$name" "memory" "$(default_field "memory" "1g")")
  DISK=$(profile_field "$name" "disk" "$(default_field "disk" "5g")")

  if [[ -z "$GATEWAY_PORT" ]]; then die "Profile '${name}' missing 'gateway_port'"; fi
  if [[ -z "$DASHBOARD_PORT" ]]; then die "Profile '${name}' missing 'dashboard_port'"; fi
}

lookup_secret() {
  local key="$1"
  if [[ ! -f "$SECRET_FILE" ]]; then
    die "Secret file not found: ${SECRET_FILE}"
  fi
  local val
  val=$(grep -E "^${key}=" "$SECRET_FILE" | head -1 | cut -d'=' -f2-)
  if [[ -z "$val" ]]; then
    die "Secret '${key}' not found in ${SECRET_FILE}"
  fi
  echo "$val"
}

resolve_placeholders() {
  local src_file="$1"
  if [[ ! -f "$src_file" ]]; then
    die "File not found: ${src_file}"
  fi
  if [[ ! -f "$SECRET_FILE" ]]; then
    die "Secret file not found: ${SECRET_FILE}"
  fi

  local tmpfile
  tmpfile=$(mktemp)
  TEMP_FILES+=("$tmpfile")
  local unresolved=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && echo "$line" >> "$tmpfile" && continue
    local resolved="$line"
    local placeholders
    placeholders=$(grep -oP '\$\{\K[^}]+' <<< "$line" || true)
    for key in $placeholders; do
      local val
      if ! val=$(lookup_secret "$key" 2>/dev/null); then
        echo "ERROR: Secret '${key}' not found in ${SECRET_FILE}" >&2
        unresolved=1
        val="UNRESOLVED_${key}"
      fi
      resolved="${resolved//\$\{${key}\}/${val}}"
    done
    echo "$resolved" >> "$tmpfile"
  done < "$src_file"

  if [[ "$unresolved" -eq 1 ]]; then
    rm -f "$tmpfile"
    die "Unresolved placeholders in ${src_file}. Check ${SECRET_FILE}."
  fi

  echo "$tmpfile"
}

build_env_flags() {
  local profile="$1"
  local flags=""

  # Resolve shared env file (hermes.env with ${KEY} placeholders)
  if [[ -f "$ENV_FILE" ]]; then
    local resolved_env
    resolved_env=$(resolve_placeholders "$ENV_FILE")
    flags="--env-file ${resolved_env}"
  fi

  # Profile-specific env vars with ${KEY} placeholder resolution
  local env_count
  env_count=$(yq eval ".profiles.${profile}.env | length // 0" "$PROFILES_FILE" 2>/dev/null || echo "0")
  if [[ "$env_count" -gt 0 ]]; then
    while IFS='=' read -r key value; do
      local resolved_val="$value"
      local placeholders
      placeholders=$(grep -oP '\$\{\K[^}]+' <<< "$value" || true)
      for secret_key in $placeholders; do
        local secret_val
        secret_val=$(lookup_secret "$secret_key")
        resolved_val="${resolved_val//\$\{${secret_key}\}/${secret_val}}"
      done
      flags="${flags} -e ${key}=${resolved_val}"
    done < <(yq eval ".profiles.${profile}.env | to_entries[] | \"\(.key)=\(.value)\"" "$PROFILES_FILE" 2>/dev/null)
  fi

  echo "$flags"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_build() {
  echo "Building ${IMAGE_NAME} from ${BASE_IMAGE}..."
  podman build -t "$IMAGE_NAME" -f "${SCRIPT_DIR}/Dockerfile" "$SCRIPT_DIR"
  echo "Done. Image '${IMAGE_NAME}' ready."
}

cmd_setup() {
  local name="${1:?Usage: $0 setup <profile-name>}"
  profile_exists "$name" || die "Profile '${name}' not found in ${PROFILES_FILE}"
  resolve_profile "$name"

  mkdir -p "$DATA_DIR"
  chmod 777 "$DATA_DIR"

  local env_flags
  env_flags=$(build_env_flags "$name")

  echo "Setting up profile '${name}' (data: ${DATA_DIR})..."
  # shellcheck disable=SC2086
  podman run -it --rm \
    --name "${name}-setup" \
    --volume "${DATA_DIR}:/opt/data" \
    --env "HERMES_UID=$(id -u)" \
    --env "HERMES_GID=$(id -g)" \
    ${env_flags} \
    "$IMAGE_NAME" setup

  # Copy SOUL.md after setup to avoid being overwritten by hermes init
  local soul_file
  soul_file=$(profile_field "$name" "soul" "")
  if [[ -n "$soul_file" ]]; then
    local soul_abs
    soul_abs=$(cd "$(dirname "$soul_file")" && pwd)/$(basename "$soul_file")
    if [[ -f "$soul_abs" ]]; then
      local soul_dir soul_basename
      soul_dir=$(dirname "$soul_abs")
      soul_basename=$(basename "$soul_abs")
      # Copy via container to ensure correct ownership
      # shellcheck disable=SC2086
      podman run --rm \
        --volume "${DATA_DIR}:/opt/data" \
        --volume "${soul_dir}:/opt/soul-src:ro" \
        --env "HERMES_UID=$(id -u)" \
        --env "HERMES_GID=$(id -g)" \
        "$IMAGE_NAME" \
        sh -c "cp /opt/soul-src/${soul_basename} /opt/data/SOUL.md"
      echo "SOUL.md initialized from ${soul_file}"
    else
      echo "Warning: SOUL file not found: ${soul_file}"
    fi
  fi
}

cmd_start() {
  local name="${1:?Usage: $0 start <profile-name>}"
  profile_exists "$name" || die "Profile '${name}' not found in ${PROFILES_FILE}"
  resolve_profile "$name"

  # Stop existing container if running
  if podman container exists "$name" 2>/dev/null; then
    if podman inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
      echo "Stopping existing container '${name}'..."
      podman stop "$name" >/dev/null 2>&1 || true
    fi
    podman rm "$name" >/dev/null 2>&1 || true
  fi

  mkdir -p "$DATA_DIR"
  chmod 777 "$DATA_DIR"

  local env_flags
  env_flags=$(build_env_flags "$name")

  echo "Starting profile '${name}' (gateway:${GATEWAY_PORT} dashboard:${DASHBOARD_PORT} data:${DATA_DIR})..."
  # shellcheck disable=SC2086
  podman run -d \
    --name "$name" \
    --restart unless-stopped \
    --cpus="$CPU" \
    --memory="$MEMORY" \
    --volume "${DATA_DIR}:/opt/data" \
    --publish "${GATEWAY_PORT}:8642" \
    --publish "${DASHBOARD_PORT}:9119" \
    --env HERMES_DASHBOARD=1 \
    --env "HERMES_UID=$(id -u)" \
    --env "HERMES_GID=$(id -g)" \
    --shm-size=1g \
    ${env_flags} \
    "$IMAGE_NAME" gateway run

  echo "Started. Gateway: http://localhost:${GATEWAY_PORT}  Dashboard: http://localhost:${DASHBOARD_PORT}"
}

cmd_stop() {
  local name="${1:?Usage: $0 stop <profile-name>}"
  echo "Stopping '${name}'..."
  podman stop "$name" 2>/dev/null || echo "Container '${name}' not running"
  podman rm "$name" 2>/dev/null || true
  echo "Done."
}

cmd_chat() {
  local name="${1:?Usage: $0 chat <profile-name>}"
  profile_exists "$name" || die "Profile '${name}' not found in ${PROFILES_FILE}"
  resolve_profile "$name"

  mkdir -p "$DATA_DIR"
  chmod 777 "$DATA_DIR"

  local env_flags
  env_flags=$(build_env_flags "$name")

  echo "Opening chat for profile '${name}' (data: ${DATA_DIR})..."
  # shellcheck disable=SC2086
  podman run -it --rm \
    --name "${name}-chat" \
    --volume "${DATA_DIR}:/opt/data" \
    --env "HERMES_UID=$(id -u)" \
    --env "HERMES_GID=$(id -g)" \
    ${env_flags} \
    "$IMAGE_NAME"
}

cmd_logs() {
  local name="${1:?Usage: $0 logs <profile-name>}"
  local tail="${2:-100}"

  if [[ "$tail" == "--tail" ]]; then
    shift 2
    tail="${1:-100}"
  fi

  podman logs -f --tail "$tail" "$name"
}

cmd_update() {
  local name="${1:?Usage: $0 update <profile-name>}"
  profile_exists "$name" || die "Profile '${name}' not found in ${PROFILES_FILE}"

  echo "Pulling latest base image..."
  podman pull "$BASE_IMAGE"

  echo "Rebuilding custom image..."
  cmd_build

  echo "Restarting profile '${name}'..."
  cmd_stop "$name"
  cmd_start "$name"

  echo "Update complete."
}

cmd_list() {
  echo "Profiles defined in ${PROFILES_FILE}:"
  echo ""
  printf "%-15s %-10s %-10s %-10s %-30s\n" "PROFILE" "STATUS" "GATEWAY" "DASHBOARD" "DATA DIR"
  printf "%-15s %-10s %-10s %-10s %-30s\n" "-------" "------" "-------" "---------" "--------"

  local profiles
  profiles=$(yq eval '.profiles | keys | .[]' "$PROFILES_FILE" 2>/dev/null)

  for name in $profiles; do
    local gw_port dash_port data_dir status
    gw_port=$(profile_field "$name" "gateway_port")
    dash_port=$(profile_field "$name" "dashboard_port")
    data_dir=$(profile_field "$name" "data_dir" "${DEFAULT_DATA_BASE}/.${name}")

    if podman inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
      status="running"
    elif podman container exists "$name" 2>/dev/null; then
      status="stopped"
    else
      status="not created"
    fi

    printf "%-15s %-10s %-10s %-10s %-30s\n" "$name" "$status" "$gw_port" "$dash_port" "$data_dir"
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: $0 <command> [profile-name]

Commands:
  build                   Build the custom Hermes image with lark-cli
  setup  <profile-name>   First-time interactive setup
  start  <profile-name>   Start gateway + dashboard in background
  stop   <profile-name>   Stop a running container
  chat   <profile-name>   Open interactive CLI chat
  logs   <profile-name>   Tail container logs (optional: --tail N)
  update <profile-name>   Pull latest image + recreate
  list                    Show all profiles and their status

Examples:
  $0 build
  $0 setup hermes-1
  $0 start hermes-1
  $0 start hermes-2
  $0 list
  $0 chat hermes-1
  $0 logs hermes-2 --tail 50
  $0 stop hermes-1
EOF
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    build)  command -v podman &>/dev/null || die "'podman' is required but not found in PATH"; cmd_build ;;
    setup)  check_deps; cmd_setup "$@" ;;
    start)  check_deps; cmd_start "$@" ;;
    stop)   command -v podman &>/dev/null || die "'podman' is required but not found in PATH"; cmd_stop "$@" ;;
    chat)   check_deps; cmd_chat "$@" ;;
    logs)   command -v podman &>/dev/null || die "'podman' is required but not found in PATH"; cmd_logs "$@" ;;
    update) check_deps; cmd_update "$@" ;;
    list)   check_deps; cmd_list ;;
    -h|--help|help|"") usage ;;
    *) die "Unknown command: '${cmd}'. Run '$0 help' for usage." ;;
  esac
}

main "$@"
