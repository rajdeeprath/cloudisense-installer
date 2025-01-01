#!/bin/bash
#!/usr/bin/bash 


# 1. Install guest additions on guest os via gui

# 2. Map guest port 22 to host port 3022 then ssh into it
ssh -p 3022 username@127.0.0.1

# 3. After successful login do this
cd ~
sudo mount -t vboxsf cloudisense-installer /mnt/shared
cd /mnt/shared
chmod +x *.sh
./install.sh
