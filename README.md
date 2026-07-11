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

## Quick start

```bash
docker compose build        # first build downloads several GB, allow 15–40 min
docker compose up -d
# open http://localhost:8888/lab   — token: exam-demo
```

Or use the run script / make targets:

```bash
./run.sh build|start|stop|restart|status|logs|shell|kernels|collect
./run.sh clean   # remove container + exam image (results/ untouched)
./run.sh purge   # clean + base image + docker build cache
./run.sh reset-results   # wipe results/ before a new exam (asks first)
```

Set a real token for an actual exam:

```bash
JUPYTER_TOKEN=$(openssl rand -hex 16) docker compose up -d
```

## Directory layout

```
examContainer/
├── Dockerfile                  image definition (all kernels + teaching stack)
├── docker-compose.yml          service, ports, volumes
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
