### Update Process
---

**COMMAND**

```bash
./install.sh -u 1
```

From the installer's standpoint, the `update` process can broadly be broken down into the following steps:

* Detect the current instalaltion and configurations
* Fetch and parse the build manifestfrom cloud
* Determine whether installation is updatable or not
* Download the payload to disk
* Use Smartmerge to merge old and new configuration files properly to prepare the latest payload for deploymenmmt.
* Check & create python virtual environment as needed.
* Install dependencies for latest build 
* Update the systemd service if necessary


#### SmartMerge
---

`Smartmerge` is a python program that is used to merge configuration files from existing version of the software and the latest version of the software downloaded, without losing the edited configurations. Smartmerge script reuses the cloudisense virtual environment for its dependencies and hence does not require setting up a new python virtual environment.

#### AutoUpdater (experimental)

Autoupdate is a useful (experimental) feature of this installer which lets you update your existing cloudisense installation automatically in an unattended manner.

To activate autoupdater :>

1. Make sure the install.sh script has administrative rights and permissions to execute.
2. Create a CRON job in the linux system to run the bash script as the administrator automatically once a day at a specific time.

The cron job would look like this :

```bash

TO DO

```