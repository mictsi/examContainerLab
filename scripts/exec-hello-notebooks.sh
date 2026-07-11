#!/usr/bin/env bash
# =============================================================================
# Runs INSIDE the examlab container (piped in by smoke-test.sh).
#
# Executes every notebook in /home/jovyan/exams/00-hello with jupyter
# nbconvert on the kernel recorded in the notebook's metadata. If that exact
# kernel is absent but is a julia-1.x kernel, falls back to whichever julia
# kernel the base image ships (the minor version drifts with the base image).
# =============================================================================
set -uo pipefail

work="$(mktemp -d)"
cp /home/jovyan/exams/00-hello/*.ipynb "${work}/"
cd "${work}"

installed="$(jupyter kernelspec list --json \
    | python -c 'import json,sys; print("\n".join(json.load(sys.stdin)["kernelspecs"]))')"

failed=()
for nb in *.ipynb; do
    kernel="$(python -c "import json; print(json.load(open('${nb}'))['metadata']['kernelspec']['name'])")"

    if ! echo "${installed}" | grep -qx "${kernel}"; then
        case "${kernel}" in
            julia-*)
                kernel="$(echo "${installed}" | grep '^julia-' | head -1)" ;;
            *)
                echo "FAIL ${nb}: kernel '${kernel}' not installed"
                failed+=("${nb}")
                continue ;;
        esac
    fi

    echo "--- ${nb} (kernel: ${kernel})"
    if jupyter nbconvert --to notebook --execute --stdout \
            --ExecutePreprocessor.kernel_name="${kernel}" \
            --ExecutePreprocessor.startup_timeout=300 \
            --ExecutePreprocessor.timeout=300 \
            "${nb}" >/dev/null; then
        echo "PASS ${nb}"
    else
        echo "FAIL ${nb}"
        failed+=("${nb}")
    fi
done

rm -rf "${work}"

if [ "${#failed[@]}" -gt 0 ]; then
    echo "FAILED notebooks: ${failed[*]}" >&2
    exit 1
fi
echo "All hello notebooks executed successfully"
