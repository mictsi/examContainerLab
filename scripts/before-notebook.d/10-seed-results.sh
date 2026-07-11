#!/bin/bash
# Seed student working copies.
#
# Copies every exam notebook (*.ipynb) and markdown worksheet (*.md) from the
# read-only exams volume into the writable results volume, preserving the
# folder structure. Students edit the copies under results/ while the
# originals stay untouched. Existing files are never overwritten, so a
# container restart cannot destroy student work.
#
# NOTE: docker-stacks start.sh *sources* this file — it must not call `exit`
# or `set -u/-e`, or it would terminate/alter the parent startup script.

seed_results() {
    local exams_dir="${EXAMS_DIR:-/home/jovyan/exams}"
    local results_dir="${RESULTS_DIR:-/home/jovyan/results}"

    if [ ! -d "${exams_dir}" ] || [ ! -d "${results_dir}" ]; then
        return 0
    fi

    find "${exams_dir}" \( -name '*.ipynb' -o -name '*.md' \) -print0 |
    while IFS= read -r -d '' src; do
        rel="${src#"${exams_dir}"/}"
        dest="${results_dir}/${rel}"
        if [ ! -e "${dest}" ]; then
            # Never let a failure escape: start.sh sources this under `set -e`,
            # so an unguarded error here would take the whole lab down.
            if mkdir -p "$(dirname "${dest}")" && cp "${src}" "${dest}"; then
                echo "Seeded working copy: results/${rel}"
            else
                echo "WARN: could not seed results/${rel} — is results/ writable by uid $(id -u)? (host fix: chown -R 1000 results)" >&2
            fi
        fi
    done
    return 0
}

seed_results
unset -f seed_results
