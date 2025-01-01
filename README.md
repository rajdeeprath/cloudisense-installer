# Cloudisense Installer

## Introduction

`cloudisense installer` is a collection of scripts to facilitate smooth and smart installation, updates, and uninstallation of the `cloudisense` software on popular desktop/server Linux systems, as well as ARM systems such as Raspberry Pi/Orange Pi. The script is optimized to detect your system type and install all necessary dependencies required to run `cloudisense`. The installer will prompt for superuser permissions when started. These permissions are used to execute `sudo` level commands.

`cloudisense installer` uses the root's crontab to register itself as an auto-updater. The shell script is then automatically run by the system once a day (at a designated hour) to look for and update the existing `cloudisense` installation. It is important to note that updates can be done manually or automatically. We will discuss various options in the following sections.


## Requirements

The installer script uses a mix of `bash` and `Python 3.7+` to install and update `cloudisense`. While `bash` is universally available, ensure your system supports `Python 3.7 or higher`. If a supported Python version is not found, the installer will attempt to install it using the `apt`/`yum` package manager.

### System Requirements

- **Min CPU Speed**: 1 GHz
- **Min Memory**: 256 MB
- **CPU Architecture**: 64/32-bit Intel/AMD
- **Operating System**: RedHat, Ubuntu 16+, CentOS 7+

**Coming soon**: Support for Raspbian, ARMbian, and Ubuntu for ARM.

## How to Use

### Download the Installer to Your Target System

The installer needs to be downloaded from its GitHub repository, which requires `git` to be installed on your system. Install `git` using the following commands:

#### Installing Git on Debian/Ubuntu

```bash
sudo apt-get update
sudo apt-get install git
```

#### Installing Git on CentOS/RHEL

```bash
sudo yum update
sudo yum install git
```

#### Verify Git Installation

```bash
git --version
```

Clone the repository to your system:

```bash
git clone https://github.com/connessionetech/cloudisense-installer.git
```

### Grant Executable Permissions to the Installer Script

Navigate to the installer directory and make the script executable:

```bash
cd cloudisense-installer && sudo chmod +x *.sh
```

**Now you are ready to run the installer!**

### Basic Usage (Simple Install)

Run the script:

```bash
./install.sh
```

> **Note**: Do not use `sudo` to run the script. It will prompt for superuser permissions as needed.

The script will request the superuser password. Enter the password to allow the script to continue. If everything is set up correctly, the script will install the program and register a `systemd` service named `cloudisense.service`. The service is auto-started post-installation, but you can use `systemctl` to manage it manually:

- **Stop Service**:

  ```bash
  sudo systemctl stop cloudisense.service
  ```

- **Start Service**:

  ```bash
  sudo systemctl start cloudisense.service
  ```

### Arguments

| Flag | Description | Value Type |
|------|-------------|------------|
| `-i` | Run in install mode | NA |
| `-u` | Run in update mode | (0 -> install, 1 -> update, -1 -> remove) |
| `-r` | Run in uninstall mode (targets core unless the module flag is selected) | NA |
| `-m` | Sets module as the subject of operations | NA |
| `-h` | Display usage information | NA |

## Functionality & Mechanisms

### The Manifest

The manifest is a JSON-formatted file that describes the installation of the `cloudisense` core program. It defines various aspects of the installation, such as supported Python versions, release date, release version, package download URL, and package signature (MD5 hash).

Example manifest:

```json
{
  "vendor": "Cloudisense Provider",
  "released": "22-05-12 01:02:39",
  "payload": {
    "version": "1.0.18",
    "format": "zip",
    "platform": {
      "x86_64": {
        "enabled": true,
        "url": "https://example.com/cloudisense.zip",
        "md5": "6dafac4c971e23b0beee60ce92a072f4",
        "dependencies": {
          "interpreters": "3.7,3.8"
        },
        "cleanups": []
      },
      "arm64": {
        "enabled": false,
        "url": "",
        "md5": "",
        "dependencies": {
          "interpreters": ""
        },
        "cleanups": []
      }
    }
  }
}
```

The manifest supports different builds for `x86_64` and `ARM` platforms simultaneously.

- `vendor`: Name of the manifest provider
- `released`: Date and time of manifest publication
- `payload.version`: Build version number
- `payload.url`: Build download URL
- `payload.format`: Package format
- `payload.md5`: MD5 hash signature of the build package
- `payload.dependencies.interpreters`: List of supported Python interpreter versions
- `cleanups`: List of files/folders to remove after an update

### Basic Install Process

#### Command

```bash
./install.sh
```

or

```bash
./install.sh -i
```

The installation process consists of the following steps:

1. Detect the system configuration, operating system, and other details
2. Load variables from the local configuration file (`config.ini`)
3. Install all prerequisites on the system
4. Fetch and parse the build manifest from the cloud
5. Discover or install a supported version of Python (if needed)
6. Download and install the `cloudisense` payload
7. Set up a Python virtual environment
8. Create a `systemd` service for `cloudisense`

### Modules

#### Installing Modules

```bash
./install.sh -i -m <module-name>
```

- `-i`: Run the script in installation mode
- `-m`: Select module operations
- `<module-name>`: Name of the module to install (must exist in the repository)

**Restart the `cloudisense` service for changes to take effect.**

#### Removing Modules

```bash
./install.sh -r -m <module-name>
```

- `-r`: Run the script in removal mode
- `-m`: Select module operations
- `<module-name>`: Name of the module to remove

**Restart the `cloudisense` service for changes to take effect.**

### Uninstall Process

#### Command

```bash
./install.sh -r
```

or

```bash
./install.sh -u -1
```

The uninstallation process includes the following steps:

1. Check the system for an existing installation
2. Remove the `cloudisense` core and modules
3. Remove any Python virtual environment created
4. Remove any `systemd` service created
5. Delete all installation data

## Future Roadmap

- Custom manifest support for custom build installations
- Enable/disable modules
- Custom dependency injection during installation
- Enhanced smart auto-update mechanism
