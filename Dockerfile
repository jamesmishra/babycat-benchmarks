ARG RUST_VERSION
ARG PYTHON_VERSION

################################################################
################################################################
FROM rust:${RUST_VERSION} AS rust_stage


################################################################
################################################################
FROM python:${PYTHON_VERSION}-bullseye AS base
ENV DEBIAN_FRONTEND=noninteractive

# Add audio for tests.
COPY ./babycat/audio-for-tests /audio

# Install Rust.
COPY --from=rust_stage /usr/local/rustup /usr/local/rustup
COPY --from=rust_stage /usr/local/cargo /usr/local/cargo
ENV PATH=/usr/local/cargo/bin:${PATH}

# Install dependencies from Apt.
RUN apt-get update \
    && apt-get install --no-install-recommends --yes \
        git \
        build-essential \
        pkg-config \
        cmake \
        libclang-dev \
        libasound2-dev \
        yasm \
        python3 \
        python3-dev \
        python3-venv \
        python3-distutils \
        python3-pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install developer tools.
ARG MATURIN_VERSION
RUN \
    python3 -m pip install --upgrade \
        pip \
    && python3 -m pip --no-cache-dir install \
        psutil==5.9.4 \
        maturin==${MATURIN_VERSION}

# Install competing audio libraries.
RUN python3 -m pip --no-cache-dir install \
    pedalboard==0.7.0 \
    librosa==0.9.2 \
    pydub==0.25.1 \
    jupyterlab==3.6.1

# Compile Babycat.
COPY babycat babycat
WORKDIR /babycat
RUN \
    # Create output directory.
    mkdir /wheels \
    # Run Maturin.
    && maturin build \
        --manifest-path=Cargo.toml \
        --out=/wheels \
        --release \
        --profile=release \
        --no-default-features \
        --features=frontend-python,enable-ffmpeg-build

# Install the Babycat wheel.
RUN python3 -m pip install /wheels/*.whl

# Install the Babycat benchmark.
COPY ./benchmark.py /bin/benchmark

# Create a non-root user and switch to it.
ARG NEW_USER=bench
ARG NEW_UID=10000
ARG NEW_GID=10000
RUN groupadd \
        --gid=${NEW_GID} \
        --force ${NEW_USER} \
    && useradd \
        --create-home \
        --home-dir=/home/${NEW_USER} \
        --shell=/bin/bash \
        --uid=${NEW_UID} \
        --gid=${NEW_GID} \
        ${NEW_USER} \
    && mkdir -p /home/${NEW_USER}/.cache \
    && chown ${NEW_USER}:${NEW_USER} /home/${NEW_USER}/.cache
USER ${NEW_USER}

ENTRYPOINT [ "/bin/benchmark" ]