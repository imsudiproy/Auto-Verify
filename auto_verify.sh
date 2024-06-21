#!/bin/bash

# Ensure the config file exists and is readable
config_file="./config.txt"
if [[ ! -f "$config_file" ]]; then
    echo "Config file not found: $config_file"
    exit 1
fi

# Source the config file
source "$config_file"

# Ensure the build script variable is set
if [[ -z "$build_script" ]]; then
    echo "Build script path not set in the config file."
    exit 1
fi

# Ensure the build script exists
if [[ ! -f "$build_script" ]]; then
    echo "Build script not found: $build_script"
    exit 1
fi

# Ensure the log directory exists
log_dir="/root/logs"
mkdir -p "$log_dir"

run_verification() {
    image_name=$1
    container_name=$(echo "$image_name" | tr ':/' '_')"_container"
    log_file="${log_dir}/$(echo "$image_name" | tr ':/' '_')_logs.txt"
    # If the user is root
    script_path="/build_script.sh"

    #build arg to set tests true or false
    if [ "$test" == "true" ]; then
        build_arg="yt"
    else
        build_arg="y"
    fi

    # If the user is test
    if [ "$user" == "test" ]; then
        script_path="/home/test/build_script.sh"
    fi

    # Create container
    container_id=$(docker run -d --privileged --name "$container_name" "$image_name")
    if [ $? -ne 0 ]; then
        echo "Failed to create container for image: $image_name" | tee -a "$log_file"
        return 1
    fi

    # Copy build script from host to container
    docker cp "$build_script" "$container_id:$script_path"
    if [ $? -ne 0 ]; then
        echo "Failed to copy build script to container: $container_id" | tee -a "$log_file"
        docker rm -f "$container_id"
        return 1
    fi

    # Execute build script inside the container and save logs
    if [ "$user" == "test" ]; then
        docker exec "$container_id" su - test -c "bash $script_path -$build_arg" &> "$log_file"
    else
        docker exec "$container_id" bash $script_path -$build_arg &> "$log_file"
    fi

    if [ $? -ne 0 ]; then
        echo "Build script execution failed in container: $container_id" | tee -a "$log_file"
    else
        echo "Build script executed successfully in container: $container_id" | tee -a "$log_file"
    fi

    # Print logs path
    echo "Logs saved to: $log_file"

    # Delete container
    docker rm -f "$container_id"
}

# Ensure the images array is not empty
if [ ${#images[@]} -eq 0 ]; then
    echo "No Docker images specified in the config file."
    exit 1
fi

for image_name in "${images[@]}"; do
    echo "Testing image: $image_name"
    run_verification "$image_name"
done
