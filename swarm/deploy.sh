#!/bin/sh
# Author: Yevhen Pavliuchek

# You can set the number of replicas; otherwise, it will use the default value from docker-compose.yml.
if [ $# -eq 0 ]; then
   cat <<END_USAGE


    Usage:


        $0 <FOLDER_NAME>                          # Deploy stack


        $0 <FOLDER_NAME> <REPLICAS>               # Change number of stack replicas


        $0 <FOLDER_NAME> ps                       # Display status of stack


        $0 <FOLDER_NAME> up                       # Update replicas (for images with version in tag)


        $0 <FOLDER_NAME> update                   # Force update replicas (for images with "latest" in tag)


        $0 <FOLDER_NAME> remove                   # Remove stack



END_USAGE
    exit 1
fi

first_arg=$(echo "$1" | sed 's:/$::')
second_arg="$2"

# Get the path to the current directory where the script is located
script_dir="$(dirname "$0")"

# Get the name of the current directory
current_directory="$(basename "${script_dir}")"

# Check the existence of files
env_file="${script_dir}/.env"
env_images_file="${script_dir}/.images"
compose_file="${script_dir}/${first_arg}/docker-compose.yml"

for file in "$env_file" "$env_images_file" "$compose_file"; do
    if [ ! -f "$file" ]; then
        echo
        echo "Error: $file is missing."
        echo
        exit 1
    fi
done

run() {
    local arg="$1"
    echo
    echo "======================================================================================"
    echo "${arg}"
    echo "======================================================================================"
    echo
    eval "${arg}"
    echo
}

# Update replicas in the docker-compose.yml if specified
if [ -n "$second_arg" ] && [ "$second_arg" -eq "$second_arg" ] 2>/dev/null; then
    sed -i "0,/^\(.*\)replicas: \s*/s|\(.*\)replicas: .*\s*|\1replicas: ${second_arg}|" "${script_dir}/${first_arg}/docker-compose.yml"

fi

# Check if up is specified
if [ "$second_arg" = "up" ] ; then
    services=$(docker stack services --format "{{.Name}}" $first_arg )
    for service in $services; do
        run "docker service update $service --with-registry-auth"
    done
fi

# Check if update is specified
if [ "$second_arg" = "update" ] ; then
    # exclude_list="(mysql|rabbitmq|redis|portainer|traefik)"
    # services=$(docker stack services --format "{{.Name}}" $first_arg | grep -Ev "$exclude_list")
    services=$(docker stack services --format "{{.Name}}" $first_arg)
    for service in $services; do
        run "docker service update --force $service --with-registry-auth"
    done
fi

# Check if remove is specified
if [ "$second_arg" = "remove" ] || [ "$second_arg" = "rm" ] || [ "$second_arg" = "down" ]; then
    run "docker stack rm ${first_arg}"
    if docker stack ps "${first_arg}" &> /dev/null; then
        echo "Waiting for containers to be removed..."
        while docker stack ps "${first_arg}" &> /dev/null; do
            sleep 1
        done
    fi
fi

# Check if up is specified
if [ "$second_arg" = "ps" ] ; then
    run "docker stack services $first_arg"
fi

# Deploying Docker Stack
if [ -z "$second_arg" ] || [ "$second_arg" -eq "$second_arg" ] 2>/dev/null; then
    (
        run "set -a && source '$env_file' && source '$env_images_file' && set +a && docker stack deploy -c '${script_dir}/${first_arg}/docker-compose.yml' --with-registry-auth --prune --detach=true $first_arg"
    )
fi

run "docker stack ps ${first_arg}"