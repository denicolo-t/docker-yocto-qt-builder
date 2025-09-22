#!/bin/bash
# deploy-config.sh - Configuration for remote device deployment

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Function to test SSH connection
test_ssh_connection() {
    local device_ip=$1
    local device_user=$2
    local device_password=$3
    
    if [ -n "$device_password" ]; then
        sshpass -p "$device_password" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$device_user@$device_ip" "echo 'SSH connection test successful'" 2>/dev/null
    else
        ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$device_user@$device_ip" "echo 'SSH connection test successful'" 2>/dev/null
    fi
}

# Function for SFTP upload
upload_sftp() {
    local executable_path=$1
    local device_ip=$2
    local device_user=$3
    local device_password=$4
    local remote_dir=$5
    
    local executable_name=$(basename "$executable_path")
    
    echo "Uploading with SFTP: $executable_path -> $device_user@$device_ip:$remote_dir/"
    
    if [ -n "$device_password" ]; then
        sshpass -p "$device_password" sftp -o StrictHostKeyChecking=no "$device_user@$device_ip" << EOF
cd $remote_dir
put $executable_path
chmod +x $executable_name
quit
EOF
    else
        sftp -o StrictHostKeyChecking=no "$device_user@$device_ip" << EOF
cd $remote_dir
put $executable_path
chmod +x $executable_name
quit
EOF
    fi
}

# Function for RSYNC upload
upload_rsync() {
    local executable_path=$1
    local device_ip=$2
    local device_user=$3
    local device_password=$4
    local remote_dir=$5
    
    echo "Uploading with RSYNC: $executable_path -> $device_user@$device_ip:$remote_dir/"
    
    if [ -n "$device_password" ]; then
        sshpass -p "$device_password" rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no" \
            "$executable_path" "$device_user@$device_ip:$remote_dir/"
    else
        rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no" \
            "$executable_path" "$device_user@$device_ip:$remote_dir/"
    fi
    
    # Make executable
    local executable_name=$(basename "$executable_path")
    if [ -n "$device_password" ]; then
        sshpass -p "$device_password" ssh -o StrictHostKeyChecking=no "$device_user@$device_ip" \
            "chmod +x $remote_dir/$executable_name"
    else
        ssh -o StrictHostKeyChecking=no "$device_user@$device_ip" \
            "chmod +x $remote_dir/$executable_name"
    fi
}

# Function to execute application remotely
run_remote() {
    local device_ip=$1
    local device_user=$2
    local device_password=$3
    local remote_dir=$4
    local executable_name=$5
    local run_args=$6
    
    echo "========================================="
    echo "Remote execution on $device_ip"
    echo "Command: $remote_dir/$executable_name $run_args"
    echo "========================================="
    
    if [ -n "$device_password" ]; then
        sshpass -p "$device_password" ssh -o StrictHostKeyChecking=no -t "$device_user@$device_ip" \
            "cd $remote_dir && ./$executable_name $run_args"
    else
        ssh -o StrictHostKeyChecking=no -t "$device_user@$device_ip" \
            "cd $remote_dir && ./$executable_name $run_args"
    fi
}