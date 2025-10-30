# ==============================================================================
# 🏰 Bastille Blockchain - Production Dockerfile
# ==============================================================================
# Multi-stage build for optimal final image
# Stack: Elixir + Rust (post-quantum crypto) + CubDB + Blake3

# ==============================================================================
# Stage 1: Build Environment
# ==============================================================================
FROM ubuntu:22.04 AS builder

# Basic configuration
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install necessary system dependencies
RUN apt-get update && apt-get install -y \
    # Build essentials
    build-essential \
    cmake \
    curl \
    git \
    # Crypto and SSL
    libssl-dev \
    pkg-config \
    # System tools
    ca-certificates \
    gnupg \
    lsb-release \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# Rust Installation (for bastille_crypto NIF)
# ==============================================================================
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && echo 'source ~/.cargo/env' >> ~/.bashrc
ENV PATH="/root/.cargo/bin:${PATH}"

# Rust optimizations for NIFs
ENV RUSTFLAGS="-C target-cpu=native -C opt-level=3"

# ==============================================================================
# Erlang/OTP and Elixir Installation
# ==============================================================================
RUN curl -fSL https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb -o erlang-solutions.deb \
    && dpkg -i erlang-solutions.deb \
    && apt-get update \
    && apt-get install -y \
        esl-erlang=1:26.* \
        elixir=1.15.* \
    && rm -rf /var/lib/apt/lists/* \
    && rm erlang-solutions.deb

# ==============================================================================
# Build workspace configuration
# ==============================================================================
WORKDIR /app

# Install Elixir tools
RUN mix local.hex --force \
    && mix local.rebar --force

# ==============================================================================
# Copy and compile dependencies
# ==============================================================================
# Copy dependency configuration files first
COPY mix.exs mix.lock ./
COPY native/bastille_crypto/Cargo.toml native/bastille_crypto/Cargo.lock ./native/bastille_crypto/

# Install Elixir dependencies
RUN MIX_ENV=prod mix deps.get --only prod

# ==============================================================================
# Copy source code and compilation
# ==============================================================================
# Copy source code
COPY . .

# Copy French BIP39 words
COPY priv/bip39_french.txt priv/

# Compile Rust NIF (post-quantum crypto)
RUN cd native/bastille_crypto && \
    cargo build --release && \
    cd /app

# Elixir compilation with optimizations
RUN MIX_ENV=prod mix compile

# Create release
RUN MIX_ENV=prod mix release bastille

# ==============================================================================
# Stage 2: Runtime Environment (Minimal final image)
# ==============================================================================
FROM ubuntu:22.04 AS runtime

# Basic configuration
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install minimal runtime
RUN apt-get update && apt-get install -y \
    # Erlang runtime
    libssl3 \
    libsctp1 \
    # Network tools
    netbase \
    # Minimal system tools
    ca-certificates \
    curl \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# Bastille Configuration
# ==============================================================================
# Create bastille user (security)
RUN groupadd -r bastille && useradd -r -g bastille -d /opt/bastille -s /bin/bash bastille

# Create data directories
RUN mkdir -p /opt/bastille/data \
    && mkdir -p /opt/bastille/logs \
    && chown -R bastille:bastille /opt/bastille

# Copy release from builder stage
COPY --from=builder --chown=bastille:bastille /app/_build/prod/rel/bastille /opt/bastille/

# User configuration
USER bastille
WORKDIR /opt/bastille

# ==============================================================================
# Network and volume configuration
# ==============================================================================
# Bastille ports
EXPOSE 8333/tcp   # P2P Network
EXPOSE 8332/tcp   # RPC JSON API (optional)

# Volumes for data persistence
VOLUME ["/opt/bastille/data", "/opt/bastille/logs"]

# ==============================================================================
# Environment variables
# ==============================================================================
ENV MIX_ENV=prod
ENV BASTILLE_ENV=prod
ENV BASTILLE_DATA_PATH="/opt/bastille/data"
ENV BASTILLE_LOG_PATH="/opt/bastille/logs"

# Default network configuration
ENV BASTILLE_P2P_PORT=8333
ENV BASTILLE_RPC_PORT=8332
ENV BASTILLE_MAX_PEERS=25

# Erlang VM optimizations
ENV ERL_AFLAGS="+K true +A 64"
ENV ELIXIR_ERL_OPTIONS="+K true +A 64"

# ==============================================================================
# Health and startup scripts
# ==============================================================================
# Health script for Docker/Kubernetes
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8332/health || exit 1

# ==============================================================================
# Startup command
# ==============================================================================
# Entry point with command support
ENTRYPOINT ["/opt/bastille/bin/bastille"]
CMD ["start"]

# ==============================================================================
# Labels and metadata
# ==============================================================================
LABEL maintainer="Bastille Blockchain Team"
LABEL description="🏰 Bastille - Post-Quantum Blockchain with French Revolution Theme"
LABEL version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/laurentf/bastille"
LABEL org.opencontainers.image.title="Bastille Blockchain"
LABEL org.opencontainers.image.description="Revolutionary post-quantum blockchain with democratic consensus"
LABEL org.opencontainers.image.licenses="MIT"

# Stack info
LABEL tech.stack.language="Elixir"
LABEL tech.stack.crypto="Rust (post-quantum)"
LABEL tech.stack.consensus="Blake3 Proof-of-Work"
LABEL tech.stack.storage="CubDB (RocksDB-compatible)"
LABEL tech.crypto.algorithms="Dilithium2,Falcon-512,SPHINCS+"
LABEL blockchain.theme="French Revolution 1789"
LABEL blockchain.token="BAST (Bastille Token)"
LABEL blockchain.reward="1789 BAST per block" 
