# =============================================================================
# University exam / lab image
#
# JupyterLab with kernels for:
#   Python 3, R, Julia (from the base image)
#   C, C++11/14/17, Java 21, Perl, .NET 10 (C#, F#, PowerShell)
#
# Teaching stack (per https://jupyter4edu.github.io/jupyter-edu-book/):
#   nbgrader, nbdime, nbconvert, jupytext, ipywidgets, ipympl, ipyleaflet, plotly
#
# Volumes (see docker-compose.yml):
#   /home/jovyan/exams    read-only  exam sheets + instructions
#   /home/jovyan/results  writable   student working copies / submissions
# =============================================================================
ARG BASE_IMAGE=quay.io/jupyter/datascience-notebook:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="exam-jupyterlab" \
      org.opencontainers.image.description="Polyglot JupyterLab image for programming and math exams"

USER root

# -----------------------------------------------------------------------------
# Native toolchains and build dependencies
#   build-essential / gdb / valgrind : C and C++ exams
#   openjdk-21                       : Java exams (runtime for the IJava kernel)
#   cpanminus + libzmq3-dev + libffi-dev : Perl kernel (Devel::IPerl)
#   libicu74                         : required by the .NET runtime
# -----------------------------------------------------------------------------
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        gdb \
        valgrind \
        openjdk-21-jdk-headless \
        cpanminus \
        pkg-config \
        libzmq3-dev \
        libffi-dev \
        libicu74 \
        curl \
        unzip \
        zip \
        ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Perl kernel: Devel::IPerl (kernel spec is copied in below)
# -----------------------------------------------------------------------------
RUN cpanm --notest Devel::IPerl && rm -rf /root/.cpanm
COPY kernels/iperl ${CONDA_DIR}/share/jupyter/kernels/iperl

# -----------------------------------------------------------------------------
# .NET 10 SDK (system-wide install)
# -----------------------------------------------------------------------------
ENV DOTNET_ROOT=/opt/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_ROLL_FORWARD=LatestMajor
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel 10.0 --install-dir /opt/dotnet \
    && ln -s /opt/dotnet/dotnet /usr/local/bin/dotnet \
    && rm /tmp/dotnet-install.sh

# Startup hook: seed writable working copies of the exam files into results/
COPY scripts/before-notebook.d/ /usr/local/bin/before-notebook.d/
RUN chmod +x /usr/local/bin/before-notebook.d/*.sh

USER ${NB_UID}
WORKDIR /home/jovyan

# -----------------------------------------------------------------------------
# Teaching / visualization stack (jupyter4edu recommendations)
#   nbgrader  : create, distribute and autograde assignments
#   nbdime    : notebook-aware diffing (grading, version control)
#   jupytext  : pair notebooks with markdown files
#   plotly / ipympl / ipywidgets / ipyleaflet : interactive plots and widgets
# (numpy, scipy, pandas, matplotlib, seaborn, sympy ship with the base image)
# -----------------------------------------------------------------------------
RUN mamba install -y -c conda-forge \
        plotly \
        ipympl \
        ipywidgets \
        ipyleaflet \
        jupytext \
        nbdime \
        nbgrader \
    && mamba clean --all -f -y

# -----------------------------------------------------------------------------
# C++ kernels: xeus-cling in its own conda env (its pins conflict with the
# base env); kernel specs registered into the base env so JupyterLab sees them
# -----------------------------------------------------------------------------
RUN mamba create -y -n cling -c conda-forge xeus-cling \
    && for k in xcpp11 xcpp14 xcpp17; do \
         jupyter kernelspec install --sys-prefix "${CONDA_DIR}/envs/cling/share/jupyter/kernels/${k}"; \
       done \
    && mamba clean --all -f -y

# -----------------------------------------------------------------------------
# C kernel: jupyter-c-kernel (each cell is a complete program compiled with gcc)
# -----------------------------------------------------------------------------
RUN pip install --no-cache-dir jupyter-c-kernel \
    && install_c_kernel --user

# -----------------------------------------------------------------------------
# Java kernel: IJava (JShell-based)
# -----------------------------------------------------------------------------
RUN curl -fsSL -o /tmp/ijava.zip \
        https://github.com/SpencerPark/IJava/releases/download/v1.3.0/ijava-1.3.0.zip \
    && unzip -q /tmp/ijava.zip -d /tmp/ijava \
    && python /tmp/ijava/install.py --sys-prefix \
    && rm -rf /tmp/ijava /tmp/ijava.zip

# -----------------------------------------------------------------------------
# .NET interactive kernels (C#, F#, PowerShell)
# -----------------------------------------------------------------------------
ENV PATH="${PATH}:/home/jovyan/.dotnet/tools"
RUN dotnet tool install -g Microsoft.dotnet-interactive \
    && dotnet interactive jupyter install \
    && rm -rf /home/jovyan/.nuget/packages/*

# -----------------------------------------------------------------------------
# Fix: route the C++ kernels through a wrapper that puts the cling env first
# on PATH — otherwise cling (clang 9) picks up the base env's GCC 15 libstdc++
# headers and segfaults on startup ("Possible C++ standard library mismatch").
# -----------------------------------------------------------------------------
USER root
COPY --chmod=755 scripts/xcpp-cling /usr/local/bin/xcpp-cling
USER ${NB_UID}
RUN sed -i 's|"/opt/conda/envs/cling/bin/*xcpp"|"/usr/local/bin/xcpp-cling"|' \
        ${CONDA_DIR}/share/jupyter/kernels/xcpp*/kernel.json

EXPOSE 8888
