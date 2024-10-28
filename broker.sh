#!/usr/bin/env bash

export BROKER_DIR="$HOME/.config/broker"
export BROKER_STACKS_DIR="$BROKER_DIR/bundles"
export BROKER_ACCESS_CFG="$BROKER_DIR/access.cfg"
export BROKER_DEFAULTS_CFG="$BROKER_DIR/defaults.cfg"

# Check for the existence of required files and directories
if [[ ! -d "$BROKER_STACKS_DIR" ]]; then
    mkdir -p $BROKER_STACKS_DIR
fi

if [[ ! -f "$BROKER_ACCESS_CFG" ]]; then
    touch $BROKER_ACCESS_CFG
fi

if [[ ! -f "$BROKER_DEFAULTS_CFG" ]]; then
    touch $BROKER_DEFAULTS_CFG
fi

# Define color codes
export COLOR_YELLOW="\033[1;33m"
export COLOR_GREEN="\033[1;32m"
export COLOR_RED="\033[1;31m"
export COLOR_CYAN="\033[1;36m"
export COLOR_RESET="\033[0m"

# Variable to control behavior on error
export BROKER_STOP_ON_ERROR=false

headline() {
    local message="$1"
    echo -e "\n${COLOR_YELLOW}${message}${COLOR_RESET}\n"
}

info() {
    local message="$1"
    echo -e "\n${COLOR_CYAN}//${COLOR_RESET} ${message}\n"
}

task() {
    local message="$1"
    local command="${*:2}"
    
    command_output=$(eval "$command" 2>&1)
    #command_output=$(eval "$command" 2>&1 1>/dev/null)

    local status=$?
    if [ $status -eq 0 ]; then
        echo -e "[${COLOR_GREEN}X${COLOR_RESET}] ${message}"
    else
        echo -e "[${COLOR_RED}!${COLOR_RESET}] ${message}\n\n$command_output\n"
        if [ "$BROKER_STOP_ON_ERROR" = true ]; then
            error "Error occurred. Please review the output above for details."
        fi
    fi
    return $status
}

success() {
    local message="$1"
    echo -e "\n${COLOR_GREEN}${message}${COLOR_RESET}\n"
    exit 0
}

error() {
    local message="$1"
    echo -e "\n${COLOR_RED}${message}${COLOR_RESET}\n"
    exit 1
}

template() {
    local filepath="$1"
    local marker="$2"
    local start_marker="{{"
    local end_marker="}}"

    # Parse the provided marker argument if supplied
    if [[ -n $marker ]]; then
        # Extract start and end markers
        IFS=',' read -r start_marker end_marker <<< "$marker"
    fi

    if [[ ! -f $filepath ]]; then
        echo "Error: File '$filepath' not found."
        return 1
    fi

    # Process the file
    while IFS= read -r line || [[ -n "$line" ]]; do
        local regex="\\${start_marker} *([A-Z_][A-Z0-9_]*) *\\${end_marker}"
        # Use a regular expression to find placeholders
        while [[ "$line" =~ $regex ]]; do
            # Extract the variable name from the match
            var_name="${BASH_REMATCH[1]}"
            # Get the value of the environment variable
            var_value="${!var_name}"
            # Replace the first occurrence of this placeholder with the variable value
            line="${line//${start_marker} *$var_name *${end_marker}/$var_value}"
        done
        # Output the processed line
        echo "$line"
    done < "$filepath"
}

# Export functions for subshell use
export -f headline task info success error template

# Function to display usage/help information
usage() {
    headline "Broker: Streamlined Remote Task Execution via SSH"
    echo "Usage Synopsis:"
    echo "  To execute an action remotely:"
    echo "    ssh <server> <stack> <action> [additional_args...]"
    echo
    echo "  To list available stacks and actions:"
    echo "    ssh <server> ls"
    echo
    echo "Description:"
    echo "  Broker simplifies the execution of predefined tasks on server-side stacks"
    echo "  for various users through a secure SSH connection."
    echo
    echo "Direct Invocation:"
    echo "  When invoking Broker directly, specify the target user explicitly:"
    echo "    $0 <user> <stack> <action> [additional_args...]"
    echo
    echo "Practical Examples:"
    echo "  Deploy a website using a specific branch:"
    echo "    ssh acme.com website deploy --branch=main"
    echo
    echo "  List all stacks and actions available for a user on a server:"
    echo "    ssh acme.com ls"
    echo
    exit 1
}

# Extract the action and project, which are always the first two arguments
user=$1
stack=$2
action=$3

# Remove the first two elements (action and project) from the array
additional_args=("${@:4}")

# Function to validate input
validate_input() {
    local input="$1"
    # Allow only alphanumeric characters and some common safe symbols like hyphen and underscore
    if [[ "$input" =~ ^[a-zA-Z0-9_=-]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check user permissions
check_permissions() {
    local BROKER_ACCESS_CFG="$1"
    local user="$2"
    local stack="$3"
    local action="$4"
    local allowed=0
    local current_user=""

    # Read the configuration file line by line
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Check for section headers (e.g., [John])
        if [[ $key =~ ^\[.*\]$ ]]; then
            current_user=$(echo "${key#[}" | xargs)
            current_user=$(echo "${current_user%]}" | xargs)
        elif [[ "$current_user" == "$user" ]]; then
            # Check stacks under the current user section
            if [[ "$key" == "$stack" ]]; then
                IFS=',' read -ra actions <<< "$value"
                for act in "${actions[@]}"; do
                    if [[ "$(echo "$act" | xargs)" == "$action" ]]; then
                        allowed=1
                        break
                    fi
                done
            fi
        fi
    done < "$BROKER_ACCESS_CFG"
    return $allowed
}

# Function to extract stack-specific configurations
get_defaults() {
    local stack="$2"
    local action="$3"
    local config_args=""

    # Construct the stack/action pattern
    local stack_action="$stack/$action"

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" == "$stack_action "* ]]; then
            # Extract everything after the stack/action prefix
            config_args="${line#"$stack_action "}"
            break
        fi
    done < "$BROKER_DEFAULTS_CFG"

    echo "$config_args"
}

# Function to list all actions for a given user
list_user_actions() {
    local user="$1"
    local found_actions=0  # Initialize a counter for found actions
    
    headline "Stacks and actions available for $user:"
    
    local current_user=""
    
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Trim leading and trailing whitespace from key
        key=$(echo "$key" | xargs)
        
        # Skip empty lines
        if [[ -z "$key" ]]; then
            continue
        fi
        
        if [[ $key =~ ^\[.*\]$ ]]; then
            current_user=$(echo "$key" | tr -d '[]')
        elif [[ "$current_user" == "$user" ]]; then
            # Use printf for aligned output
            printf "%-20s : %s\n" "$key" "$value"
            found_actions=1  # Increment the counter if an action is found
        fi
    done < "$BROKER_ACCESS_CFG"

    # Check if no actions were found for the user
    if [[ $found_actions -eq 0 ]]; then
        error "There are no accessible stacks/actions. At least for this user."
    else
        echo
    fi
}

# Check if we are listing stacks
if [[ "$2" == "ls" ]]; then
    list_user_actions "$1"
    exit 0
fi

# Validate main inputs
if ! validate_input "$user" || ! validate_input "$stack" || ! validate_input "$action"; then
    usage
    exit 1
fi

# Validate optional additional arguments
for arg in "${additional_args[@]}"; do
    if ! validate_input "$arg"; then
        echo "Invalid additional argument detected: $arg. Exiting."
        exit 1
    fi
done

# Check permissions
echo "$BROKER_ACCESS_CFG" "$user" "$stack" "$action"
check_permissions "$BROKER_ACCESS_CFG" "$user" "$stack" "$action"

if [[ $? -eq 1 ]]; then
    export BROKER_PWD="$BROKER_STACKS_DIR/$stack"
    script_file="$BROKER_STACKS_DIR/$stack/$action.sh"

    # Export User for child scripts
    BROKER_USER="$user"
    export BROKER_USER
    if [[ -x "$script_file" ]]; then  # Check if the script exists and is executable
        # Get stack-specific configurations
        stack_args=($(get_defaults "$BROKER_DEFAULTS_CFG" "$stack" "$action"))
        "$script_file" "${additional_args[@]}" "${stack_args[@]}"
        exit $?
    else
        echo "Script $script_path does not exist or is not executable."
    fi
else
    echo -e "User $cr$user$cn is not allowed to perform $cr$action$cn on $cr$stack$cn."
fi