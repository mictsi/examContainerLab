#!/usr/bin/env bash
# run.sh — manage the exam lab container
#
#   ./run.sh build            build the image
#   ./run.sh start            start the lab (detached) and print the URL
#   ./run.sh stop             stop and remove the container (results/ is kept)
#   ./run.sh restart          restart the container
#   ./run.sh status           show container status
#   ./run.sh logs             follow container logs
#   ./run.sh shell            open a shell inside the running container
#   ./run.sh kernels          list installed Jupyter kernels
#   ./run.sh collect          archive results/ into archives/
#   ./run.sh clean [-y]       stop + remove the exam image and dangling images
#   ./run.sh purge [-y]       clean + base image + docker build cache
#   ./run.sh reset-results [-y]  delete everything in results/ (DESTROYS student work)
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="exam-jupyterlab:demo"
BASE_IMAGE="quay.io/jupyter/datascience-notebook"
SERVICE="examlab"
PORT="${PORT:-8888}"

confirm() {
    # confirm <message> — skipped when -y/--yes was passed
    if [[ "${ASSUME_YES}" == "1" ]]; then return 0; fi
    read -r -p "$1 [y/N] " reply
    [[ "${reply}" =~ ^[Yy]$ ]]
}

ASSUME_YES=0
args=()
for a in "$@"; do
    case "$a" in
        -y|--yes) ASSUME_YES=1 ;;
        *) args+=("$a") ;;
    esac
done
set -- "${args[@]:-}"

cmd="${1:-help}"
[[ $# -gt 0 ]] && shift

case "${cmd}" in
    build)
        docker compose build "$@"
        ;;
    start|up)
        docker compose up -d
        echo
        echo "Exam lab running:  http://localhost:${PORT}/lab"
        echo "Login token:       ${JUPYTER_TOKEN:-exam-demo}"
        echo "Exams (read-only): exams/    Student work: results/"
        ;;
    stop|down)
        docker compose down
        echo "Stopped. Student work in results/ is preserved."
        ;;
    restart)
        docker compose restart
        ;;
    status|ps)
        docker compose ps
        ;;
    logs)
        docker compose logs -f
        ;;
    shell)
        docker compose exec "${SERVICE}" bash
        ;;
    kernels)
        docker compose exec "${SERVICE}" jupyter kernelspec list
        ;;
    collect)
        ./scripts/collect-results.sh
        ;;
    clean)
        confirm "Remove container + image ${IMAGE} and dangling images?" || exit 1
        docker compose down --remove-orphans
        docker image rm -f "${IMAGE}" 2>/dev/null || true
        docker image prune -f
        echo "Cleaned. results/ and archives/ were NOT touched."
        ;;
    purge)
        confirm "Remove container, ${IMAGE}, base image ${BASE_IMAGE} and the docker build cache?" || exit 1
        docker compose down --remove-orphans
        docker image rm -f "${IMAGE}" 2>/dev/null || true
        docker image ls -q "${BASE_IMAGE}" | xargs -r docker image rm -f
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
        sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
        ;;
esac
