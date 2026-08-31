#!/usr/bin/env bash

set -Eeuo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
schema="${repository_root}/profiles/schema.json"

for command in docker jq; do
  command -v "${command}" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "${command}" >&2
    exit 1
  }
done

# A newline-delimited membership list instead of an associative array, so the
# script also runs on the bash 3.2 that macOS ships.
seen_ids=$'\n'
profile_count=0

while IFS= read -r profile; do
  profile_directory="$(dirname -- "${profile}")"
  profile_id="$(jq -er '.id' "${profile}")"
  directory_id="$(basename -- "${profile_directory}")"

  jq -e --slurpfile schema "${schema}" '
    .schema_version == $schema[0].properties.schema_version.const
    and (.id | test($schema[0].properties.id.pattern))
    and (.display_name | type == "string" and length > 0)
    and (.gameplay == "modded" or .gameplay == "vanilla-like")
    and .game == "zomboid"
    and (.zomboid_build | type == "string" and test("^[0-9]+(\\.[0-9]+)*$"))
    and .loader.type == "workshop"
    and .loader.version == null
    and .compose_file == "compose.yaml"
  ' "${profile}" >/dev/null

  [[ "${profile_id}" == "${directory_id}" ]] || {
    printf 'error: profile id %s must match directory %s\n' "${profile_id}" "${directory_id}" >&2
    exit 1
  }
  [[ "${seen_ids}" != *$'\n'"${profile_id}"$'\n'* ]] || {
    printf 'error: duplicate profile id: %s\n' "${profile_id}" >&2
    exit 1
  }
  seen_ids="${seen_ids}${profile_id}"$'\n'

  compose_file="${profile_directory}/$(jq -r '.compose_file' "${profile}")"
  [[ -f "${compose_file}" ]] || {
    printf 'error: missing Compose file for %s\n' "${profile_id}" >&2
    exit 1
  }

  # A pin list is exact name:version lines — the resolver's own contract.
  mods_source="$(jq -r '.mods.source // empty' "${profile}")"
  if [[ -n "${mods_source}" ]]; then
    [[ -f "${profile_directory}/${mods_source}" ]] || {
      printf 'error: missing mod source for %s: %s\n' "${profile_id}" "${mods_source}" >&2
      exit 1
    }
    # A Workshop item is a numeric id; the Workshop has no versions, so a pin
    # list cannot carry one. What makes a mod set reproducible here is the
    # captured payload of a release, not this file.
    bad_ids="$(grep -Ev '^[[:space:]]*(#|$)' "${profile_directory}/${mods_source}" \
      | grep -Ev '^[0-9]+$' || true)"
    [[ -z "${bad_ids}" ]] || {
      printf 'error: malformed Workshop ids for %s:\n%s\n' "${profile_id}" "${bad_ids}" >&2
      exit 1
    }
  fi

  rendered="$(
    docker compose \
      --project-directory "${profile_directory}" \
      -f "${compose_file}" \
      config --format json
  )"
  zomboid_build="$(jq -r '.zomboid_build' "${profile}")"
  # profile_directory is already absolute; plain concatenation avoids GNU
  # realpath flags the macOS userland does not have.
  expected_data_directory="${profile_directory}/data"

  # The image tag IS the runtime version — the engine has no separate loader —
  # so the profile's zomboid_version and the Compose file must agree.
  # The image tag cannot carry the build the way factorio's does — the server
  # tracks a Steam branch — so the profile's build is documentation and the
  # Compose checks are about shape: the data mount, the two game ports, RCON on
  # localhost, and no restart policy fighting an idle stop.
  jq -e \
    --arg expected_data_directory "${expected_data_directory}" '
      any(.services.zomboid.volumes[]; .target == "/project-zomboid-config" and .source == $expected_data_directory)
      and any(.services.zomboid.ports[]; .target == 16261 and .protocol == "udp")
      and any(.services.zomboid.ports[]; .target == 16262 and .protocol == "udp")
      and any(.services.zomboid.ports[]; .target == 27015 and .host_ip == "127.0.0.1")
      and .services.zomboid.restart == "no"
      and (.services.zomboid.environment | has("RCON_PASSWORD"))
    ' <<<"${rendered}" >/dev/null

  printf 'profile=%s result=valid\n' "${profile_id}"
  profile_count=$((profile_count + 1))
done < <(find "${repository_root}/profiles" -mindepth 2 -maxdepth 2 -name profile.json -type f | sort)

(( profile_count > 0 )) || {
  printf 'error: no profiles found\n' >&2
  exit 1
}

printf 'result=passed profiles=%d\n' "${profile_count}"
