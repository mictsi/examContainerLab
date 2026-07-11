#!/usr/bin/env bash
# =============================================================================
# Smoke test for the exam image.
#
# Requires the examlab container to be running (docker compose up -d).
#   1. Waits for the JupyterLab API to respond
#   2. Verifies all expected kernels are installed
#   3. Executes every notebook in exams/00-hello on its kernel
#
# Usage: ./scripts/smoke-test.sh
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-8888}"

echo "==> Waiting for JupyterLab API on port ${PORT}"
for i in $(seq 1 60); do
    if curl -fsS "http://localhost:${PORT}/api" >/dev/null 2>&1; then
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "ERROR: JupyterLab did not come up within 120s" >&2
        docker compose logs --tail 50
        exit 1
    fi
    sleep 2
done
echo "    JupyterLab is up: $(curl -fsS "http://localhost:${PORT}/api")"

echo "==> Checking installed kernels"
kernels="$(docker compose exec -T examlab jupyter kernelspec list)"
echo "${kernels}"
missing=0
# julia is checked as a prefix: the base image pins the minor version (julia-1.x)
for k in python3 ir julia- c xcpp11 xcpp14 xcpp17 java iperl \
         .net-csharp .net-fsharp .net-powershell; do
    if ! echo "${kernels}" | grep -q "  ${k}"; then
        echo "ERROR: missing kernel: ${k}" >&2
        missing=1
    fi
done
[ "${missing}" -eq 0 ] || exit 1
echo "    All expected kernels present"

echo "==> Executing hello notebooks (exams/00-hello) inside the container"
docker compose exec -T examlab bash -s < scripts/exec-hello-notebooks.sh

echo "==> Smoke test PASSED"
