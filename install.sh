#!/bin/bash


# Copyright © 2024 Rajdeep Rath. All Rights Reserved.
#
# This codebase is open-source and provided for use exclusively with the Cloudisense platform,
# as governed by its End-User License Agreement (EULA). Unauthorized use, reproduction,
# or distribution of this code outside of the Cloudisense ecosystem is strictly prohibited.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# You may not use this file except in compliance with the License.
# A copy of the License is available at:
# http://www.apache.org/licenses/LICENSE-2.0
#
# This code may include third-party open-source libraries subject to their respective licenses.
# Such licenses are referenced in the source files or accompanying documentation.
#
# For questions or permissions beyond the scope of this notice, please contact Rajdeep Rath.


# PYTHON SETTINGS
# ------------------
PYTHON_DEFAULT_VENV_NAME="virtualenvs"
#PYTHON_VIRTUAL_ENV_LOCATION=~/
PYTHON_VIRTUAL_ENV_DEFAULT_LOCATION=
PYTHON_VIRTUAL_ENV_INTERPRETER=
CUSTOM__VIRTUAL_ENV_LOCATION=false
INSTALLATION_PYTHON_VERSION=
PYTHON_REQUIREMENTS_FILENAME=base.txt
PYTHON_RPI_REQUIREMENTS_FILENAME=rpi.txt
SPECIFIED_REQUIREMENTS_FILE=
RASPBERRY_PI=
PYTHON_VERSION=
CURRENT_INSTALLATION_PROFILE=
UIGUIDE_LAYOUT=


# GENERAL SETTINGS
# -------------------
PROGRAM_INSTALL_LOCATION=~
PROGRAM_NAME=cloudisense
PROGRAM_SERVICE_NAME=$PROGRAM_NAME
PROGRAM_SERVICE_LOCATION=/lib/systemd/system
DEFAULT_PROGRAM_PATH="/usr/local/$PROGRAM_NAME"
PROGRAM_CONFIGURATION_MERGER=/python/smartmerge.py
PROGRAM_SERVICE_AUTOSTART=false
PROGRAM_INSTALL_AS_SERVICE=true
PROGRAM_INSTALL_REPORT_NAME=report.json
PYTHON_MAIN_FILE=run.py
PROGRAM_DEFAULT_DOWNLOAD_FOLDER_NAME="tmp"
PROGRAM_DEFAULT_DOWNLOAD_FOLDER=
PROGRAM_DOWNLOAD_URL=
PROGRAM_VERSION=
PROGRAM_ERROR_LOG_FILE_NAME="log/error.log"
PROGRAM_UPDATE_CRON_HOUR=11
PROGRAM_SUPPORTED_INTERPRETERS=
PROGRAM_HASH=
CLIENT_INSTALL=


# LOGGING
LOG_FILE_NAME=cloudisense_installer.log
LOG_FILE=$PWD/$LOG_FILE_NAME
LOGGING=false



# shell argument variables
args_install_client_request=0
args_module_request=
args_update_request=
args_update_mode=
args_install_request=
args_requirements_file=
args_module_name=v
args_profile_request=
args_profile_name=
# shellcheck disable=SC2034
args_enable_disable_request=
# shellcheck disable=SC2034
args_enable_disable=
virtual_environment_exists=0
virtual_environment_valid=0


IS_64_BIT=0
OS_NAME=
OS_VERSION=
PLATFORM_ARCH=
OS_MAJ_VERSION=
OS_TYPE=
OS_DEB="DEBIAN"
OS_RHL="REDHAT"
INIT_SYSTEM=


has_min_python_version=0
python_install_success=0
virtual_environment_exists=0
virtual_environment_valid=0
latest_download_success=0
client_download_success=0
service_install_success=0
module_install_success=0

package_enabled=
package_url=
package_version=		
package_hash=
supported_interpreters=
__version__=


#############################################
# Change directory to the script's directory
# GLOBALS:
#	BASH_SOURCE
# RETURN:
#	
#############################################
switch_dir()
{
	local SCRIPT_DIR
	SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
	cd "$SCRIPT_DIR" || return
}



#############################################
# Added special user for cloudisense with admin rights
# Cloudisnese service must run as this special user!!
# GLOBALS:
#	PROGRAM_NAME
# RETURN:
#	
#############################################
add_user() {
    local user="$1"  # Accept username as parameter

    # Validate username
    if ! [[ "$user" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "Invalid username. Exiting."
        return 1
    fi

    # Check if the user already exists
    if id "$user" &>/dev/null; then
        echo "User $user already exists. Exiting."
        return 1
    fi

    # Create the user
    if ! seudo useradd -m -s "/bin/bash" "$user"; then
        echo "Error: Failed to create user $user. Exiting."
        return 1
    fi

    # Add the user to the sudo group
    if ! seudo usermod -aG sudo "$user"; then
        echo "Error: Failed to add $user to sudo group. Exiting."
        return 1
    fi
    echo "$user has been added to the sudo group."

    # Define the sudoers rule
    SUDO_RULE="$user ALL=(ALL) NOPASSWD: /usr/sbin/useradd, /usr/sbin/usermod, /bin/systemctl"

    # Validate the sudoers rule syntax before writing
    if ! echo "$SUDO_RULE" | seudo visudo -cf -; then
        echo "Invalid sudoers rule. Exiting."
        return 1
    fi

    # Create a new sudoers file for the user
    echo "# Sudo rules for $user" | seudo tee "/etc/sudoers.d/$user" > /dev/null
	echo "$SUDO_RULE" | seudo tee -a "/etc/sudoers.d/$user" > /dev/null


    # Set appropriate permissions
    seudo chmod 0440 "/etc/sudoers.d/$user"
    echo "Passwordless sudo configured for $user."

    # Validate the sudoers configuration
    if ! seudo visudo -cf /etc/sudoers; then
        echo "Error: Invalid sudoers configuration. Cleaning up." >&2
        seudo rm -f "/etc/sudoers.d/$user"
        return 1
    fi

    echo "Sudoers file validated successfully. Passwordless sudo configured for $user."
}





#############################################
# Removes special user for cloudisense from system

# GLOBALS:
#	
# RETURN:
#	
#############################################
remove_user() {
    local user="$1"  # Accept username as parameter

    # Validate username
    if ! [[ "$user" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "Invalid username. Exiting."
        return 1
    fi

    # Check if the user exists
    if ! id "$user" &>/dev/null; then
        echo "User '$user' does not exist. Exiting."
        return 1
    fi

    # Remove the user and optionally their home directory
    if seudo userdel -r "$user"; then
        echo "User '$user' and their home directory have been removed."
    else
        echo "Error: Failed to remove user '$user'. Exiting."
        return 1
    fi

    # Remove the user from the sudo group
    if seudo gpasswd -d "$user" sudo &>/dev/null; then
        echo "User '$user' has been removed from the sudo group."
    else
        echo "Warning: User '$user' was not in the sudo group or removal failed."
    fi

    # Check if the sudoers file exists and remove it
    if [ -f "/etc/sudoers.d/$user" ]; then
        if seudo rm -f "/etc/sudoers.d/$user"; then
            echo "Sudoers file for '$user' has been removed."
        else
            echo "Error: Failed to remove sudoers file for '$user'."
            return 1
        fi
    else
        echo "No sudoers file found for '$user'."
    fi

    echo "User '$user' has been successfully removed from the system."
}



#############################################
# Function to check if a user exists

# GLOBALS:
#	
# RETURN:
#	
#############################################
user_exists() {
    id "$1" &>/dev/null
}



#############################################
# Function to check if the user is in the 
# sudo group

# GLOBALS:
#	
# RETURN:
#	
#############################################
user_in_sudo_group() {
    groups "$1" | grep -q "\bsudo\b"
}



#############################################
# Checks if user exists
#
# GLOBALS:
#	
# RETURN:
#	Returns true if user exists in system
#   else returns false.
#	
#############################################
has_user() 
{
    local user="$1"  # Accept username as parameter

    if user_exists "$user"; then
        return 0  # Success
    else
        return 1  # Failure
    fi
}



#############################################
# Checks if user exists in sudo group
#
# GLOBALS:
#	
# RETURN:
#	Returns true if user exists in sudo group
#   else returns false.
#	
#############################################
is_user_sudoer()
{
	local user="$1"  # Accept username as parameter
	
	# Check if the user is in the sudo group
	if user_in_sudo_group "$user"; then
		true
	else
		false
	fi
}



#############################################
# Check if super user permissiosn have been 
# granted or not.
#
# GLOBALS:
#	
# RETURN:
#	true if permissiosn have been granted,
#	false otherwise.
#	
#############################################
validatePermissions()
{
	if [[ $EUID -ne 0 ]]; then
		false
	else
		true
	fi
}




#############################################
# Force request super user permissions
#
# GLOBALS:
#	
# RETURN:
#	
#############################################
request_permission()
{
	if [ "$EUID" -ne 0 ]; then
        sudo -v
    else
        return
    fi
}



#############################################
# Execute command as root
#
# GLOBALS:
#	
# RETURN:
#	
#############################################
# shellcheck disable=SC2086
seudo() 
{
    local cmd="$*"

    if [ "$EUID" -ne 0 ]; then        
        sudo $cmd
    else
        $cmd
    fi
}




#############################################
# Write content to external log file and also 
# print to console.
#
# GLOBALS:
#		LOGGING, LOG_FILE
# ARGUMENTS:
#		String to print
# RETURN:
#	
#############################################
lecho()
{
	if [ $# -eq 0 ]; then
		return
	else
		echo "$1"

		if $LOGGING; then
			sh -c "logger -s $1 2>> $LOG_FILE"
		fi
	fi
}



#############################################
# Write error to external log file and also 
# print to console.
#
# GLOBALS:
#		LOGGING, LOG_FILE
# ARGUMENTS:
#		Error string to print
# RETURN:
#	
#############################################
lecho_err()
{
	if [ $# -eq 0 ]; then
		return
	else
		# Red in Yellow
		echo -e "\e[41m $1\e[m"

		if $LOGGING; then
			sh -c "logger -s $1 2>> $LOG_FILE"
		fi
	fi
}





#############################################
# Write warning to external log file and also 
# print to console.
#
# GLOBALS:
#		LOGGING, LOG_FILE
# ARGUMENTS:
#		Error string to print
# RETURN:
#	
#############################################
lecho_warn()
{
	if [ $# -eq 0 ]; then
		return
	else
		echo -e "\e[33m $1\e[m"


		if $LOGGING; then
			sh -c "logger -s $1 2>> $LOG_FILE"
		fi
	fi
}





#############################################
# Write notice message to external log file and also 
# print to console.
#
# GLOBALS:
#		LOGGING, LOG_FILE
# ARGUMENTS:
#		Message string to print
# RETURN:
#	
#############################################
lecho_notice()
{
	if [ $# -eq 0 ]; then
		return
	else
		
		echo -e "\e[45m $1\e[m"

		if $LOGGING; then
			sh -c "logger -s $1 2>> $LOG_FILE"
		fi
	fi
}



#############################################
# Clear external log file
#
# GLOBALS:
#		LOG_FILE
# ARGUMENTS:
#		String to print
# RETURN:
#	
#############################################
clear_log()
{
	truncate -s 0 "$LOG_FILE"
}



#############################################
# Delete external log file
#
# GLOBALS:
#		LOG_FILE
# ARGUMENTS:
#		String to print
# RETURN:
#	
#############################################
delete_log()
{
	rm "$LOG_FILE"
}


######################################################################################
############################ MISC ----- METHODS ######################################


#############################################
# Clear console
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
cls()
{
	printf "\033c"
}



#############################################
# Create a interactive pause at console by 
# asking for an input from user
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
empty_pause()
{
	printf "\n"
	read -r -p 'Press any [ Enter ] key to continue...'
}


#############################################
# Print newline at console
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
empty_line()
{
	printf "\n"
}


######################################################################################
############################ MISC TOOL INSTALLS ######################################


#############################################
# Check for available supported python versions 
# on local system, going by the list of possible 
# versions provided by PROGRAM_SUPPORTED_INTERPRETERS. 
# On success PYTHON_VERSION is set to the best match 
# found.
#
# GLOBALS:
#		has_min_python_version, PROGRAM_SUPPORTED_INTERPRETERS,
#		PYTHON_VERSION, PYTHON_LOCATION
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_python()
{
	if is_pyenv_installed; then
        check_pyenv_python  # Use pyenv to check Python
        return 0
    fi

    if check_system_python; then
        return 0  # System Python found, exit successfully
    fi

    # If no valid system Python is found, install pyenv
    if install_pyenv; then
        echo "Pyenv installed successfully. Checking Python again..."
        check_pyenv_python
        return 0
    else
        echo "Error: Pyenv installation failed!"
        return 1
    fi
}




check_system_python() 
{
    has_min_python_version=0  # Reset flag

    echo "Checking for compatible Python installations on system..."
    
    for ver in "${PROGRAM_SUPPORTED_INTERPRETERS[@]}"; do
        echo "Checking for python$ver on local system..."

        # Find Python binary
        local PYTHON_EXISTS
        PYTHON_EXISTS=$(command -v python"$ver")

        # Ensure it is a valid executable before proceeding
        if [[ -x "$PYTHON_EXISTS" ]]; then
            echo "python$ver found @ $PYTHON_EXISTS"
            has_min_python_version=1  # Set global flag
            PYTHON_LOCATION="$PYTHON_EXISTS"
            PYTHON_VERSION="$ver"  # Store version
            return  0 # Stop searching after finding the first match
        fi
    done

    
	echo "No compatible system Python found."
	return  1
}




#############################################
# Check for available supported python versions 
# in pyenv, going by the list of possible 
# versions provided by PROGRAM_SUPPORTED_INTERPRETERS. 
# On success PYTHON_VERSION is set to the best match 
# found.
#
# GLOBALS:
#		has_min_python_version, PROGRAM_SUPPORTED_INTERPRETERS,
#		PYTHON_VERSION, PYTHON_LOCATION
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_pyenv_python() {
    has_min_python_version=0  # Reset global flag

    echo "Checking for compatible Python installations in pyenv..."

    # Loop through all installed Python versions in pyenv
    while read -r py_version; do
        # Extract only the major.minor version (e.g., 3.9)
        local PYTHON_VERSION_FOUND
        PYTHON_VERSION_FOUND=$(echo "$py_version" | cut -d'.' -f1,2)

        # Check if this version is supported
        for ver in "${PROGRAM_SUPPORTED_INTERPRETERS[@]}"; do
            if [[ "$PYTHON_VERSION_FOUND" == "$ver" ]]; then
                echo "Compatible Python $ver found in pyenv."
                has_min_python_version=1  # Set flag
                PYTHON_VERSION="$ver"
                PYTHON_LOCATION="$(pyenv root)/versions/$py_version/bin/python"
                return 0 # Stop searching after finding the first match
            fi
        done
    done < <(pyenv versions --bare)

    echo "No compatible Python version found in pyenv."
	return 1
}





#############################################
# Check if pyenv is used to manage python 
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN: 0 (true) | 1 (false)
#	
#############################################
is_pyenv_installed() {
    # Check if 'pyenv' command exists
    if ! command -v pyenv &> /dev/null; then
        return 1  # False, pyenv is not installed
    fi

    # Check if Python executable path is inside pyenv directories
    if [[ "$(python -c 'import sys; print(sys.executable)')" == *"$HOME/.pyenv/versions/"* ]]; then
        return 0  # True, pyenv is managing Python
    fi

    # Check if pyenv is currently setting the global/local version
    if [[ -n "$(pyenv version-name 2>/dev/null)" ]]; then
        return 0  # True, pyenv is actively managing Python
    fi

    return 1  # False, pyenv is not managing Python
}



# Public

#############################################
# Check if sudo module is available on the 
# linux system. 
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_procps()
{
	# Check if sudo is installed
	if command -v procps > /dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}



#############################################
# Check if sudo module is available on the 
# linux system. 
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_sudo()
{
	# Check if sudo is installed
	if command -v sudo > /dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}





#############################################
# Check if unzip module is available on the 
# linux system. 
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_unzip()
{

    # Check if unzip is installed
    if command -v unzip > /dev/null 2>&1; then
		return 0		
    else
		return 1
    fi
}



#############################################
# Check if jq module is available on the 
# linux system. 
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_jq()
{
    # Check if jq is installed
    if command -v jq > /dev/null 2>&1; then
		return 0
    else
		return 1
    fi
}



#############################################
# Check if mail module is available on the 
# linux system. 
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
############################################
check_mail()
{
    if isDebian; then
        # Check if mailutils is installed on Debian-based systems
        if command -v mail > /dev/null 2>&1; then
			return 0
        else
			return 1
        fi
    else
        # Check for mailx on non-Debian systems
        if command -v mailx > /dev/null 2>&1; then
			return 0
        else
			return 1 
        fi
    fi
}



#############################################
# Check if git module is available on the 
# linux system. 
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_git()
{

    # Check if git is installed
    if command -v git > /dev/null 2>&1; then
		return 0 
    else
		return 1 
    fi
}




#############################################
# Check if curl module is available on the 
# linux system. If true then curl_check_success 
# is set to 1, otherwise 0.
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_curl()
{
    # Check if curl is installed
    if command -v curl > /dev/null 2>&1; then
		return 0 
    else
		return 1 
    fi
}





#############################################
# Check if supervisor module is available on the 
# linux system. 
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_supervisor()
{
    # Check if wget is installed
    if command -v supervisord >/dev/null 2>&1; then
		return 0 
    else
		return 1 
    fi
}




#############################################
# Check if crontab module is available on the 
# linux system.
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_crontab()
{
	if command -v crontab >/dev/null; then
		return 0 
	else
		return 1 
	fi
}




#############################################
# Check if wget module is available on the 
# linux system. If true then wget_check_success 
# is set to 1, otherwise 0.
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_wget()
{

    # Check if wget is installed
    if command -v wget > /dev/null 2>&1; then
		return 0 
    else
		return 1 
    fi
}



#############################################
# Check if bc module is available on the 
# linux system. If true then wget_check_success 
# is set to 1, otherwise 0.
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_bc()
{
    # Check if bc is installed
    if command -v bc > /dev/null 2>&1; then
		return 0  # Success, bc is installed
    else
        return 1  # Failure, bc is not installed
    fi
}




#############################################
# Check if systemd module is available on the 
# linux system. If true then systemd_check_success 
# is set to 1, otherwise 0.
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
check_systemd()
{
    # Check if systemd is installed
    if command -v systemd > /dev/null 2>&1; then
        return 0  # Return success if systemd is found
    else
        return 1  # Return failure if systemd is not found
    fi
}



#############################################
# Installs additional dependencies and libraries 
# needed by python core installation.
#
# GLOBALS:
#		
# ARGUMENTS:
#		$1: Python version number. 
# 		For DEB it is major.minor and
# 		for major.minor RHLE.
# RETURN:
#	
#############################################
ensure_python_additionals()
{
	local ver=$1

	if is_pyenv_installed; then
		lecho "Nothing to do here"
	else
		if isDebian; then		
			install_python_additionals_deb "$ver"
		else
			# remove dot from version number for rhle
			local vernum=${ver//./}  # Output: 123
			install_python_additionals_rhl "$vernum"
		fi
	fi
}




#############################################
# Installs additional dependencies and libraries 
# needed by python core installation on Debian.
#
# GLOBALS:
#		
# ARGUMENTS:
#		$1: Python version number.
# RETURN:
#	
#############################################
install_python_additionals_deb() {
    local ver=$1

    lecho "Installing additional dependencies"

    # Check and install python version-specific venv if available
    if apt-cache madison python"$ver"-venv | grep -q "python$ver-venv"; then
        seudo apt-get install -y python"$ver"-venv
    fi

    # Check and install python version-specific dev package if available
    if apt-cache madison python"$ver"-dev | grep -q "python$ver-dev"; then
        seudo apt-get install -y python"$ver"-dev
    fi

    # Install common Python packages
    seudo apt-get install -y python3-pip python3-venv python3-testresources
}






#############################################
# Installs additional dependencies and libraries 
# needed by python core installation on RHLE/Centos.
#
# GLOBALS:
#		
# ARGUMENTS:
#		$1: Python version number.
# RETURN:
#	
#############################################
install_python_additionals_rhl()
{
	local ver=$1
	seudo yum install -y python3-pip python"$ver"-devel python3-venv python3-testresources

}





#############################################
# Installs pyenv
#
# GLOBALS:
#		
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
install_pyenv() 
{
    echo "Installing dependencies for pyenv..."
   

    echo "Cloning pyenv repository..."
    git clone https://github.com/pyenv/pyenv.git ~/.pyenv

    echo "Setting up pyenv environment variables..."
    # Detect the shell and set up pyenv in the correct profile
    if [[ $SHELL == */zsh ]]; then
        PROFILE_FILE="$HOME/.zshrc"
    else
        PROFILE_FILE="$HOME/.bashrc"
    fi

    # Add pyenv to shell profile if not already added
    if ! grep -q "export PYENV_ROOT=\"$HOME/.pyenv\"" "$PROFILE_FILE"; then
        {
            echo "export PYENV_ROOT=\"$HOME/.pyenv\""
            echo "export PATH=\"\$PYENV_ROOT/bin:\$PATH\""
            echo "eval \"\$(pyenv init --path)\""
            echo "eval \"\$(pyenv init -)\""
        } >> "$PROFILE_FILE"
    fi

    echo "Applying pyenv configuration..."
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init --path)"
    eval "$(pyenv init -)"

    echo "pyenv installation completed successfully."
    return 0
}





#############################################
# Installs python core on Debain and RHLE. If
# installation is successful python_install_success
# is set to 1, otherwise 0
# GLOBALS:
#		python_install_success
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
install_python()
{	
	python_install_success=0

	if is_pyenv_installed; then
		install_pyenv_python
	else
		install_system_python
	fi	

	# verify
	check_python

	if [ $has_min_python_version -eq 1 ]; then
		lecho "Python $PYTHON_VERSION successfully installed at $PYTHON_LOCATION"
		# shellcheck disable=SC2034
		python_install_success=1
	else
		lecho "Could not install required version of python"
	fi
}





#############################################
# Checks to see if a particular version of python
# can be installed from supported list of interpreters, 
# and then installs it.
#
# GLOBALS:

# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_pyenv_python()
{
	# Check for supported Python versions in the yum repository
    for version in "${PROGRAM_SUPPORTED_INTERPRETERS[@]}"; do
        lecho "Checking for python$version in pyenv..."
        if can_install_pyenv_python "$version"; then
			lecho "Installing python$version in pyenv..."
			install_pyenv_python_version "$version"
			return
		fi
    done

	lecho "Could not install any of the supported version of python in pyenv..."
}




#############################################
# Installs specified version of python through 
# pyenv.
# GLOBALS:

# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_pyenv_python_version() {
    local python_version="$1"  # Get the Python version from function argument

    if [[ -z "$python_version" ]]; then
        echo "Error: No Python version specified. Usage: install_pyenv_python <version>"
        return 1
    fi

    # Check if the requested Python version is already installed
    if pyenv versions --bare | grep -q "^$python_version$"; then
        echo "Python $python_version is already installed via pyenv."
    else
        echo "Installing Python $python_version using pyenv..."
        pyenv install "$python_version"
    fi

	# Setting python version to use henceforth
	PYTHON_VERSION="$python_version"
    echo "Python $PYTHON_VERSION installation completed successfully via pyenv."
    return 0
}




#############################################
# Install system python
# GLOBALS:

# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_system_python()
{
	if isDebian; then
	install_python_deb	
	else
	install_python_rhl
	fi
}




#############################################
# Checks if a particular major version of python
# can be installed by pyenv
# Where target_version is passed in as parameter
# GLOBALS:

# ARGUMENTS:
#
# RETURN:
#	
#############################################
can_install_pyenv_python() {
    local target_version="$1"  # Accepts major.minor (e.g., "3.8")

    echo "Checking for the Python $target_version.x availablity in pyenv..."

    # Get the latest available patch version from pyenv
    local latest_patch_version
    latest_patch_version=$(pyenv install --list 2>/dev/null | 
        grep -E "^\s*${target_version}\.[0-9]+$" | 
        tr -d ' ' | sort -V | tail -n1)

    if [[ -z "$latest_patch_version" ]]; then
        echo "No available Python version for $target_version.x in pyenv."
        return 1
    fi

    echo "Latest Python version found: $latest_patch_version"
    return 0
}




# Private


#############################################
# Installs python specific version from source on Debain.
# Where VER is passed in as parameter
# GLOBALS:

# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_python_deb_src() 
{
    local ver="$1"

    if [ -z "$ver" ]; then
        echo "Error: Python version is not specified. Usage: install_python_deb_src <version>" >&2
        return 1
    fi

    echo "Installing Python $ver from source..."

    # Update and install prerequisites
    prerequisites_update_deb
    seudo apt-get install -y build-essential libssl-dev zlib1g-dev libncurses5-dev \
        libnss3-dev libreadline-dev libffi-dev curl libbz2-dev libsqlite3-dev wget || {
        echo "Error: Failed to install prerequisites." >&2
        return 1
    }

    # Fetch the latest patch version
    local LATEST_VERSION
    LATEST_VERSION=$(curl -s https://www.python.org/ftp/python/ | grep -oP "$ver\.\d+" | sort -V | tail -n 1)

    if [ -z "$LATEST_VERSION" ]; then
        echo "Error: Failed to find the latest patch version for Python $ver." >&2
        return 1
    fi

    # Form the download URL
    local DOWNLOAD_URL="https://www.python.org/ftp/python/$LATEST_VERSION/Python-$LATEST_VERSION.tgz"
    echo "Latest Python $ver version: $LATEST_VERSION"
    echo "Download URL: $DOWNLOAD_URL"

    # Download and extract the source code
    local TEMP_DIR="/tmp/python-src"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || {
        echo "Error: Failed to navigate to $TEMP_DIR." >&2
        return 1
    }

    curl -O "$DOWNLOAD_URL" || {
        echo "Error: Failed to download Python source." >&2
        return 1
    }

    tar -xf "Python-$LATEST_VERSION.tgz" || {
        echo "Error: Failed to extract Python source." >&2
        return 1
    }

    cd "Python-$LATEST_VERSION" || {
        echo "Error: Python source directory not found." >&2
        return 1
    }

    # Build and install Python
    seudo ./configure --enable-optimizations --enable-loadable-sqlite-extensions || {
        echo "Error: Configuration failed." >&2
        return 1
    }

    local CORES
    CORES=$(nproc)
    seudo make -j"$CORES" || {
        echo "Error: Build failed." >&2
        return 1
    }

    seudo make altinstall || {
        echo "Error: Installation failed." >&2
        return 1
    }

    echo "Python $LATEST_VERSION installed successfully."
}




#############################################
# Installs python specific version from source on redhat systems.
# Where VER is passed in as parameter
# GLOBALS:

# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_python_rhl_src() {
    local version="$1"

    if [ -z "$version" ]; then
        echo "Error: Python version not specified. Usage: install_python_rhl_src <version>" >&2
        return 1
    fi

    echo "Installing Python $version from source on Red Hat-based system..."

    # Install required development tools and libraries
    if ! seudo yum install -y gcc openssl-devel bzip2-devel libffi-devel wget; then
        echo "Error: Failed to install dependencies." >&2
        return 1
    fi

    # Define variables
    local TMP_DIR="/tmp/python-src"
    local PYTHON_TARBALL="Python-$version.tgz"
    local PYTHON_URL="https://www.python.org/ftp/python/$version/$PYTHON_TARBALL"
    local PYTHON_SRC_DIR="Python-$version"

    # Prepare temporary directory
    mkdir -p "$TMP_DIR" || { echo "Error: Failed to create temporary directory $TMP_DIR." >&2; return 1; }
    cd "$TMP_DIR" || { echo "Error: Failed to change to directory $TMP_DIR." >&2; return 1; }

    # Download and extract the Python source tarball
    if ! wget "$PYTHON_URL"; then
        echo "Error: Failed to download $PYTHON_URL." >&2
        return 1
    fi
    if ! tar xzf "$PYTHON_TARBALL"; then
        echo "Error: Failed to extract $PYTHON_TARBALL." >&2
        return 1
    fi

    # Build and install Python
    cd "$PYTHON_SRC_DIR" || { echo "Error: Directory $PYTHON_SRC_DIR not found." >&2; return 1; }
    if ! ./configure --enable-optimizations; then
        echo "Error: Configuration failed." >&2
        return 1
    fi

    local CORES
    CORES=$(nproc)
    if ! seudo make -j"$CORES"; then
        echo "Error: Build failed." >&2
        return 1
    fi

    if ! seudo make altinstall; then
        echo "Error: Installation failed." >&2
        return 1
    fi

    # Cleanup
    cd /
    rm -rf "$TMP_DIR"

    echo "Python $version installation complete."
}





#############################################
# Checks available python versions on apt against
# the list of supported versions provided by
# PROGRAM_SUPPORTED_INTERPRETERS. Installs the one
# that is supported as well as available on apt. 
#
# GLOBALS:
#		PROGRAM_SUPPORTED_INTERPRETERS, PYTHON_VERSION
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_python_deb()
{
	local supported_python_package_check_success=0	


	for ver in "${PROGRAM_SUPPORTED_INTERPRETERS[@]}"
	do
		echo "Checking for python$ver on apt"	

		if ! deb_package_exists "python$ver"; then
			if ! grep -q "^deb .\+deadsnakes" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
				echo "The 'deadsnakes' repository is not enabled. Adding it now..."
				seudo add-apt-repository ppa:deadsnakes/ppa -y
				seudo apt-get update -qq
			fi
		fi		

		local PYTHON_PACKAGE_EXISTS
		PYTHON_PACKAGE_EXISTS=$(apt-cache search --names-only "^python$ver-.*" | wc -l)
		PYTHON_VERSION=$ver

		if [[ $PYTHON_PACKAGE_EXISTS -gt 0 ]]; then
			# package found...use this version
			echo "python$ver found on apt"			
			supported_python_package_check_success=1
			break
		else
			echo "python$ver not found"
			supported_python_package_check_success=0
		fi
	done
	
	if [ "$supported_python_package_check_success" -eq 1 ]; then
		# Installing Python from apt
		lecho "Installing python$PYTHON_VERSION from apt..."
		
		if ! seudo apt-get install -y "python$PYTHON_VERSION"; then
			lecho_err "Error: Failed to install python$PYTHON_VERSION from apt." >&2
			return 1
		fi
		
		# Install additional Python-related dependencies
		install_python_additionals_deb "$PYTHON_VERSION"
	else
		lecho "No supported python package found in apt repository. Attempting to install from source..."

		# Prompt the user for confirmation to continue with installation from source
		read -r -p "Do you wish to continue installing Python $PYTHON_VERSION from source? [y/N] " response
		
		case "$response" in
			[yY][eE][sS]|[yY]) 
					if [ ${#PROGRAM_SUPPORTED_INTERPRETERS[@]} -gt 0 ]; then
						# Get the first item from the array
						PYTHON_VERSION="${PROGRAM_SUPPORTED_INTERPRETERS[0]}"
						lecho "Proceeding with Python $PYTHON_VERSION installation from source for Debian."
						if ! install_python_deb_src "$PYTHON_VERSION"; then
							lecho_err "Error: Failed to install Python $PYTHON_VERSION from source." >&2
							return 1
						fi
					else
						# list is empty
						lecho_err "something is wrong. I see no interpreters to install. Please contact administrator." >&2
					fi				
				;;
			*)
				lecho_err "Aborting Python installation. Please contact administrator." >&2
				return 1
				;;
		esac
	fi


}



# Private

#############################################
# Checks available python versions on yum against
# the list of supported versions provided by
# PROGRAM_SUPPORTED_INTERPRETERS. Installs the one
# that is supported as well as available on yum. 
#
# GLOBALS:
#		PROGRAM_SUPPORTED_INTERPRETERS, PYTHON_VERSION
# ARGUMENTS:
#
# RETURN:
#	
#############################################
# Needs to be checked against real OS
install_python_rhl() {
    local python_version_found=""
    local version_no_dots=""
    
    lecho "Starting Python installation for RedHat-based systems."

    # Check for supported Python versions in the yum repository
    for version in "${PROGRAM_SUPPORTED_INTERPRETERS[@]}"; do
        lecho "Checking for python$version in yum repository..."

        version_no_dots="${version//./}"  # Remove dots, e.g., 3.7 -> 37
        if yum list available 2>/dev/null | grep -qE "python${version_no_dots}(\s|$)"; then
            lecho "Found python$version in yum repository."
            python_version_found="$version"
            break
        fi
    done

    if [[ -n $python_version_found ]]; then
        # Install the detected Python package from yum
        lecho "Installing python$python_version_found from yum..."
        if ! seudo yum install -y "python${python_version_found//./}"; then
            lecho_err "Error: Failed to install python$python_version_found from yum." >&2
            return 1
        fi

        # Install additional Python-related dependencies
        if ! install_python_additionals_rhl "${python_version_found//./}"; then
            lecho_err "Error: Failed to install additional dependencies for python$python_version_found." >&2
            return 1
        fi
    else
        # No supported Python package found, attempt to install from source
        lecho "No supported python package found in yum repository. Proceeding with installation from source..."
		if [ ${#PROGRAM_SUPPORTED_INTERPRETERS[@]} -gt 0 ]; then
			# Get the first item from the array
			PYTHON_VERSION="${PROGRAM_SUPPORTED_INTERPRETERS[0]}"
			# Prompt user for confirmation to install from source
			read -r -p "No package found for python$PYTHON_VERSION. Do you wish to continue with installation from source? [y/N] " response
			case $response in
				[yY][eE][sS]|[yY])
					lecho "Installing python$PYTHON_VERSION from source..."
					if ! install_python_rhl_src "$PYTHON_VERSION"; then
						lecho_err "Error: Failed to install python$PYTHON_VERSION from source." >&2
						return 1
					fi
					;;
				*)
					lecho_err "Aborting Python installation. Please contact the administrator if needed." >&2
					return 1
					;;
        	esac

		else
			# list is empty
			lecho_err "something is wrong. I see no interpreters to install. Please contact administrator." >&2
		fi	        
        
    fi

    lecho "Python installation process completed successfully."
    return 0
}





# Public

#############################################
# Installs procps on the linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_procps()
{
	if isDebian; then
	install_procps_deb	
	else
	echo "procps Not installable"
	fi		
}



#############################################
# Installs sudo on the linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_sudo()
{
	if isDebian; then
	install_sudo_deb	
	else
	install_sudo_rhl
	fi		
}




#############################################
# Installs unzip on the linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_unzip()
{
	if isDebian; then
	install_unzip_deb	
	else
	install_unzip_rhl
	fi		
}



#############################################
# Installs jq on the linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_jq()
{
	if isDebian; then
	install_jq_deb	
	else
	install_jq_rhl
	fi		
}



#############################################
# Installs mail utilities on the linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_mail()
{
	if isDebian; then
	install_mail_deb	
	else
	install_mail_rhl
	fi
}


# Private

#############################################
# Installs mail utilities on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_mail_deb()
{
	seudo apt-get install -y mailutils

	install_mail="$(which mailutils)";
	lecho "mailutils installed at $install_mail"
}



#############################################
# Installs mail utilities on RHLE/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_mail_rhl()
{
	seudo yum -y install mailx

	local install_mail
	install_mail="$(which mailx)";
	lecho "mailx installed at $install_mail"
}



#############################################
# Installs jq on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_jq_deb()
{
	seudo apt-get install -y jq

	install_jq="$(which jq)";
	lecho "jq installed at $install_jq"
}



#############################################
# Installs jq on RHLE/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_jq_rhl()
{
	seudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
	seudo yum install jq -y

	local install_jq
	install_jq="$(which jq)";
	lecho "jq installed at $install_jq"
}




#############################################
# Installs procps on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_procps_deb()
{
	local install_procps
    
    if apt-get install -y procps; then
        install_procps="$(which procps)"
        lecho "procps installed at $install_procps"
    else
        lecho "Failed to install procps."
        return 1  # Indicate failure
    fi
}




#############################################
# Installs sudo on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_sudo_deb()
{
	local install_sudo
    
    # Try to install sudo -> if you are sudo already you dont need sudo installed
    if apt-get install -y sudo; then
        install_sudo="$(which sudo)"
        lecho "sudo installed at $install_sudo"
    else
        lecho "Failed to install sudo."
        return 1  # Indicate failure
    fi
}



#############################################
# Installs sudo on RHLe/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_sudo_rhl()
{
	local install_sudo

    # Try to install sudo -> if you are sudo already you dont need sudo installed
    if yum -y install sudo; then
        install_sudo="$(which sudo)"
        lecho "sudo installed at $install_sudo"
    else
        lecho "Failed to install sudo."
        return 1  # Indicate failure
    fi
}




#############################################
# Installs unzip on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_unzip_deb()
{
	local install_unzip
	seudo apt-get install -y unzip

	install_unzip="$(which unzip)";
	lecho "Unzip installed at $install_unzip"
}



#############################################
# Installs unzip on RHLe/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_unzip_rhl()
{
	local install_unzip
	seudo yum -y install unzip

	install_unzip="$(which unzip)";
	lecho "Unzip installed at $install_unzip"
}



#############################################
# Installs git utility on linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_git()
{
	if isDebian; then
	install_git_deb	
	else
	install_git_rhl
	fi		
}




#############################################
# Installs curl utility on linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_curl()
{
	if isDebian; then
	install_curl_deb	
	else
	install_curl_rhl
	fi		
}



#############################################
# Installs supervisor utility on linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_supervisor()
{
	if isDebian; then
	install_supervisor_deb	
	else
	install_supervisor_rhl
	fi		
}



#############################################
# Installs cron utility on linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_crontab()
{
	if isDebian; then
		install_crontab_deb	
	else
		install_crontab_rhl
	fi		
}





#############################################
# Installs wget utility on linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_wget()
{
	if isDebian; then
	install_wget_deb	
	else
	install_wget_rhl
	fi		
}



#############################################
# Installs bc utility on linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_bc()
{
	if isDebian; then
	install_bc_deb	
	else
	install_bc_rhl
	fi		
}



#############################################
# Installs systemd utility on linux system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_systemd()
{
	if isDebian; then
	install_systemd_deb	
	else
	install_systemd_rhl
	fi		
}



#############################################
# Installs git on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################

install_git_deb()
{
	seudo apt-get install -y git

	local install_loc
	install_loc="$(which git)";
	lecho "git installed at $install_loc"
}



#############################################
# Installs git on RHLE/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################

install_git_rhl()
{	
	seudo yum -y install git
	
	local install_loc
	install_loc="$(which git)";
	lecho "git installed at $install_loc"
}



#############################################
# Installs curl on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################

install_curl_deb()
{
	seudo apt-get install -y curl

	local install_loc
	install_loc="$(which curl)";
	lecho "curl installed at $install_loc"
}




#############################################
# Installs curl on RHLE/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################

install_curl_rhl()
{
	# yup update
	seudo yum -y install curl

	local install_loc
	install_loc="$(which curl)";
	lecho "curl installed at $install_loc"
}




#############################################
# Installs supervisor on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################

install_supervisor_deb()
{
	seudo apt-get install -y supervisor

	local install_loc
	install_loc="$(which supervisord)";
	lecho "supervisor installed at $install_loc"
}




#############################################
# Installs cron on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################

install_crontab_deb()
{
	seudo apt-get install -y cron

    # Check installation location
    local install_loc
    install_loc="$(which crontab)"
    if [ -n "$install_loc" ]; then
        echo "cron installed successfully. 'crontab' located at $install_loc"
    else
        echo "cron installation failed or 'crontab' not found."
    fi
}





#############################################
# Installs wget on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################

install_wget_deb()
{
	seudo apt-get install -y wget

	local install_loc
	install_loc="$(which wget)";
	lecho "wget installed at $install_loc"
}




#############################################
# Installs wget on RHLE/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_supervisor_rhl()
{
	# yup update
	seudo yum -y install supervisor

	local install_loc
	install_loc="$(which supervisor)";
	lecho "supervisor installed at $install_loc"
}



#############################################
# Installs wget on RHLE/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_crontab_rhl()
{
	# Install cron using yum
    seudo yum install -y cronie

    # Check installation location
    local install_loc
    install_loc="$(which crontab)"
    if [ -n "$install_loc" ]; then
        lecho "cron installed successfully. 'crontab' located at $install_loc"
    else
        lecho "cron installation failed or 'crontab' not found."
    fi
}



#############################################
# Installs wget on RHLE/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_wget_rhl()
{
	# yup update
	seudo yum -y install wget

	local install_loc
	install_loc="$(which wget)";
	lecho "wget installed at $install_loc"
}




#############################################
# Installs bc on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_bc_deb()
{
	seudo apt-get install -y bc

	local install_loc
	install_loc="$(which bc)";
	lecho "bc installed at $install_loc"
}


#############################################
# Installs systemd on Debian
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_systemd_deb()
{
	seudo apt-get install -y systemd

	local install_loc
	install_loc="$(which systemd)";
	lecho "systemd installed at $install_loc"
}



#############################################
# Installs bc on RHLE/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_bc_rhl()
{
	# yup update
	seudo yum -y install bc

	local install_loc
	install_loc="$(which bc)";
	lecho "bc installed at $install_loc"
}




#############################################
# Installs systemd on RHLE/CentOS
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_systemd_rhl()
{
	# yup update
	seudo yum -y install systemd

	local install_loc
	install_loc="$(which systemd)";
	lecho "bc systemd at $install_loc"
}


# Public

######################################################################################



#############################################
# Check if cloudisense is installed on system
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#		True if it is installed, false otherwise
#############################################
program_exists()
{	
	if [ -d "$DEFAULT_PROGRAM_PATH" ]; then
		
		local main_file="$DEFAULT_PROGRAM_PATH/$PYTHON_MAIN_FILE"
		local rules_directory="$DEFAULT_PROGRAM_PATH/rules"

		if [ -f "$main_file" ]; then
			if [ -d "$rules_directory" ]; then
				true
			fi
		else
			false
		fi
	else
	  false
	fi
}




#############################################
# Create virtual environemnt if not exists
# 
# GLOBALS:
#		virtual_environment_exists, VENV_FOLDER
# ARGUMENTS:
#
# RETURN:
#		
#############################################
check_create_virtual_environment()
{
	if is_pyenv_installed; then
		check_create_pyenv_virtual_environment
	else
		check_create_system_virtual_environment
	fi
}





#############################################
# Check and create virtual environment for cloudisense,
# using the python version determined.If environment
# already exists, determine its usability. Then
# either reuse the same environment or create new.
# 
# GLOBALS:
#		virtual_environment_exists, VENV_FOLDER
# ARGUMENTS:
#
# RETURN:
#		
#############################################
check_create_system_virtual_environment()
{
	virtual_environment_exists=0


	VENV_FOLDER="$PYTHON_VIRTUAL_ENV_LOCATION/$PROGRAM_FOLDER_NAME"


	if [ ! -d "$PYTHON_VIRTUAL_ENV_LOCATION" ]; then	
		mkdir -p "$PYTHON_VIRTUAL_ENV_LOCATION"
		chown -R "$USER:" "$PYTHON_VIRTUAL_ENV_LOCATION"
	fi	

	python=$(which "python$PYTHON_VERSION")
	pipver=$(which pip3)

	$python -m pip install --upgrade pip
	$pipver install --upgrade setuptools wheel pip
	
	

	if [ ! -d "$VENV_FOLDER" ]; then

		echo "Creating virtual environment @ $VENV_FOLDER"
		$python -m venv "$VENV_FOLDER"
		chown -R "$USER:" "$VENV_FOLDER"

		if [ -f "$VENV_FOLDER/bin/activate" ]; then
			lecho "Virtual environment created successfully"
			virtual_environment_exists=1
		else
			lecho "Fatal error! Virtual environment could not be created." && exit 1
		fi

	else

		echo "Virtual environment folder already exists.. let me check it.." && sleep 1
		if [ ! -f "$VENV_FOLDER/bin/activate" ] || [ ! -f "$VENV_FOLDER/bin/pip" ] || [ ! -f "$VENV_FOLDER/bin/python3" ]; then
			echo "Virtual environment seems broken. Trying to re-create"
			rm -rf "$VENV_FOLDER" && sleep 1
			check_create_system_virtual_environment # Create virtual environment again
		else
			lecho "Activating virtual environment"
			# shellcheck disable=SC1091
			source "$VENV_FOLDER/bin/activate"
			
			local venv_python
			venv_python=$(python --version)

			deactivate
			
			if [[ "$venv_python" == *"python$PYTHON_VERSION"* ]]; then
				echo "Virtual environment has same version of python."
			else
				rm -rf "$VENV_FOLDER" && sleep 1
				check_create_system_virtual_environment # Create virtual environment again
			fi

			echo "Virtual environment is folder is ok to use." && sleep 1
			virtual_environment_exists=1
		fi		

	fi
}




#############################################
# Check and create virtual environment for cloudisense,
# using the python version determined with pyenv.If environment
# already exists, determine its usability. Then
# either reuse the same environment or create new.
# 
# GLOBALS:
#		virtual_environment_exists, VENV_FOLDER
# ARGUMENTS:
#
# RETURN:
#		
#############################################
check_create_pyenv_virtual_environment() 
{
    virtual_environment_exists=0  # Reset flag

    # Define custom virtual environment location
    VENV_FOLDER="$PYTHON_VIRTUAL_ENV_LOCATION/$PROGRAM_FOLDER_NAME"

    echo "Checking if virtual environment exists at: $VENV_FOLDER"
    if [ ! -d "$VENV_FOLDER" ]; then
        echo "Creating virtual environment at $VENV_FOLDER using pyenv Python..."
        PYENV_VERSION="$PYTHON_VERSION" python -m venv "$VENV_FOLDER"
    else
        echo "Virtual environment folder already exists.. verifying it.." && sleep 1
    fi

    # Ensure the virtual environment is not broken
    if [ ! -f "$VENV_FOLDER/bin/python" ] || [ ! -f "$VENV_FOLDER/bin/pip" ]; then
        echo "Virtual environment seems broken. Recreating..."
        rm -rf "$VENV_FOLDER" && sleep 1
        check_create_pyenv_custom_virtual_environment  # Recreate the environment
    fi

    # Check if the activate script exists before sourcing
    if [ -f "$VENV_FOLDER/bin/activate" ]; then
        echo "Activating virtual environment..."
        # shellcheck disable=SC1091
        source "$VENV_FOLDER/bin/activate"
    else
        echo "Error: Activate script not found in $VENV_FOLDER/bin/. Virtual environment setup may have failed."
        return 1
    fi
	
    # Check Python version in the virtual environment
    local venv_python
    venv_python=$(python --version 2>/dev/null)

    if [[ "$venv_python" != *"Python $PYTHON_VERSION"* ]]; then
        echo "Python version mismatch in virtual environment! Recreating..."
        rm -rf "$VENV_FOLDER" && sleep 1
        check_create_pyenv_custom_virtual_environment  # Recreate the environment
    fi

    echo "Upgrading pip and essential packages..."
    python -m pip install --upgrade pip
    pip install --upgrade setuptools wheel

    echo "Custom pyenv virtual environment is set up and ready to use at $VENV_FOLDER."
    virtual_environment_exists=1
}






#############################################
# Activate the virtual environment for cloudisense
# 
# GLOBALS:
#		virtual_environment_valid, VENV_FOLDER
# ARGUMENTS:
#
# RETURN:
#		
#############################################
activate_virtual_environment()
{
	if is_pyenv_installed; then
		activate_custom_pyenv_virtual_environment
	else
		activate_system_virtual_environment
	fi
}




#############################################
# Activate the system python based virtual environment
# 
# GLOBALS:
#		virtual_environment_valid, VENV_FOLDER
# ARGUMENTS:
#
# RETURN:
#		
#############################################
activate_system_virtual_environment() 
{
    lecho "Activating system virtual environment"

	virtual_environment_valid=0

	VENV_FOLDER="$PYTHON_VIRTUAL_ENV_LOCATION/$PROGRAM_FOLDER_NAME"

	if [ -d "$VENV_FOLDER" ] && [ -f "$VENV_FOLDER/bin/activate" ]; then	
		# shellcheck disable=SC1091	
		source "$VENV_FOLDER/bin/activate"
		
		local pipver
		pipver=$(which pip3)		

		$pipver install --upgrade setuptools wheel pip

		local path
		path=$(pip -V)

		if [[ $path == *"$VENV_FOLDER"* ]]; then
			virtual_environment_valid=1	
			lecho "Virtual environment active"	
		else
			lecho "Incorrect virtual environment path"	
		fi		
	else
		virtual_environment_valid=0
		lecho "Oops something is wrong! Virtual environment is invalid"
	fi	
}






#############################################
# Activate the pyenv based virtual environment
# 
# GLOBALS:
#		virtual_environment_valid, VENV_FOLDER
# ARGUMENTS:
#
# RETURN:
#		
#############################################
activate_custom_pyenv_virtual_environment() 
{
    lecho "Activating custom pyenv virtual environment"

    virtual_environment_valid=0  # Reset flag

    # Define custom virtual environment location
    VENV_FOLDER="$PYTHON_VIRTUAL_ENV_LOCATION/$PROGRAM_FOLDER_NAME"

    # Check if the virtual environment exists
    if [ ! -d "$VENV_FOLDER" ] || [ ! -f "$VENV_FOLDER/bin/activate" ]; then
        lecho "Error: Custom virtual environment not found or incomplete at $VENV_FOLDER"
        return 1
    fi

    # Activate the virtual environment
    echo "Activating virtual environment at: $VENV_FOLDER"
    # shellcheck disable=SC1091
    source "$VENV_FOLDER/bin/activate"

    # Verify if the environment was activated correctly
    local venv_python
    venv_python=$(python --version 2>/dev/null)

    if [[ "$venv_python" == *"Python $PYTHON_VERSION"* ]]; then
        virtual_environment_valid=1
        lecho "Custom pyenv virtual environment is now active"
    else
        lecho "Error: Python version mismatch after activation!"
        return 1
    fi

    # Upgrade pip and essential packages
    echo "Upgrading pip and essential packages..."
    python -m pip install --upgrade pip
    pip install --upgrade setuptools wheel
}




#############################################
# Install dependencies in virtual environment
# from the specified requirements file
# 
# GLOBALS:
#		RASPBERRY_PI, REQUIREMENTS_FILE, DEFAULT_PROGRAM_PATH,
#		PYTHON_RPI_REQUIREMENTS_FILENAME, PYTHON_REQUIREMENTS_FILENAME,
#		SPECIFIED_REQUIREMENTS_FILE
# ARGUMENTS:
#
# RETURN:
#		
#############################################
install_python_program_dependencies()
{	
	lecho "Installing dependencies"

	if $RASPBERRY_PI; then
		REQUIREMENTS_FILE="$DEFAULT_PROGRAM_PATH/requirements/$PYTHON_RPI_REQUIREMENTS_FILENAME"
	else
		REQUIREMENTS_FILE="$DEFAULT_PROGRAM_PATH/requirements/$PYTHON_REQUIREMENTS_FILENAME"
	fi	

	if [ -n "$SPECIFIED_REQUIREMENTS_FILE" ]; then 
		REQUIREMENTS_FILE="$DEFAULT_PROGRAM_PATH/requirements/$SPECIFIED_REQUIREMENTS_FILE"
	fi

	install_pip_dependencies "$REQUIREMENTS_FILE"	

	# Brute force hack for exception after first time dependencies install
	# activates when atleast one param is passed to this function
	#if [ $# -gt 0 ]; then
	#	sleep 2
	#	#install_pip_dependencies "$REQUIREMENTS_FILE"	
	#fi	
	
}




#############################################
# Install dependencies in virtual environment
# from the by parsing requirements file and installing
# each dependency individually. 
# Virtual environemnt must be activated before calling
# this function
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#		
#############################################
install_pip_dependencies()
{
	local source=$1

	# Define the requirements file
	REQUIREMENTS_FILE="$source"

	# Check if the requirements file exists
	if [[ ! -f $REQUIREMENTS_FILE ]]; then
		echo "Error: $REQUIREMENTS_FILE not found!"
		exit 1
	fi

	# Read and install each dependency line by line
	while IFS= read -r dependency || [[ -n "$dependency" ]]; do
		# Strip comments and whitespace
		clean_dependency=$(echo "$dependency" | sed -e 's/#.*//' | xargs)

		# Skip empty lines after cleaning
		if [[ -z "$clean_dependency" ]]; then
			continue
		fi

		echo "Installing: $clean_dependency"
		if pip install "$clean_dependency"; then
			echo "Successfully installed: $clean_dependency"
		else
			echo "Failed to install: $clean_dependency"
		fi
		echo "-----------------------------"
		
	done < "$REQUIREMENTS_FILE"
}




#############################################
# Install dependencies in virtual environment
# from the specified requirements file
# 
# GLOBALS:
#		RASPBERRY_PI, REQUIREMENTS_FILE, DEFAULT_PROGRAM_PATH,
#		PYTHON_RPI_REQUIREMENTS_FILENAME, PYTHON_REQUIREMENTS_FILENAME,
#		SPECIFIED_REQUIREMENTS_FILE
# ARGUMENTS:
#			$1 = requirement file path - String#
#			$2 = Whether to operate in silent mode or verbose mode - Boolean
#
# RETURN:
#		
#############################################
install_module_dependencies()
{
	local error=0
	local err_message=
	local silent_mode=0
	local requirements_file=
	
	if [ $# -lt 1 ]; then
			error=1
			err_message="Minimum of 1 parameter is required!"
	else	
			if [ $# -gt 1 ]; then
				requirements_file=$1				
				silent_mode=$2
			else
				requirements_file=$1				
			fi


			local requirements_file=$1
			VENV_FOLDER="$PYTHON_VIRTUAL_ENV_LOCATION/$PROGRAM_FOLDER_NAME"	

			if [ ! -d "$VENV_FOLDER" ] || [ ! -f "$VENV_FOLDER/bin/activate" ]; then
				error=1
				err_message="Virtual environment is invalid or was not found"
			fi
		
	fi


	if [[ "$error" -eq 0 ]]; then
		#pip3 install -r "$REQUIREMENTS_FILE"
		local pip="$VENV_FOLDER/bin/pip3"

		if [[ "$silent_mode" -eq 0 ]]; then
			$pip install -r "$requirements_file"
			lecho "Module dependencies installed."
		else
			local result
			result=$("$pip" install -r "$requirements_file")
		fi

	else

		if [[ "$silent_mode" -eq 0 ]]; then
			lecho_err "An error occurred. $err_message"
		fi
	fi	
		
}




#############################################
# Deactivates previously activated virtual 
# environment.
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################
deactivate_virtual_environment()
{
	deactivate
}




#############################################
# Downloads and installs cloudisense distribution 
# from a url. If files are copied properly to 
# location, the value of latest_download_success
# is set to 1.
# 
# GLOBALS:
#		PROGRAM_ARCHIVE_NAME, latest_download_success,
#		PROGRAM_MANIFEST_LOCATION, PROGRAM_DOWNLOAD_URL,
# 		DEFAULT_PROGRAM_PATH, PYTHON_MAIN_FILE
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################
install_from_url()
{
	clear
		
	latest_download_success=0

	local ARCHIVE_FILE_NAME
	local PROGRAM_DOWNLOAD_URL
	local TMP_DIR

	ARCHIVE_FILE_NAME=$PROGRAM_ARCHIVE_NAME
	#PROGRAM_DOWNLOAD_URL=$(curl -s "$PROGRAM_MANIFEST_LOCATION" | grep -Pom 1 '"url": "\K[^"]*')
	PROGRAM_DOWNLOAD_URL=$PROGRAM_ARCHIVE_LOCATION
	TMP_DIR=$(mktemp -d -t ci-XXXXXXXXXX)

	lecho "Downloading program url $PROGRAM_DOWNLOAD_URL"
	wget -O "/tmp/$ARCHIVE_FILE_NAME" "$PROGRAM_DOWNLOAD_URL"
	

	if [ -f "/tmp/$ARCHIVE_FILE_NAME" ]; then
		lecho "download success"
		lecho "Extracting files"
		unzip "/tmp/$ARCHIVE_FILE_NAME" -d "$TMP_DIR"		
		if [ -f "$TMP_DIR/$PYTHON_MAIN_FILE" ]; then
			# Extraction successful - copy to main location
			lecho "Moving files to program location $DEFAULT_PROGRAM_PATH"
			cp -R "$TMP_DIR"/. "$DEFAULT_PROGRAM_PATH/"	
			chown -R "$USER": "$DEFAULT_PROGRAM_PATH"
			chmod a+rwx "$DEFAULT_PROGRAM_PATH"
			if [ -f "$DEFAULT_PROGRAM_PATH/$PYTHON_MAIN_FILE" ]; then	
				# Copying successful 
				lecho "files copied to program path"

				# Unpack runtime so files
				unpack_runtime_libraries
			fi	
		fi
	fi


	if program_exists; then
		latest_download_success=1
	else
		latest_download_success=0
	fi

}





#############################################
# Unpacks runtime libraries meant for current 
# platform from the archives and deployes them
# to appropriate location in the program installation.
#
# NOTE: Requires build manifest, system detection
# as well as python detection.
# 
# GLOBALS:
#		DEFAULT_PROGRAM_PATH, PLATFORM_ARCH
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################

unpack_runtime_libraries()
{
	local current_python="${PYTHON_VERSION//./}"

	local tmp_dir
	tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)

	local runtime_base_dir="$DEFAULT_PROGRAM_PATH/runtime/$PLATFORM_ARCH"
	local deploy_base_dir="$DEFAULT_PROGRAM_PATH"

	# Check if runtime_base_dir exists
    if [ ! -d "$runtime_base_dir" ]; then
        lecho_warn "Error: Runtime directory $runtime_base_dir does not exist."
        return 1
    fi

	# Using find and reading directly with a while loop to avoid subshell issues
	while IFS= read -r -d '' i; do
		local filename
		filename=$(basename -- "$i")

		local dest="$tmp_dir/$filename"
		local deploy_file="${i//.zip/.so}"
		local possible_conflict_file="${i//.zip/.py}"
		local deploy_path="${deploy_file//$runtime_base_dir/$deploy_base_dir}"
		local possible_conflict_file_path="${possible_conflict_file//$runtime_base_dir/$deploy_base_dir}"

		# Unzip the file into the temporary directory
		unzip -q "$i" -d "$dest/"

		# Process extracted files
		for j in "$dest"/*; do
			local soname
			soname=$(basename -- "$j")

			if [[ "$soname" == *"$current_python.so" ]]; then
				# Move .so file to the deployment directory
				lecho "Moving runtime file $j to $deploy_path"
				mv "$j" "$deploy_path"

				# Remove conflicting .py file, if it exists
				if [ -f "$possible_conflict_file_path" ]; then
					lecho "Removing conflicting file $possible_conflict_file_path"
					rm "$possible_conflict_file_path"
				fi
			fi
		done
	done < <(find "$runtime_base_dir" -type f -name "*.zip" -print0)
	rm -rf "$tmp_dir"
}





#############################################
# Reads installation manifest from the internet
# url defined and parses.
# 
# GLOBALS:
#		PROGRAM_MANIFEST_LOCATION, PROGRAM_INSTALL_LOCATION,
#		PLATFORM_ARCH, PROGRAM_VERSION, PROGRAM_HASH, PROGRAM_SUPPORTED_INTERPRETERS
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################
# shellcheck disable=SC2034
# shellcheck disable=SC2155
get_install_info()
{
	local UNIQ=$(date +%s)

    # Fetch central manifest with a timestamp to avoid caching issues
	local response=$(curl --write-out '%{http_code}' --silent --output /dev/null "$PROGRAM_MANIFEST_LOCATION?$UNIQ")

    if [[ "$response" -ne 200 ]]; then
        lecho_err "Failed to fetch central manifest. HTTP response code: $response"
        exit 1
    fi


	# Now fetch the full central manifest content    
    local central_manifest_response=$(curl -H 'Cache-Control: no-cache' -sk "$PROGRAM_MANIFEST_LOCATION?$UNIQ")
	

    if [[ -z "$central_manifest_response" ]]; then
        lecho_err "Failed to fetch central manifest data."
        exit 1
    fi


	# Extract key information from central manifest
	local manifest_url package_version changes
	manifest_url=$(echo "$central_manifest_response" | jq -r '.manifest')
	package_version=$(echo "$central_manifest_response" | jq -r '.version')
	changes=$(echo "$central_manifest_response" | jq -r '.changes')

	# Fix: Check the correct variables
	if [[ -z "$manifest_url" || -z "$package_version" ]]; then
		lecho_err "Central manifest is missing required fields."
		exit 1
	fi

	lecho "Central Manifest Read Successfully"
	lecho "Version: $package_version"
	lecho "Changes: $changes"
	lecho "Fetching build manifest from: $manifest_url"



	# Fetch the actual build manifest with a timestamp
    local build_manifest_response=$(curl -H 'Cache-Control: no-cache' -sk "$manifest_url?$UNIQ")	

    if [[ -z "$build_manifest_response" ]]; then
        lecho_err "Failed to fetch build manifest."
        exit 1
    fi


	# Extract common payload information
	local client_enabled client_url platform_section package_version changes
	client_enabled=$(echo "$build_manifest_response" | jq -r '.payload.client.enabled')
	client_url=$(echo "$build_manifest_response" | jq -r '.payload.client.url')

	# Extract version and changes from manifest
	package_version=$(echo "$build_manifest_response" | jq -r '.payload.version // "unknown"')
	changes=$(echo "$build_manifest_response" | jq -r '.changes // "No changes provided"')

	# Determine platform-specific section
	if [[ "$PLATFORM_ARCH" == "x86_64" ]]; then
		platform_section=".payload.platforms.x86_64"
	elif [[ "$PLATFORM_ARCH" == "aarch64" ]]; then
		platform_section=".payload.platforms.aarch64"
	else
		lecho_err "Unknown/unsupported CPU architecture: $PLATFORM_ARCH"
		exit 1
	fi

	# Extract platform-specific details
	local package_enabled package_url package_hash supported_interpreters cleanups
	package_enabled=$(echo "$build_manifest_response" | jq -r "$platform_section.enabled // false")
	package_url=$(echo "$build_manifest_response" | jq -r "$platform_section.url // \"\"")
	package_hash=$(echo "$build_manifest_response" | jq -r "$platform_section.md5 // \"\"")
	supported_interpreters=$(echo "$build_manifest_response" | jq -r "$platform_section.dependencies.interpreters // \"\"")
	cleanups=$(echo "$build_manifest_response" | jq -c "$platform_section.cleanups // []")

	# Check if package is available
	if [[ "$package_enabled" != "true" ]]; then
		lecho_err "Package installation is unavailable or disabled. Contact support for further assistance."
		exit 1
	fi

	# Store extracted values
	PROGRAM_VERSION=$package_version
	PROGRAM_CHANGES=$changes
	PROGRAM_ARCHIVE_LOCATION=$package_url
	PROGRAM_HASH=$package_hash
	PROGRAM_CLIENT_URL=$client_url
	PROGRAM_CLEANUPS=$cleanups

	# Convert interpreter list into an array (handle empty case)
	if [[ -n "$supported_interpreters" ]]; then
		IFS=',' read -ra PROGRAM_SUPPORTED_INTERPRETERS <<< "$supported_interpreters"
	else
		PROGRAM_SUPPORTED_INTERPRETERS=()
	fi

	# Logging extracted values
	lecho "Installation Information:"
	lecho "  - Version: $PROGRAM_VERSION"
	lecho "  - Changes: $PROGRAM_CHANGES"
	lecho "  - Supported Interpreters: ${PROGRAM_SUPPORTED_INTERPRETERS[*]}"

}




#############################################
# Returns module package download url (if exists), 
# using the main program package url and module name.
# empty variable/unset variable is returned if module
# does not exist (owing to incorrect name)
# This method does not check if url exists or not
# 
# GLOBALS:
#		PROGRAM_ARCHIVE_LOCATION#
# ARGUMENTS:
#		$1 : module name
# RETURN:
#		Module download url (if exists). Else
# empty variable/unset variable is returned
#############################################
get_module_url()
{
	local module_name="$1.zip"
	local url=$PROGRAM_ARCHIVE_LOCATION
	url=${url/core/modules}
	url=${url/cloudisense.zip/$module_name}
	if http_file_exists "$url"; then
		echo "$url"
	else
		echo NULL
	fi
}




#############################################
# Returns profile package download url (if exists), 
# using the main program package url and profile name.
# empty variable/unset variable is returned if profile
# does not exist (owing to incorrect name)
# This method does not check if url exists or not
# 
# GLOBALS:
#		PROGRAM_ARCHIVE_LOCATION#
# ARGUMENTS:
#		$1 : profile name
# RETURN:
#		profile download url (if exists). Else
# empty variable/unset variable is returned
#############################################
get_profile_url()
{
	local profile_name="$1.zip"
	local url=$PROGRAM_ARCHIVE_LOCATION
	url="${url//core/profiles}"
	url="${url//cloudisense.zip/$profile_name}"
	url="${url//$PLATFORM_ARCH\//}"

	if http_file_exists "$url"; then
		echo "$url"
	else
		local NULL
		echo "$NULL"
	fi
}





#############################################
# Check if file exists over a http url
# 
# GLOBALS:
#		
# ARGUMENTS:
#		$1: HTTP url of the file
# RETURN:
#		true if file exists otherwise false
#############################################
http_file_exists()
{
	local module_url=$1
	if wget --spider "$module_url" 2>/dev/null; then
		true
	else
		false
	fi
}



#############################################
# Enable a cloudisense module
# 
# GLOBALS:
#		
# ARGUMENTS:
#		$1: Module name
# RETURN:
#		
#############################################

enable_module()
{
	local module_name=$1
	local module_conf_path="$DEFAULT_PROGRAM_PATH/modules/conf/$module_name.json"

	if [ -f "$module_conf_path" ]; then
		# enable required modules
		local tmpfile="${module_conf_path/.json/.tmp}"
		jq '.enabled = "true"' "$module_conf_path" > "$tmpfile"
		mv "$tmpfile" "$module_conf_path"
	else
		echo "Module config for '$module_name' not found!"
	fi
}




#############################################
# Disable a cloudisense module
# 
# GLOBALS:
#		
# ARGUMENTS:
#		$1: Module name
# RETURN:
#		
#############################################

disable_module()
{
	local module_name=$1
	local module_conf_path="$DEFAULT_PROGRAM_PATH/modules/conf/$module_name.json"
	
	if [ -f "$module_conf_path" ]; then		
		local tmpfile="${module_conf_path/.json/.tmp}"
		jq '.enabled = "false"' "$module_conf_path" > "$tmpfile"
		mv "$tmpfile" "$module_conf_path"
	else
		echo "Module config for '$module_name' not found!"
	fi
}




#############################################
# Enable a cloudisense reaction rule
# 
# GLOBALS:
#		
# ARGUMENTS:
#		$1: Rule name
# RETURN:
#		
#############################################

enable_reaction_rule()
{
	local rule_name=$1
	local rule_path="$DEFAULT_PROGRAM_PATH/rules/$rule_name.json"

	if [ -f "$rule_path" ]; then
		# enable required modules
		local tmpfile="${rule_path/.json/.tmp}"
		jq '.enabled = "true"' "$rule_path" > "$tmpfile"
		mv "$tmpfile" "$rule_path"
	else
		echo "Rule by name '$rule_name' not found!"
	fi
}





#############################################
# Disable a cloudisense reaction rule
# 
# GLOBALS:
#		
# ARGUMENTS:
#		$1: Rule name
# RETURN:
#		
#############################################

disable_reaction_rule()
{
	local rule_name=$1
	local rule_path="$DEFAULT_PROGRAM_PATH/rules/$rule_name.json"

	if [ -f "$rule_path" ]; then
		# enable required modules
		local tmpfile="${rule_path/.json/.tmp}"
		jq '.enabled = "false"' "$rule_path" > "$tmpfile"
		mv "$tmpfile" "$rule_path"
	else
		echo "Rule by name '$rule_name' not found!"
	fi
}




#############################################
# Installs a cloudisense module meant for current 
# platform/python version from the archives to
# the currently active cloudisense installation
# 
# NOTE: Requires build manifest, system detection
# as well as python detection.
#
# GLOBALS:
#		DEFAULT_PROGRAM_PATH, PROGRAM_NAME
#
# ARGUMENTS:
#			$1 = module name - String
#			$2 = base directory path of cloudisense installation. defaults to DEFAULT_PROGRAM_PATH - String path
#			$3 = Whether to force install (overwriting without prompt). - Boolean
#
#
# RETURN:
#		
#############################################

install_module()
{
	local module_name=
	local base_dir=$DEFAULT_PROGRAM_PATH	
	local force=false
	local return_status=0
	local error=0
	local err_message=
	local silent_mode=0

	module_install_success=0

	check_current_installation 1 1

	if [ "$program_exists" -eq 1 ]; then

		if [ $# -lt 0 ]; then
			error=1
			err_message="Minimum of 1 parameter is required!"
		else
			if [ $# -gt 4 ]; then
				module_name=$1
				base_dir=$2
				force=$3
				return_status=$4
				silent_mode=$5

				if [[ "$return_status" -eq 1 ]] || [[ "$silent_mode" -eq 1 ]]; then
					force=true
				fi
			elif [ $# -gt 3 ]; then
				module_name=$1
				base_dir=$2
				force=$3
				return_status=$4
				
				if [[ "$return_status" -eq 1 ]]; then
					force=true
				fi
			elif [ $# -gt 2 ]; then
				module_name=$1
				base_dir=$2
				force=$3
			elif [ $# -gt 1 ]; then
				module_name=$1
				base_dir=$2
			elif [ $# -gt 0 ]; then
				module_name=$1 
			fi


			# check and see if module excists and if yes fetch url
			local deploy_path
			local module_conf
			local url

			deploy_path="$base_dir/cdsmaster/modules"
			module_conf="$deploy_path/conf/$module_name.json"
			url=$(get_module_url "$module_name")			


			if [ -z "$url" ]; then

				error=1
				err_message="Module not found/cannot be installed!"
			
			elif [ -f "$module_conf" ]; then

				if [ "$force" = false ] ; then

					local response=
					lecho "Module already exists. Proceeding forward operation will overwrite the existing module."
					read -r -p "Do you wish to continue? [y/N] " response
						case $response in
						[yY][eE][sS]|[yY]) 
							lecho "Installing module.."
						;;
						*)
							error=1
							err_message="Module installation cancelled!"
						;;
						esac
				fi
			fi
		fi


		# ALL OK -> Do Ops	
		if [[ "$error" -eq 0 ]]; then			

			local current_python="${INSTALLATION_PYTHON_VERSION//./}"
			
			local tmp_dir
			tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)

			local module="$tmp_dir/$module_name.zip"	
			local dest="$tmp_dir/$module_name"
			local module_requirements_file="$dest/requirements.txt"

			wget -O "$module" "$url"
			unzip "$module" -d "$dest"

			# if there is a requirements.txt - install dependencies into virtual environment
			if [ -f "$module_requirements_file" ]; then
				# Install dependencies
				if [[ "$silent_mode" -eq 0 ]]; then
					lecho "Requirements file found!. Installing dependencies from file $j"						
				fi

				install_module_dependencies "$module_requirements_file"
			fi
			

			for j in "$dest"/*; do

				local name
				name=$(basename -- "$j")
				
				local filename="${name%.*}"

				if [[ "$name" =~ .*"$current_python"\.so$ ]]; then
					# Move tmp file to main location
					if [[ "$silent_mode" -eq 0 ]]; then
						lecho "Moving runtime file $j to $deploy_path/$module_name.so"
					fi
					mv "$j" "$deploy_path"/"$module_name".so
					chown "$USER": "$deploy_path/$module_name.so"

					# so and py versions of same module are mutually exclusive
					if [ -f "$deploy_path/$filename.py" ]; then
						rm "$deploy_path/$module_name.py"
					fi

				elif [[ $name == *".json" ]]; then					
					# Move tmp file to main location
					if [[ "$silent_mode" -eq 0 ]]; then
						lecho "Moving conf file $j to $deploy_path/conf/$module_name.json"
					fi
					mv "$j" "$deploy_path"/conf/"$module_name".json
					chown "$USER": "$deploy_path/conf/$module_name.json"
				elif [[ $name == *".py" ]]; then					
					# Move tmp file to main location
					if [[ "$silent_mode" -eq 0 ]]; then
						lecho "Moving runtime file $j to $deploy_path/$module_name.py"
					fi
					mv "$j" "$deploy_path"/"$module_name".py
					chown "$USER": "$deploy_path/$module_name.py"

					# so and py versions of same module are mutually exclusive
					if [ -f "$deploy_path/$filename.so" ]; then
						rm "$deploy_path/$module_name.so"
					fi
				fi

			done

			# success
			module_install_success=1

			if [[ "$return_status" -eq 1 ]]; then
				error=0 && echo $error
			else
				if [[ "$silent_mode" -eq 0 ]]; then
					lecho "Processing completed. You may want to restart $PROGRAM_NAME service"
				fi
			fi

		else

			if [[ "$return_status" -eq 1 ]]; then
				error=1 && echo $error
			else
				if [[ "$silent_mode" -eq 0 ]]; then
					lecho_err "An error occurred. $err_message"
				fi
			fi		

		fi			
	
	else

		if [[ "$return_status" -eq 1 ]]; then
			error=1 && echo $error
		else
			if [[ "$silent_mode" -eq 0 ]]; then
				lecho_err "Program core was not found. Please install the program before attempting to install modules."
			fi
		fi		
	fi
}




#############################################
# Removes a cloudisense module meant from
# the currently active cloudisense installation
# 
# GLOBALS:
#		DEFAULT_PROGRAM_PATH, PROGRAM_NAME
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################

remove_module()
{
	local module_name=$1
	local deploy_path="$DEFAULT_PROGRAM_PATH/cdsmaster/modules"
	local found=false

	# Find all the relevant files and store them in an array
	files_to_remove=$(find "$deploy_path" -type f \( -name "*$module_name.so" -o -name "*$module_name.json" -o -name "*$module_name.py" \))

	# Loop through the results
	while IFS= read -r file; do
		local name
		name=$(basename -- "$file")

		# Removing the matching file
		found=true
		lecho "Removing module file $file"
		rm -rf "$file"
	done <<< "$files_to_remove"
	
	if $found; then
		lecho "Processing completed. You may want to restart $PROGRAM_NAME service"
	else
		lecho "Module not found. Nothing was removed"
	fi
}





#############################################
# Installs a cloudisense profile meant for current 
# platform/python version from the archives to
# the currently active cloudisense installation
# 
# NOTE: Requires build manifest, system detection
# as well as python detection.
#
# GLOBALS:
#		DEFAULT_PROGRAM_PATH, PROGRAM_NAME
#
# ARGUMENTS:
#			$1 = profile name - String
#			$2 = base directory path of cloudisense installation. defaults to DEFAULT_PROGRAM_PATH - String path
#			$3 = Whether to force install (overwriting without prompt). - Boolean
#
#
# RETURN:
#		
#############################################

install_profile()
{
	local profile_name=
	local base_dir=$DEFAULT_PROGRAM_PATH	
	local force=false
	local return_status=0
	local silent_mode=0
	local error=0
	local err_message=	

	check_current_installation 1 1

	if [ "$program_exists" -eq 1 ]; then

		if [ $# -lt 1 ]; then
			error=1
			err_message="Minimum of 1 parameter is required!"
		else
			if [ $# -gt 2 ]; then
				profile_name=$1
				base_dir=$2
				force=$3
			elif [ $# -gt 1 ]; then
				profile_name=$1
				base_dir=$2
			elif [ $# -gt 0 ]; then
				profile_name=$1 
			fi

			local url
			url=$(get_profile_url "$profile_name")

			if [ -z ${url+x} ]; then
				error=1
				err_message="Profile not found/cannot be installed!"
			fi

			# ALL OK -> Do Ops		
			if [[ "$error" -eq 0 ]]; then
				local tmp_dir
				tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)				

				local profile_archive="$tmp_dir/$profile_name.zip"	
				local profile_package_path="$tmp_dir/$profile_name"

				local module_conf_source_path="$profile_package_path/modules/conf"
				local scripts_source_path="$profile_package_path/scripts"
				local rules_source_path="$profile_package_path/rules"
				local template_source_path="$profile_package_path/ui/template"
				local layout_source_path="$profile_package_path/ui/layout"
				
				
				local module_install_path="$base_dir/cdsmaster/modules"
				local module_conf_install_path="$base_dir/cdsmaster/modules/conf"
				local scripts_install_path="$base_dir/scripts"
				local rules_install_path="$base_dir/rules"
				local template_install_path="$base_dir/cdsmaster/ui/template"
				local layout_install_path="$base_dir/cdsmaster/ui/layout"

				local layout_installed=0

				# extract profile archive to a tmp location

				wget -O "$profile_archive" "$url"
				unzip "$profile_archive" -d "$profile_package_path"	

				# read meta file
				local meta_file="$profile_package_path/meta.json"

				local result
				result=$(<"$meta_file")				

				local profile_name
				profile_name=$(jq -r '.name' <<< "$result")

		
				IFS=',' read -r -a add_dependencies <<< "$(jq -r '.dependencies.add[]' <<< "$result" | tr '\n' ',')"
				IFS=',' read -r -a add_modules <<< "$(jq -r '.modules.add[]' <<< "$result" | tr '\n' ',')"
				IFS=',' read -r -a remove_modules <<< "$(jq -r '.modules.remove[]' <<< "$result" | tr '\n' ',')"
				IFS=',' read -r -a add_rules <<< "$(jq -r '.rules.add[]' <<< "$result" | tr '\n' ',')"
				IFS=',' read -r -a remove_rules <<< "$(jq -r '.rules.remove[]' <<< "$result" | tr '\n' ',')"
				IFS=',' read -r -a add_scripts <<< "$(jq -r '.scripts.add[]' <<< "$result" | tr '\n' ',')"
				IFS=',' read -r -a remove_scripts <<< "$(jq -r '.scripts.remove[]' <<< "$result" | tr '\n' ',')"

				
				# install dependencies
				local pip=
				local VENV="$PYTHON_VIRTUAL_ENV_LOCATION/$PROGRAM_FOLDER_NAME"

				# Check if the virtual environment folder exists
				if [ -d "$VENV" ]; then
					# Check for pip or pip3 inside the virtual environment
					if [ -x "$VENV/bin/pip3" ]; then
						pip="$VENV/bin/pip3"
					elif [ -x "$VENV/bin/pip" ]; then
						pip="$VENV/bin/pip"
					fi

					# install dependencies into virtual environment
					if [ -n "$pip" ]; then						
						for dependency in "${add_dependencies[@]}"
						do				
							dependency=${dependency//$'\n'/} # Remove all newlines.							
							"$pip" install "$dependency"
						done
					else
						lecho_err "Neither pip3 nor pip found in the virtual environment at $VENV." && exit 1
					fi
				else
					lecho_err "Virtual environment folder $VENV does not exist." && exit 1
				fi



				# install required modules

				for module in "${add_modules[@]}"
				do				
					module=${module//$'\n'/} # Remove all newlines.
					#local install_error=$(install_module $module $DEFAULT_PROGRAM_PATH true 1)
					install_module "$module" "$DEFAULT_PROGRAM_PATH" true 0 1
					
					if [ "$module_install_success" -eq 1 ]; then					
						err_message="Failed to install module $module."
						error=1
						break
					fi

					local module_conf_source_file="$module_conf_source_path/$module.json"
					local module_conf_target_file="$module_conf_install_path/$module.json"			

					# copy over any specific configuration
					if [ -f "$module_conf_source_file" ]; then
						lecho "Copying over custom module configuration $module_conf_source_file to $module_conf_target_file"
						mv "$module_conf_source_file" "$module_conf_target_file"							
						chown "$USER": "$module_conf_target_file"			
					fi

					# enable required modules
					local tmpfile="${module_conf_target_file/.json/.tmp}"
					jq '.enabled = "true"' "$module_conf_target_file" > "$tmpfile"
					mv "$tmpfile" "$module_conf_target_file"
				done

				# If no module installer error -> continue profile setup				

				if [[ "$module_install_success" -eq 1 ]]; then

					# remove unwanted modules
					for module in "${remove_modules[@]}"
					do
						module=${module//$'\n'/} # Remove all newlines.

						local module_so_file="$module_install_path/$module.so"
						local module_py_file="$module_install_path/$module.py"
						local module_conf_file="$module_conf_install_path/$module.json"

						# delete module file
						if [ -f "$module_so_file" ]; then
							lecho "Deleting module file $module_so_file"
							rm "$module_so_file"
						elif [ -f "$module_py_file" ]; then
							lecho "Deleting module file $module_py_file"
							rm "$module_py_file"
						fi

						# delete module conf file
						if [ -f "$module_conf_file" ]; then
							lecho "Deleting module config file $module_conf_file"
							rm "$module_conf_file"
						fi

					done


					# install required rules

					for rule in "${add_rules[@]}"
					do

						rule=${rule//$'\n'/} # Remove all newlines.

						local installable_rule="$rules_source_path/$rule.json" 
						local target_rule="$rules_install_path/$rule.json"

						if [ -f "$installable_rule" ]; then

							if [ -f "$target_rule" ]; then

								local response=
								lecho "Target $target_rule rule already exists. Proceeding with this operation will overwrite the existing rule."
								read -r -p "Do you wish to continue? [y/N] " response
								case $response in
									[yY][eE][sS]|[yY]) 
										lecho "Installing rule.."
									;;
									*)
										error=1
										lecho_err "Rule installation for $installable_rule cancelled!"
										continue
									;;
								esac
								
							fi

							lecho "Moving rule $installable_rule to $target_rule"
							mv "$installable_rule" "$target_rule"
							chown "$USER": "$target_rule"
						else
							lecho "Something is wrong! Installable rule $installable_rule does not exist in the profile package."					
						fi

					done



					# remove unwanted rules

					for rule in "${remove_rules[@]}"
					do

						rule=${rule//$'\n'/} # Remove all newlines.

						local removable_rule="$rules_install_path/$rule.json"

						if [ -f "$removable_rule" ]; then
							rm "$removable_rule"
						else
							lecho "Rule $removable_rule does not exist at target location. Nothing to remove here!."					
						fi

					done


					# install required scripts

					for script in "${add_scripts[@]}"
					do

						script=${script//$'\n'/} # Remove all newlines.

						local installable_script="$scripts_source_path/$script.sh" 
						local target_script="$scripts_install_path/$script.sh"

						if [ -f "$installable_script" ]; then

							if [ -f "$target_script" ]; then
								local response=
								lecho "Target script $target_script already exists. Proceeding with this operation will overwrite the existing script."
								read -r -p "Do you wish to continue? [y/N] " response
								case $response in
									[yY][eE][sS]|[yY]) 
										lecho "Installing script.."
									;;
									*)
										error=1
										lecho_err "Script installation for $installable_rule cancelled!"
										continue
									;;
								esac								
							fi

							lecho "Moving script $installable_script to $target_script"
							mv "$installable_script" "$target_script"
							chown "$USER": "$target_script"
							chmod +x "$target_script"
						else
							lecho "Something is wrong! Installable script $installable_script does not exist in the profile package."					
						fi

					done


					# remove unwanted scripts

					for script in "${remove_scripts[@]}"
					do

						script=${script//$'\n'/} # Remove all newlines.

						local removable_script="$scripts_install_path/$script.sh"

						if [ -f "$removable_script" ]; then
							rm "$removable_script"
						else
							lecho "Script $removable_script does not exist at target location. Nothing to remove here!."					
						fi

					done


					# install template and profile if available
					

					# Define file paths
					local source_template="$template_source_path/default.json"
					local source_layout="$layout_source_path/default.json"
					local target_template="$template_install_path/default.json"
					local target_layout="$layout_install_path/default.json"

					# Check if we have template to install
					if [ -f "$source_template" ]; then
						# Check if target_template exists and back it up if necessary
						if [ -f "$target_template" ]; then
							lecho "Backing up current template"
							mv "$target_template" "${target_template%.json}.bak"
						fi
						# Copy source_template to target_template
						cp "$source_template" "$target_template"
						
						# Check if we have layout to install
						if [ -f "$source_layout" ]; then
							# Check if target_layout exists and back it up if necessary
							if [ -f "$target_layout" ]; then
							lecho "Backing up current layout"
							mv "$target_layout" "${target_layout%.json}.bak"
							fi
							# Copy source_layout to target_layout
							cp "$source_layout" "$target_layout"
							
							lecho "Layout installed successfully"
							layout_installed=1
						fi
					fi



					# once eveything is done mark current profile selection 
					# => store active profile somewhere
					if [ ! -f "$PROGRAM_INSTALLATION_REPORT_FILE" ]; then
						echo "No installation report found."
					else
						update_installation_meta "$profile_name" "$layout_installed"
					fi


					# restart service
					restart_service


					#if [[ "$return_status" -eq 1 ]]; then
					#	error=0 && echo $error
					#else
					#	lecho "Processing completed. You may want to restart $PROGRAM_NAME service"
					#fi

				else

					# If there is module instalaltion error during profile installation,
					# we remove all profile related modules
					
					for module in "${add_modules[@]}"
					do

						module=${module//$'\n'/} # Remove all newlines.

						local module_so_file="$module_install_path/$module.so"
						local module_py_file="$module_install_path/$module.py"
						local module_conf_file="$module_conf_install_path/$module.json"

						# delete module file
						if [ -f "$module_so_file" ]; then
							lecho "Deleting module file $module_so_file"
							rm "$module_so_file"
						elif [ -f "$module_py_file" ]; then
							lecho "Deleting module file $module_py_file"
							rm "$module_py_file"
						fi

						# delete module conf file
						if [ -f "$module_conf_file" ]; then
							lecho "Deleting module config file $module_conf_file"
							rm "$module_conf_file"
						fi

					done


					if [[ "$return_status" -eq 1 ]]; then
						error=1 && echo $error
					else
						lecho_err "Error in module installation to install module $err_message."
					fi									
				fi				
			else
				if [[ "$return_status" -eq 1 ]]; then
					error=1 && echo $error
				else
					lecho_err "An error occurred. $err_message"
				fi
			fi
		fi	
	else

		if [[ "$return_status" -eq 1 ]]; then
			error=1 && echo $error
		else
			lecho_err "Program core was not found. Please install the program before attempting to install profiles."
		fi		
	fi	
}






#############################################
# Removes any installed profile resetting
# cloudisense to vanilla state.
# 
#
# GLOBALS:
#		DEFAULT_PROGRAM_PATH, PROGRAM_NAME
#
# ARGUMENTS:
#			$1 = base directory path of cloudisense installation. defaults to DEFAULT_PROGRAM_PATH - String path
#
#
# RETURN:
#		
#############################################
# shellcheck disable=SC2120

clear_profile()
{ 
	local base_dir=$DEFAULT_PROGRAM_PATH	
	local return_status=0
	local silent_mode=0
	local error=0
	local err_message=	

	check_current_installation 1 1

	if [ "$program_exists" -eq 1 ]; then

		if [ $# -gt 0 ]; then
			base_dir=$1
			
			if [ ! -d "$base_dir" ]; then
				error=1
				err_message="Path $base_dir does not exist!"
			fi
		fi

		# read manifest
		read_installation_meta

		# identify profile
		local profile_name=$CURRENT_INSTALLATION_PROFILE


		if [ -z ${profile_name+x} ]; then

			error=1
			err_message="No profile was found set for the current installation!"

		else
					
			# download profile
			local url
			url=$(get_profile_url "$profile_name")	

			if [ -z ${url+x} ]; then
				error=1
				err_message="Profile not found/cannot be installed!"
			fi

		fi

		
		# ALL OK -> Do Ops		
		if [[ "$error" -eq 0 ]]; then
			local tmp_dir
			tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)

			local profile_archive="$tmp_dir/$profile_name.zip"	
			local profile_package_path="$tmp_dir/$profile_name"

			local module_conf_source_path="$profile_package_path/modules/conf"
			local scripts_source_path="$profile_package_path/scripts"
			local rules_source_path="$profile_package_path/rules"
			
			local module_install_path="$base_dir/cdsmaster/modules"
			local module_conf_install_path="$base_dir/cdsmaster/modules/conf"
			local scripts_install_path="$base_dir/scripts"
			local rules_install_path="$base_dir/rules"
			local template_install_path="$base_dir/cdsmaster/ui/template"
			local layout_install_path="$base_dir/cdsmaster/ui/layout"


			# extract profile archive to a tmp location

			wget -O "$profile_archive" "$url"
			unzip "$profile_archive" -d "$profile_package_path"	

			# read meta file
			local meta_file="$profile_package_path/meta.json"
			
			local result
			result=$(<"$meta_file")

			local profile_name
			profile_name=$(jq -r '.name' <<< "${result}")		
			IFS=$'\n' read -r -d '' -a add_modules < <(jq -r '.modules.add[]' <<< "$result" && printf '\0')
			IFS=$'\n' read -r -d '' -a remove_modules < <(jq -r '.modules.remove[]' <<< "$result" && printf '\0')
			IFS=$'\n' read -r -d '' -a add_rules < <(jq -r '.rules.add[]' <<< "$result" && printf '\0')
			IFS=$'\n' read -r -d '' -a remove_rules < <(jq -r '.rules.remove[]' <<< "$result" && printf '\0')
			IFS=$'\n' read -r -d '' -a add_scripts < <(jq -r '.scripts.add[]' <<< "$result" && printf '\0')
			IFS=$'\n' read -r -d '' -a remove_scripts < <(jq -r '.scripts.remove[]' <<< "$result" && printf '\0')


			# remove profile modules
			for module in "${add_modules[@]}"
			do				
				module=${module//$'\n'/} # Remove all newlines.

				local module_so_file="$module_install_path/$module.so"
				local module_py_file="$module_install_path/$module.py"
				local module_conf_file="$module_conf_install_path/$module.json"

				# delete module file
				if [ -f "$module_so_file" ]; then
					lecho "Deleting module file $module_so_file"
					rm "$module_so_file"
				elif [ -f "$module_py_file" ]; then
					lecho "Deleting module file $module_py_file"
					rm "$module_py_file"
				fi

				# delete module conf file
				if [ -f "$module_conf_file" ]; then
					lecho "Deleting module config file $module_conf_file"
					rm "$module_conf_file"
				fi

			done


			# remove profile rules

			for rule in "${add_rules[@]}"
			do

				rule=${rule//$'\n'/} # Remove all newlines.

				local removable_rule="$rules_install_path/$rule.json"

				if [ -f "$removable_rule" ]; then
					rm "$removable_rule"
				else
					lecho "Rule $removable_rule does not exist at target location. Nothing to remove here!."					
				fi
			done



			# remove profile scripts

			for script in "${add_scripts[@]}"
			do
				script=${script//$'\n'/} # Remove all newlines.

				local removable_script="$scripts_install_path/$script.sh"

				if [ -f "$removable_script" ]; then
					rm "$removable_script"
				else
					lecho "Script $removable_script does not exist at target location. Nothing to remove here!."					
				fi

			done


			# restore previous template & layout
			# install template and profile if available

			# Define file paths
			local original_template="$template_install_path/default.bak"
			local original_layout="$layout_install_path/default.bak"
			local installed_template="$template_install_path/default.json"
			local installed_layout="$layout_install_path/default.json"

			if [ "$UIGUIDE_LAYOUT" -eq 1 ]; then
				# Check if both default.bak files exist
				if [ -f "$original_template" ] && [ -f "$original_layout" ]; then
					# Check if default.json exists in both template and layout folders
					if [ -f "$installed_template" ] && [ -f "$installed_layout" ]; then
						# Remove the default.json files
						rm "$installed_template"
						rm "$installed_layout"
						
						# Rename default.bak to default.json in both template and layout folders
						mv "$original_template" "$installed_template"
						mv "$original_layout" "$installed_layout"
						
						lecho "Reverted template and layout to previous state"
					else
						lecho_err "Unknown error! Current layout and/or template not found." && exit 1
					fi
				else
					lecho "No previous layout installation detected. Nothing to restore."
				fi
			fi


			

			# once eveything is done mark current profile selection 
			# => store active profile somewhere
			if [ ! -f "$PROGRAM_INSTALLATION_REPORT_FILE" ]; then
				echo "No installation report found."
			else
				update_installation_meta ""
			fi

			# restart service
			restart_service
		else
			if [[ "$return_status" -eq 1 ]]; then
				error=1 && echo $error
			else
				lecho_err "An error occurred while clearing profile. $err_message"
			fi
		fi
	else

		if [[ "$return_status" -eq 1 ]]; then
			error=1 && echo $error
		else
			lecho_err "Program core was not found. Please install the program before attempting to install profiles."
		fi		
	fi
	
}






#############################################
# Registers cron in root's crontab to run autoupdater
# once a day at designated hour.
# 
# GLOBALS:
#		PROGRAM_UPDATE_CRON_HOUR
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################

register_updater()
{
	local SCRIPT_PATH
	SCRIPT_PATH=$(realpath "$0")

	# file method
	#crontab -l > cronjobs.txt
	#crontab -l | grep -v "$SCRIPT_PATH -u 1" > cronjobs.txt
	#echo "0 11 * * * $SCRIPT_PATH -u 1" >> cronjobs.txt
	#crontab cronjobs.txt	

	# direct method
	lecho "Registering autoupdater..."
	crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH -u 1" | crontab -	
	(crontab -l 2>/dev/null; echo "0 $PROGRAM_UPDATE_CRON_HOUR * * * $SCRIPT_PATH -u 1") | crontab -
}






#############################################
# Deregisters autoupdate cron from root's crontab.
# 
# GLOBALS:
#		PROGRAM_UPDATE_CRON_HOUR
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################

deregister_updater()
{
	local SCRIPT_PATH
	SCRIPT_PATH=$(realpath "$0")

	# direct method
	crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH -u 1" | crontab -	
}



# Parse the major, minor and patch versions
# out.
# You use it like this:
#    semver="3.4.5+xyz"
#    a=($(parse_semver "$semver"))
#    major=${a[0]}
#    minor=${a[1]}
#    patch=${a[2]}
#    printf "%-32s %4d %4d %4d\n" "$semver" $major $minor $patch
function parse_semver() {
    local token="$1"
    local major=0
    local minor=0
    local patch=0

    if echo "$token" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' >/dev/null 2>&1; then
        # It has the correct syntax.
        local n=${token//[!0-9]/ }
        local a
		IFS='.' mapfile -d ' ' -t a <<< "$n"
        major=${a[0]}
        minor=${a[1]}
        patch=${a[2]}
    fi
    
    echo "$major $minor $patch"
}




#############################################
# Reads and returns program's version string
# 
# GLOBALS:
#		PROGRAM_UPDATE_CRON_HOUR
#
# ARGUMENTS:
#
# RETURN:
#		String representing version number
#		
#############################################
get_program_version()
{
	local version_file="$1"
	local existing_version=
	local version=
	local old_version_num=

	while IFS= read -r line
	do
	if [[ $line = __version__* ]]
		then
			existing_version="${line/$target/$blank}" 
			break
	fi

	done < "$version_file"

	local replacement=""
	version="${existing_version//__version__/$replacement}"
	version="${version//=/$replacement}"
	version="${version//\'/$replacement}"
	version="${version//\'/$replacement}"
	echo "$version"
}




#############################################
# Performs rollback on a recently failed update
# 
# GLOBALS:
#		INSTALLATION_PYTHON_VERSION, DEFAULT_PROGRAM_PATH
#		PYTHON_MAIN_FILE
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################
# shellcheck disable=SC2034
rollback_update()
{	
	local err=0
	lecho "Attempting roll back"


	# We need to get back esrlier python version or compatible python version
	PYTHON_VERSION=$INSTALLATION_PYTHON_VERSION


	# delete from main location where updated content was placed
	rm -rf "${DEFAULT_PROGRAM_PATH:?}/*"



	# stop running service of program
	echo "Stopping running program"
	if is_service_installed; then
		if is_service_running; then
			stop_service
		fi
	fi


	# copy back old files into main location
	local temp_dir_for_existing=$1	
	cp -a "$temp_dir_for_existing"/. "$DEFAULT_PROGRAM_PATH"/
	if [ ! -f "$DEFAULT_PROGRAM_PATH/$PYTHON_MAIN_FILE" ]; then
		lecho "Copy unsuccessful. Update will now exit! Installation is probably broken. Remove & Re-Install program manually to fix the issue."
		exit 1
	fi


	# We need to create virtual environment for esrlier python
	post_download_install	
}




#############################################
# Performs an update of the currently installed
# program.
# 
# GLOBALS:
#		PROGRAM_CONFIGURATION_MERGER, PROGRAM_VERSION,
#		PROGRAM_DOWNLOAD_URL, DEFAULT_PROGRAM_PATH, 
#		PYTHON_MAIN_FILE, PYTHON_VIRTUAL_ENV_INTERPRETER,
#		PROGRAM_SUPPORTED_INTERPRETERS, PROGRAM_ERROR_LOG_FILE_NAME
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################
# shellcheck disable=SC2034
update()
{	
	
	local CAN_UPDATE=0

	if is_first_time_install; then
		lecho "This is a first time installation. Update cannot proceed!"
		exit 1
	fi	

	
	local MERGE_SCRIPT="$PWD/$PROGRAM_CONFIGURATION_MERGER"	

	## get version info of available file 
	local available_version_string=$PROGRAM_VERSION
	read -r -a available_version <<< "$(parse_semver "$available_version_string")"

	local major_new=${available_version[0]}
	local minor_new=${available_version[1]}
	local patch_new=${available_version[2]}

	# read version info from installed program
	local installed_version_string
	local installed_version
	local version_file="$DEFAULT_PROGRAM_PATH/cdsmaster/version.py"	
	installed_version_string=$(get_program_version "$version_file")	
	read -r -a installed_version <<< "$(parse_semver "$installed_version_string")"
	local major_old=${installed_version[0]}
	local minor_old=${installed_version[1]}
	local patch_old=${installed_version[2]}

	
	# check to see if upgrade is possible
	if [[ "$major_new" -gt "$major_old" ]]; then
		CAN_UPDATE=1
	elif [[ "$minor_new" -gt "$minor_old" ]]; then
		CAN_UPDATE=1
	elif [[ "$patch_new" -gt "$patch_old" ]]; then
		CAN_UPDATE=1
	fi


	# check if can update and exit if not
	if [ $CAN_UPDATE -eq 0 ]; then
		lecho "Program is not elligible for an update. Update will now exit!"
		exit 1
	else
		lecho "Ready to update!"
	fi

	
	# download archive and extract into a tmp location
	local latest_download_success=0
	local ARCHIVE_FILE_NAME
	local PROGRAM_DOWNLOAD_URL
	local temp_dir_for_latest
	local temp_dir_for_existing
	local temp_dir_for_download
	local temp_dir_for_updated
	local downloaded_archive

	
	ARCHIVE_FILE_NAME=$PROGRAM_ARCHIVE_NAME
	PROGRAM_DOWNLOAD_URL=$(curl -s "$PROGRAM_MANIFEST_LOCATION" | grep -Pom 1 '"url": "\K[^"]*')
	temp_dir_for_latest=$(mktemp -d -t ci-XXXXXXXXXX)
	temp_dir_for_existing=$(mktemp -d -t ci-XXXXXXXXXX)
	temp_dir_for_download=$(mktemp -d -t ci-XXXXXXXXXX)
	temp_dir_for_updated=$(mktemp -d -t ci-XXXXXXXXXX)
	downloaded_archive="$temp_dir_for_download/$ARCHIVE_FILE_NAME"

	echo "Downloading program url $PROGRAM_DOWNLOAD_URL"
	wget -O "$downloaded_archive" "$PROGRAM_DOWNLOAD_URL"

	# extract package to tmp
	if [ -f "$downloaded_archive" ]; then
		echo "download success"		
		archive_hash=$(md5sum "${downloaded_archive}" | awk '{ print $1 }')
		unzip "$downloaded_archive" -d "$temp_dir_for_latest"

		if [ -f "$temp_dir_for_latest/$PYTHON_MAIN_FILE" ]; then
			echo "Extraction successful"

			# double check version number
			local new_version_file="$temp_dir_for_latest/cdsmaster/version.py"
			local new_version
			new_version="$(get_program_version "$new_version_file")"


			if [[ "$available_version_string" != "$new_version" ]]; then
				echo "Version defined by manifest $available_version_string and actual version of downloaded file $new_version are not same"
				exit 1
			fi
		else
			echo "Extraction failed. Update will now exit!"
			exit 1
		fi
	fi


	# stop running service of program	
	if is_service_installed; then
		echo "Stopping running program"
		if is_service_running; then
			stop_service
		fi
	fi


	# check to see if python version has changed. if yes create new virtual environment	
	local gotpython=0
	echo "Checking to see if we already have necessary version of python for this update or we need to install"
	for ver in "${PROGRAM_SUPPORTED_INTERPRETERS[@]}"
	do
		if [[ "$ver" == "$INSTALLATION_PYTHON_VERSION" ]]; then
			gotpython=1
			break
		fi
	done

	# installs python + creates virtual environment and install dependencies as well
	if [ $gotpython -eq 0 ]; then
		# python version has changed so we need tro install compatible version fo python and create Virtual environment again
		echo "Installing required version of python" && sleep 5
		prerequisites_python && post_download_install
	else
		#python version is unchanged so just install requirements again
		echo "Python version is ok. No need to install new version. Simply reinstall dependencies" && sleep 5
		install_python_program_dependencies
	fi


	# Discover list of modules found in the new build
	local new_modules=()
	local module_conf_dir2="$temp_dir_for_latest/cdsmaster/modules/conf"

	while IFS= read -r -d '' file; do
		filename=$(basename -- "$file")
		filename="${filename%.*}" # Remove the file extension
		new_modules+=("$filename")
	done < <(find "$module_conf_dir2" -type f -name "*.json" -print0)




	# >>> Collect list of modules in existing <<<
	local existing_modules=()
	local module_conf_dir="$DEFAULT_PROGRAM_PATH/cdsmaster/modules/conf"

	while IFS= read -r -d '' file; do
		filename=$(basename -- "$file")
		filename="${filename%.*}" # Remove the file extension
		existing_modules+=("$filename")
	done < <(find "$module_conf_dir" -type f -name "*.json" -print0)


	

	# copy current to tmp workspace
	cp -a "$DEFAULT_PROGRAM_PATH"/. "$temp_dir_for_existing"/
	if [ ! -f "$temp_dir_for_existing/$PYTHON_MAIN_FILE" ]; then
		lecho "Copy unsuccessful. Update will now exit!"
		exit 1
	fi	


	## First we copy all old files into update workspace
	cp -a "$temp_dir_for_existing"/. "$temp_dir_for_updated"/
	if [ ! -f "$temp_dir_for_updated/$PYTHON_MAIN_FILE" ]; then
		lecho "Copy unsuccessful. Update will now exit!"
		exit 1
	fi


	## check if any profile was active on current installation
	local has_profile=0
	read_installation_meta

	local profile_dir_path=""

	local profile_name=$CURRENT_INSTALLATION_PROFILE
	if [ -n "${profile_name}" ]; then
		lecho "profile was found for this installation" 
		local url
		url=$(get_profile_url "$profile_name")
		if [ -z "${url}" ]; then
			error=1
			err_message="Profile url not found!. Update will disregard profile"
			profile_name=""
		else
			local tmp_dir
			tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)

			local profile_archive="$tmp_dir/$profile_name.zip"	
			local profile_package_path="$tmp_dir/$profile_name"

			# extract profile archive to a tmp location
			wget -O "$profile_archive" "$url"
			unzip "$profile_archive" -d "$profile_package_path"

			local meta_file="$profile_package_path/meta.json"
			if [ -f "$meta_file" ]; then
				profile_dir_path=$profile_package_path
				has_profile=1
			fi			
		fi
	
	else
		lecho "No profile found for this installation" 	
	fi



	# >>> Install updates for existing modules <<<
	lecho "Installing addon modules for latest build"
	local base_dir=$temp_dir_for_latest
	for i in "${existing_modules[@]}"
	do
	: 		
		if [[ ! " ${new_modules[*]} " == *" $i "* ]]; then
			sleep 1
			lecho "Module $i was not found in latest core build. attempting to install as an addon.."
			install_module "$i" "$temp_dir_for_latest" true # force install module into latest build download
		fi
	done



	
	# leave all files that are in old version but not in new version (custom modules and custom rules and custom scripts)
	# carefully merge old configuration json with new configuration json -> validate jsons	
	# carefully merge old rules json with new rules json -> validate jsons	
	local EXECUTABLE_PYTHON=$PYTHON_VIRTUAL_ENV_INTERPRETER


	
	# pass tmp dir paths to merger	
	chmod +x "$MERGE_SCRIPT"

	local merge_result
	merge_result=$($EXECUTABLE_PYTHON "$MERGE_SCRIPT" "$temp_dir_for_latest" "$temp_dir_for_updated" "$profile_dir_path")
	if [[ $merge_result != *"merge ok"* ]]; then
		lecho "Merging failed. Update will now exit!"
		exit 1
	fi

	if [ ! -f "$temp_dir_for_updated/$PYTHON_MAIN_FILE" ]; then
		lecho "Merging incorrect.Update will now exit!"
		exit 1
	fi


	lecho "Configuration merge successful! @ $temp_dir_for_updated" && sleep 2


	# merge successfull updated tmp dir contains updated program files
	# Overwrite updated installation to active installation
	lecho "Moving updated files to main program directory"

	cp -a "$temp_dir_for_updated"/. "$DEFAULT_PROGRAM_PATH"/
	if [ ! -f "$DEFAULT_PROGRAM_PATH/$PYTHON_MAIN_FILE" ]; then
		lecho "Overwrite unsuccessful. Update will now exit!" && exit
	else
		lecho "Unpacking runtime files. Warning old runtime files will be overwritten!"

		# Unpack runtime so files
		unpack_runtime_libraries
	fi	

	
	
	# restart service	
	if is_service_installed; then
		lecho "Restarting program"
		if ! is_service_running; then
			start_service
		fi
		#optionally monitor error log of the program post startup. 
		#if we see startup errors then revert to old version
		sleep 8 # wait for few seconds to allow service to startup

		local ERROR_LOG_FILE="$DEFAULT_PROGRAM_PATH/$PROGRAM_ERROR_LOG_FILE_NAME"

		if [ -f "$ERROR_LOG_FILE" ]; then
			local error_status
			error_status=$(grep ERROR "$ERROR_LOG_FILE")
			if [ -n "$error_status" ]; then
				lecho_err "Program seems to have startup errors. Update needs to be reverted"		
				lecho_err "Update has failed!"
				lecho "Start rollback!"
				#rollback_update $temp_dir_for_existing
			fi
		
		else
			write_installation_meta
			lecho "Update completed successfully"		
		fi
	else

		# if service is not installed we cannot autostart it. so tell user to do it manually instead
		lecho_notice "Update was installed, but you need to run it to see if there are ny errors or not. If you see errors, we advise a rollback of the update or a clean re-install."
	fi
}




#############################################
# Installs cloudisense client
# 
# GLOBALS:
#		DEFAULT_PROGRAM_PATH
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################
install_client() 
{
	client_download_success=0

    local client_url="$PROGRAM_CLIENT_URL"
    local client_dest="$DEFAULT_PROGRAM_PATH/cdsmaster/client"
    local tmp_dir=$(mktemp -d -t client-download-XXXXXXXXXX)
    local client_archive="$tmp_dir/cloudisense.zip"

    # Ensure destination folder exists
    if [[ ! -d "$client_dest" ]]; then
        lecho "Creating client directory at $client_dest..."
        mkdir -p "$client_dest"
    fi

    # Validate client URL
    if [[ -z "$client_url" || "$client_url" == "null" ]]; then
        lecho_err "Client URL is not defined or invalid. Skipping client installation."
        return 1
    fi

    lecho "Downloading client from: $client_url"

    # Download client archive
    if ! curl -o "$client_archive" --fail --silent --show-error "$client_url"; then
        lecho_err "Failed to download client package. Please check the URL or network connection."
        return 1
    fi

    lecho "Client package downloaded successfully."

    # Extract client archive
    lecho "Extracting client package to $client_dest..."
    if ! unzip -o "$client_archive" -d "$client_dest"; then
        lecho_err "Failed to extract client package."
        return 1
    fi

    # Set appropriate permissions
    chown -R "$USER":"$USER" "$client_dest"
    chmod -R 755 "$client_dest"

    lecho "✅ Cloudisense client installed successfully at $client_dest."
	client_download_success=1

    # Cleanup
    rm -rf "$tmp_dir"
	
}





#############################################
# Installs cloudisense
# 
# GLOBALS:
#		latest_download_success
#
# ARGUMENTS:
#
# RETURN:
#		
#############################################
auto_install_program()
{
	latest_download_success=0
	client_download_success=0


	# Download zip or clone from repo based on config
	echo "Preparing to install to $DEFAULT_PROGRAM_PATH"
	sleep 2


	if [ ! -d "$DEFAULT_PROGRAM_PATH" ]; then
		mkdir -p "$DEFAULT_PROGRAM_PATH"
		chmod -R 0755 "$DEFAULT_PROGRAM_PATH"
		chown -R "$USER": "$DEFAULT_PROGRAM_PATH"
	fi


	lecho "Installing program"
	install_from_url
		

	if [ "$latest_download_success" -eq 0 ]; then
		lecho_err "Failed to get distribution from source. Please contact support!"
		empty_pause && exit
	fi


	if [[ "$CLIENT_INSTALL" -eq 1 ]]; then
		lecho "Installing client"
		install_client

		if [ "$client_download_success" -eq 0 ]; then
			lecho_err "Failed to get client distribution from source. Please contact support!"
			empty_pause && exit
		fi
	fi	


	lecho "Program installed successfully!"
	sleep 2
	
}



#############################################
# Starts service on user prompt using systemctl
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################	
prompt_start_service()
{	
	if is_service_installed; then
		lecho "Do you want to start the service now?"
		read -r -p "Are you sure? [y/N] " response

		case $response in
		[yY][eE][sS]|[yY]) 
		start_service
		;;
		*)
		lecho "Service will be autostarted on next system start. You can also manually start it from shell."
		lecho "For more info please refer to documentation!"
		;;
		esac
	else
		lecho_err "Service not found/installed!"
	fi
}



#############################################
# Starts service using systemctl
# 
# GLOBALS:
#		PROGRAM_SERVICE_LOCATION, PROGRAM_SERVICE_NAME
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################	
start_service()
{
    lecho "Start $PROGRAM_NAME service"
    
    seudo systemctl start $PROGRAM_SERVICE_NAME

	local status=$?	
	if [ "$status" -eq 0 ]; then
		lecho "$PROGRAM_NAME service started!"
	else
		lecho "$PROGRAM_NAME service file was not started!"
		lecho "Please check service file $PROGRAM_SERVICE_LOCATION/$PROGRAM_SERVICE_NAME"
	fi
    sleep 2
}





#############################################
# Restarts cloudisense service using systemctl
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
restart_service()
{
	if is_service_installed; then
		stop_service && sleep 2 && start_service
	else
		lecho_err "Service not found!"
	fi
}




#############################################
# Stops cloudisense service using systemctl
# 
# GLOBALS:
#		PROGRAM_SERVICE_LOCATION, PROGRAM_SERVICE_NAME
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################	
stop_service(){
    lecho "Stop $PROGRAM_NAME service"
    seudo systemctl stop $PROGRAM_SERVICE_NAME
    sleep 2
}




#############################################
# Checks installation and registers cloudisense 
# as system service
# 
# GLOBALS:
#		PROGRAM_SERVICE_LOCATION, PROGRAM_SERVICE_NAME
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################	
register_as_service()
{
	check_current_installation 1

	if [ "$program_exists" -eq 1 ]; then

		if [ -f "$PROGRAM_SERVICE_LOCATION/$PROGRAM_SERVICE_NAME" ]; then
			lecho "Service already exists. Do you wish to re-install ?" 
			read -r -p "Are you sure? [y/N] " response

			case $response in
			[yY][eE][sS]|[yY]) 
			register_service
			;;
			*)
			lecho "Service installation cancelled"
			;;
			esac

		else
			register_service
		fi
	fi

	if [ $# -eq 0 ]
	  then
	    empty_pause
	fi
}



#############################################
# Unregister cloudisense as system service
# 
# GLOBALS:
#		PROGRAM_SERVICE_LOCATION, PROGRAM_SERVICE_NAME
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
unregister_as_service()
{
	check_current_installation 0

	if [ "$program_exists" -eq 1 ]; then

		if [ ! -f "$PROGRAM_SERVICE_LOCATION/$PROGRAM_SERVICE_NAME" ]; then
			lecho "Service does not exists. Nothing to remove" 
		else
			unregister_service
		fi

	fi

	if [ $# -eq 0 ]
	  then
	    empty_pause
	fi
}


#############################################
# Install from archive
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install_archive()
{			
	clear
	lecho "Installing from zip not implemented" && exit
}



#############################################
# Checks if file is a valid archive of cloudisense
# dist.
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
isValidArchive()
{
	local archive_path=$1

	if [ ! -f "$archive_path" ]; then
		lecho "Invalid archive file path $archive_path"
		false
	else
		local filename
		local filesize
		local extension

		filename=$(basename "$archive_path")
		extension="${filename##*.}"
		filename="${filename%.*}"

		filesize=$(stat -c%s "$archive_path")
		
		if [ "$filesize" -lt 30000 ]; then
			lecho "Invalid archive file size detected for $archive_path. Probable corrupt file!"
			false
		else
			case "$extension" in 
			zip|tar|gz*) 
			    true
			    ;;	
			*)
			    lecho "Invalid archive type $extension"
			    false
			    ;;
			esac
		fi
	fi
}



#############################################
# Checks if archive is single level or not
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#		true is it is single level, false otherwise
#	
#############################################
isSingleLevel()
{
	local lvl_tmp, count
	
	lvl_tmp=$1
	count=$(find "$lvl_tmp" -maxdepth 1 -type d | wc -l)

	if [ "$count" -gt 2 ]; then
		true
	else
		false
	fi
}


#############################################
# Writes system service file for cloudisense
# 
# GLOBALS:
#		PYTHON_VIRTUAL_ENV_LOCATION, PROGRAM_FOLDER_NAME,
#		PYTHON_VERSION, PYTHON_VIRTUAL_ENV_INTERPRETER,
#		DEFAULT_PROGRAM_PATH, PYTHON_MAIN_FILE,
#		PROGRAM_SERVICE_LOCATION, PROGRAM_SERVICE_NAME,
#		service_install_success
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
register_service() {
    # Permission check
    if ! validatePermissions; then
        request_permission;
    fi

    # Remove user if exists
    if has_user "$PROGRAM_NAME"; then
        remove_user "$PROGRAM_NAME"
    fi

    # Add user for cloudisene
    add_user "$PROGRAM_NAME"

    service_install_success=0

    lecho "Preparing to install service..."
    sleep 2

    PYTHON_VIRTUAL_ENV_INTERPRETER="$PYTHON_VIRTUAL_ENV_LOCATION/$PROGRAM_FOLDER_NAME/bin/python$PYTHON_VERSION"

    #######################################################

    service_script="[Unit]
    Description=$PROGRAM_NAME Service
    After=multi-user.target

    [Service]
    Type=simple
    User=$PROGRAM_NAME
    WorkingDirectory=$DEFAULT_PROGRAM_PATH

    ExecStart=$PYTHON_VIRTUAL_ENV_INTERPRETER $DEFAULT_PROGRAM_PATH/$PYTHON_MAIN_FILE
    Restart=always

    [Install]
    WantedBy=multi-user.target
    "

    #######################################################

    lecho "Writing service script"
    sleep 1


    # Check if systemd is present
    if command -v systemctl &>/dev/null && [ -e /run/systemd/system ]; then
        lecho "Systemd detected, registering service with systemd..."

		local SERVICE_SCRIPT_PATH="$PROGRAM_SERVICE_LOCATION/$PROGRAM_SERVICE_NAME"

		seudo touch "$SERVICE_SCRIPT_PATH" && seudo chmod 755 "$SERVICE_SCRIPT_PATH"

		# Write script to file
		echo "$service_script" | seudo tee "$SERVICE_SCRIPT_PATH" > /dev/null


		# Make service file executable
		seudo chmod 644 "$SERVICE_SCRIPT_PATH"
		echo "$SERVICE_SCRIPT_PATH" && sleep 2

        # Reload systemd daemon
        seudo systemctl daemon-reload

        lecho "Enabling service \"$PROGRAM_SERVICE_NAME\" with systemd"

        # Enable and start service with systemd
        seudo systemctl enable "$PROGRAM_SERVICE_NAME"
        seudo systemctl start "$PROGRAM_SERVICE_NAME"

        lecho "Service installed and started successfully with systemd!"    

    else

		lecho "Error: No supported init system found. Attempting to install supervisor."
		
		if register_supervisor; then
			lecho "Service installed and registered with supervisor!"
		else
			lecho "Service installation failed!"
			exit 1
		fi
    fi

    # shellcheck disable=SC2034
    service_install_success=1
}






#############################################
# Writes system service file for cloudisense
# 
# GLOBALS:
#		DEFAULT_PROGRAM_PATH, PYTHON_MAIN_FILE,
#		PROGRAM_NAME, DEFAULT_PROGRAM_PATH
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
# shellcheck disable=SC2181
register_supervisor()
{
	# Variables
	local SERVICE_NAME="$PROGRAM_NAME"
	local SERVICE_PATH="$DEFAULT_PROGRAM_PATH/$PYTHON_MAIN_FILE"
	local WORKING_DIR="$DEFAULT_PROGRAM_PATH"
	local USER="$PROGRAM_NAME"
	local LOG_DIR="$DEFAULT_PROGRAM_PATH/log"                  # Directory for log files
	local SUPERVISOR_CONF="/etc/supervisor/conf.d/$PROGRAM_NAME.conf"

	# Create the Supervisor configuration file
	echo "Creating Supervisor configuration for $SERVICE_NAME..."
	tee $SUPERVISOR_CONF > /dev/null <<EOL	
	[program:$SERVICE_NAME]
	command=$SERVICE_PATH             # Full path to Cloudisense executable or script
	directory=$WORKING_DIR            # Working directory
	user=$USER                        # User to run the service as
	autostart=true                     # Automatically start on supervisor startup
	autorestart=true                   # Restart if the program crashes
	stderr_logfile=$LOG_DIR/$SERVICE_NAME.err.log  # Log file for errors
	stdout_logfile=$LOG_DIR/$SERVICE_NAME.out.log  # Log file for standard output
	environment=PATH="/usr/local/bin:/usr/bin"   # Environment variables (if needed)
EOL

	# Check if the Supervisor configuration file was created successfully	
	if [ $? -ne 0 ]; then
		echo "Error: Failed to create Supervisor configuration file for $SERVICE_NAME."
		return 1
	fi

	# Reload Supervisor configuration
	echo "Reloading Supervisor configuration..."
	supervisorctl reread
	if [ $? -ne 0 ]; then
		echo "Error: Failed to reload Supervisor configuration."
		return 1
	fi
	
	supervisorctl update
	if [ $? -ne 0 ]; then
		echo "Error: Failed to update Supervisor with the new configuration."
		return 1
	fi

	# Enable Supervisor to start on boot
	echo "Enabling Supervisor to start on boot..."
	seudo systemctl enable supervisor
	if [ $? -ne 0 ]; then
		echo "Error: Failed to enable Supervisor to start on boot."
		return 1
	fi

	# Start the Cloudisense service
	echo "Starting Cloudisense service..."
	supervisorctl start $SERVICE_NAME
	if [ $? -ne 0 ]; then
		echo "Error: Failed to start Cloudisense service."
		return 1
	fi

	# Check the status of the Cloudisense service
	echo "Checking Cloudisense service status..."
	supervisorctl status $SERVICE_NAME
	if [ $? -ne 0 ]; then
		echo "Error: Cloudisense service is not running."
		return 1
	fi

	echo "Cloudisense service setup complete and running."
}





#############################################
# Removes system service file for cloudisense
# 
# GLOBALS:
#		PROGRAM_SERVICE_NAME, PROGRAM_SERVICE_LOCATION
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
unregister_service() {
    # Permission check
    if ! validatePermissions; then
        request_permission;
    fi

    # Remove user if exists
    if has_user "$PROGRAM_NAME"; then
        remove_user "$PROGRAM_NAME"
    fi

    lecho "Unregistering service \"$PROGRAM_SERVICE_NAME\""
    sleep 1	

    local SERVICE_SCRIPT_PATH="$PROGRAM_SERVICE_LOCATION/$PROGRAM_SERVICE_NAME"

	echo "$SERVICE_SCRIPT_PATH" && sleep 2

    if [ -f "$SERVICE_SCRIPT_PATH" ]; then
        # Check if systemd is present
        if command -v systemctl &>/dev/null && [ -e /run/systemd/system ]; then
            lecho "Systemd detected, unregistering service with systemd..."

            # Reload systemd daemon
            seudo systemctl daemon-reload

            lecho "Disabling service \"$PROGRAM_SERVICE_NAME\" with systemd"

            # Disable and stop the service
            seudo systemctl stop "$PROGRAM_SERVICE_NAME"
            seudo systemctl disable "$PROGRAM_SERVICE_NAME"
            
            # Remove service file (if applicable)
            seudo rm -f "$SERVICE_SCRIPT_PATH"

            lecho "Service successfully removed from systemd."

        else
            lecho "Error: No supported init system found. Service unregistration failed."
            return 1
        fi
    else
        lecho "Service script not found at $SERVICE_SCRIPT_PATH. Unregistration skipped."
    fi
}




#############################################
# Checks to see if script is running in docker
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#		true is service is installed, false otherwise
#	
#############################################
is_running_in_docker()
{
	if [ -f /.dockerenv ] || grep -qE "/docker|/lxc" /proc/1/cgroup 2>/dev/null; then
		return 0
	else
		return 1
	fi
}




#############################################
# Checks to see if service is installed or not.
# 
# GLOBALS:
#		PROGRAM_SERVICE_NAME, PROGRAM_SERVICE_LOCATION
#
# ARGUMENTS:
#
# RETURN:
#		true is service is installed, false otherwise
#	
#############################################
is_service_installed() 
{
    # Check if the service script is present in the systemd locations

    # Check for systemd service
    if command -v systemctl &>/dev/null && [ -e /run/systemd/system ]; then
        # Check if the service unit file exists in systemd locations
        if [ -f "/etc/systemd/system/$PROGRAM_SERVICE_NAME" ] || [ -f "/lib/systemd/system/$PROGRAM_SERVICE_NAME" ]; then
            return 0  # Service is installed (systemd)
        fi
    fi

    # If not found
    return 1  # Service is not installed
}




#############################################
# Checks to see if service is installed or not.
# 
# GLOBALS:
#		PROGRAM_SERVICE_NAME
#
# ARGUMENTS:
#
# RETURN:
#		true is service is installed, false otherwise
#	
#############################################
is_service_running()
{
	if seudo systemctl is-active --quiet $PROGRAM_SERVICE_NAME; then
		true
	else
		false
	fi
}



#############################################
# Checks and verifies the current installation 
# of cloudisense. Takes two optional arguments.
# 
# GLOBALS:
#		PROGRAM_SERVICE_NAME
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
# shellcheck disable=SC2034
check_current_installation()
{
	program_exists=0
	local check_silent=0
	local version=""

	# IF second param is set then turn on silent mode quick check
	if [ $# -eq 2 ]; then
		check_silent=1		
	fi


	if [ ! "$check_silent" -eq 1 ] ; then
		lecho "Looking for program at install location..."
		sleep 2
	fi


	if [ ! -d "$DEFAULT_PROGRAM_PATH" ]; then
		if [ ! "$check_silent" -eq 1 ] ; then
  		lecho "No installation found at install location : $DEFAULT_PROGRAM_PATH"
		fi
	else
		local executable="$DEFAULT_PROGRAM_PATH/$PYTHON_MAIN_FILE"
		local rules_directory="$DEFAULT_PROGRAM_PATH/rules"

		
		if [ -f "$executable" ]; then			
			if [ -d "$rules_directory" ]; then
				program_exists=1

				version_file="$DEFAULT_PROGRAM_PATH/cdsmaster/version.py"
				while IFS= read -r line
				do
				if [[ $line = __version__* ]]
					then
						version_found_old="${line/$target/$blank}" 
						break
				fi

				done < "$version_file"

				local replacement=""
				version="${version_found_old//__version__/$replacement}"
				version="${version//=/ $replacement}"

				local old_version_num=
				IFS='.'
				read -ra ADDR <<< "$version_found_old"
				count=0
				ver_num=""
				for i in "${ADDR[@]}"; do # access each element of array
					old_version_num="$old_version_num$i"
					count=$((count+1))	
					if [[ $count -eq 3 ]]; then
					break
					fi	
				done
				IFS=' '

				old_version_num="${old_version_num// /}"
				old_version_num=${old_version_num//\'/}
				old_version_num=$__version__

				if [ ! "$check_silent" -eq 1 ] ; then
					lecho "Installation of version $version found at install location : $DEFAULT_PROGRAM_PATH"
				fi
			fi
		else
			lecho "There were files found at install location : $DEFAULT_PROGRAM_PATH, but the installation might be broken !. I could not locate version information"
		fi
				
	fi

	if [ $# -eq 0 ]; then
		empty_line		
	fi


	# return true or false
	if [ ! "$program_exists" -eq 1 ] ; then
		true
	else
		false
	fi

}


#############################################
# Writes instalaltion report after a successful
# installation.
# 
# GLOBALS:
#		PYTHON_VERSION, PYTHON_VIRTUAL_ENV_LOCATION,
#		REQUIREMENTS_FILE, PROGRAM_INSTALLATION_REPORT_FILE
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
# shellcheck disable=SC2034
write_installation_meta()
{
	local now
	local installtime
	local profile
	local pythonversion
	local replacement
	local subject
	local interpreterpath
	local requirements_filename
	local layout

	now=$(date)
	installtime=$now
	profile="$CURRENT_INSTALLATION_PROFILE"
	pythonversion=${PYTHON_VERSION/python/$replacement}
	replacement=""
	subject="python"
	interpreterpath="$PYTHON_VIRTUAL_ENV_LOCATION/$PROGRAM_FOLDER_NAME/bin/python$PYTHON_VERSION"
	requirements_filename=$(basename -- "$REQUIREMENTS_FILE")
	layout="$UIGUIDE_LAYOUT"
	
	jq -n \
	--arg profile "$profile" \
	--arg interpreterpath "$interpreterpath" \
	--arg pythonversion "$pythonversion" \
	--arg installtime "$installtime" \
	--arg requirements_filename "$requirements_filename" \
	--arg layout "$layout" \
	'{install_time: $installtime, python_version: $pythonversion, interpreter: $interpreterpath, requirements: $requirements_filename, profile: $profile, layout: $layout}' | \
	tee "$PROGRAM_INSTALLATION_REPORT_FILE" > /dev/null

	seudo chown -R "$USER": "$PROGRAM_INSTALLATION_REPORT_FILE"
}





#############################################
# Updates current instalaltion profile in the instalaltion report
# 
# GLOBALS:
#	PROGRAM_INSTALLATION_REPORT_FILE
#
# ARGUMENTS:
#	$1: Profile name
#
# RETURN:
#	
#############################################

update_installation_meta()
{
	if [ ! -f "$PROGRAM_INSTALLATION_REPORT_FILE" ]; then
		lecho_err "No installation report found."
	else

		if [ $# -gt 0 ]; then
			local profile_name
			local layout_value
			local tmpfile
			local jq_filter="."

			# If the first parameter is set, it's the profile
			if [ -n "$1" ]; then
				profile_name=$1
				CURRENT_INSTALLATION_PROFILE=$profile_name
				jq_filter="$jq_filter | .profile = \"$CURRENT_INSTALLATION_PROFILE\""
			fi

			# If the second parameter is set, it's the layout
			if [ -n "$2" ]; then
				layout_value=$2
				UIGUIDE_LAYOUT="$layout_value"
				jq_filter="$jq_filter | .layout = \"$layout_value\""
			fi

			# Apply the jq filter to update the JSON file
			tmpfile="${PROGRAM_INSTALLATION_REPORT_FILE/.json/.tmp}"
			jq "$jq_filter" "$PROGRAM_INSTALLATION_REPORT_FILE" > "$tmpfile"
			mv "$tmpfile" "$PROGRAM_INSTALLATION_REPORT_FILE"
		else
			lecho_err "Minimum of 1 parameter is required!"
		fi


	fi
}




#############################################
# Reads from existing instalaltion report
# 
# GLOBALS:
#		INSTALLATION_PYTHON_VERSION, PROGRAM_INSTALLATION_REPORT_FILE,
#		PYTHON_VIRTUAL_ENV_INTERPRETER, PYTHON_REQUIREMENTS_FILENAME
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################

read_installation_meta()
{
	if [ ! -f "$PROGRAM_INSTALLATION_REPORT_FILE" ]; then
		echo "No installation report found."
	else

		local result
		local installtime
		local pythonversion
		local interpreterpath
		local requirements_filename
		local profile
		local layout

		result=$(<"$PROGRAM_INSTALLATION_REPORT_FILE")
		installtime=$(jq -r '.install_time' <<< "${result}")
		pythonversion=$(jq -r '.python_version' <<< "${result}")
		interpreterpath=$(jq -r '.interpreter' <<< "${result}")
		requirements_filename=$(jq -r '.requirements' <<< "${result}")
		profile=$(jq -r '.profile' <<< "${result}")
		layout=$(jq -r '.layout' <<< "${result}")

		INSTALLATION_PYTHON_VERSION="$pythonversion"
		PYTHON_VIRTUAL_ENV_INTERPRETER=$interpreterpath
		PYTHON_REQUIREMENTS_FILENAME=$requirements_filename
		CURRENT_INSTALLATION_PROFILE="$profile"
		UIGUIDE_LAYOUT="$layout"


	fi
}




#############################################
# Deletes existing instalaltion report
# 
# GLOBALS:
#		PROGRAM_INSTALLATION_REPORT_FILE
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
clear_installation_meta()
{
	if [ -f "$PROGRAM_INSTALLATION_REPORT_FILE" ]; then
		rm -rf "$PROGRAM_INSTALLATION_REPORT_FILE"
	fi
}



#############################################
# Checks to see if this is first time installation
# or not. Also reads the installation report to memory.
# 
# GLOBALS:
#		PROGRAM_INSTALLATION_REPORT_FILE
#
# ARGUMENTS:
#
# RETURN:
#		true if thsi is first time installation , otherwise false
#	
#############################################
is_first_time_install()
{
	if [ -f "$PROGRAM_INSTALLATION_REPORT_FILE" ]; then
		read_installation_meta
		if [ -z ${INSTALLATION_PYTHON_VERSION+x} ]; then 
			true 
		else
			false
		fi
	else
		true
	fi

}




#############################################
# Performs additional steps needed after 
# installing the main python program. This usually 
# includes creating virtual enviromnent, installing
# dependencies etc:
# 
# GLOBALS:
#		virtual_environment_exists, virtual_environment_valid,
#		PROGRAM_SERVICE_AUTOSTART
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
post_download_install()
{
	check_create_virtual_environment

	if [[ $virtual_environment_exists -eq 1 ]]; then	
		
		activate_virtual_environment

		if [[ $virtual_environment_valid -eq 1 ]]; then	
			
			install_python_program_dependencies 1

			deactivate_virtual_environment

			write_installation_meta

			if $PROGRAM_INSTALL_AS_SERVICE; then

				# stop if running
				if is_service_installed; then
					if is_service_running; then
						stop_service	
					fi
				fi

				# Remove if exists
				if is_service_installed; then
					unregister_as_service 1
				fi
				
				# Install
				if is_running_in_docker; then
					local interpreterpath="$PYTHON_VIRTUAL_ENV_LOCATION/$PROGRAM_FOLDER_NAME/bin/python$PYTHON_VERSION"
					lecho "Inside docker! Run program using '$interpreterpath $DEFAULT_PROGRAM_PATH/$PYTHON_MAIN_FILE'"
				else
					register_as_service 1				
				fi


				if ! is_running_in_docker; then
					if $PROGRAM_SERVICE_AUTOSTART; then
						start_service
					else
						prompt_start_service
					fi			
				fi
				
			fi

			post_update_deb

			# register cron for update
			# deregister_updater && register_updater
		else
			echo -e "\e[41m Invalid virtual environment!\e[m"
		fi
	else
		echo -e "\e[41m Failed to create virtual environment!\e[m"
	fi
}




#############################################
# Removes the existing installation of cloudisense
# 
# GLOBALS:
#		PYTHON_VIRTUAL_ENV_LOCATION, PROGRAM_FOLDER_NAME,
#		VENV_FOLDER, DEFAULT_PROGRAM_PATH
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
uninstall()
{
	# stop if running
	if is_service_installed; then
		if is_service_running; then
			stop_service	
		fi
	fi

	# Remove if exists
	if is_service_installed; then
		unregister_as_service 1
	fi
	

	# remove virtual environment
	VENV_FOLDER="$PYTHON_VIRTUAL_ENV_LOCATION/$PROGRAM_FOLDER_NAME"
	if [ -d "$VENV_FOLDER" ]; then	
		rm -rf "$VENV_FOLDER"
	fi

	# remove program files
	if [ -d "$DEFAULT_PROGRAM_PATH" ]; then	
		rm -rf "$DEFAULT_PROGRAM_PATH"
	fi

	# remove installation info
	clear_installation_meta

	# remove autoupdater (if exists)
	deregister_updater

	lecho "Uninstall completed successfully!"
}




#############################################
# Main install method 
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
install()
{
	if ! validatePermissions; then
		request_permission;
	fi

	auto_install_program

	if [[ $latest_download_success -eq 1 ]]; then
		post_download_install
	else
		echo -e "\e[41m Failed to install program!\e[m"
	fi	
}


######################################################################################
################################ INIT FUNCTIONS ######################################


#############################################
# Loads installer configuration from config.ini file
# 
# GLOBALS:
#		PROGRAM_INSTALL_LOCATION
#		CURRENT_DIRECTORY, DEFAULT_PROGRAM_PATH
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
load_configuration()
{
	# Set install location if not set

	CURRENT_DIRECTORY=$PWD


	if [ -z ${PROGRAM_FOLDER_NAME+x} ]; then 
		PROGRAM_FOLDER_NAME=$PROGRAM_NAME
	fi
	

	if [ -z ${PROGRAM_INSTALL_LOCATION+x} ]; then 
		DEFAULT_PROGRAM_PATH="$CURRENT_DIRECTORY/$PROGRAM_FOLDER_NAME"
	else
		DEFAULT_PROGRAM_PATH="$PROGRAM_INSTALL_LOCATION/$PROGRAM_FOLDER_NAME"			
	fi


	PROGRAM_DEFAULT_DOWNLOAD_FOLDER="$CURRENT_DIRECTORY/$PROGRAM_DEFAULT_DOWNLOAD_FOLDER_NAME"
	[ ! -d foo ] && mkdir -p "$PROGRAM_DEFAULT_DOWNLOAD_FOLDER" && chmod ugo+w "$PROGRAM_DEFAULT_DOWNLOAD_FOLDER"

	
	if [ -z ${PROGRAM_MANIFEST_LOCATION+x} ]; then 
		PROGRAM_MANIFEST_LOCATION=$(echo 'aHR0cHM6Ly9jbG91ZGlzZW5zZS5zMy51cy1lYXN0LTEuYW1hem9uYXdzLmNvbS9tYW5pZmVzdC5qc29u' | base64 --decode)
	fi
	

	PROGRAM_INSTALLATION_REPORT_FILE="$DEFAULT_PROGRAM_PATH/$PROGRAM_INSTALL_REPORT_NAME"
	PROGRAM_ARCHIVE_NAME="$PROGRAM_NAME.zip"
	PROGRAM_SERVICE_NAME="$PROGRAM_NAME.service"
}





#############################################
# Detect init system
# 
# GLOBALS:
#		INIT_SYSTEM
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
detect_init_system() {
    if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
        echo "Systemd is the init system."
		INIT_SYSTEM=Systemd
    elif [ "$(ps -p 1 -o comm=)" = "init" ]; then
        if command -v initctl >/dev/null 2>&1; then
            echo "Upstart is the init system."
			INIT_SYSTEM=Upstart
        fi
    else
        echo "Unknown init system."
    fi
}




#############################################
# Detect system parameters, OS, architechture etc
# 
# GLOBALS:
#		RASPBERRY_PI, OS_NAME
#		OS_VERSION, ARCH, IS_64_BIT,
#		PROGRAM_DEFAULT_DOWNLOAD_FOLDER,
#		DEFAULT_PROGRAM_PATH, OS_TYPE,
#		PYTHON_VIRTUAL_ENV_DEFAULT_LOCATION
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
# shellcheck disable=SC2034
detect_system()
{

	local ARCH
	ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')	

	local modelname=

	RASPBERRY_PI=false

	if [ -f /etc/lsb-release ]; then
	    # shellcheck disable=SC1091
	    . /etc/lsb-release
	    OS_NAME=$DISTRIB_ID
	    OS_VERSION=$DISTRIB_RELEASE
	elif [ -f /etc/debian_version ]; then	
	
		local version
        version=$(seudo grep -oP '(?<=^VERSION_CODENAME=).+' /etc/os-release | tr -d '"')

		local name
        name=$(seudo grep -oP '(?<=^NAME=).+' /etc/os-release | tr -d '"')
	
		if [ -f /proc/device-tree/model ]; then
			modelname=$(seudo tr -d '\0' </proc/device-tree/model)
			if [[ "$modelname" == *"Raspberry"* ]]; then
				RASPBERRY_PI=true
			fi
		fi
		
		if $RASPBERRY_PI; then
			OS_NAME=$name
			OS_VERSION=$version
		else		
			OS_NAME=Debian  # XXX or Ubuntu??
			OS_VERSION=$(seudo cat /etc/debian_version)
		fi
	elif [ -f /etc/redhat-release ]; then
	    # TODO add code for Red Hat and CentOS here
	    OS_VERSION=$(seudo rpm -q --qf "%{VERSION}" "$(rpm -q --whatprovides redhat-release)")
        OS_NAME=$(seudo rpm -q --qf "%{RELEASE}" "$(rpm -q --whatprovides redhat-release)")
	else
	    OS_NAME=$(uname -s)
	    OS_VERSION=$(uname -r)
	fi

	local valid_system=1
	OS_MAJ_VERSION=${OS_VERSION%\.*}

	case $(uname -m) in
	x86_64)
		PLATFORM_ARCH="x86_64"
	    ARCH=x64  # AMD64 or Intel64 or whatever
	    IS_64_BIT=1
	    os_bits="64 Bit"
	    ;;
	arm64)
		PLATFORM_ARCH="arm64"
	    ARCH=arm 
	    IS_64_BIT=1
	    os_bits="64 Bit"
	    ;;
	aarch64)
		PLATFORM_ARCH="aarch64"
	    ARCH=arm	    
	    IS_64_BIT=1
	    os_bits="64 Bit"
	    ;;
	*)
	    # leave ARCH as-is
		valid_system=0
	    ;;
	esac

	lecho "Distribution: $OS_NAME"
	lecho "Version: $OS_VERSION"
	lecho "Kernel: $os_bits"


	total_mem=$(awk '/MemTotal/ {printf( "%.2f\n", $2 / 1024 )}' /proc/meminfo)
	total_mem=$(printf "%.0f" "$total_mem")
	#total_mem=$(LANG=C free -m|awk '/^Mem:/{print $2}')
	lecho "Total Memory: $total_mem  MB"


	free_mem=$(awk '/MemFree/ {printf( "%.2f\n", $2 / 1024 )}' /proc/meminfo)
	free_mem=$(printf "%.0f" "$free_mem")
	lecho "Free Memory: $free_mem  MB"

	
	if [ "$valid_system" -eq "0" ]; then
		lecho_err "Unsupported system detected!! Please contact support for further assistance/information.";
		exit;
	fi

	empty_line	

    USER_HOME=$(getent passwd "$USER" | cut -d: -f6)
	lecho "Home directory: $USER_HOME"
	
	lecho "Install directory: $DEFAULT_PROGRAM_PATH"
	lecho "Downloads directory: $PROGRAM_DEFAULT_DOWNLOAD_FOLDER"

	
	if [[ $OS_NAME == *"Ubuntu"* || $OS_NAME == *"Debian"* ]]; then
	OS_TYPE=$OS_DEB
	elif [[ $OS_NAME == *"Raspbian"* ]]; then
	OS_TYPE=$OS_DEB
	else
	OS_TYPE=$OS_RHL
	fi

	
	CURR_HOME=~
	PYTHON_VIRTUAL_ENV_DEFAULT_LOCATION="$CURR_HOME/$PYTHON_DEFAULT_VENV_NAME"
	if [ -z "$PYTHON_VIRTUAL_ENV_LOCATION" ]; then 
		PYTHON_VIRTUAL_ENV_LOCATION=$PYTHON_VIRTUAL_ENV_DEFAULT_LOCATION; 
	else
		CUSTOM__VIRTUAL_ENV_LOCATION=true
	fi

	if $LOGGING; then
		seudo chown -R "$USER": "$LOG_FILE"
	fi
}




#############################################
# Main entry point of the installer
# 
# GLOBALS:
#		UPDATE
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################

main()
{
	switch_dir

	# Load configuration
	load_configuration && detect_system	

	validate_args
	

	if [[ $args_update_mode -eq -1 ]]; then

		if [[ $args_profile_request -eq 1 ]]; then
			echo "Clearing  profile" 
			get_install_info &&	clear_profile
		elif [[ $args_module_request -eq 1 ]]; then
			echo "Uninstalling module" 
			remove_module "$args_module_name"
		else
			echo "Uninstalling core & modules" && uninstall
		fi				
		
	else
		prerequisites 
		get_install_info

		if [[ $args_update_mode -eq 0 ]]; then
		
			if [[ $args_profile_request -eq 1 ]]; then

				if is_first_time_install; then
					prerequisites_python
				fi

				echo "Installing profile $args_profile_name" && sleep 2
				install_profile "$args_profile_name"				

			elif [[ $args_module_request -eq 1 ]]; then

				if is_first_time_install; then
					prerequisites_python
				fi
				

				# Check if it's a comma-separated list
				if [[ "$args_module_name" == *","* ]]; then
					# Remove spaces before and after commas using Bash parameter substitution
					args_module_name="${args_module_name// ,/,}"  # Remove spaces before commas
					args_module_name="${args_module_name//, /,}"  # Remove spaces after commas

					# Split into an array
					IFS=',' read -ra modules <<< "$args_module_name"

					echo "Detected multiple modules: ${modules[*]}"

					# Loop through and install each module, trimming leading/trailing spaces
					for module in "${modules[@]}"; do
						module="$(echo "$module" | xargs)"  # Trim leading/trailing spaces
						echo "Installing module $module" && sleep 2
						install_module "$module"
					done
				else
					# Single module installation (trim leading/trailing spaces)
					args_module_name="$(echo "$args_module_name" | xargs)"
					echo "Installing module $args_module_name" && sleep 2
					install_module "$args_module_name"
				fi

			else				
				echo "Installing core" && sleep 2 

				# Check for existing installation
				check_current_installation 1 1	
				if [ "$program_exists" -eq 1 ]; then
					printf "\n" && lecho_err "Installation already exists!.Uninstall existing deployment and try again or try updating instead."
					empty_pause && exit
				fi

				prerequisites_python
				install
			fi			
			
		elif [[ $args_update_mode -eq 1 ]]; then			
			echo "Updating" && sleep 2
			prerequisites_python
			update
		else
			echo "Unknown update request type" && sleep 2
			exit
		fi
	fi 
}




#############################################
# Installs all prerequisites necessary for 
# installer to run properly
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites()
{
	lecho "Checking installation prerequisites..."
	sleep 2	

	prerequisites_update

	prerequisites_sudo	
	prerequisites_procps
	prerequisites_jq
	#prerequisites_git	
	prerequisites_unzip
	prerequisites_wget
	prerequisites_curl
	prerequisites_bc
	prerequisites_systemd
	prerequisites_crontab


	# detect init system and install supervisor if needed
	detect_init_system
	if [ -z "${INIT_SYSTEM}" ]; then
		prerequisites_supervisor
	fi
}





#############################################
# Checks for and installs git if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_git()
{
	if check_git; then
        echo -e "git \u2714"
    else
        echo "Installing git..."
        sleep 2
        install_git
    fi
}





# Function to check if a package exists in the APT repository
deb_package_exists() 
{
    local package_name="$1"

    if [[ -z "$package_name" ]]; then
        echo "Usage: check_package_exists <package-name>"
        return 1
    fi

    # Search for the package
    if apt-cache policy "$package_name" | grep -q 'Candidate: (none)'; then
        return 1
    else
        return 0
    fi
}





#############################################
# Checks for and installs python if not found
# 
# GLOBALS:
#		has_min_python_version
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_python()
{
	# Checking java
	lecho "Checking python requirements"
	sleep 2
	check_python

	
	if [ "$has_min_python_version" -eq 0 ]; then
		echo "Python not found. Installing required python interpreter..."
		install_python
	else
		ensure_python_additionals "$PYTHON_VERSION"
	fi 
}



#############################################
# Checks for and installs pyenv if not found
# 
# GLOBALS:
#		has_min_python_version
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_pyenv()
{
	if ! is_pyenv_installed; then

		lecho "Pyenv not found! Installing..."

		# Install dependencies required for pyenv (Debian/Ubuntu)
		if [[ -f /etc/debian_version ]]; then
			seudo apt update
			seudo apt install -y make build-essential libssl-dev zlib1g-dev \
								libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
								libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
								libffi-dev liblzma-dev
		elif [[ -f /etc/redhat-release ]]; then
			# Install dependencies for RHEL/CentOS
			seudo yum install -y gcc gcc-c++ make patch zlib-devel bzip2 bzip2-devel \
								readline-devel sqlite sqlite-devel openssl-devel \
								libffi-devel xz-devel
		elif [[ -f /etc/arch-release ]]; then
			# Install dependencies for Arch Linux
			seudo pacman -Sy --needed base-devel openssl zlib \
								xz tk libffi
		fi
	else
		lecho "Pyenv is already installed on this system"
	fi
}



#############################################
# Runs system update command
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_update()
{

	if isDebian; then
	prerequisites_update_deb
	else
	prerequisites_update_rhl
	fi
}



#############################################
# Runs system update command for Debian
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_update_deb()
{	
	sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list	
	seudo apt-get update -qq
	seudo apt-get install -y software-properties-common 
}




#############################################
# cleans up apt install remains
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
post_update_deb()
{	
	seudo apt-get clean && rm -rf /var/lib/apt/lists/*
}




#############################################
# Runs system update command for RHLE/CentOS
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_update_rhl()
{
	seudo yum -y update
	seudo yum install -y yum-utils
}



#############################################
# Checks for and installs procps if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_procps()
{
    # Check if sudo is installed by running check_sudo
    if check_procps; then
		echo -e "procps \u2714"
    else
        echo "Installing procps..."
        sleep 2
        install_procps
    fi
}



#############################################
# Checks for and installs sudo if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_sudo()
{
    # Check if sudo is installed by running check_sudo
    if check_sudo; then
		echo -e "sudo \u2714"
    else
        echo "Installing sudo..."
        sleep 2
        install_sudo
    fi
}


#############################################
# Checks for and installs unzip if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_unzip()
{	
    # Check if unzip is installed by running check_unzip
    if check_unzip; then
		echo -e "unzip \u2714"
    else
        echo "Installing unzip..."
        sleep 2
        install_unzip
    fi
}


#############################################
# Checks for and installs jq if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_jq()
{
    # Check if jq is installed by running check_jq
    if check_jq; then
		echo -e "jq \u2714"
    else
        echo "Installing jq..."
        sleep 2
        install_jq
    fi
}


#############################################
# Checks for and installs mail utilities if 
# not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_mail()
{	
    # Check if mail is installed by running check_mail
    if check_mail; then
		echo -e "mail \u2714"
    else
        echo "Installing mail..."
        sleep 2
        install_mail
    fi
}


#############################################
# Checks for and installs curl if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_curl()
{
    # Check if curl is installed by running check_curl
    if check_curl; then
		echo -e "curl \u2714"
    else
        echo "Installing curl..."
        sleep 2
        install_curl
    fi
}




#############################################
# Checks for and installs wget if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_supervisor()
{	
    # Check if supervisor is installed
    if check_supervisor; then
		echo -e "supervisor \u2714"
    else
        echo "Installing supervisor..."
        sleep 2
        install_supervisor
    fi
}



#############################################
# Checks for and installs crontab if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_crontab()
{	
    # Check if crontab is installed by running check_wget
    if check_crontab; then
		echo -e "crontab \u2714"
    else
        echo "Installing crontab..."
        sleep 2
        install_crontab
    fi
}


#############################################
# Checks for and installs wget if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_wget()
{	
    # Check if wget is installed by running check_wget
    if check_wget; then
		echo -e "wget \u2714"
    else
        echo "Installing wget..."
        sleep 2
        install_wget
    fi
}


#############################################
# Checks for and installs bc if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_bc()
{
    # Check if bc is installed by running check_bc
    if check_bc; then
		echo -e "bc \u2714"
    else
        echo "Installing bc..."
        sleep 2
        install_bc
    fi
}


#############################################
# Checks for and installs systemd if not found
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
prerequisites_systemd()
{
    # Check if systemd is installed by running check_systemd
    if check_systemd; then
		echo -e "systemd \u2714"
    else
        echo "Installing systemd..."
        sleep 2
        install_systemd
    fi
}




######################################################################################
########################### postrequisites FUNCTION ##################################



#############################################
# Checks for and installs other necessary 
# softwares
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
postrequisites()
{
	lecho "Resolving and installing additional dependencies.."
	sleep 2

	if isDebian; then
	postrequisites_deb
	else
	postrequisites_rhl
	fi	
}



#############################################
# Checks for and installs other necessary 
# softwares on RHLE/CentOS
# 
# GLOBALS:
#
# ARGUMENTS:
#
# RETURN:
#	
#############################################
postrequisites_rhl()
{
	seudo yum -y install ntp
}




#############################################
# Checks for and installs other necessary 
# softwares on Debian
# 
# GLOBALS:
#		OS_MAJ_VERSION
# ARGUMENTS:
#
# RETURN:
#	
#############################################
postrequisites_deb()
{

	if [[ "$OS_MAJ_VERSION" -eq 18 ]]; then
		lecho "Installing additional dependencies for Ubuntu 18";
	else
		lecho "Installing additional dependencies for Ubuntu 16";
	fi

	seudo apt-get install -y ntp
	
}


######################################################################################
############################## isinstalled FUNCTION ##################################


#############################################
# Checks to see if a software is installed 
# in the linux system
# softwares
# 
# GLOBALS:
#
# ARGUMENTS:
#		$1 : linux package name
# RETURN:
#	
#############################################
isinstalled()
{
	if isDebian; then
	isinstalled_deb ""$"1" 
	else
	isinstalled_rhl "$1"
	fi
}



#############################################
# Checks to see if a software is installed 
# in the RHLE/CentOS system
# 
# GLOBALS:
#
# ARGUMENTS:
#		$1 : linux package name
# RETURN:
#	
#############################################
isinstalled_rhl()
{
	if yum list installed "$@" >/dev/null 2>&1; then
	true
	else
	false
	fi
}



#############################################
# Checks to see if a software is installed 
# in the Debian system
# 
# GLOBALS:
#
# ARGUMENTS:
#		
# RETURN:
#	
#############################################
isinstalled_deb()
{
	local PKG_OK
	PKG_OK=$(dpkg-query -W --showformat='${Status}\n' "$1"|grep "install ok installed")

	if [ -z "$PKG_OK" ]; then
	false
	else
	true
	fi
}


#############################################
# Checks to see if OS is Debian based
# 
# GLOBALS:
#		OS_TYPE, OS_DEB
# ARGUMENTS:
#
# RETURN:
#	
#############################################
isDebian()
{
	if [ "$OS_TYPE" == "$OS_DEB" ]; then
	true
	else
	false
	fi
}




#############################################
# Validates argumenst passed on invocation
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#	
#############################################
validate_args()
{
	# if core update requested
	if [[ "$args_update_request" -eq 1 ]]; then

		# validate value
		if [ "$args_update_mode" -lt "-1" ] || [ "$args_update_mode" -gt "1" ]; then
			lecho_err "Invalid value for -update flag." && exit 1
		fi
	fi
	


	# if profile requested
	if [[ "$args_profile_request" -eq 1 ]]; then

		# if uninstall requested
		if [[ "$args_update_mode" -lt 0 ]]; then # removal

			# validate value
			if [ "$args_profile_name" != "reset" ]; then
				lecho_err "Invalid profile parameter provided!.For clearing profile, please use the profile name as -> \"reset\"." && exit 1
			fi	

		elif [[ "$args_update_mode" -eq 0 ]]; then # installation

			# validate value
			if [ -z ${args_profile_name+x} ]; then
				lecho_err "Profile name must be expected but was not provided." && exit 1
			fi
		fi
	fi


	# Validate client installation request
	if [[ "$args_install_client_request" -eq 1 ]]; then
		if [[ "$args_install_request" -ne 1 ]]; then
			echo "Error: The -c | --client option must be used with -i | --install."
			exit 1
		fi
		CLIENT_INSTALL=1
	fi



	# if module installation requested
	if [[ "$args_module_request" -eq 1 ]]; then
		
		# validate value
		if [ -z ${args_module_name+x} ]; then
			lecho_err "Module name must be expected but was not provided." && exit 1
		fi

		# if enable disable mode is set
		#if [ ! -z ${args_enable_disable+x} ]; then

		#	if [ "$args_enable_disable" == "true" ] ||  [ "$args_enable_disable" == "false" ]; then
		#		args_enable_disable_request=1
		#	else
		#		lecho_err "Enable/Disable request is rejected due to incorrect parameter value -> $args_enable_disable." && exit 1
		#	fi

		#fi

	fi


	# validate if special dependency file has to be used
	if [ -n "$args_requirements_file" ]; then
		SPECIFIED_REQUIREMENTS_FILE=$args_requirements_file
		local FILE="$DEFAULT_PROGRAM_PATH/requirements/$SPECIFIED_REQUIREMENTS_FILE"
		if [ ! -f "$FILE" ]; then
			echo "Invalid filename specified for python dependencies. File does not exist!" && exit 1
		fi
	fi	
}



#############################################
# Prints usage instructions for the script
# 
# GLOBALS:
#		
# ARGUMENTS:
#
# RETURN:
#		Prints help message and exits
#############################################
usage() {	
    echo "Usage: bash ./install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -u, --update [MODE]       Update mode:"
    echo "                               -1 : Uninstall program"
    echo "                                0 : Install program"
    echo "                                1 : Update existing installation"
    echo ""
    echo "  -r, --remove              Uninstall Cloudisense completely"
    echo "  -m, --module [NAME]       Install a specific module"
    echo "  -p, --profile [NAME]      Install a specific profile"
    echo "  -d, --dependencies [FILE] Specify a custom requirements file"
    echo "  -i, --install             Perform a fresh installation"
    echo "  -c, --client              Install the client (must be used with -i)"
    echo "  -h, --help                Show this help message and exit"
    echo ""
    echo "Examples:"
    echo "  bash ./install.sh -u 1       # Update existing installation"
    echo "  bash ./install.sh -m module1 # Install module1"
    echo "  bash ./install.sh -p profile # Install profile"
    echo "  bash ./install.sh -i -c      # Install program and client"
    echo "  bash ./install.sh -r         # Remove the program"
    echo ""
    exit 0
}




# shellcheck disable=SC2034
# Grab any shell arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--module)
            if [[ -n "$2" && "$2" != -* ]]; then
                args_module_request=1
                args_module_name="$2"
                shift 2
            else
                echo "Error: Missing module name for -m|--module option."
                usage
            fi
        ;;
        -p|--profile)
            if [[ -n "$2" && "$2" != -* ]]; then
                args_profile_request=1
                args_profile_name="$2"
                shift 2
            else
                echo "Error: Missing profile name for -p|--profile option."
                usage
            fi
        ;;
        -u|--update)
            if [[ -n "$2" && "$2" =~ ^-?[0-1]$ ]]; then
                args_update_request=1
                args_update_mode="$2"
                shift 2
            else
                echo "Error: Invalid update mode for -u|--update. Allowed values: -1, 0, 1."
                usage
            fi
        ;;
        -i|--install)
            args_install_request=1
            args_update_mode=0
            shift
        ;;
        -c|--client)
            if [[ $args_install_request -eq 0 ]]; then
                echo "Error: The -c | --client option must be used with -i | --install."
                usage
            fi
            args_install_client_request=1
            shift
        ;;
        -r|--remove)
            args_update_mode=-1
            shift
        ;;
        -d|--dependencies)
            if [[ -n "$2" && "$2" != -* ]]; then
                args_requirements_file="$2"
                shift 2
            else
                echo "Error: Missing file name for -d|--dependencies option."
                usage
            fi
        ;;
        -h|--help)
            usage
        ;;
        *)
            echo "Error: Unknown option $1"
            usage
        ;;
    esac
done
shift $(( OPTIND - 1 ))


# Permission check
if ! validatePermissions; then
	request_permission;
fi


#############################################
# THIS PROGRAM SHOULD NOT BE RUN WITH `sudo` command#	
#############################################
# Main entry point
main