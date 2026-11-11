#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/../.."
umask 077

web_local=${1:-deploydock/web:local}
api_local=${2:-deploydock/api:local}
root=$(mktemp -d /tmp/deploydock-qa.XXXXXXXX)
project="ddqa-${root##*.}"
project=${project,,}
registry_container=''
variant_container=''
registry=''
port=''
export DEPLOYDOCK_ROOT=$root

cleanup() {
    local rc=$?
    trap - EXIT
    if (( rc )) && [[ -s $root/host.env ]]; then
        scripts/deploydock status >&2 || true
        scripts/deploydock logs >&2 || true
    fi
    if [[ -n $port ]]; then
        APP_PORT=$port DB_PASSWORD_FILE="$root/secrets/db_password" docker compose             -p "$project" -f compose.yaml down --volumes --remove-orphans >/dev/null || true
    fi
    if [[ -n $variant_container ]]; then docker rm "$variant_container" >/dev/null || true; fi
    if [[ -n $registry_container ]]; then docker rm -f -v "$registry_container" >/dev/null || true; fi
    if [[ -n $registry ]]; then
        docker image rm "$registry/web:a" "$registry/api:a" "$registry/api:b" >/dev/null 2>&1 || true
    fi
    if [[ $root == /tmp/deploydock-qa.* && -d $root ]]; then rm -rf -- "$root"; fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

expect_exit() {
    local expected=$1 actual=0
    shift
    "$@" || actual=$?
    [[ $actual == "$expected" ]] || {
        printf 'Expected exit %s, got %s from %s\n' "$expected" "$actual" "$*" >&2
        return 1
    }
}

# The engine, registry, fixture containers and HTTP client must share this Linux host.
registry_container=$(docker run -d --name "$project-registry" -p 127.0.0.1::5000     registry:3@sha256:38907510915c3f1604c7e83d6ab602ab3020d092f73bdaed8696773693ff768c)
registry=$(docker port "$registry_container" 5000/tcp)
curl --silent --show-error --fail --retry 12 --retry-all-errors --retry-delay 1 --max-time 3 "http://$registry/v2/" >/dev/null

# Bind a candidate port on loopback, then hand it to Compose.
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
url="http://127.0.0.1:$port"
mkdir "$root/secrets"
openssl rand -hex 32 > "$root/secrets/db_password"
chmod 0444 "$root/secrets/db_password"
printf 'PROJECT=%s\nAPP_ENV=integration\nAPP_PORT=%s\nWAIT_SECONDS=65\n' "$project" "$port" > "$root/host.env"

docker tag "$web_local" "$registry/web:a"
docker tag "$api_local" "$registry/api:a"
variant_container=$(docker create "$api_local")
docker commit --change 'LABEL org.opencontainers.image.title=deploydock-rollback-fixture'     "$variant_container" "$registry/api:b" >/dev/null
web=$(scripts/push-image "$registry/web:a")
api_a=$(scripts/push-image "$registry/api:a")
api_b=$(scripts/push-image "$registry/api:b")
[[ $api_a != "$api_b" ]]

# Compose resolves the candidate-only service image at runtime.
# shellcheck disable=SC2016
sed -e 's/^      RELEASE_ID:.*/      RELEASE_ID: incorrect-runtime-version/' \
    -e '/^networks:/i\  candidate_only:\n    image: ${API_IMAGE}\n    command: ["sleep", "300"]\n    networks: [edge]' \
    compose.yaml > "$root/bad-smoke.yaml"
sed '/^  api:$/a\    command: ["sh", "-c", "exit 1"]' compose.yaml > "$root/unready.yaml"

scripts/deploydock check-host
expect_exit 1 scripts/deploydock deploy "$root/bad-smoke.yaml" first-bad "$web" "$api_a"
[[ $(cat "$root/state") == $'-\n-\n-' ]]
[[ -z $(docker ps -q --filter "label=com.docker.compose.project=$project") ]]

scripts/deploydock deploy compose.yaml good-a "$web" "$api_a"
expect_exit 65 scripts/deploydock deploy compose.yaml good-a "$web" "$api_b"
note=$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"persistent release fixture"}' "$url/api/notes" | jq -er '.id')
check_note() {
    curl -fsS "$url/api/notes/$note" | jq -e '.text == "persistent release fixture"' >/dev/null
}
container_id() {
    docker ps -q --filter "label=com.docker.compose.project=$project" --filter "label=com.docker.compose.service=$1"
}
check_api_image() {
    [[ $(docker inspect --format '{{.Config.Image}}' "$(container_id api)") == "$1" ]]
}

scripts/deploydock deploy compose.yaml good-b "$web" "$api_b"
check_api_image "$api_b"
check_note
failure_log=$(expect_exit 1 scripts/deploydock deploy "$root/bad-smoke.yaml" bad-smoke "$web" "$api_a" 2>&1)
printf '%s\n' "$failure_log"
[[ $failure_log == *'API did not report expected release bad-smoke'* ]]
if [[ -n $(docker ps -aq --filter "label=com.docker.compose.project=$project" --filter label=com.docker.compose.service=candidate_only) ]]; then
    printf 'A candidate-only service survived restoration.\n' >&2
    exit 1
fi
[[ $(cat "$root/state") == $'good-b\ngood-a\n-' ]]
scripts/deploydock verify good-b
check_api_image "$api_b"
check_note

sed -i 's/WAIT_SECONDS=65/WAIT_SECONDS=20/' "$root/host.env"
expect_exit 1 scripts/deploydock deploy "$root/unready.yaml" unready "$web" "$api_a"
[[ $(cat "$root/state") == $'good-b\ngood-a\n-' ]]
scripts/deploydock verify good-b
check_api_image "$api_b"

# Simulate the journal left after a process dies before committing good-b.
printf 'good-a\n-\ngood-b\n' > "$root/state"
expect_exit 75 scripts/deploydock verify
scripts/deploydock recover
scripts/deploydock verify good-a
check_api_image "$api_a"
check_note

scripts/deploydock deploy compose.yaml good-b "$web" "$api_b"
scripts/deploydock rollback
scripts/deploydock verify good-a
check_api_image "$api_a"
check_note
db_container=$(container_id db)
docker stop "$db_container" >/dev/null
[[ $(curl -sS -o /dev/null -w '%{http_code}' "$url/health/ready") == 503 ]]
curl -fsS "$url/health/live" | jq -e '.status == "live"' >/dev/null
docker start "$db_container" >/dev/null
curl --silent --show-error --fail --retry 12 --retry-all-errors --retry-delay 1 --max-time 5 "$url/health/ready" >/dev/null
scripts/deploydock verify good-a
check_note

# Make the stored good bundle temporarily unavailable to exercise recovery failure.
mv "$root/releases/good-a/compose.yaml" "$root/held-compose.yaml"
expect_exit 2 scripts/deploydock deploy "$root/bad-smoke.yaml" failed-restore "$web" "$api_b"
[[ $(cat "$root/state") == $'good-a\ngood-b\nfailed-restore' ]]
mv "$root/held-compose.yaml" "$root/releases/good-a/compose.yaml"
scripts/deploydock recover
scripts/deploydock verify good-a
check_note

printf 'Integration passed: initial failure, image rollback after health and smoke failures, interrupted and failed recovery, manual rollback, database outage and persistence.\n'
