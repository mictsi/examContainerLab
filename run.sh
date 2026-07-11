#!/usr/bin/env bash
# run.sh — manage the exam lab containers
#
#   ./run.sh <command> [full|python] [-y]
#
#   Variants:   full     polyglot lab (Python, R, Julia, C, C++, Java, Perl, .NET)  port 8888
#               python   Python-only lab (e.g. KTH BB1000)                          port 8889
#   No variant given: an interactive menu asks which lab (default: full).
#   Non-interactive runs (CI, pipes) fall back to full. Env override: VARIANT=python
#
#   ./run.sh build [variant]        build the image
#   ./run.sh start [variant]        start the lab (detached) and print the URL
#   ./run.sh stop [variant]         stop and remove the container (results/ is kept)
#   ./run.sh restart [variant]      restart the container
#   ./run.sh status                 show status of both labs
#   ./run.sh logs [variant]         follow container logs
#   ./run.sh shell [variant]        open a shell inside the running container
#   ./run.sh kernels [variant]      list installed Jupyter kernels
#   ./run.sh collect                archive results/ into archives/
#   ./run.sh clean [variant] [-y]   stop + remove that variant's exam image
#   ./run.sh purge [-y]             clean BOTH variants + base images + build cache
#   ./run.sh reset-results [-y]     delete everything in results/ (DESTROYS student work)
set -euo pipefail
cd "$(dirname "$0")"

VARIANT="${VARIANT:-}"

confirm() {
    # confirm <message> — skipped when -y/--yes was passed
    if [[ "${ASSUME_YES}" == "1" ]]; then return 0; fi
    read -r -p "$1 [y/N] " reply
    [[ "${reply}" =~ ^[Yy]$ ]]
}

# choose_variant — resolve ${VARIANT} (interactive menu if unset and on a TTY)
# and set SERVICE / IMAGE / BASE_IMAGE / PORT / COMPOSE accordingly.
choose_variant() {
    if [[ -z "${VARIANT}" ]]; then
        if [[ -t 0 ]]; then
            echo "Which lab version?"
            echo "  1) full    polyglot — Python, R, Julia, C, C++, Java, Perl, .NET  (port 8888)"
            echo "  2) python  Python-only — e.g. KTH BB1000                          (port 8889)"
            read -r -p "Choose [1-2, default 1]: " pick
            case "${pick}" in
                ""|1|full) VARIANT=full ;;
                2|python)  VARIANT=python ;;
                *) echo "Invalid choice: ${pick}" >&2; exit 1 ;;
            esac
        else
            VARIANT=full
        fi
    fi
    case "${VARIANT}" in
        full)
            SERVICE="examlab"
            IMAGE="exam-jupyterlab:demo"
            BASE_IMAGE="quay.io/jupyter/datascience-notebook"
            PORT="${PORT:-8888}"
            COMPOSE=(docker compose)
            ;;
        python)
            SERVICE="examlab-python"
            IMAGE="exam-jupyterlab-python:demo"
            BASE_IMAGE="quay.io/jupyter/scipy-notebook"
            PORT="${PORT:-8889}"
            COMPOSE=(docker compose --profile python)
            ;;
        *)
            echo "Unknown variant '${VARIANT}' (use: full | python)" >&2
            exit 1
            ;;
    esac
}

ASSUME_YES=0
args=()
for a in "$@"; do
    case "$a" in
        -y|--yes)    ASSUME_YES=1 ;;
        full|python) VARIANT="$a" ;;
        *)           args+=("$a") ;;
    esac
done
set -- "${args[@]:-}"

cmd="${1:-help}"
[[ $# -gt 0 ]] && shift

case "${cmd}" in
    build)
        choose_variant
        "${COMPOSE[@]}" build "${SERVICE}" "$@"
        ;;
    start|up)
        choose_variant
        "${COMPOSE[@]}" up -d "${SERVICE}"
        echo
        echo "Exam lab (${VARIANT}) running:  http://localhost:${PORT}/lab"
        echo "Login token:       ${JUPYTER_TOKEN:-exam-demo}"
        echo "Exams (read-only): exams/    Student work: results/"
        ;;
    stop|down)
        choose_variant
        "${COMPOSE[@]}" stop "${SERVICE}"
        "${COMPOSE[@]}" rm -f "${SERVICE}" >/dev/null
        echo "Stopped ${SERVICE}. Student work in results/ is preserved."
        ;;
    restart)
        choose_variant
        "${COMPOSE[@]}" restart "${SERVICE}"
        ;;
    status|ps)
        docker compose --profile python ps
        ;;
    logs)
        choose_variant
        "${COMPOSE[@]}" logs -f "${SERVICE}"
        ;;
    shell)
        choose_variant
        "${COMPOSE[@]}" exec "${SERVICE}" bash
        ;;
    kernels)
        choose_variant
        "${COMPOSE[@]}" exec "${SERVICE}" jupyter kernelspec list
        ;;
    collect)
        ./scripts/collect-results.sh
        ;;
    clean)
        choose_variant
        confirm "Remove container + image ${IMAGE} and dangling images?" || exit 1
        "${COMPOSE[@]}" stop "${SERVICE}" 2>/dev/null || true
        "${COMPOSE[@]}" rm -f "${SERVICE}" >/dev/null 2>&1 || true
        docker image rm -f "${IMAGE}" 2>/dev/null || true
        docker image prune -f
        echo "Cleaned ${VARIANT}. results/ and archives/ were NOT touched."
        ;;
    purge)
        confirm "Remove BOTH labs, their images, base images and the docker build cache?" || exit 1
        docker compose --profile python down --remove-orphans
        docker image rm -f exam-jupyterlab:demo exam-jupyterlab-python:demo 2>/dev/null || true
        for base in quay.io/jupyter/datascience-notebook quay.io/jupyter/scipy-notebook; do
            docker image ls -q "${base}" | xargs -r docker image rm -f
        done
        docker image prune -f
        docker builder prune -f
        echo "Purged. results/ and archives/ were NOT touched."
        ;;
    reset-results)
        confirm "DELETE all student work in results/ ? This cannot be undone." || exit 1
        find results -mindepth 1 ! -name '.gitkeep' -delete
        echo "results/ is empty again."
        ;;
    help|--help|-h|*)
        sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
        ;;
esac
