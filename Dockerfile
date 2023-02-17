ARG RUST_VERSION
ARG PYTHON_VERSION

################################################################
################################################################
FROM rust:${RUST_VERSION} AS rust_stage

################################################################
################################################################
FROM quay.io/pypa/manylinux2014_x86_64:latest AS babycat_builder
ENV DEBIAN_FRONTEND=noninteractive

# Copy Rust compiler into Python image.
COPY --from=rust_stage /usr/local/rustup /usr/local/rustup
COPY --from=rust_stage /usr/local/cargo /usr/local/cargo
ENV PATH=/usr/local/cargo/bin:${PATH}

# Install libclang.so
RUN \
    yum update -y \
    && yum install llvm-toolset-7 -y \
    && yum clean all

# Install Maturin
ARG MATURIN_VERSION
RUN python3.8 -m pip install maturin==${MATURIN_VERSION}

# Compile Babycat
COPY babycat babycat
WORKDIR /babycat
RUN \
    # Create output directory.
    mkdir /wheels \
    # Enable llvm-toolset-7 so we can find libclang.so.
    && source /opt/rh/llvm-toolset-7/enable \
    # Run Maturin.
    && /opt/python/cp38-cp38/bin/maturin build \
        --no-sdist \
        --manifest-path=Cargo.toml \
        --out=/wheels \
        --cargo-extra-args="--release --no-default-features --features=frontend-python,enable-ffmpeg-build"


################################################################
################################################################
FROM python:${PYTHON_VERSION}-bullseye AS base

# Install developer tools.
RUN python3 -m pip --no-cache-dir install \
    psutil==5.9.4

# Install competing audio libraries.
RUN python3 -m pip --no-cache-dir install \
    pedalboard==0.7.0 \
    librosa==0.9.2 \
    pydub==0.25.1

# Install the Babycat wheel.
COPY --from=babycat_builder /wheels /babycat-wheels
RUN python3 -m pip install /babycat-wheels/*.whl \
    && rm -rfv /babycat-wheels

# Install the Babycat benchmark.
COPY ./benchmark.py /bin/benchmark

# Add audio for tests.
COPY ./babycat/audio-for-tests /audio

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