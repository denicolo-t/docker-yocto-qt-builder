#!/bin/bash
set -e

# Source deploy configuration functions
source /opt/deploy-config.sh

# Function to display help
show_help() {
    echo "Cross-Compiler and Deploy Tool"
    echo ""
    echo "Usage:"
    echo "  build <debug|release>                    - Build only"
    echo "  deploy <executable_path> [options]      - Deploy only"
    echo "  build-deploy <debug|release> [options]  - Build + Deploy"
    echo ""
    echo "Deploy Options:"
    echo "  --ip <ip>              Target device IP (required)"
    echo "  --user <username>      SSH username (default: root)"
    echo "  --password <password>  SSH password (optional, uses SSH keys if not specified)"
    echo "  --remote-dir <path>    Remote directory (default: /tmp)"
    echo "  --upload-method <sftp|rsync>  Upload method (default: rsync)"
    echo "  --run-args <args>      Execution arguments (e.g.: '--platform eglfs')"
    echo "  --no-run              Upload but do not execute"
    echo ""
    echo "Examples:"
    echo "  # Build only"
    echo "  docker run ... your-image build debug"
    echo ""
    echo "  # Build + Deploy + Run"
    echo "  docker run ... your-image build-deploy debug --ip 192.168.1.100 --run-args '--platform eglfs'"
    echo ""
    echo "  # Deploy existing executable only"
    echo "  docker run ... your-image deploy /workspace/build/myapp --ip 192.168.1.100"
    echo ""
    echo "  # Deploy with SFTP and password"
    echo "  docker run ... your-image build-deploy release --ip 192.168.1.100 --user pi --password raspberry --upload-method sftp"
}

# Build function (modified from original version)
do_build() {
    local BUILD_TYPE="$1"
    
    if [ "$BUILD_TYPE" != "debug" ] && [ "$BUILD_TYPE" != "release" ]; then
        echo "ERROR: Invalid build type. Use 'debug' or 'release'"
        exit 1
    fi

    # Automatically find environment-setup file in SDK directory
    ENVIRONMENT_SETUP=$(find /opt/poky-sdk -name "environment-setup-*" -type f | head -1)

    if [ -z "$ENVIRONMENT_SETUP" ]; then
        echo "ERROR: environment-setup file not found in /opt/poky-sdk"
        echo "Contents of /opt/poky-sdk:"
        ls -la /opt/poky-sdk/
        exit 1
    fi

    echo "Using environment setup: $ENVIRONMENT_SETUP"

    # Source the environment setup
    source "$ENVIRONMENT_SETUP"

    # Find source directory (first directory containing a .pro file)
    SOURCE_DIR=""
    PRO_NAME=""

    for dir in /workspace/*/; do
        if [ -d "$dir" ] && find "$dir" -maxdepth 1 -name "*.pro" -type f | grep -q .; then
            SOURCE_DIR="$dir"
            # Find first .pro file and extract name without extension
            PRO_FILE=$(find "$dir" -maxdepth 1 -name "*.pro" -type f | head -1)
            PRO_NAME=$(basename "$PRO_FILE" .pro)
            break
        fi
    done

    if [ -z "$SOURCE_DIR" ] || [ -z "$PRO_NAME" ]; then
        echo "ERROR: No directory with .pro file found in /workspace/"
        echo "Contents of /workspace:"
        ls -la /workspace/
        exit 1
    fi

    SOURCE_DIR="${SOURCE_DIR%/}"  # Remove trailing slash

    # Get kit name from environment variable
    if [ -n "$CC" ]; then
        KIT_NAME=$(echo $CC | sed 's/.*-\([^-]*-[^-]*-[^-]*\)-.*/\1/' | sed 's/-/_/g')
    else
        # Fallback: extract from environment-setup filename
        KIT_NAME=$(basename "$ENVIRONMENT_SETUP" | sed 's/environment-setup-//' | sed 's/-/_/g')
    fi

    if [ -z "$KIT_NAME" ]; then
        KIT_NAME="cross_compile_kit"
    fi

    # Build directory with subdirectory for type (debug/release)
    BUILD_DIR="${SOURCE_DIR}/../${PRO_NAME}-build-${KIT_NAME}-${BUILD_TYPE}"

    echo "========================================="
    echo "Cross-compiling with $BUILD_TYPE configuration"
    echo "Kit: $KIT_NAME"
    echo "Environment: $(basename "$ENVIRONMENT_SETUP")"
    echo "Source directory: $SOURCE_DIR"
    echo "Build directory: $BUILD_DIR"
    echo "Cross-compiler: ${CC:-N/A}"
    echo "========================================="

    # Create build directory
    mkdir -p "$BUILD_DIR"

    # Navigate to build directory
    cd "$BUILD_DIR"

    # Configure qmake based on build type
    if [ "$BUILD_TYPE" = "debug" ]; then
        echo "DEBUG configuration..."
        qmake "$SOURCE_DIR" CONFIG+=debug CONFIG-=release
    elif [ "$BUILD_TYPE" = "release" ]; then
        echo "RELEASE configuration..."
        qmake "$SOURCE_DIR" CONFIG+=release CONFIG-=debug
    fi

    # Compile
    echo "Starting compilation..."
    make -j$(nproc)

    echo "========================================="
    echo "Build completed in: $BUILD_DIR"
    
    # Find created executable
    EXECUTABLE_PATH=$(find "$BUILD_DIR" -type f -executable ! -name "*.so*" ! -name "Makefile" | head -1)
    if [ -n "$EXECUTABLE_PATH" ]; then
        echo "Executable: $EXECUTABLE_PATH"
        # Export for use in calling functions
        export BUILT_EXECUTABLE="$EXECUTABLE_PATH"
    fi
    echo "========================================="
}

# Deploy function
do_deploy() {
    local executable_path="$1"
    local device_ip="$2"
    local device_user="$3"
    local device_password="$4"
    local remote_dir="$5"
    local upload_method="$6"
    local run_args="$7"
    local no_run="$8"
    
    # Check if executable exists
    if [ ! -f "$executable_path" ]; then
        echo "ERROR: Executable not found: $executable_path"
        exit 1
    fi
    
    # Verify it's executable
    if [ ! -x "$executable_path" ]; then
        echo "ERROR: File is not executable: $executable_path"
        exit 1
    fi
    
    # Test SSH connection
    echo "Testing SSH connection to $device_user@$device_ip..."
    if ! test_ssh_connection "$device_ip" "$device_user" "$device_password"; then
        echo "ERROR: Cannot connect via SSH to $device_user@$device_ip"
        echo "Check IP, username, password/SSH keys"
        exit 1
    fi
    echo "SSH connection OK"
    
    # Create remote directory if needed
    if [ -n "$device_password" ]; then
        sshpass -p "$device_password" ssh -o StrictHostKeyChecking=no "$device_user@$device_ip" \
            "mkdir -p $remote_dir"
    else
        ssh -o StrictHostKeyChecking=no "$device_user@$device_ip" \
            "mkdir -p $remote_dir"
    fi
    
    # Upload executable
    case "$upload_method" in
        "sftp")
            upload_sftp "$executable_path" "$device_ip" "$device_user" "$device_password" "$remote_dir"
            ;;
        "rsync")
            upload_rsync "$executable_path" "$device_ip" "$device_user" "$device_password" "$remote_dir"
            ;;
        *)
            echo "ERROR: Invalid upload method: $upload_method"
            exit 1
            ;;
    esac
    
    # Execute application if requested
    if [ "$no_run" != "true" ]; then
        local executable_name=$(basename "$executable_path")
        run_remote "$device_ip" "$device_user" "$device_password" "$remote_dir" "$executable_name" "$run_args"
    else
        echo "Upload completed. Executable available at $device_user@$device_ip:$remote_dir/$(basename "$executable_path")"
    fi
}

# Parse parameters
COMMAND="$1"
shift

case "$COMMAND" in
    "build")
        if [ $# -lt 1 ]; then
            echo "ERROR: Specify build type (debug|release)"
            show_help
            exit 1
        fi
        do_build "$1"
        ;;
    
    "deploy")
        if [ $# -lt 1 ]; then
            echo "ERROR: Specify executable path"
            show_help
            exit 1
        fi
        
        executable_path="$1"
        shift
        
        # Deploy default parameters
        device_ip=""
        device_user="root"
        device_password=""
        remote_dir="/tmp"
        upload_method="rsync"
        run_args=""
        no_run="false"
        
        # Parse deploy options
        while [[ $# -gt 0 ]]; do
            case $1 in
                --ip)
                    device_ip="$2"
                    shift 2
                    ;;
                --user)
                    device_user="$2"
                    shift 2
                    ;;
                --password)
                    device_password="$2"
                    shift 2
                    ;;
                --remote-dir)
                    remote_dir="$2"
                    shift 2
                    ;;
                --upload-method)
                    upload_method="$2"
                    shift 2
                    ;;
                --run-args)
                    run_args="$2"
                    shift 2
                    ;;
                --no-run)
                    no_run="true"
                    shift
                    ;;
                *)
                    echo "ERROR: Unknown option: $1"
                    show_help
                    exit 1
                    ;;
            esac
        done
        
        # Validations
        if [ -z "$device_ip" ]; then
            echo "ERROR: Device IP is required (--ip)"
            exit 1
        fi
        
        if ! validate_ip "$device_ip"; then
            echo "ERROR: Invalid IP: $device_ip"
            exit 1
        fi
        
        do_deploy "$executable_path" "$device_ip" "$device_user" "$device_password" "$remote_dir" "$upload_method" "$run_args" "$no_run"
        ;;
    
    "build-deploy")
        if [ $# -lt 1 ]; then
            echo "ERROR: Specify build type (debug|release)"
            show_help
            exit 1
        fi
        
        build_type="$1"
        shift
        
        # Deploy default parameters
        device_ip=""
        device_user="root"
        device_password=""
        remote_dir="/tmp"
        upload_method="rsync"
        run_args=""
        no_run="false"
        
        # Parse deploy options
        while [[ $# -gt 0 ]]; do
            case $1 in
                --ip)
                    device_ip="$2"
                    shift 2
                    ;;
                --user)
                    device_user="$2"
                    shift 2
                    ;;
                --password)
                    device_password="$2"
                    shift 2
                    ;;
                --remote-dir)
                    remote_dir="$2"
                    shift 2
                    ;;
                --upload-method)
                    upload_method="$2"
                    shift 2
                    ;;
                --run-args)
                    run_args="$2"
                    shift 2
                    ;;
                --no-run)
                    no_run="true"
                    shift
                    ;;
                *)
                    echo "ERROR: Unknown option: $1"
                    show_help
                    exit 1
                    ;;
            esac
        done
        
        # Validations
        if [ -z "$device_ip" ]; then
            echo "ERROR: Device IP is required (--ip)"
            exit 1
        fi
        
        if ! validate_ip "$device_ip"; then
            echo "ERROR: Invalid IP: $device_ip"
            exit 1
        fi
        
        # Build first
        do_build "$build_type"
        
        # Then deploy the just-built executable
        if [ -n "$BUILT_EXECUTABLE" ]; then
            do_deploy "$BUILT_EXECUTABLE" "$device_ip" "$device_user" "$device_password" "$remote_dir" "$upload_method" "$run_args" "$no_run"
        else
            echo "ERROR: No executable found after build"
            exit 1
        fi
        ;;
    
    *)
        echo "ERROR: Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac