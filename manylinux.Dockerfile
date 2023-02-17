ARG RUST_VERSION
ARG PYTHON_VERSION


FROM rust:${RUST_VERSION} AS rust_stage

FROM quay.io/pypa/manylinux2014_x86_64
ENV DEBIAN_FRONTEND=noninteractive

# Fix permissions issues with our pip cache.
#RUN mkdir /.cache && chmod --recursive 777 /.cache

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
