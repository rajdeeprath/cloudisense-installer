#!/bin/bash
#!/usr/bin/bash 


# start containr
sudo docker run --rm -it -v "$PWD:/app" -w /app python:3.8-slim bash

## after you are in shell
 chmod +x *.sh
 ./install.sh


