# Keystone Development Container
FROM nixos/nix:latest

# Install basic utilities and enable flakes
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Create a non-root user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN addgroup -g $USER_GID $USERNAME \
    && adduser -D -u $USER_UID -G $USERNAME $USERNAME \
    && mkdir -p /etc/sudoers.d \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Install sudo for the user
RUN nix-env -iA nixpkgs.sudo

# Set working directory
WORKDIR /workspace

# Switch to the non-root user
USER $USERNAME

# Pre-build the dev environment to speed up container creation
# This will be overridden by the actual workspace when the container starts
COPY --chown=$USERNAME:$USERNAME flake.nix flake.lock /tmp/keystone/
RUN cd /tmp/keystone && nix develop --command echo "Dev environment cached" || true

# Default command
CMD ["/bin/sh"]
