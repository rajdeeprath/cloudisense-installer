#!/bin/bash
#!/usr/bin/bash 


# start containr
sudo docker run -it -v /home/username/Documents/GitHub/cloudisense-installer:/app ubuntu:20.04


## after you are in shell
 cd /app
 chmod +x *.sh
 ./install.sh


