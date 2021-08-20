#!/bin/bash

set -x
d=30s
readarray -t rates < <(seq 100 100 1000)

# https://superuser.com/a/548193
function wait-untile-startup() {
  local svc pattern fifo
  svc="$1"
  pattern="$2"
  fifo=$(mktemp --dry-run)

  mkfifo "${fifo}" || return 1
  {
      # run tail in the background so that the shell can
      # kill tail when notified that grep has exited
      docker compose logs --tail=1 --follow "${svc}" &
      # wait for notification that grep has exited
      local x
      # shellcheck disable=SC2034
      read -r x <"${fifo}"
      # grep has exited, time to go
      MSYS_NO_PATHCONV=1 taskkill /F /IM docker-compose.exe
  } | {
      grep -m 1 "${pattern}"
      # notify the first pipeline stage that grep is done
      echo 1 >"${fifo}"
  }
  # clean up
  rm "${fifo}"
}

for c in 1 2 3 4; do
  for r in "${rates[@]}"; do
    docker compose down -v --remove-orphans >/dev/null 2>&1
    docker compose up -d "app${c}"
    wait-untile-startup "app${c}" 'Started PetClinicApplication'
    docker compose logs "app${c}" | head -n 5
    exit
    if ! vegeta attack -duration=120s -rate=10 -targets=target.txt >/dev/null 2>&1; then
      exit
    fi
    key="cpus-${c}-r-${r}"
    vegeta attack -name="${key}" -duration=${d} -rate="${r}" -targets=target.txt -timeout 60s | tee "${key}.bin" | vegeta report -type=text | head -n 8
  done
done

docker compose down -v --remove-orphans
