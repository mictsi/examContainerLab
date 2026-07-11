# examContainer — polyglot JupyterLab for university exams and labs

A Docker Compose setup that serves programming and math exams in JupyterLab.
Exam sheets are mounted **read-only**; students work on automatically seeded
copies in a **writable** results volume that the instructor collects afterwards.

## Languages / kernels

| Language      | Kernel                | Provided by                          |
|---------------|-----------------------|--------------------------------------|
| Python 3      | `python3`             | base image (ipykernel)               |
| R             | `ir`                  | base image (IRkernel)                |
| Julia         | `julia-*`             | base image (bonus)                   |
| C             | `c`                   | jupyter-c-kernel (gcc, cell = full program) |
| C++ 11/14/17  | `xcpp11/14/17`        | xeus-cling                           |
| Java 21       | `java`                | IJava (JShell-based)                 |
| Perl          | `iperl`               | Devel::IPerl                         |
| C#, F#, PowerShell (.NET 10) | `.net-csharp` etc. | .NET SDK 10 + dotnet-interactive |

Base image: `quay.io/jupyter/datascience-notebook` (numpy, scipy, pandas,
matplotlib, seaborn, sympy included). `gdb` and `valgrind` are installed for
C/C++ labs.

## Teaching & visualization stack

Per the [Teaching and Learning with Jupyter](https://jupyter4edu.github.io/jupyter-edu-book/jupyter.html)
handbook:

- **nbgrader** — create, distribute, autograde assignments
- **nbdime** — notebook-aware diff/merge (great for grading: `nbdiff a.ipynb b.ipynb`)
- **nbconvert** — export notebooks to HTML/PDF/scripts
- **jupytext** — pair notebooks with markdown files (edit `.md` as a notebook)
- **ipywidgets, ipympl, ipyleaflet, plotly** — interactive plots, widgets, maps
- Markdown editing + live preview is built into JupyterLab

Not included: `jupyter-contrib-nbextensions` (classic-notebook only, incompatible
with JupyterLab 4). For multi-student deployments, put this image behind
**JupyterHub** (DockerSpawner) — one container per student.

## Python-only variant (e.g. KTH BB1000)

For courses that only need Python — such as
[BB1000 Programming in Python](https://www.kth.se/student/kurser/kurs/BB1000?l=en) —
`Dockerfile.python` builds a much smaller image (scipy-notebook base, ~4 GB
vs 10.6 GB) with just the Python 3 kernel:

- **Course libraries** (from the base image): numpy, scipy, pandas,
  matplotlib, seaborn, sympy, scikit-learn, ipywidgets, ipympl
- **pytest** — program testing / test-driven development
- **git + jupyterlab-git** — version control from the CLI and the Lab UI
- **nbgrader, nbdime, jupytext** — same teaching stack as the full image

```bash
docker compose --profile python build
docker compose --profile python up -d
# open http://localhost:8889/lab   — token: exam-demo
```

It uses the same `exams/` (read-only) and `results/` (writable) volumes and
the same seed hook as the full lab, and runs on port **8889** so both labs can
run side by side. Non-Python demo exams in `exams/` will still be seeded but
their kernels are absent — point the volume at a course-specific folder
(e.g. `./exams-bb1000:/home/jovyan/exams:ro`) for a real exam.

## Hardware requirements

Numbers measured on the built image (10.6 GB, all kernels exercised):

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| Disk     | 15 GB free | 30 GB free | image is 10.6 GB; building needs headroom for the base-image download and build cache |
| RAM      | 4 GB    | 8 GB        | idle lab ≈ 0.4 GB; each running kernel adds ~0.2–0.6 GB (.NET, Java and Julia are the heavy ones) |
| CPU      | 2 cores | 4+ cores    | the C++ kernels (cling) JIT-compile per cell; more cores also speed up the first build |

- **Single seat / demo**: any laptop with 8 GB RAM runs the lab comfortably.
- **Multi-student** (JupyterHub, one container per seat): budget **2 GB RAM and
  1–2 cores per student** — this matches the `mem_limit: 2g` / `cpus: 2`
  suggestions in `docker-compose.yml`. The 10.6 GB image is shared and stored
  once per host, regardless of how many containers run on it.
- **First build**: ~5 min on a fast machine with good bandwidth, up to ~40 min
  on slower hardware — the base-image download alone is several GB.

## Quick start

```bash
docker compose build        # first build downloads several GB, allow 15–40 min
docker compose up -d
# open http://localhost:8888/lab   — token: exam-demo
```

Or use the run script / make targets:

```bash
./run.sh build|start|stop|restart|logs|shell|kernels [full|python]
./run.sh status|collect
./run.sh clean [full|python]  # remove that variant's container + image
./run.sh purge   # BOTH variants + base images + docker build cache
./run.sh reset-results   # wipe results/ before a new exam (asks first)
```

Commands that target one lab take an optional variant (`full` = polyglot on
port 8888, `python` = Python-only on port 8889). Without one, an interactive
menu asks (default `full`); non-interactive runs fall back to `full`, or set
`VARIANT=python` in the environment.

Set a real token for an actual exam:

```bash
JUPYTER_TOKEN=$(openssl rand -hex 16) docker compose up -d
```

## Directory layout

```
examContainer/
├── Dockerfile                  image definition (all kernels + teaching stack)
├── Dockerfile.python           minimal Python-only image (see above)
├── docker-compose.yml          services, ports, volumes
├── run.sh                      start/stop/clean helper (see Quick start)
├── exams/                      → mounted read-only at /home/jovyan/exams
│   ├── INSTRUCTIONS.md         student-facing instructions
│   ├── 00-hello/               hello-world notebook per language (warm-up)
│   ├── 01-python/ … 08-dotnet/ demo exams, one folder per language
│   ├── 02-math/                incl. math-basics-exam + markdown worksheet
│   ├── 09-visualization/       plotting/graphing exam (matplotlib, plotly)
│   └── 10-r-visualization/     R graphics exam (base plots, ggplot2)
├── results/                    → mounted writable at /home/jovyan/results
├── kernels/iperl/              Perl kernel spec baked into the image
├── scripts/
│   ├── before-notebook.d/      startup hook: seeds working copies into results/
│   └── collect-results.sh      host-side: archive results/ after the exam
└── archives/                   collected result tarballs
```

## How the exam flow works

1. Instructor drops exam notebooks / markdown worksheets into `exams/`.
2. On container start, a hook copies every `*.ipynb` and `*.md` from
   `exams/` into `results/` (never overwriting existing files, so restarts
   are safe).
3. Students work **only** in `results/` — `exams/` is read-only at the mount
   level, enforced by Docker, not by Jupyter.
4. After the exam: `make collect` → `archives/results-<timestamp>.tar.gz`.

## Grading tips

```bash
# Re-execute a submission top-to-bottom, fail on error:
docker compose exec examlab jupyter nbconvert --to notebook --execute \
    results/01-python/python-exam.ipynb --output /tmp/check.ipynb

# Diff a submission against the original exam:
docker compose exec examlab nbdiff exams/01-python/python-exam.ipynb \
    results/01-python/python-exam.ipynb
```

For structured autograding, author the exams with **nbgrader**
(`### BEGIN SOLUTION` / hidden tests) — it is preinstalled.

## Hardening for real exams

- **Rootless container** (already on in `docker-compose.yml`): the container is
  pinned to `user: "1000:100"` (jovyan), starts with **all Linux capabilities
  dropped** and `no-new-privileges`, so nothing inside — student code included —
  can escalate to root. Consequence: the docker-stacks root features
  (`NB_UID` remapping, `GRANT_SUDO`) are unavailable, and `results/` on the
  host must be writable by uid 1000 (see Troubleshooting).
- **Token**: set a per-session `JUPYTER_TOKEN` (see above).
- **Resources**: uncomment `mem_limit` / `cpus` in `docker-compose.yml`.
- **No internet**: an `internal: true` Docker network also breaks the
  published port, so block egress on the host instead, e.g.:
  `iptables -I DOCKER-USER -s <container-subnet> ! -d <lab-subnet> -j DROP`,
  or run behind a filtering proxy.
- **One container per student**: use JupyterHub + DockerSpawner, or run one
  compose project per seat with different ports and results subfolders.
- **Reproducibility**: pin the base image to a dated tag
  (`--build-arg BASE_IMAGE=quay.io/jupyter/datascience-notebook:2025-...`)
  and rebuild well before the exam date.

## Troubleshooting

- **Permission denied writing to results/** — the container user `jovyan` is
  uid 1000. On Linux/WSL hosts: `sudo chown -R 1000 results` (or
  `chmod o+w results` for a quick demo).
- **Kernel missing from the launcher** — `./run.sh kernels` should list:
  python3, ir, julia-1.12, c, xcpp11/14/17, java, iperl, .net-csharp,
  .net-fsharp, .net-powershell.
- **.NET note** — the SDK is .NET 10; the dotnet-interactive kernel runs on it
  via `DOTNET_ROLL_FORWARD=LatestMajor`.
- **C cells** — must contain a complete program with `main()`; stdin is not
  supported.
