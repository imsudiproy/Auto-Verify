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
    script_path="/build_script.sh"
    patch_path="/patch"

    if [ "$user" == "test" ]; then
        script_path="/home/test/build_script.sh"
        patch_path="/home/test/patch"
    fi

    # Create container
    container_id=$(docker run -d --name "$container_name" "$image_name")
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

    # Copy patch folder to container if patch is set to true
    if [ "$patch" == "true" ]; then
        if [[ -d "$patch_folder" ]]; then
            docker cp "$patch_folder" "$container_id:$patch_path"
            if [ $? -ne 0 ]; then
                echo "Failed to copy patch folder to container: $container_id" | tee -a "$log_file"
                docker rm -f "$container_id"
                return 1
            fi
        else
            echo "Patch folder not found: $patch_folder"
            docker rm -f "$container_id"
            return 1
        fi
    fi

    # Update the build script inside the container to use the copied patch path
    docker exec "$container_id" sed -i "s|PATCH_URL=\".*\"|PATCH_URL=\"$patch_path\"|g" "$script_path"
    if [ $? -ne 0 ]; then
        echo "Failed to update the patch URL in the build script inside the container: $container_id" | tee -a "$log_file"
        docker rm -f "$container_id"
        return 1
    fi

    # Execute build script inside the container and save logs
    if [ "$user" == "test" ]; then
        docker exec "$container_id" su - test -c "bash $script_path ${test:+-yt}" &> "$log_file"
    else
        docker exec "$container_id" bash $script_path ${test:+-yt} &> "$log_file"
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
