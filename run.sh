#!/usr/bin/env bash
# run.sh — manage the exam lab containers
#
#   ./run.sh <command> [full|python|all|hub] [-y]
#
#   Variants:   full     polyglot lab (Python, R, Julia, C, C++, Java, Perl, .NET)  port 8888
#               python   Python-only lab (e.g. KTH BB1000)                          port 8889
#               all      both labs at once
#               hub      multi-user JupyterHub, one container per student           port 8000
#   No variant given: an interactive menu asks which lab (default: full).
#   Non-interactive runs (CI, pipes) fall back to full. Env override: VARIANT=python
#   Params (JUPYTER_TOKEN, container names) live in .env.
#   Hub accounts + per-user lab access: hub/userlist (username:password:lab[:admin]).
#
#   ./run.sh build [variant]        build the image(s)
#   ./run.sh start [variant]        start the lab(s) (detached) and print the URL(s)
#   ./run.sh stop [variant]         stop and remove the container(s) (results/ is kept)
#   ./run.sh restart [variant]      restart the container(s)
#   ./run.sh status                 show status of all labs + hub + student containers
#   ./run.sh logs [variant]         follow container logs
#   ./run.sh shell [variant]        open a shell inside the running container (not "all")
#   ./run.sh kernels [variant]      list installed Jupyter kernels
#   ./run.sh collect                archive results/ into archives/
#   ./run.sh clean [variant] [-y]   stop + remove that variant's exam image(s)
#   ./run.sh purge [-y]             clean ALL variants + hub + base images + build cache
#   ./run.sh reset-results [-y]     delete everything in results/ (DESTROYS student work)
set -euo pipefail
cd "$(dirname "$0")"

# Load .env (simple KEY=VALUE lines). docker compose reads it on its own; run.sh
# needs the values too (e.g. to print the login token). A variable already set
# in the environment wins over .env, matching compose's own precedence.
if [[ -f .env ]]; then
    while IFS= read -r line; do
        [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
        key="${line%%=*}"
        if [[ -z "${!key+x}" ]]; then export "${line}"; fi
    done < .env
fi

VARIANT="${VARIANT:-}"

confirm() {
    # confirm <message> — skipped when -y/--yes was passed
    if [[ "${ASSUME_YES}" == "1" ]]; then return 0; fi
    read -r -p "$1 [y/N] " reply
    [[ "${reply}" =~ ^[Yy]$ ]]
}

# choose_variant — resolve ${VARIANT} (interactive menu if unset and on a TTY)
# and set SERVICES / IMAGES / PORTS / COMPOSE accordingly ("all" covers both labs).
choose_variant() {
    if [[ -z "${VARIANT}" ]]; then
        if [[ -t 0 ]]; then
            echo "Which lab version?"
            echo "  1) full    polyglot — Python, R, Julia, C, C++, Java, Perl, .NET  (port 8888)"
            echo "  2) python  Python-only — e.g. KTH BB1000                          (port 8889)"
            echo "  3) all     both labs"
            echo "  4) hub     multi-user JupyterHub — accounts from hub/userlist    (port 8000)"
            read -r -p "Choose [1-4, default 1]: " pick
            case "${pick}" in
                ""|1|full) VARIANT=full ;;
                2|python)  VARIANT=python ;;
                3|all)     VARIANT=all ;;
                4|hub)     VARIANT=hub ;;
                *) echo "Invalid choice: ${pick}" >&2; exit 1 ;;
            esac
        else
            VARIANT=full
        fi
    fi
    case "${VARIANT}" in
        full)
            SERVICES=(examlab)
            IMAGES=(exam-jupyterlab:demo)
            PORTS=("${PORT:-8888}")
            COMPOSE=(docker compose)
            ;;
        python)
            SERVICES=(examlab-python)
            IMAGES=(exam-jupyterlab-python:demo)
            PORTS=("${PORT:-8889}")
            COMPOSE=(docker compose --profile python)
            ;;
        all)
            SERVICES=(examlab examlab-python)
            IMAGES=(exam-jupyterlab:demo exam-jupyterlab-python:demo)
            PORTS=(8888 8889)
            COMPOSE=(docker compose --profile python)
            ;;
        hub)
            SERVICES=(hub)
            IMAGES=(exam-jupyterhub:demo)
            PORTS=(8000)
            COMPOSE=(docker compose --profile hub)
            ;;
        *)
            echo "Unknown variant '${VARIANT}' (use: full | python | all | hub)" >&2
            exit 1
            ;;
    esac
}

ASSUME_YES=0
args=()
for a in "$@"; do
    case "$a" in
        -y|--yes)            ASSUME_YES=1 ;;
        full|python|all|hub) VARIANT="$a" ;;
        *)                   args+=("$a") ;;
    esac
done
set -- "${args[@]:-}"

cmd="${1:-help}"
[[ $# -gt 0 ]] && shift

case "${cmd}" in
    build)
        choose_variant
        "${COMPOSE[@]}" build "${SERVICES[@]}" "$@"
        ;;
    start|up)
        choose_variant
        if [[ "${VARIANT}" == "hub" && ! -f hub/userlist ]]; then
            cp hub/userlist.example hub/userlist
            echo "Created hub/userlist from example — edit accounts/passwords there."
        fi
        "${COMPOSE[@]}" up -d "${SERVICES[@]}"
        echo
        if [[ "${VARIANT}" == "hub" ]]; then
            echo "Exam hub running:  http://localhost:${PORTS[0]}"
            echo "Accounts:          hub/userlist  (username:password:lab[:admin])"
            echo "Spawns one lab container per student — lab images must exist"
            echo "(./run.sh build all). Student work: results/<username>/"
        else
            for i in "${!SERVICES[@]}"; do
                echo "Exam lab (${SERVICES[$i]}) running:  http://localhost:${PORTS[$i]}/lab/tree/results"
            done
            echo "Login token:       ${JUPYTER_TOKEN:-exam-demo}"
            echo "Exams (read-only): exams/    Student work: results/"
        fi
        ;;
    stop|down)
        choose_variant
        "${COMPOSE[@]}" stop "${SERVICES[@]}"
        "${COMPOSE[@]}" rm -f "${SERVICES[@]}" >/dev/null
        if [[ "${VARIANT}" == "hub" ]]; then
            # also remove the student containers the hub spawned
            docker ps -aq --filter "name=exam-user-" | xargs -r docker rm -f >/dev/null
        fi
        echo "Stopped ${SERVICES[*]}. Student work in results/ is preserved."
        ;;
    restart)
        choose_variant
        "${COMPOSE[@]}" restart "${SERVICES[@]}"
        ;;
    status|ps)
        docker compose --profile python --profile hub ps
        # student containers spawned by the hub (not compose-managed)
        docker ps --filter "name=exam-user-" \
            --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | tail -n +2
        ;;
    logs)
        choose_variant
        "${COMPOSE[@]}" logs -f "${SERVICES[@]}"
        ;;
    shell)
        choose_variant
        if [[ "${VARIANT}" == "all" ]]; then
            echo "shell needs a single variant (full or python)" >&2
            exit 1
        fi
        "${COMPOSE[@]}" exec "${SERVICES[0]}" bash
        ;;
    kernels)
        choose_variant
        if [[ "${VARIANT}" == "hub" ]]; then
            echo "kernels: the hub itself has no kernels — use full, python or all" >&2
            exit 1
        fi
        for s in "${SERVICES[@]}"; do
            if [[ ${#SERVICES[@]} -gt 1 ]]; then echo "== ${s} =="; fi
            "${COMPOSE[@]}" exec "${s}" jupyter kernelspec list
        done
        ;;
    collect)
        ./scripts/collect-results.sh
        ;;
    clean)
        choose_variant
        confirm "Remove container(s) + image(s) ${IMAGES[*]} and dangling images?" || exit 1
        "${COMPOSE[@]}" stop "${SERVICES[@]}" 2>/dev/null || true
        "${COMPOSE[@]}" rm -f "${SERVICES[@]}" >/dev/null 2>&1 || true
        docker image rm -f "${IMAGES[@]}" 2>/dev/null || true
        docker image prune -f
        echo "Cleaned ${VARIANT}. results/ and archives/ were NOT touched."
        ;;
    purge)
        confirm "Remove ALL labs + hub, their images, base images and the docker build cache?" || exit 1
        docker ps -aq --filter "name=exam-user-" | xargs -r docker rm -f >/dev/null
        docker compose --profile python --profile hub down --remove-orphans --volumes
        docker image rm -f exam-jupyterlab:demo exam-jupyterlab-python:demo exam-jupyterhub:demo 2>/dev/null || true
        for base in quay.io/jupyter/datascience-notebook quay.io/jupyter/scipy-notebook quay.io/jupyterhub/jupyterhub; do
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
        sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
        ;;
esac
