#!/usr/bin/env bash
#
# Run the Flutter Quickstart E2E suite end to end: start a ThunderID server, provision the test
# application and user, build and install the sample, then drive it with Maestro.
#
# Every stage is idempotent, so re-running is safe and is the normal way to iterate.
#
# Usage:
#   ./run-e2e.sh                      Everything
#   ./run-e2e.sh --skip-server        Server already running and provisioned
#   ./run-e2e.sh --skip-build         Sample already installed on the device
#   ./run-e2e.sh flows/signin.yaml    Run one flow instead of the whole suite
#
#   Any argument that is not a recognised flag is passed through to Maestro, so extra Maestro
#   options and a specific flow path both work.
#
# Environment:
#   THUNDERID_VERSION  Release to run, without the leading "v" (default: latest release)
#   SERVER_URL         Where the server is reachable (default https://localhost:8090)
#   ADMIN_USERNAME     Admin user to bootstrap (default admin)
#   ADMIN_PASSWORD     Admin password (default admin)
#   E2E_USERNAME       Test user to create (default e2e_mobile_user)
#   E2E_PASSWORD       Test user password (default TestPassword@123)
#   INSTALL_DIR        Where to unpack the distribution (default ./.thunderid-server)
#
# Why not `npx thunderid`? That wrapper renders an interactive TUI and aborts with
# "bubbletea: could not open TTY" when stdout is not a terminal, which is always the case on a CI
# runner. The distribution's own setup.sh/start.sh take the same arguments non-interactively.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVER_URL="${SERVER_URL:-https://localhost:8090}"
ADMIN_USER="${ADMIN_USERNAME:-admin}"
ADMIN_PASS="${ADMIN_PASSWORD:-admin}"
E2E_USER="${E2E_USERNAME:-e2e_mobile_user}"
E2E_PASS="${E2E_PASSWORD:-TestPassword@123}"
INSTALL_DIR="${INSTALL_DIR:-$SCRIPT_DIR/.thunderid-server}"

# The sample owns its own application config, not the test script.
CONFIG_FILE="$SCRIPT_DIR/../../samples/quickstart/thunderid-config/thunderid-config.yaml"

# Must match the `id` in $CONFIG_FILE and the application ID the sample is built with.
APP_ID="019e5b10-1001-7a2b-9c3d-4e5f60718293"

do_server=true
do_build=true
do_test=true
maestro_args=()
for arg in "$@"; do
    case "$arg" in
        --skip-server) do_server=false ;;
        --skip-build) do_build=false ;;
        --skip-test) do_test=false ;;
        -h | --help) sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) maestro_args+=("$arg") ;;
    esac
done

for tool in curl jq openssl; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is required but not installed." >&2; exit 1; }
done

# ---------------------------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------------------------
start_server() {
    # Reuse a server that is already serving. All three mobile SDK suites bind the same port, so
    # failing here would mean tearing down a perfectly good server just to start an identical one.
    # Provisioning runs regardless and is idempotent, so the reused server still ends up correct.
    if curl -sk -o /dev/null --max-time 3 "$SERVER_URL/health/liveness" 2>/dev/null; then
        echo "==> A server is already serving at $SERVER_URL, reusing it"
        return 0
    fi

    command -v unzip >/dev/null 2>&1 || { echo "ERROR: unzip is required but not installed." >&2; exit 1; }

    local pkg_os pkg_arch
    case "$(uname -s)" in
        Darwin) pkg_os="macos" ;;
        Linux) pkg_os="linux" ;;
        *) echo "ERROR: unsupported OS $(uname -s)." >&2; exit 1 ;;
    esac
    case "$(uname -m)" in
        arm64 | aarch64) pkg_arch="arm64" ;;
        x86_64 | amd64) pkg_arch="x64" ;;
        *) echo "ERROR: unsupported architecture $(uname -m)." >&2; exit 1 ;;
    esac

    local version="${THUNDERID_VERSION:-}"
    if [ -z "$version" ]; then
        echo "==> Resolving the latest ThunderID release"
        version=$(curl -sSL https://api.github.com/repos/thunder-id/thunderid/releases/latest |
            jq -r '.tag_name // empty' | sed 's/^v//')
        if [ -z "$version" ]; then
            echo "ERROR: could not resolve the latest release (rate limited?). Set THUNDERID_VERSION." >&2
            exit 1
        fi
    fi

    local archive="thunderid-${version}-${pkg_os}-${pkg_arch}.zip"
    local url="https://github.com/thunder-id/thunderid/releases/download/v${version}/${archive}"
    local dist_home="$INSTALL_DIR/thunderid-${version}-${pkg_os}-${pkg_arch}"

    if [ ! -d "$dist_home" ]; then
        echo "==> Downloading $archive"
        mkdir -p "$INSTALL_DIR"
        curl -sSLf "$url" -o "$INSTALL_DIR/$archive"
        unzip -q "$INSTALL_DIR/$archive" -d "$INSTALL_DIR"
    fi

    echo "==> Running first-time setup"
    (cd "$dist_home" && ./setup.sh --admin-username "$ADMIN_USER" --admin-password "$ADMIN_PASS")

    echo "==> Starting the server"
    # The server has to outlive the step that starts it, which means leaving this process group:
    # `nohup` alone only ignores SIGHUP, so anything that signals the group still takes the server
    # down with it. setsid does that but does not exist on macOS, so fall back to Python, whose
    # start_new_session flag calls setsid in the child.
    if command -v setsid >/dev/null 2>&1; then
        (cd "$dist_home" && setsid ./start.sh > "$INSTALL_DIR/server.log" 2>&1 < /dev/null &)
    else
        python3 - "$dist_home" "$INSTALL_DIR/server.log" <<'PY'
import subprocess
import sys

dist_home, log_path = sys.argv[1], sys.argv[2]
with open(log_path, "ab") as log:
    subprocess.Popen(
        ["./start.sh"],
        cwd=dist_home,
        stdout=log,
        stderr=log,
        stdin=subprocess.DEVNULL,
        start_new_session=True,
    )
PY
    fi

    echo "==> Waiting for $SERVER_URL to accept connections"
    # The server serves a self-signed certificate on localhost, hence -k.
    local i
    for i in $(seq 1 120); do
        if curl -sk -o /dev/null --max-time 3 "$SERVER_URL/health/liveness"; then
            echo "    up"
            return 0
        fi
        sleep 2
    done

    echo "ERROR: the server did not come up within 240s. Last 50 log lines:" >&2
    tail -50 "$INSTALL_DIR/server.log" >&2 || true
    exit 1
}

# ---------------------------------------------------------------------------------------------
# Admin token
#
# /applications and /users require a bearer token; the Direct-Auth-Secret header does not apply
# to them (it only gates /auth/, /register/passkey/ and /access/). Mirrors mint_admin_token() in
# the product's tests/e2e/run-e2e.sh: the CONSOLE client runs an authorization-code + PKCE
# exchange, whose credentials step is submitted over the Flow Execution API.
# ---------------------------------------------------------------------------------------------
mint_admin_token() {
    local redirect_uri="$SERVER_URL/console"
    local verifier challenge
    verifier=$(openssl rand -hex 32 | cut -c1-43)
    challenge=$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')

    local headers_file location auth_id exec_id
    headers_file=$(mktemp)
    curl -sk -o /dev/null -D "$headers_file" \
        -G "$SERVER_URL/oauth2/authorize" \
        --data-urlencode "client_id=CONSOLE" \
        --data-urlencode "redirect_uri=$redirect_uri" \
        --data-urlencode "scope=system" \
        --data-urlencode "resource=$SERVER_URL/mcp" \
        --data-urlencode "response_type=code" \
        --data-urlencode "code_challenge=$challenge" \
        --data-urlencode "code_challenge_method=S256"
    location=$(grep -i "^location:" "$headers_file" | tr -d '\r' | sed 's/^[Ll]ocation: //' || true)
    rm -f "$headers_file"

    auth_id=$(sed -n 's/.*[?&]authId=\([^&]*\).*/\1/p' <<<"$location")
    exec_id=$(sed -n 's/.*[?&]executionId=\([^&]*\).*/\1/p' <<<"$location")
    if [ -z "$auth_id" ] || [ -z "$exec_id" ]; then
        echo "ERROR: could not parse authId/executionId from the authorize redirect." >&2
        echo "Location: $location" >&2
        exit 1
    fi

    # The console login flow runs an SSO check ahead of the credentials prompt. This is a fresh,
    # cookie-less login, so the first call advances past that check and mints a challenge token;
    # the second submits the admin credentials with it.
    local prompt_resp challenge_token flow_resp assertion
    prompt_resp=$(curl -sk -X POST "$SERVER_URL/flow/execute" \
        -H "Content-Type: application/json" \
        -d "{\"executionId\": \"$exec_id\"}")
    challenge_token=$(jq -r '.challengeToken // empty' <<<"$prompt_resp")
    if [ -z "$challenge_token" ]; then
        echo "ERROR: no challenge token. Response: $prompt_resp" >&2
        exit 1
    fi

    flow_resp=$(curl -sk -X POST "$SERVER_URL/flow/execute" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg executionId "$exec_id" \
            --arg challengeToken "$challenge_token" \
            --arg username "$ADMIN_USER" \
            --arg password "$ADMIN_PASS" \
            '{executionId: $executionId, challengeToken: $challengeToken, action: "action_001",
              inputs: {username: $username, password: $password}}')")
    assertion=$(jq -r '.assertion // empty' <<<"$flow_resp")
    if [ -z "$assertion" ]; then
        echo "ERROR: admin login returned no assertion. Response: $flow_resp" >&2
        exit 1
    fi

    local callback_resp auth_code token_resp
    callback_resp=$(curl -sk -X POST "$SERVER_URL/oauth2/auth/callback" \
        -H "Content-Type: application/json" \
        -d "{\"authId\": \"$auth_id\", \"assertion\": \"$assertion\"}")
    auth_code=$(jq -r '.redirect_uri // empty' <<<"$callback_resp" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')
    if [ -z "$auth_code" ]; then
        echo "ERROR: callback returned no authorization code. Response: $callback_resp" >&2
        exit 1
    fi

    token_resp=$(curl -sk -X POST "$SERVER_URL/oauth2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=authorization_code" \
        --data-urlencode "code=$auth_code" \
        --data-urlencode "redirect_uri=$redirect_uri" \
        --data-urlencode "client_id=CONSOLE" \
        --data-urlencode "resource=$SERVER_URL/mcp" \
        --data-urlencode "code_verifier=$verifier")
    ADMIN_TOKEN=$(jq -r '.access_token // empty' <<<"$token_resp")
    if [ -z "$ADMIN_TOKEN" ]; then
        echo "ERROR: token endpoint returned no access token. Response: $token_resp" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------------------------
# Provision
# ---------------------------------------------------------------------------------------------
provision() {
    echo "==> Obtaining admin token from $SERVER_URL"
    mint_admin_token

    echo "==> Importing the E2E application"
    local import_resp
    import_resp=$(jq -n --arg content "$(cat "$CONFIG_FILE")" \
        '{content: $content, options: {upsert: true}}' |
        curl -sk -X POST "$SERVER_URL/import" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d @-)
    if [ "$(jq -r '.summary.failed // 1' <<<"$import_resp")" != "0" ]; then
        echo "ERROR: import failed. Response: $import_resp" >&2
        exit 1
    fi

    # POST /import drops the attestation block (see the note in $CONFIG_FILE), so without
    # this the app stores attestation: null and /flow/execute rejects the sample with FES-1016.
    # Re-applying it over PUT is the only way to get devMode persisted today.
    echo "==> Re-applying attestation devMode over PUT (import drops it)"
    local app_json updated put_resp
    app_json=$(curl -sk "$SERVER_URL/applications/$APP_ID" -H "Authorization: Bearer $ADMIN_TOKEN")
    updated=$(jq '.attestation = {devMode: true}' <<<"$app_json")
    put_resp=$(curl -sk -X PUT "$SERVER_URL/applications/$APP_ID" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$updated")
    if [ "$(jq -r '.attestation.devMode // false' <<<"$put_resp")" != "true" ]; then
        echo "ERROR: attestation devMode did not persist. Response: $put_resp" >&2
        exit 1
    fi

    echo "==> Ensuring test user '$E2E_USER' exists"
    # The filter grammar accepts exactly one `attribute eq "value"` clause.
    local filter existing ou_id create_resp
    filter=$(printf 'username eq "%s"' "$E2E_USER" | jq -sRr @uri)
    existing=$(curl -sk "$SERVER_URL/users?filter=$filter" -H "Authorization: Bearer $ADMIN_TOKEN")
    if [ "$(jq -r '(.users // []) | length' <<<"$existing")" -gt 0 ]; then
        echo "    already present, leaving it as is"
    else
        ou_id=$(curl -sk "$SERVER_URL/user-types" -H "Authorization: Bearer $ADMIN_TOKEN" |
            jq -r '.types[] | select(.name == "Person") | .ouId')
        if [ -z "$ou_id" ] || [ "$ou_id" = "null" ]; then
            echo "ERROR: could not resolve the ouId of the Person user type." >&2
            exit 1
        fi
        create_resp=$(curl -sk -X POST "$SERVER_URL/users" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg u "$E2E_USER" --arg p "$E2E_PASS" --arg ou "$ou_id" \
                '{ouId: $ou, type: "Person",
                  attributes: {username: $u, password: $p, email: ($u + "@example.com"),
                               given_name: "E2E", family_name: "Mobile"}}')")
        if [ -z "$(jq -r '.id // empty' <<<"$create_resp")" ]; then
            echo "ERROR: failed to create the test user. Response: $create_resp" >&2
            exit 1
        fi
        echo "    created"
    fi
}

# ---------------------------------------------------------------------------------------------
# Device
# ---------------------------------------------------------------------------------------------
# Resolve a booted simulator, booting one if necessary, so a local run and a CI run take the same
# path. Which iPhone models exist depends on the installed Xcode, so prefer SIMULATOR_NAME but
# fall back to whatever iPhone is available.
resolve_simulator() {
    SIM_UDID=$(xcrun simctl list devices booted | grep -oE "[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}" | head -1 || true)
    if [ -n "$SIM_UDID" ]; then
        echo "==> Using the booted simulator $SIM_UDID"
        return 0
    fi

    local wanted="${SIMULATOR_NAME:-iPhone 17}"
    SIM_UDID=$(xcrun simctl list devices available | grep -m1 "$wanted (" |
        grep -oE "[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}" || true)
    if [ -z "$SIM_UDID" ]; then
        SIM_UDID=$(xcrun simctl list devices available | grep -m1 -E "^[[:space:]]+iPhone " |
            grep -oE "[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}" || true)
    fi
    if [ -z "$SIM_UDID" ]; then
        echo "ERROR: no available iPhone simulator." >&2
        xcrun simctl list devices available >&2
        exit 1
    fi

    echo "==> Booting simulator $SIM_UDID"
    xcrun simctl boot "$SIM_UDID"
    xcrun simctl bootstatus "$SIM_UDID" -b
}

# ---------------------------------------------------------------------------------------------
# Build and install the sample
# ---------------------------------------------------------------------------------------------
build_sample() {
    local sample_dir="$SCRIPT_DIR/../../samples/quickstart"

    echo "==> Configuring the sample"
    # These flows run on iOS: the sample's iOS target carries an NSAllowsArbitraryLoads exemption
    # so it accepts the server's self-signed certificate, while its Android target has no
    # equivalent and the plugin exposes no allowInsecureConnections option of its own.
    cat > "$sample_dir/.env" <<ENVFILE
THUNDERID_BASE_URL=$SERVER_URL
THUNDERID_APP_ID=$APP_ID
THUNDERID_ATTESTATION_ENABLED=false
THUNDERID_CLOUD_PROJECT_NUMBER=
ENVFILE

    echo "==> Building and installing the sample"
    (cd "$sample_dir" && flutter pub get && flutter build ios --debug --simulator)
    xcrun simctl install "$SIM_UDID" \
        "$sample_dir/build/ios/iphonesimulator/Runner.app"
}

# ---------------------------------------------------------------------------------------------
# Run the flows
# ---------------------------------------------------------------------------------------------
run_flows() {
    command -v maestro >/dev/null 2>&1 || {
        echo "ERROR: maestro is not installed. See https://maestro.mobile.dev/getting-started/installing-maestro" >&2
        exit 1
    }
    # Default to the whole suite when no flow path was passed through. Checking the length before
    # expanding matters: under `set -u`, bash 3.2 (still the default on macOS) treats expanding an
    # empty array as an unbound variable.
    local target
    if [ "${#maestro_args[@]}" -eq 0 ]; then
        target=("flows/")
    else
        target=("${maestro_args[@]}")
    fi

    echo "==> Running Maestro"
    # The JUnit report is what makes a failed run readable without scraping the console log; it
    # sits alongside Maestro's own debug output and CI collects both.
    (cd "$SCRIPT_DIR" && maestro --device "$SIM_UDID" test "${target[@]}" \
        --format=JUNIT \
        --output=report.xml \
        -e E2E_USERNAME="$E2E_USER" \
        -e E2E_PASSWORD="$E2E_PASS")
}

if $do_server; then
    start_server
    provision
    echo
    echo "  server         : $SERVER_URL"
    echo "  application id : $APP_ID"
    echo "  test user      : $E2E_USER"
    echo
fi
if $do_build || $do_test; then resolve_simulator; fi
$do_build && build_sample
$do_test && run_flows
