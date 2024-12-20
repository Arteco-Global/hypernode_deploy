Hypernode Installer Script Documentation

This script automates the installation and update process for the Hypernode service suite. It includes functionalities for installing Docker, Git, cloning repositories from GitHub, and managing Docker containers for various services.

## Features

- **Progress Bar and Spinner**: Provides visual feedback during the installation process.
- **Command Execution with Spinner**: Executes commands with a spinner animation and handles errors gracefully.
- **ASCII Art**: Displays ASCII art at the beginning of the script.
- **Menu Options**: Presents a menu for selecting installation or update options.
- **Configuration**: Prompts the user for configuration options such as ports and branches.
- **Docker Installation**: Installs Docker if not already installed.
- **Git Installation**: Installs Git if not already installed.
- **Repository Cloning**: Clones necessary repositories from GitHub.
- **Service Installation and Update**: Installs or updates various services using Docker Compose.
- **Cleanup**: Provides options for cleaning up Docker containers, images, and volumes.

## Usage

Run the script with the desired options. The script supports various command-line arguments to skip certain steps or provide specific configurations.

```bash
./installer.sh [options]
```

### Command-Line Options

- `-erase-db`: Erase the database.
- `-skip-branch-ask`: Skip asking for branch names.
- `-skip-clean`: Skip the cleaning procedure.
- `-skip-docker-install`: Skip Docker installation.
- `-skip-git-install`: Skip Git installation.
- `-skip-clone`: Skip cloning repositories from GitHub.
- `-help`: Display help information.

## Functions

- `start_spinner`: Starts the spinner animation.
- `stop_spinner`: Stops the spinner animation.
- `update_progress`: Updates the progress bar.
- `execute_with_spinner`: Executes a command with a spinner animation.
- `show_ascii_art`: Displays ASCII art.
- `show_progress`: Displays the progress bar.
- `get_my_local_ip`: Retrieves the local IP address.
- `end_with_message`: Ends the script with a success or failure message.
- `drop_server_collection`: Drops the 'server' collection from the MongoDB database.
- `additionalServiceInstall`: Installs or updates an additional service.
- `dockerInstall`: Installs Docker.
- `installGit`: Installs Git.
- `cloningCode`: Clones repositories from GitHub.
- `show_menu`: Displays the menu options.
- `get_config`: Prompts the user for configuration options.
- `cleanProcedure`: Cleans up the code directory.
- `dockerNuke`: Stops and removes all Docker containers, images, networks, and volumes.
- `checkIfHypernodeIsInstalled`: Checks if Hypernode is already installed.
- `check_docker_installed`: Checks if Docker is installed.

## Example

```bash
./installer.sh -skip-docker-install -skip-git-install
```

This example runs the script while skipping Docker and Git installation steps.

## Notes

- Ensure you have the necessary permissions to run Docker and install packages.
- The script uses ANSI color codes for colored output.
- The script requires an active internet connection to clone repositories from GitHub.

## License

This script is provided "as is" without any warranty. Use it at your own risk.

