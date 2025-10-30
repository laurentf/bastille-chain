# 🏰 Bastille Blockchain - Docker Deployment Guide

## Overview

This directory contains all Docker-related files for deploying the Bastille blockchain using Docker, whether for a full node, mining node, or developm4. **Runtime Image**: Minimal image witdocker exec -it bastille-node /opt/bastille/bin/bastille remote
```

## 💾 Data Persistence

### Docker Volumes runtime dependencies

## 📊 Monitoring and Maintenance

### Logsnvironment.

## 📁 Directory Structure

```
docker/
├── Dockerfile              # Multi-stage production Dockerfile
├── docker-compose.yml      # Docker Compose configuration
├── deploy.sh               # Deployment script
└── README.md               # This comprehensive guide
```

## 🔧 Prerequisites

### System Requirements
- **OS**: Linux (Ubuntu 20.04+ recommended), macOS, or Windows with WSL2
- **RAM**: Minimum 2GB, recommended 4GB+
- **Storage**: Minimum 10GB free space
- **Network**: Stable internet connection

### Required Software
```bash
# Docker (version 20.10+)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Docker Compose (version 2.0+)
sudo apt-get install docker-compose-plugin
```

## 🚀 Quick Deployment

### Option 1: From Project Root
```bash
git clone https://github.com/laurentf/bastille.git
cd bastille

# Make deployment script executable
chmod +x docker/deploy.sh

# Complete deployment
./docker/deploy.sh start

# Check status
./docker/deploy.sh status
```

### Option 2: From Docker Directory
```bash
git clone https://github.com/laurentf/bastille.git
cd bastille/docker

# Make script executable
chmod +x deploy.sh

# Complete deployment
./deploy.sh start

# Check status
./deploy.sh status
```

### Verify Deployment
```bash
# Check Docker status
docker ps

# Test node health
curl http://localhost:8332/health
```

## 📋 Available Commands

### Deployment Script
```bash
./deploy.sh [COMMAND]

Commands:
  build       # Build Docker image
  deploy      # Deploy node only
  start       # Complete deployment (build + deploy)
  stop        # Stop the node
  restart     # Restart the node
  logs        # Display logs
  status      # Deployment status
  address     # Generate mining address
  clean       # Clean up completely
  help        # Help
```

### Direct Docker Compose
```bash
# Start (from project root)
docker-compose -f docker/docker-compose.yml up -d

# Stop
docker-compose -f docker/docker-compose.yml down

# Logs
docker-compose -f docker/docker-compose.yml logs -f bastille

# Restart
docker-compose -f docker/docker-compose.yml restart bastille

# From docker directory
cd docker
docker-compose up -d
docker-compose logs -f bastille
```

## ⚙️ Configuration

### Environment Variables (.env in project root)
```bash
# Network configuration
BASTILLE_P2P_PORT=8333          # P2P blockchain port
BASTILLE_RPC_PORT=8332          # JSON-RPC API port
MONITOR_PORT=8080               # Monitoring port (optional)
BASTILLE_MAX_PEERS=25           # Maximum number of peers

# Mining configuration
BASTILLE_MINING_ENABLED=false   # Enable mining (true/false)
BASTILLE_MINING_ADDRESS=        # Mining address

# Logging configuration
BASTILLE_LOG_LEVEL=info         # Log level (debug, info, warning, error)

# Environment
BASTILLE_ENV=prod               # Environment (prod/test)

# New configurations (January 2025)
# - test: mining automatically enabled, f789 prefix, data/test storage
# - prod: mining to be configured manually, 1789 prefix, data/prod storage
```

### Mining Configuration
```bash
# 1. Generate a mining address
./deploy.sh address

# 2. Update .env (in project root)
BASTILLE_MINING_ENABLED=true
BASTILLE_MINING_ADDRESS=1789abc123def456789012345678901234567890

# 3. Restart
./deploy.sh restart
```

## 🌐 Deployment Types

### Full Node (Non-Mining)
```bash
# Configuration .env
BASTILLE_MINING_ENABLED=false
BASTILLE_MAX_PEERS=50

# Deployment
./deploy.sh start
```

### Mining Node
```bash
# 1. Generate address
./deploy.sh address

# 2. Configuration .env
BASTILLE_MINING_ENABLED=true
BASTILLE_MINING_ADDRESS=YourAddressHere
BASTILLE_MAX_PEERS=25

# 3. Deployment
./deploy.sh start
```

### Development Node
```bash
# Configuration .env
BASTILLE_P2P_PORT=18333
BASTILLE_RPC_PORT=18332
BASTILLE_MAX_PEERS=10

# Deployment
./deploy.sh start
```

## 🔧 Docker Architecture

### Multi-stage Build
- **Builder Stage**: Ubuntu 22.04 with Elixir, Rust, and build tools
- **Runtime Stage**: Minimal Ubuntu 22.04 with only runtime dependencies

### Key Features
- **Post-quantum cryptography**: Dilithium2, Falcon512, SPHINCS+
- **Optimized Rust NIFs**: Native performance for crypto operations
- **Secure user**: Non-root `bastille` user
- **Health checks**: Built-in container health monitoring
- **Persistent volumes**: Data and logs persistence
- **Resource limits**: Memory and CPU constraints

### Network Ports
- **8333**: P2P blockchain network
- **8332**: JSON-RPC API (optional)
- **8080**: Monitoring interface (optional)

### Volumes
- `bastille_blockchain_data`: Blockchain data persistence
- `bastille_blockchain_logs`: Application logs

## 🏗️ Build Process

The Dockerfile implements a multi-stage build:

1. **Dependencies Installation**: System packages, Rust, Erlang/OTP, Elixir
2. **Source Compilation**: Rust NIFs and Elixir application
3. **Release Creation**: Production-ready Elixir release
4. **Runtime Image**: Minimal image with only runtime dependencies

## � Monitoring and Maintenance

### Logs
```bash
# Real-time logs
docker logs bastille-node -f

# Recent hours logs
docker logs bastille-node --since=2h

# Logs with timestamps
docker logs bastille-node -t
```

### Health Check
```bash
# Check node health
curl http://localhost:8332/health

# Docker container status
docker ps
docker stats bastille-node

# View health check logs
docker inspect bastille-node | grep -A 10 Health
```

### Shell Access
```bash
# Container access
docker exec -it bastille-node /bin/bash

# Elixir console
docker exec -it bastille-node /opt/bastille/bin/bastille remote
```

## � Data Persistence

### Docker Volumes
```bash
# Data location
docker volume ls | grep bastille

# Backup
docker run --rm -v bastille_blockchain_data:/data -v $(pwd):/backup alpine tar czf /backup/bastille_backup.tar.gz -C /data .

# Restore
docker run --rm -v bastille_blockchain_data:/data -v $(pwd):/backup alpine tar xzf /backup/bastille_backup.tar.gz -C /data
```

### Manual Backup
```bash
# Stop the node
./deploy.sh stop

# Backup
docker cp bastille-node:/opt/bastille/data ./backup_data

# Restart
./deploy.sh start
```

## 🔥 Troubleshooting

### Common Issues

**Port already in use**
```bash
# Change port in .env
BASTILLE_P2P_PORT=18333
BASTILLE_RPC_PORT=18332

# Restart
./deploy.sh restart
```

**Memory shortage**
```bash
# Check memory usage
docker stats bastille-node

# Increase limits in docker-compose.yml
memory: 4G
```

**Rust compilation error**
```bash
# Clean and rebuild
./deploy.sh clean
./deploy.sh build
```

### Advanced Debug
```bash
# Build in debug mode
docker build --target=builder -f Dockerfile -t bastille:debug ..

# Debug container
docker run -it --rm bastille:debug /bin/bash

# Detailed Erlang logs
docker exec -it bastille-node /opt/bastille/bin/bastille remote
```

## 🌍 Production Deployment

### Security
```bash
# Firewall (UFW)
sudo ufw allow 8333/tcp    # P2P
sudo ufw deny 8332/tcp     # RPC (only if necessary)

# Dedicated user
sudo useradd -r -s /bin/false bastille
sudo usermod -aG docker bastille
```

### Optimizations
```bash
# System limits
echo "bastille soft nofile 65536" >> /etc/security/limits.conf
echo "bastille hard nofile 65536" >> /etc/security/limits.conf

# Swap (optional)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Production Monitoring
```bash
# With monitoring enabled
docker-compose --profile monitoring up -d

# Access monitoring
http://localhost:8080
```

## 📈 Performance

### Docker Optimizations
```yaml
# In docker-compose.yml
deploy:
  resources:
    limits:
      memory: 4G      # Adjust according to your system
      cpus: '4.0'     # Adjust according to your system
```

### System Optimizations
```bash
# Kernel parameters
echo 'vm.swappiness=10' >> /etc/sysctl.conf
echo 'net.core.rmem_max=134217728' >> /etc/sysctl.conf
echo 'net.core.wmem_max=134217728' >> /etc/sysctl.conf
```

## 🔒 Security Features

- Non-root user execution
- Minimal runtime image
- Resource constraints
- Health monitoring
- Secure defaults

## 📞 Support

### System Information
```bash
# Docker version
docker version

# Image information
docker images bastille

# Network configuration
docker network ls
docker network inspect bastille_net
```

### Diagnostic Logs
```bash
# Export logs for support
docker logs bastille-node > bastille_logs.txt 2>&1

# System information
docker system df
docker system info
```

### Getting Help

1. Check container logs: `./deploy.sh logs`
2. Verify configuration: `./deploy.sh status`
3. Test connectivity: `curl http://localhost:8332/health`
4. Access container shell: `docker exec -it bastille-node /bin/bash`

---

## 🎉 Congratulations!

Your Bastille node is now deployed and operational. Vive la révolution blockchain! 🏰⚡
