# Broker: Streamlined Remote Task Execution via SSH

## Introduction

Broker is a lightweight solution that allows the secure execution of custom shell scripts over SSH, ensuring that task access and settings are managed through a simple and intuitive configuration files.

### Key Benefits

- **Security:** Utilize SSH key-based authentication for secure access, ensuring that only authorized users can execute specific tasks.
- **Efficiency:** Execute complex tasks with a single command, reducing the time and effort involved in performing repetitive actions.
- **Access Control:** Offers fine-grained user permissions, allowing precise control over who can perform which tasks.
- **Flexibility:** Easily adapt scripts to various contexts and environments, supporting a wide range of use cases.

### Common Use Cases

- **Deployment:** Quickly deploy applications using pre-configured scripts, simplifying and speeding up the roll-out process.
- **Backup:** Automate data backups to maintain data integrity and ensure consistent results without manual intervention.
- **Maintenance:** Run maintenance tasks effortlessly, keeping systems updated and running smoothly with minimal overhead.

By utilizing Bash for both, Broker and its tasks we minimize complexity and dependencies, making it an ideal choice for users that value simplicity and robustness.

## Quickstart

### Installation

First, create a new user named `broker`. This user will be dedicated to managing and running the tasks that the Broker tool handles.

```bash
sudo adduser broker
```

Then install the script to a common directory like `/usr/local/bin/`, so it’s accessible system-wide.

```bash
sudo curl -o /usr/local/bin/broker https://raw.githubusercontent.com/bw9ubwo/broker/refs/heads/main/broker.sh && sudo chmod +x /usr/local/bin/broker
```

### SSH Key-Auth & Configuration

On your local machine, generate & show your public SSH key.

```bash
ssh-keygen -t ed25519 -C "alice@example.com"
cat ~/.ssh/id_ed25519.pub
```

This will print the public key to your terminal. It will look like this:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI<rest-of-the-key> alice@example.com
```

On your server, edit the `~/.ssh/authorized_keys` file for the `broker` user and include the key, like in this example. If the file doesn't exist beforehand, set the rights with `chmod 600 ~/.ssh/authorized_keys`.

```plaintext
command="/usr/local/bin/broker alice $SSH_ORIGINAL_COMMAND" ssh-ed25519 AAAAC3NzaC1AI<rest-of-the-key> alice@example.com
```

This setup ensures that `alice` can connect without a password, and Broker can manage the task execution and access rights.

### Broker's Directory Structure

Here is how Broker organizes its configuration and user-available script bundles:

```
~/.config/broker/
│
├── defaults.cfg                  # Global configuration file for default script arguments
├── access.cfg                    # Global configuration file for defining user permissions
│
└── bundles/                      # Subdirectory containing all script bundles
    │
    ├── web/                      # Original stack with base deployment scripts
    │   ├── deploy.sh             # Script for deploying applications
    │   └── backup.sh             # Script for handling backups
    │
    ├── production -> web/        # Virtual stack for production (symlink to web)
    └── staging -> web/           # Virtual stack for staging (symlink to web)
```

### Create a Custom Script Bundle

A bundle is just a folder containing various shell scripts. Broker manages the access rights and can set default arguments. Here is a simple example:

```bash
#!/bin/bash

NAME="World"
for ARG in "$@"; do
  case $ARG in
    --name=*)
      NAME="${ARG#*=}"
      ;;
  esac
done

headline "Hello $NAME!"
```

For consistency, use only named attributes like `--name` or `-n` and utilize the provided helper functions `headline`, `task`, `info`,  `success` and `error` to maintain a cohesive look.

Place this script in `~/.config/broker/bundles/example/hello.sh` and make it executable:

```bash
mkdir -p ~/.config/broker/bundles/example
chmod +x ~/.config/broker/bundles/example/hello.sh
```

### Manage Access

Now let's add Alice to `~/.config/broker/access.cfg` and give her the rights to execute the `hello` script inside the `example` bundle.

```ini
[alice]
example=hello
```

### List & Execute Tasks

We can now run the script on our remote. Just connect to the broker user on your server and pass the bundle, script, and additional arguments.

```bash
ssh broker@server_address example hello
ssh broker@server_address example hello --name=Alice
ssh broker@server_address example hello --name=John
```

It's also possible to view all available bundles & tasks for a user with:

```bash
ssh broker@server_address ls
```

### Set Default Arguments

You can set default arguments for a script in the `~/.config/broker/defaults.cfg` file. These arguments are the default and cannot be overwritten by user arguments:

```ini
example/hello --name=John
```

Try the execution examples you ran before to see the difference.

## Virtual Bundles

Virtual bundles allow distinct configurations for different environments by using symlinks.

**Create Symlinks:**

```bash
ln -s ~/.config/broker/bundles/web ~/.config/broker/bundles/production
ln -s ~/.config/broker/bundles/web ~/.config/broker/bundles/staging
```

**Define User Permissions in `access.cfg`:**

```ini
[alice]
production=deploy,backup
staging=deploy,backup

[bob]
staging=backup
```

**Set Environment-Specific Defaults in `defaults.cfg`:**

```ini
production/deploy --env=production --domain=prod.example.com
staging/deploy --env=staging --domain=staging.example.com
```

### Task Execution

Examples of task execution with virtual bundles:

```bash
ssh broker@server_address production deploy   # Deploying to Production
ssh broker@server_address staging backup      # Backing Up in Staging
```


## Provided Variables and Functions for Script Execution

When using Broker for executing scripts, several built-in variables and functions are available to facilitate and standardize script operations. These tools help ensure consistent task execution, error handling, and progress reporting.

### Variables

- **`BROKER_USER`**: This variable represents the user who is executing the script.
- **`BROKER_PWD`**: The current location.


### Functions

- **`headline <message>`**: 
  - Displays a prominent headline at the beginning of a script or major section to signify what operation is being initiated.
  - **Example Usage**: 
    ```bash
    headline "Deployment Process Initiated"
    ```

- **`info <message>`**: 
  - Outputs an informational message. Useful for logging steps or checks that are important to note but do not affect execution flow.
  - **Example Usage**: 
    ```bash
    info "Performing pre-deployment checks."
    ```

- **`task <message> <command>`**: 
  - Executes a given command. It detects if the command succeeds or fails and provides appropriate feedback.
  - **Single-line Example Usage**:
    ```bash
    task "Change to deployment directory" cd ~/projects/myapp
    ```
  - **Multi-line Example Usage**:
    ```bash
    task "Update repository to the latest changes" "
        git fetch origin main &&
        git reset --hard origin/main
    "
    ```
    Alternative as a function to keep syntax highlighting intact for better readability.
    ```bash
    cmd () {
        git fetch origin main &&
        git reset --hard origin/main
    }
    task "Backup existing configuration and apply new settings" cmd
    ```

- **`error <message>`**: 
  - Logs an error message in red and stops script execution. Useful for critical errors that require immediate intervention.
  - **Example Usage**: 
    ```bash
    error "Failed to apply new configuration settings."
    ```

- **`success <message>`**: 
  - Logs a success message in green, indicating the successful completion of a process. Typically used at the end of a script.
  - **Example Usage**: 
    ```bash
    success "Deployment completed successfully!"
    ```

- **`template <file> [marker]`**: 
  - Used for substituting placeholders within text files using environment variables, allowing dynamic configuration generation.
  - **Syntax**: 
    ```bash
    template <template-file> [marker]
    ```
  - **Parameters**:
    - `<template-file>`: Path to the template file containing placeholders.
    - `[marker]`: *(Optional)* Customize the placeholder format, specified as `"start_marker,end_marker"`. Defaults to `"{{,}}"`.
  - **Example Process**:
    ```bash
    SERVER_NAME="myserver.com"
    DB_HOST="db.myserver.com"
    template $BROKER_PWD/app.config.template > /tmp/app.config
    ```


## Best Practices

Manage your Broker configurations (including `bundles`, `access.cfg`, and `defaults.cfg`) within a Git repository.


### Example Repository Structure

```plaintext
repo-root/
│
├── access.cfg
├── defaults.cfg
└── bundles/
    ├── broker/
    │   └── update.sh
```

### Configuration Files

**`access.cfg`:**

```ini
[alice]
broker=update
```

**`defaults.cfg`:**

```ini
broker/update --repo=https://your-git-repository-url --branch=main
```

### Update Script

**`broker/update.sh`:**

```bash
#!/bin/bash

REPO_URL=""
BRANCH=""

for ARG in "$@"; do
  case $ARG in
    --repo=*)
      REPO_URL="${ARG#*=}"
      ;;
    --branch=*)
      BRANCH="${ARG#*=}"
      ;;
  esac
done

if [ -z "$REPO_URL" ] || [ -z "$BRANCH" ]; then
  error "Error: Both repository URL and branch must be specified."
  exit 1
fi

headline "Configuration update from $REPO_URL on branch $BRANCH."

cmd () {
  cd ~/.config/broker || exit &&
  git fetch "$REPO_URL" "$BRANCH" &&
  git reset --hard FETCH_HEAD
}; task "Fetch and apply changes" cmd

success "Done!"
```

### Execution

Then you can invoke the script to update the local configuration from remote git:

```bash
ssh broker@server_address broker update
```