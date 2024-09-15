#!/bin/bash

# Make log of update
# Define the directory where logs will be stored
LOG_DIR="$HOME/documents/nixos-update-logs"

# Create the log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Generate a log file name based on the current date and time
LOG_FILE="$LOG_DIR/$(date +"%Y-%m-%d_%H-%M-%S").log"

# Make log of the update and store it in the log file
exec > >(tee "$LOG_FILE") 2>&1

log() {
    echo -e "\e[32m[INFO]\e[0m $1"
}

# Log prompt message
log_action() {
    echo -e "\e[34m[PROMPT]\e[0m $1"  # Blue color for prompts
}

# Log error message and exit
log_error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 command not found."
    fi
}

# Function to run txr command
run_txr() {
    check_command "/home/crackz/.local/bin/txr"
    log "Running txr..."
    /home/crackz/.local/bin/txr || log_error "txr command failed."
}

# Function to run lazygit
run_lazygit() {
    check_command "lazygit"
    log "Running lazygit..."
    cd "$HOME/repos/NixOS-config/" || { log_error "Failed to change directory to $HOME/repos/NixOS-config/"; return 1; } 
    lazygit || log_error "lazygit command failed."
}

# Function to perform nixos-rebuild with flake
run_nixos_switch() {
    check_command "nixos-rebuild"
    log "Running nixos-rebuild..."
    cd /persist/etc/nixos || { log_error "Failed to change directory to /persist/etc/nixos"; return 1; }  # Stop on failure
    sudo nixos-rebuild switch --flake ".#nixbox" || { log_error "nixos-rebuild failed."; return 1; }  # Stop on failure
    log "NixOS switch completed successfully."
}

# Function to run home-manager switch
run_home_manager_switch() {
    check_command "home-manager"
    log "Running home-manager switch..."
    cd ~/.config/home-manager || { log_error "Failed to change directory to ~/.config/home-manager"; return 1; }  # Stop on failure
    home-manager switch --flake ".#crackz" || { log_error "home-manager switch failed."; return 1; }  # Stop on failure
    log "Home-manager switch completed successfully."
}

# Function to dry run nixos-rebuild with flake
nixos_dry_run() {
    log "Performing flake-based dry run for nixos..."
    cd /persist/etc/nixos || log_error "Failed to change directory to /persist/etc/nixos"
    sudo nixos-rebuild dry-run --flake ".#nixbox" || log_error "Failed to perform flake-based dry run."
}

# Function to dry run home-manager with flake
home_manager_dry_run() {
    log "Performing flake-based dry run for home-manager..."
    cd ~/.config/home-manager || { log_error "Failed to change directory to ~/.config/home-manager"; return 1; }  # Stop on failure
    home-manager build --dry-run --flake ".#crackz" --extra-experimental-features "nix-command flakes" || {
        log_error "Failed to perform flake-based dry run for home-manager."
        return 1  # Stop if dry run fails
    }
    log "Dry run for home-manager completed successfully."
}

# Function to clean old generations and garbage collection, including removing orphaned packages
cleanup_system() {
    log "Cleaning up old generations and running garbage collection..."
    sudo nix-collect-garbage --delete-older-than 30d || log_error "Failed to clean up old generations."
    sudo nix-store --gc || log_error "Failed to clean up orphaned dependencies."
    remove_orphaned_packages
}

# Function to remove orphaned packages
remove_orphaned_packages() {
    log "Removing orphaned packages..."
    sudo nix-env --delete-generations || log_error "Failed to remove orphaned packages."
}

# Function to update flake
update_flake() {
    log "Updating flake.lock..."
    cd "$HOME/repos/NixOS-config/nixos/" || log_error "Failed to change directory to $HOME/repos/NixOS-config/nixos/"
    nix flake update || log_error "Failed to update flake.lock."
}

# Function to check disk space and display available space
check_disk_space() {
    log "Checking disk space usage..."
    avail=$(df -h / | awk 'NR==2 {print $4}')
    log "Available disk space: $avail"
}

# Function to ask for a complete clean
complete_clean() {
    while true; do
        log_action "Do you want to do a COMPLETE clean of old generatiions, performance gabage collection, and remove all orphaned packages? (YES/n) "
        read -r answer
        if [ "$answer" == "YES" ]; then
            log "Performing complete clean of all old generations and unused files..."
            sudo nix-collect-garbage -d || log_error "Failed to perform complete clean."
            sudo nix-store --gc || log_error "Failed to clean up unused dependencies."
            sudo nix-env --delete-generations || log_error "Failed to remove orphaned packages."
            log "Complete clean finished."
            log "***It's a good idea to rebuild the system after a complete clean to clear old boot entries and to make sure nothing went wrong!***"
            return 0
        else
            log "Skipping complete clean."
            return 1
        fi
    done
}

# Ask the user if they want to run system switch
ask_nixos_switch() {
    while true; do
        log_action "Do you want to switch your NixOS configuration? (y/n) "
        read -r answer
        case $answer in
            [Yy]* )
                log_action "Do you want to perform a dry run first? (y/n)"
                read -r dry_run_answer
                if [[ "$dry_run_answer" =~ [Yy]* ]]; then
                    if ! nixos_dry_run; then
                        log_error "Dry run failed. Exiting."
                        return 1  # Exit if dry run fails
                    fi

                    # Ask for confirmation after the dry run completes
                    log_action "Dry run completed. Do you want to proceed with the actual NixOS switch? (y/n)"
                    read -r proceed_answer
                    if [[ "$proceed_answer" =~ [Yy]* ]]; then
                        run_nixos_switch  # Now actually proceed with the switch
                    else
                        log "Skipping NixOS switch after dry run."
                    fi
                    return 0  # Exit the function after processing the decision
                else
                    run_nixos_switch  # No dry run, proceed with the actual switch
                fi
                break
                ;;
            [Nn]* )
                log "Skipping NixOS switch."
                break
                ;;
            * )
                log "Please answer y or n."
                ;;
        esac
    done
}

# Ask the user if they want to switch home-manager configuration
ask_switch_home_manager() {
    while true; do
        log_action "Do you want to switch your home-manager configuration? (y/n) "
        read -r answer
        case $answer in
            [Yy]* )
                log_action "Do you want to perform a dry run first? (y/n)"
                read -r dry_run_answer
                if [[ "$dry_run_answer" =~ [Yy]* ]]; then
                    if ! home_manager_dry_run; then
                        log_error "Dry run for home-manager failed. Exiting."
                        return 1  # Exit if dry run fails
                    fi

                    # Ask for confirmation after the dry run completes
                    log_action "Dry run completed. Do you want to proceed with the actual home-manager switch? (y/n)"
                    read -r proceed_answer
                    if [[ "$proceed_answer" =~ [Yy]* ]]; then
                        run_home_manager_switch  # Proceed with the actual switch
                    else
                        log "Skipping home-manager switch after dry run."
                    fi
                    return 0  # Exit the function after processing the decision
                else
                    run_home_manager_switch  # No dry run, proceed with the actual switch
                fi
                break
                ;;
            [Nn]* )
                break
                ;;
            * )
                log "Please answer y or n."
                ;;
        esac
    done
}

# Combined logic to ask for home-manager switch, then nixos if skipped
ask_switches() {
    if ask_switch_home_manager; then
        log "Skipping home-manager switch..."
    fi
    ask_nixos_switch
}


# Ask about cleaning up the system and removing orphaned packages
ask_cleanup() {
    while true; do
        log_action "Do you want to clean old generations, perform garbage collection, and remove orphaned packages? (y/n) "
        read -r answer
        case $answer in
            [Yy]* )
                cleanup_system
                break
                ;;
            [Nn]* )
                log "Skipping cleanup."
                break
                ;;
            * )
                log "Please answer y or n."
                ;;
        esac
    done
}

# Ask the user if they want to update the flake
ask_update_flake() {
    while true; do
        log_action "Do you want to update the flake? (y/n) "
        read -r answer
        case $answer in
            [Yy]* )
                sleep 1  # Add a small delay to avoid missing initial output

                # Run the update flake command and print output directly to the terminal
                update_flake

                log "Flake update completed."
                break
                ;;
            [Nn]* )
                log "Skipping flake update."
                break
                ;;
            * )
                log "Please answer y or n."
                ;;
        esac
    done
}

# Ask the user if they want to rebuild after a complete clean
ask_rebuild_after_clean() {
    while true; do
        log_action "Do you want to rebuild the system after the complete clean? (y/n) "
        read -r answer
        case $answer in
            [Yy]* )
                run_nixos_rebuild
                break
                ;;
            [Nn]* )
                log "Skipping rebuild."
                break
                ;;
            * )
                log "Please answer y or n."
                ;;
        esac
    done
}

# Change to the working directory
log "Running NixOS Update Script - $(date +"%Y-%m-%d %H:%M:%S")"# Log status message

# Run txr and lazygit
run_txr
run_lazygit

# Check disk space after lazygit is closed
check_disk_space

# Ask the user if they want to update the flake
ask_update_flake 

# Ask the user if they want to switch either home-manager or nixos configurations
ask_switches

# Ask if the user wants to clean up the system and remove orphaned packages
ask_cleanup

# Ask if the user wants to perform a complete clean
if complete_clean; then
    # If the user did the complete clean, ask if they want to rebuild the system
    ask_rebuild_after_clean
fi

log "*** REMEMBER THIS SCRIPT IS SYMLINKED MANUALLY, ONCE YOU MOVE THE SYMLINK TO NIXOS CONFIG YOU CAN REMOVE THIS ***"
