# Use Python 3.8 as the base image
FROM python:3.8

# Set working directory
WORKDIR /app

# Install dependencies and utilities
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# Clone the installer repository
RUN git clone https://github.com/rajdeeprath/cloudisense-installer /cloudisense-installer

# Grant execution permissions for installer scripts
RUN chmod +x /cloudisense-installer/*.sh

# Run the core installation
RUN /cloudisense-installer/install.sh -i -c

# Install specified modules
RUN /cloudisense-installer/install.sh -i -m "shell,logmonitor,reaction,system,filesystem,rpcgateway,security"

# Expose port 8000
EXPOSE 8000

# Set environment variable
ENV ENV_BIND_HOST=0.0.0.0

# Set the command to run Cloudisense
CMD ["/root/virtualenvs/cloudisense/bin/python3.8", "/root/cloudisense/run.py"]
