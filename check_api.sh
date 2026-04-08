#!/usr/bin/env bash

#-------------------------------------------------------------
# Title: check_api.sh
# Description: Monitor API Magalu Cloud and send alert to GChat
# Author: Eduardo Silva
#-------------------------------------------------------------

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

# CONSTANTS
readonly __dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly __file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
readonly __file_name="$(basename "$__file")"
readonly __base="$(basename "${__file}" .sh)"

readonly _MSG_PARAMETER_REQUIRED_TEMPLATE="Missing required parameter: %s arg"
readonly URL="https://api.magalu.cloud/consumption/usage"

#-------------------------------------------------------------
# MAIN
#-------------------------------------------------------------
main() {
    need_cmd "curl"
    need_cmd "jq"

    info "Starting API check..."

    local endpoint="${URL}?accrual_period=${_parameter}"

    info "Calling endpoint: ${endpoint}"

    local response_file
    response_file=$(mktemp)

    local result
    result=$(curl \
        --silent \
        --show-error \
        --output "$response_file" \
        --write-out "%{http_code} %{time_total}" \
        --request GET \
        --url "$endpoint" \
        --header "x-api-key: ${API_KEY}" \
        --max-time 15 \
        --retry 3 \
        --retry-delay 5
    )

    local http_code
    local latency

    http_code=$(echo "$result" | awk '{print $1}')
    latency=$(echo "$result" | awk '{print $2}')

    log "HTTP Status: ${http_code}"
    log "Latency: ${latency}s"

    if [[ "$http_code" -ne 200 ]]; then
        error "API returned non-200 status"

        local response_body
        response_body=$(cat "$response_file")

        send_gchat_alert "❌ API ERROR
Endpoint: ${endpoint}
Status: ${http_code}
Latency: ${latency}s
Response: ${response_body}"

        exit 1
    fi

    info "API check succeeded ✅"
}

#-------------------------------------------------------------
# SEND GCHAT ALERT
#-------------------------------------------------------------
send_gchat_alert() {
    local message="$1"

    ensure_not_empty "${GCHAT_WEBHOOK_URL}" "GCHAT_WEBHOOK_URL"

    info "Sending alert to Google Chat..."

    local payload
    payload=$(jq -n --arg text "$message" '{text: $text}')

    curl \
        --silent \
        --show-error \
        --request POST \
        --header "Content-Type: application/json" \
        --data "$payload" \
        "$GCHAT_WEBHOOK_URL" || log "Failed to send GChat alert"
}

#-------------------------------------------------------------
# USAGE
#-------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$__file_name") -p accrual_period

Example:
  ./check_api.sh -p 2026-03

Required:
  -p, --parameter     accrual_period (ex: 2026-03)

Environment variables:
  API_KEY
  GCHAT_WEBHOOK_URL
EOF
  exit
}

#-------------------------------------------------------------
# PARAMS
#-------------------------------------------------------------
parse_params() {
  _flag=0
  _parameter=

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -f | --flag) _flag=1 ;;
    -p | --parameter)
      _parameter="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  ensure_not_empty "$_parameter" "$(printf "$_MSG_PARAMETER_REQUIRED_TEMPLATE" "-p or --parameter")"
}

#-------------------------------------------------------------
# CLEANUP
#-------------------------------------------------------------
cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
}

#-------------------------------------------------------------
# COLORS
#-------------------------------------------------------------
setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    ORANGE='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
  else
    NOFORMAT=''
    RED=''
    GREEN=''
    ORANGE=''
    BLUE=''
    PURPLE=''
    CYAN=''
    YELLOW=''
  fi
}

#-------------------------------------------------------------
# LOGGING
#-------------------------------------------------------------
msg() { echo >&2 -e "${1-}"; }

now(){ date +%F-%T; }

info(){ msg "${BLUE}${__file_name} | $(now) - INFO: ${1-} ${NOFORMAT}"; }

log(){ msg "${YELLOW}${__file_name} | $(now) - LOG: ${1-} ${NOFORMAT}"; }

error(){ msg "${RED}${__file_name} | $(now) - ERROR: ${1-} ${NOFORMAT}"; }

die() {
  local msg=$1
  local code=${2-1}
  error "$msg"
  exit "$code"
}

ensure() { if ! "$@"; then die "command failed: $*"; fi; }

ensure_not_empty() {
  if [ -z "$1" ]; then die "found empty string: $2"; fi
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "command not found: $1"
  fi
}

#-------------------------------------------------------------
# RUN
#-------------------------------------------------------------
setup_colors
parse_params "$@"
main "$@"
