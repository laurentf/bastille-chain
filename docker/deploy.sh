#!/bin/bash
# ==============================================================================
# 🏰 Bastille Blockchain - Deployment Script
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Docker paths
DOCKER_DIR="./docker"
DOCKER_COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
DOCKERFILE="$DOCKER_DIR/Dockerfile"

# Functions
print_banner() {
    echo -e "${PURPLE}"
    echo "🏰 =================================================="
    echo "   BASTILLE BLOCKCHAIN DEPLOYMENT"
    echo "   Revolutionary Post-Quantum Blockchain"
    echo "   =================================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}🔧 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_requirements() {
    print_step "Checking requirements..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check docker directory exists
    if [ ! -d "$DOCKER_DIR" ]; then
        print_error "Docker directory not found: $DOCKER_DIR"
        exit 1
    fi
    
    print_success "Requirements OK"
}

create_env_file() {
    if [ ! -f .env ]; then
        print_step "Creating environment file..."
        cat > .env << EOF
# Bastille Blockchain Configuration
BASTILLE_P2P_PORT=8333
BASTILLE_RPC_PORT=8332
MONITOR_PORT=8080
BASTILLE_MAX_PEERS=25
BASTILLE_MINING_ENABLED=false
BASTILLE_MINING_ADDRESS=
BASTILLE_LOG_LEVEL=info
BASTILLE_ENV=prod
EOF
        print_success "Environment file created (.env)"
        print_warning "Edit .env file to customize your configuration"
    else
        print_success "Environment file already exists"
    fi
}

build_image() {
    print_step "Building Bastille Docker image..."
    
    # Build with progress from docker directory
    docker build \
        --progress=plain \
        --target=runtime \
        -f "$DOCKERFILE" \
        -t bastille:latest \
        .
    
    print_success "Docker image built successfully"
}

deploy_node() {
    print_step "Deploying Bastille node..."
    
    # Create volumes
    docker volume create bastille_blockchain_data || true
    docker volume create bastille_blockchain_logs || true
    
    # Deploy with docker-compose from docker directory
    if command -v docker-compose &> /dev/null; then
        docker-compose -f "$DOCKER_COMPOSE_FILE" up -d bastille
    else
        docker compose -f "$DOCKER_COMPOSE_FILE" up -d bastille
    fi
    
    print_success "Bastille node deployed"
}

show_status() {
    print_step "Checking deployment status..."
    
    # Show container status
    if command -v docker-compose &> /dev/null; then
        docker-compose -f "$DOCKER_COMPOSE_FILE" ps
    else
        docker compose -f "$DOCKER_COMPOSE_FILE" ps
    fi
    
    echo ""
    print_step "Useful commands:"
    echo "  View logs:     docker logs bastille-node -f"
    echo "  Stop node:     ./deploy.sh stop"
    echo "  Restart node:  ./deploy.sh restart"
    echo "  Shell access:  docker exec -it bastille-node /bin/bash"
    echo ""
    
    print_step "Network endpoints:"
    echo "  P2P Port:      8333"
    echo "  RPC API:       http://localhost:8332"
    echo "  Monitoring:    http://localhost:8080 (if enabled)"
}

generate_mining_address() {
    print_step "Generating mining address..."
    
    # Run address generation in container
    docker run --rm -it bastille:latest /opt/bastille/bin/bastille eval '
        keypair = Bastille.Shared.Crypto.generate_keypair()
        address = Bastille.Shared.Crypto.generate_bastille_address(keypair)
        IO.puts("Mining address: #{address}")
    '
    
    print_warning "Save this address securely and update BASTILLE_MINING_ADDRESS in .env"
}

show_help() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  build       Build Docker image"
    echo "  deploy      Deploy Bastille node"
    echo "  start       Full deployment (build + deploy)"
    echo "  stop        Stop the node"
    echo "  restart     Restart the node"
    echo "  logs        Show node logs"
    echo "  status      Show deployment status"
    echo "  address     Generate mining address"
    echo "  clean       Remove containers and images"
    echo "  help        Show this help"
    echo ""
    echo "Docker files location: $DOCKER_DIR/"
}

# Main script
main() {
    print_banner
    
    case "${1:-help}" in
        "build")
            check_requirements
            build_image
            ;;
        "deploy")
            check_requirements
            create_env_file
            deploy_node
            show_status
            ;;
        "start")
            check_requirements
            create_env_file
            build_image
            deploy_node
            show_status
            ;;
        "stop")
            if command -v docker-compose &> /dev/null; then
                docker-compose -f "$DOCKER_COMPOSE_FILE" down
            else
                docker compose -f "$DOCKER_COMPOSE_FILE" down
            fi
            print_success "Bastille node stopped"
            ;;
        "restart")
            if command -v docker-compose &> /dev/null; then
                docker-compose -f "$DOCKER_COMPOSE_FILE" restart bastille
            else
                docker compose -f "$DOCKER_COMPOSE_FILE" restart bastille
            fi
            print_success "Bastille node restarted"
            ;;
        "logs")
            docker logs bastille-node -f
            ;;
        "status")
            show_status
            ;;
        "address")
            generate_mining_address
            ;;
        "clean")
            print_step "Cleaning up..."
            if command -v docker-compose &> /dev/null; then
                docker-compose -f "$DOCKER_COMPOSE_FILE" down -v --rmi all
            else
                docker compose -f "$DOCKER_COMPOSE_FILE" down -v --rmi all
            fi
            docker system prune -f
            print_success "Cleanup completed"
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Run main function
main "$@" 
