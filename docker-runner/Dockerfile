FROM ubuntu:22.04

# Install required tools
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    jq \
    openssh-client \
    bash \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Hetzner Cloud CLI
RUN curl -L https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz \
    | tar xz -C /usr/local/bin hcloud

# Create working directory
WORKDIR /netbird

# Copy deployment scripts
COPY *.sh ./
COPY *.md ./

# Make scripts executable
RUN chmod +x *.sh

# Set up SSH directory
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

# Entry point
ENTRYPOINT ["/bin/bash"]
