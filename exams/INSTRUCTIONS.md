# Exam Instructions — read this first

Welcome to the exam environment. This JupyterLab instance runs in a container
prepared by your instructors.

## Where to work — IMPORTANT

| Folder     | Access         | Purpose                                        |
|------------|----------------|------------------------------------------------|
| `exams/`   | **read-only**  | Original exam sheets and these instructions    |
| `results/` | **writable**   | YOUR working copies — everything you submit    |

When the container starts, a working copy of every exam notebook and markdown
worksheet is placed in `results/` automatically (same folder structure).

**Only work on the files in `results/`. Only files in `results/` are collected
and graded.** Anything saved elsewhere (e.g. your home folder) is lost when
the container is removed.

Save often: `Ctrl+S` (or File → Save Notebook).

## Choosing the right kernel

Each notebook is pre-configured with the correct kernel. If you accidentally
change it, restore it via *Kernel → Change Kernel…*:

| Exam language | Kernel to select          |
|---------------|---------------------------|
| Python / Math | Python 3 (ipykernel)      |
| R             | R                         |
| C             | C                         |
| C++           | C++17 (or C++11 / C++14)  |
| Java          | Java                      |
| Perl          | Perl (IPerl)              |
| C# (.NET 10)  | .NET (C#)                 |

## Language-specific notes

- **C** — every code cell must be a *complete program* including `main()`.
  Each cell is compiled with `gcc` and executed when you run it. Do not read
  from stdin; hard-code the test values shown in the task.
- **C++** — cells are interpreted incrementally (cling). You can define a
  function in one cell and call it in the next, like Python.
- **Java** — cells run in JShell mode: you may write methods and expressions
  directly, without wrapping them in a class. A trailing expression prints
  its value.
- **Perl** — the value of the last expression in a cell is displayed; use
  `print`/`say` for explicit output.
- **C# / .NET** — top-level statements work directly; LINQ and records are
  available.
- **Markdown worksheets** — some tasks ask for written answers in a `.md`
  file. Edit the copy in `results/`, save it, done. Right-click the file →
  *Open With → Markdown Preview* to see the rendered version.

## Plotting

Plots (matplotlib, plotly, R graphics, ipywidgets) render inline in the
notebook and are saved with it — make sure the plot output is visible in the
saved notebook before you finish.

## Before you finish

1. *Kernel → Restart Kernel and Run All Cells* — verify everything runs
   top-to-bottom without errors.
2. Check that plots and outputs are visible.
3. Save (`Ctrl+S`).
4. Leave the files in `results/` — they are collected automatically.
