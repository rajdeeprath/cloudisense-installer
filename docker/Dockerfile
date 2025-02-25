# Use a minimal base image
FROM python:3.8-slim

# Set working directory
WORKDIR /app

# Install necessary packages with minimal dependencies
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

# Clone the installer repository and grant execution permissions
RUN git clone https://github.com/rajdeeprath/cloudisense-installer /cloudisense-installer && \
    chmod +x /cloudisense-installer/*.sh

# Run the core installation with the environment variable set
RUN PROGRAM_INSTALL_AS_SERVICE=false /cloudisense-installer/install.sh -i -c && \
    /cloudisense-installer/install.sh -i -m "shell,logmonitor,reaction,system,filesystem,rpcgateway,security"

# Remove the installer after installation (in a separate layer)
RUN rm -rf /cloudisense-installer

# Expose port 8000
EXPOSE 8000

# Set additional environment variable
ENV ENV_BIND_HOST=0.0.0.0
ENV ENV_LOG_TARGETS='[{"enabled": true, "name": "fakelog.log", "log_file_path": "/root/log/fakelog.log"}]'


# Create the log directory
RUN mkdir -p /root/log && ln -sf /dev/null /root/log/fakelog.log

# Create a fake log generator script
RUN echo '#!/bin/bash' > /usr/local/bin/fake_log_generator.sh && \
    echo 'while true; do' >> /usr/local/bin/fake_log_generator.sh && \
    echo '  log_time=$(date)' >> /usr/local/bin/fake_log_generator.sh && \
    echo '  log_msg="INFO - Fake log message $(shuf -i 1-100 -n 1)"' >> /usr/local/bin/fake_log_generator.sh && \
    echo '  echo "$log_time - $log_msg" | tee -a /root/log/fakelog.log' >> /usr/local/bin/fake_log_generator.sh && \
    echo '  sleep $(shuf -i 1-10 -n 1)' >> /usr/local/bin/fake_log_generator.sh && \
    echo 'done' >> /usr/local/bin/fake_log_generator.sh && \
    chmod +x /usr/local/bin/fake_log_generator.sh

# Run the log generator in the background & Start Cloudisense
CMD ["/bin/bash", "-c", "/usr/local/bin/fake_log_generator.sh & exec /root/virtualenvs/cloudisense/bin/python3.8 /root/cloudisense/run.py"]
