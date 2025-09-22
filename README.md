

# Docker Environment for Qt Build and Deployment with Yocto Toolchain

## Overview

This repository provides a **Dockerfile** and a set of scripts designed to cross-compile a Qt C++ project using the **SDK toolchain** (`.sh` installer generated from the Yocto BSP) and to enable **automatic deployment** to remote embedded Linux targets.

> ⚠️ **Disclaimer**: This project is for **demonstration purposes only**.  
> It relies on open-source software components (Yocto Project, Qt, Docker, etc.).  
> Please ensure compliance with the respective licenses and intellectual property rights when using or redistributing this setup.

---

## Key Features

- ✅ **Cross-compilation** (debug/release)
- ✅ **Automatic deployment** to remote targets (SFTP/RSYNC)
- ✅ **Remote execution** with real-time output
- ✅ **SSH support** (keys or password-based)
- ✅ **Qt runtime arguments** (e.g., `--platform eglfs`)

---

## Prerequisites & References

This setup integrates multiple open-source projects. You are encouraged to review their official documentation:

- [Yocto Project Official Documentation](https://docs.yoctoproject.org/)  
- [Yocto Project Development Manual](https://docs.yoctoproject.org/dev-manual/)  
- [Qt Official Documentation](https://doc.qt.io/)  
- [Qt for Device Creation](https://doc.qt.io/QtForDeviceCreation/index.html)  
- [Qt Licensing Overview](https://www.qt.io/licensing/)  
- [Yocto Project Licensing and Compliance](https://docs.yoctoproject.org/ref-manual/ref-manual.html#license-compliance)  
- [Docker Documentation](https://docs.docker.com/)  

---

## Initial Setup

### Clone the Repository
```bash
git clone https://github.com/thomas-leanfa/docker-yocto-qt-builder.git
cd ./docker-yocto-qt-builder
```

###  Yocto SDK Toolchain

To obtain the Yocto-generated SDK toolchain (`.sh` file), build your Yocto project for the desired target. After the build completes, the SDK installer will be available in the `tmp/deploy/sdk/` directory of your Yocto build.

Copy the `.sh` file into the project root and execute it to set up the cross-compilation environment:

```bash
chmod +x <toolchain-name>.sh
./<toolchain-name>.sh
```

For detailed instructions on building and using the SDK, refer to the [Yocto Project Application Development and Extensible SDK Manual](https://docs.yoctoproject.org/sdk-manual/index.html).

### Add the Yocto SDK Toolchain
Copy your Yocto-generated SDK toolchain `.sh` file into the project root:

```
./docker-yocto-qt-builder
├── Dockerfile
├── build-and-deploy.sh
├── deploy-config.sh
├── Readme.md
└── <toolchain-installer.sh>   ← Your Yocto SDK toolchain
```

### Build the Docker Image
```bash
docker build \
  --build-arg TOOLCHAIN_FILE=<toolchain-installer.sh> \
  -t <name>-qtbuilder .
```

**Example (i.MX6):**
```bash
docker build \
  --build-arg TOOLCHAIN_FILE=fslc-framebuffer-glibc-x86_64-qt-image-armv7at2hf-neon-toolchain-2.3.sh \
  -t imx6-qtbuilder .
```

To disable caching:
```bash
docker build \
  --no-cache \
  --build-arg TOOLCHAIN_FILE=<toolchain-installer.sh> \
  -t <name>-qtbuilder .
```

---

## Usage

### Project Structure
Assume the following structure:

```
C:\<repositories-path>\<project-workspace>\
├── <ProjectName>\
│   ├── main.cpp
│   ├── *.pro
│   └── ...
```

### 1. Build Only
```bash
# Debug build
docker run \
  --rm \
  -v "C:\<repositories-path>\<project-workspace>:/workspace" \
  <name>-qtbuilder \
  build debug

# Release build
docker run \
  --rm \
  -v "C:\<repositories-path>\<project-workspace>:/workspace" \
  <name>-qtbuilder \
  build release
```

**Output:** The compiled files will be created in the following directories:

```
C:\<path-repositories>\Repositories\<workspace-project>\
├── <ProjectName>\                           ← Source files
├── <ProjectName>-build-<kit>-debug\        ← DEBUG build
│   ├── Makefile
│   ├── *.o
│   └── <executable_debug>
└── <ProjectName>-build-<kit>-release\      ← RELEASE build
    ├── Makefile
    ├── *.o
    └── <executable_release>
```

### 2. Build + Deploy + Run
With SSH keys (recommended):
```bash
docker run \
  --rm \
  -v "C:\<repositories-path>\<project-workspace>:/workspace" \
  -v ~/.ssh:/root/.ssh \
  <name>-qtbuilder \
  build-deploy release \
  --ip 192.168.1.100 \
  --user pi \
  --run-args "--platform eglfs"
```

With password:
```bash
docker run \
  --rm \
  -v "C:\<repositories-path>\<project-workspace>:/workspace" \
  <name>-qtbuilder \
  build-deploy debug \
  --ip 192.168.1.100 \
  --user root \
  --password mypassword \
  --run-args "--platform eglfs -fullscreen"
```

### 3. Deploy Only
```bash
docker run \
  --rm \
  -v "C:\<repositories-path>\<project-workspace>:/workspace" \
  <name>-qtbuilder \
  deploy /workspace/<ProjectName>-build-<kit>-release/<executable> \
  --ip 192.168.1.100 \
  --run-args "--platform eglfs"
```

---

## Common Qt Run Arguments

```bash
--run-args "--platform eglfs"                  # EGL Full Screen
--run-args "--platform eglfs -fullscreen"      # Force fullscreen
--run-args "--platform linuxfb"                # Linux framebuffer
--run-args "--platform eglfs --geometry 1920x1080"  # Specific resolution
```

---

## License & Compliance

- The **Yocto Project** is released under various open-source licenses. Please refer to the [Yocto Project Licensing Guide](https://docs.yoctoproject.org/ref-manual/ref-manual.html#license-compliance).
- **Qt** is available under both open-source (GPL/LGPL) and commercial licenses. See [Qt Licensing](https://www.qt.io/licensing/).
- Docker and related scripts are governed by their respective open-source licenses.
- Users of this repository are responsible for ensuring compliance with all applicable licenses when distributing or deploying artifacts built with this setup.

---

## Troubleshooting

- **SSH connection issues**:  
  ```bash
  ssh user@192.168.1.100
  ssh-keygen -R 192.168.1.100
  ```
- **Verify cross-compiled binaries**:  
  ```bash
  file ./build-*/MyApp
  ldd /tmp/MyApp
  ```