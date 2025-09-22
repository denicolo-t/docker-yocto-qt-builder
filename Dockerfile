FROM ubuntu:22.04

# Install base packages for compilation and deployment
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    cmake \
    python3 \
    locales \
    sudo \
    vim \
    file \
    openssh-client \
    rsync \
    sshpass \
    && rm -rf /var/lib/apt/lists/*

# Configure locale (required by some Yocto/Qt builds)
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Accept toolchain filename as build argument
ARG TOOLCHAIN_FILE
RUN test -n "$TOOLCHAIN_FILE" || (echo "ERROR: TOOLCHAIN_FILE must be specified as build argument" && exit 1)

# Copy SDK script into docker image (user-provided filename)
COPY ${TOOLCHAIN_FILE} /opt/toolchain-installer.sh

WORKDIR /opt

# Install toolchain
RUN chmod +x toolchain-installer.sh && \
    ./toolchain-installer.sh -y -d /opt/poky-sdk && \
    rm toolchain-installer.sh

# Copy build and deploy scripts
COPY build-and-deploy.sh /opt/build-and-deploy.sh
COPY deploy-config.sh /opt/deploy-config.sh

# Make scripts executable
RUN chmod +x /opt/build-and-deploy.sh /opt/deploy-config.sh

# Working directory - will be the parent directory containing both sources and build
WORKDIR /workspace

# Entry point that handles commands
ENTRYPOINT ["/opt/build-and-deploy.sh"]