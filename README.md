# 🏰 Bastille Blockchain

A **post-quantum blockchain** in Elixir/OTP featuring revolutionary **"1789..." addresses**, **14-decimal precision tokens**, and **modern Blake3 Proof-of-Work mining**.

> **🔒 Post-Quantum Ready**: Dilithium, Falcon, SPHINCS+ multi-signature schemes  
> **🏰 Revolutionary Addresses**: "1789..." thematic addressing with f789 for test  
> **🇫🇷 Bastille Day Precision**: 14 decimals (July 14th) with "juillet" smallest unit  
> **⚡ Modern Blake3 Mining**: Fast, secure, and environmentally efficient  
> **🎯 Sequential Mining**: Elegant state machine for robust block production  
> **🚀 85% Complete**: Feature-oriented architecture, comprehensive implementation

## 📊 **Current Implementation Status**

### ✅ **Fully Implemented & Production-Ready**

**🏗️ Core Blockchain Infrastructure:**
- **Blake3 Proof-of-Work**: Sequential mining with dynamic difficulty adjustment every 3-10 blocks
- **4-Database Architecture**: Time-partitioned CubDB storage (blocks, chain, state, index)
- **Memory-Optimized Design**: Fixed memory footprint with 100 recent blocks cached (~200KB), scales independently of user count
- **Transaction Processing**: Automatic fee calculation, mempool management, post-quantum validation

**🔐 Post-Quantum Cryptography:**
- **Triple-Algorithm Security**: Dilithium2, Falcon512, SPHINCS+ with 2/3 threshold signatures
- **Rust NIFs Integration**: High-performance cryptographic operations
- **Address Generation**: Revolutionary "1789..."/"f789..." addressing with mnemonic recovery

**🌐 Networking & Multi-Node:**
- **Protobuf P2P Protocol**: Complete peer-to-peer communication stack
- **Multi-Node Testing**: 3-node local environment (bootstrap, relay, miner roles)
- **Block Propagation**: Real-time block and transaction broadcasting

**🛠️ Developer & User Interface:**
- **8 JSON-RPC Endpoints**: Complete wallet integration (generate, sign, submit, query)
- **Multi-Environment Config**: Test, production, and multi-node configurations
- **Docker Deployment**: Containerization with persistent storage (to be tested - see `docker/README.md`)

**💰 Tokenomics & Mining Rewards:**
- **14-Decimal Precision**: "juillet" smallest unit (July 14th - Bastille Day)
- **Fixed Block Rewards**: 1789 BAST per block (no halving, utility token model)
- **Bitcoin-Style Coinbase Maturity**: Mining rewards mature over time for security
- **Fee-to-Miners**: 100% transaction fees distributed to miners

---

```
🏰 BASTILLE BLOCKCHAIN ROADMAP 🏰
═══════════════════════════════════════

      IMPLEMENTED ✅        →        FUTURE IDEAS 💡
    (Ready to Use!)                (Research Phase)
    
    📦 Core Features                 🚀 Enhancements
    🔐 Security                      🔬 Research  
    🌐 Networking                    🏛️ Governance
    💰 Tokenomics                    🤖 Advanced
```

---

### 🚀 **Future Enhancement Opportunities**
*Note: These are potential research directions and ideas for consideration - not committed roadmap items.*

**⚡ Performance & Scalability:**
- **Parallel Blockchain Sync**: Multi-threaded block download and validation
- **RocksDB Migration**: Higher-performance storage backend for large-scale deployments
- **Horde Implementation**: Horizontal scaling across multiple Elixir nodes/servers
- **State Pruning**: Configurable historical data cleanup for lightweight nodes

**🛡️ Security & Network Hardening:**
- **Anti-DDoS Protection**: Rate limiting, connection throttling, and peer reputation
- **Transport Layer Security**: TLS/Noise protocol encryption for P2P communications
- **MEV Protection**: Mechanisms to prevent miner extractable value exploitation
- **Advanced Peer Discovery**: DHT-based or seed-based peer discovery systems

**🏛️ Governance & Economics:**
- **Community-Voted Burn Mechanisms**: Democratic tokenomics decisions (fee burning, milestone burns, governance-directed deflationary policies)
- **On-Chain Governance**: Proposal and voting system for protocol upgrades
- **Validator Staking**: Proof-of-Stake hybrid or pure PoS transition mechanisms
- **Treasury Management**: Protocol-owned liquidity and development funding

**🤖 Advanced Features:**
- **Smart Contracts**: WebAssembly-based programmable transactions
- **Agentic Integration**: AI-powered transaction optimization and fraud detection
- **Cross-Chain Bridges**: Interoperability with Bitcoin, Ethereum, and other networks
- **Light Client Support**: SPV-style verification for mobile and IoT devices

**📊 Developer & Ecosystem Tools:**
- **Block Explorer**: Web-based blockchain browser and analytics dashboard
- **Advanced Monitoring**: Prometheus/Grafana integration with custom metrics
- **SDK Development**: Libraries for Python, JavaScript, Rust, and Go
- **Wallet Applications**: Desktop, mobile, and browser extension wallets

**🔬 Research & Innovation:**
- **Consensus Evolution Workshop**: Evaluate transition from Blake3 PoW to alternative mechanisms (PoS, DPoS, or hybrid models)
- **ASIC-Resistant PoW**: Memory-hard algorithms (Scrypt, Argon2, Equihash) to maintain mining decentralization
- **Sharding Architecture**: Horizontal blockchain scaling through chain partitioning
- **Carbon Neutrality**: Energy-efficient consensus mechanisms and carbon offsetting

**🎯 Current Status**: Bastille is a **V0 production-ready blockchain** with all core functionality implemented. This represents a solid foundation with essential features working reliably, designed to evolve and grow through community feedback and real-world usage while maintaining extensibility for future enhancements.  

## 🚀 Quick Start

### Prerequisites
- **Elixir 1.18+** and **Erlang/OTP 26+**
- **Rust 1.70+** (for cryptographic NIFs)
- **Git** for version control

### Installation & Setup

**Windows (PowerShell):**
```powershell
# Clone repository
git clone https://github.com/laurentf/bastille-chain
cd bastille-chain

# Install dependencies
mix deps.get

# Compile (including Rust NIFs)
mix compile

# Run tests to verify setup
$env:MIX_ENV="test"; mix compile
$env:MIX_ENV="test"; mix test
```

**Linux/macOS (Bash):**
```bash
# Clone repository
git clone https://github.com/laurentf/bastille-chain
cd bastille-chain

# Install dependencies
mix deps.get

# Compile (including Rust NIFs)
mix compile

# Run tests to verify setup
MIX_ENV=test mix compile
MIX_ENV=test mix test
```

### Start the Node

#### Development/Testing:

**Windows (PowerShell):**
```powershell
# Test environment (f789 addresses, fast mining)
$env:MIX_ENV="test"; mix run --no-halt

# Multi-node testing (see Multi-Node section below)
$env:MIX_ENV="node1"; mix run --no-halt  # Node 1 (bootstrap + mining)
$env:MIX_ENV="node2"; mix run --no-halt  # Node 2 (relay only)  
$env:MIX_ENV="node3"; mix run --no-halt  # Node 3 (mining + relay)
```

**Linux/macOS (Bash):**
```bash
# Test environment (f789 addresses, fast mining)
MIX_ENV=test mix run --no-halt

# Multi-node testing (see Multi-Node section below)
MIX_ENV=node1 mix run --no-halt  # Node 1 (bootstrap + mining)
MIX_ENV=node2 mix run --no-halt  # Node 2 (relay only)  
MIX_ENV=node3 mix run --no-halt  # Node 3 (mining + relay)
```

#### Production Deployment:

**Windows (PowerShell):**
```powershell
# Production environment (1789 addresses, configure mining address first)
$env:MIX_ENV="prod"; mix run --no-halt

# With mining enabled (set your mining address)
$env:BASTILLE_MINING_ADDRESS="1789your_mining_address_here"; $env:MIX_ENV="prod"; mix run --no-halt
```

**Linux/macOS (Bash):**
```bash
# Production environment (1789 addresses, configure mining address first)
MIX_ENV=prod mix run --no-halt

# With mining enabled (set your mining address)
BASTILLE_MINING_ADDRESS="1789your_mining_address_here" MIX_ENV=prod mix run --no-halt
```

**Node Features:**
- **RPC API**: `http://localhost:8332` (8 JSON-RPC 2.0 endpoints)
- **P2P Network**: Port `8333` with protobuf protocol  
- **Storage**: `data/test/`, `data/prod/`, or `data/multinode/nodeN/` (4-database architecture)
- **Blake3 Mining**: Sequential state machine with dynamic difficulty adjustment
- **Memory Efficient**: ~201KB constant GenServer memory usage (scales independently of user count)


## ⛏️ Mining Configuration

Bastille features an **elegant sequential mining system** powered by a GenServer state machine:

### Test Environment
```bash
# Mining automatically enabled with ultra-fast targets
MIX_ENV=test mix run --no-halt
```
- **Address prefix**: `f789...` (44 characters total)
- **Target time**: 10 seconds per block
- **Difficulty**: Auto-adjusting (starts very low for testing)
- **Storage**: `data/test/` directory

### Production Environment  
```bash
# Configure mining address first
MIX_ENV=prod mix run --no-halt
```
- **Address prefix**: `1789...` (44 characters total)  
- **Target time**: 60 seconds per block
- **Difficulty**: Auto-adjusting Bitcoin-like algorithm
- **Storage**: `data/prod/` directory

### Mining Features
- **🎯 Sequential State Machine**: `:idle` → `:mining` → `:idle` cycle
- **⚡ Blake3 Algorithm**: Modern, fast, and secure hashing
- **📊 Dynamic Difficulty**: Automatic adjustment every 3 blocks
- **🔄 Self-Healing**: Robust error handling and restart mechanisms
- **💰 Fixed Rewards**: 1789 BAST per block (protocol constant)

### 💎 Bitcoin-Style Coinbase Maturity System

Bastille implements Bitcoin's proven security model for mining rewards, preventing miners from spending rewards from orphaned blocks:

**🔒 Security Model:**
- **Immature Rewards**: Newly mined rewards are visible but non-spendable
- **Maturation Period**: Configurable waiting periods:
  - **Test/Multinode**: 5 blocks (50 seconds / 2.5 minutes)
  - **Production**: 89 blocks (89 minutes)
- **Automatic Processing**: Each new block processes reward maturity
- **Orphan Protection**: Orphaned blocks automatically lose their rewards

**📊 Balance Types:**
- **Total Balance**: All balance including immature rewards
- **Mature Balance**: Spendable balance (used for transactions)
- **Immature Balance**: Recent mining rewards still maturing

**🔍 Enhanced RPC:**
- `get_balance`: Returns breakdown of all balance types
- `get_immature_coinbases`: Shows pending rewards with countdown

## 🔀 Blockchain Fork Handling & Mini-Reorganizations

Bastille implements intelligent fork resolution with **automatic parent block requests** and **mini-reorganizations** to maintain network consensus while preventing deep chain attacks.

### **🔄 Fork Resolution Workflow**

**🔹 1. Initial Fork Situation**
```
          N
         / \
   N+1a  N+1b   <- temporary fork (competing blocks)
```
Honest nodes choose N+1a (or the first one they receive).
Attacker continues on N+1b in their local fork.

**🔹 2. New Block on Honest Chain**  
```
          N
         / \
   N+1a  N+1b
       \
       N+2a  <- next block on longest chain
```
N+2a points to N+1a → honest nodes accept it.
N+1b becomes a temporary orphan block for most nodes.

**🔹 3. Competing Block Broadcast**
```
          N
         / \
   N+1a  N+1b
       \      \
       N+2a   N+2b?  <- integration attempt
```
N+2b points to N+1b.
Honest nodes don't know N+1b in their main chain.
Block N+2b is rejected/orphaned → never applied.

**🔹 4. Continued Honest Growth**
```
          N
         / \
   N+1a  N+1b
       \      
       N+2a
          \
          N+3a  <- main chain continues
```
The honest chain continues growing → cumulative work increases.
Attacker's chain remains orphaned and rejected.

**🔹 5. Reorg Only Possible with >50% PoW**
Attacker succeeds in mining a longer chain:
```
          N
         / \
   N+1a   N+1b
        \      \
         N+2a   N+2b
           \      \
            N+3a   N+3b
                \    \
                 N+4a N+4b
                        \
                        N+5b  <- longer chain
```
If attacker's chain exceeds cumulative work → all nodes reorg → adopt their chain.
Otherwise, their local chain remains orphaned → no impact on main chain.

### **🛡️ Security Features**

**✅ Automatic Parent Requests:**
- Missing parent blocks are automatically requested from peers
- Anti-spam protection prevents duplicate requests
- Orphan blocks wait temporarily until parents arrive

**✅ Mini-Reorganization (Planned):**
- Limited reorg depth (5-10 blocks maximum) for security
- Automatic rollback when longer valid chain detected
- Coinbase rewards automatically revoked from orphaned blocks
- Prevents deep chain attacks while allowing natural forks

**✅ Honest Majority Protection:**
- Requires >50% network hashpower for successful attacks
- Natural forks resolve quickly through longest chain rule
- Mining rewards secured through maturation periods

## 🎯 RPC API Reference

**🔒 Security Notice**: The RPC API only accepts connections from `127.0.0.1` (localhost) for security reasons. This prevents external access to wallet operations and sensitive blockchain functions. For remote access, use a secure tunnel or proxy.

**🌐 RPC Endpoint**: All operations use JSON-RPC 2.0 at `POST http://localhost:PORT/` where PORT is:
- **Test environment**: `8332` (default)
- **Node1**: `8101` (multi-node testing)
- **Node2**: `8102` (multi-node testing)  
- **Node3**: `8103` (multi-node testing)
- **Production**: `8332` (configurable via `rpc_port` in config files)

### Core Workflow
```
1. generate_address           → Get address + mnemonic + private keys
2. create_unsigned_transaction → Prepare transaction with fee calculation
3. sign_transaction           → Sign with post-quantum private keys (Dilithium, Falcon, SPHINCS+)
4. submit_transaction         → Broadcast to P2P network and add to mempool
5. Mining automatically picks up transactions from mempool and includes in blocks
```

### 📋 API Methods

#### **1. Generate Address**
```json
{
  "jsonrpc": "2.0",
  "method": "generate_address", 
  "params": {},
  "id": 1
}
```

**Response:**
```json
{
  "result": {
    "address": "1789a1b2c3d4...",
    "mnemonic": "révolution liberté égalité...",
    "address_type": "production"
  }
}
```

#### **2. Get Balance (Enhanced)**
```json
{
  "jsonrpc": "2.0",
  "method": "get_balance",
  "params": {"address": "1789a1b2c3d4..."},
  "id": 2
}
```

**Response (with coinbase maturity breakdown):**
```json
{
  "result": {
    "address": "1789a1b2c3d4...",
    "total_balance": 5367000000000000000,
    "mature_balance": 3578000000000000000,
    "immature_balance": 1789000000000000000,
    "balance": 5367000000000000000
  }
}
```

#### **2b. Get Immature Coinbases**
```json
{
  "jsonrpc": "2.0", 
  "method": "get_immature_coinbases",
  "params": {"address": "1789a1b2c3d4..."},
  "id": 2
}
```

**Response:**
```json
{
  "result": {
    "address": "1789a1b2c3d4...",
    "count": 3,
    "total_immature_amount": 5367000000000000000,
    "immature_coinbases": [
      {
        "block_hash": "000abc123...",
        "amount": 1789000000000000000,
        "amount_bast": "1789.00000000000000 BAST",
        "block_height": 15,
        "maturity_height": 35,
        "status": "immature",
        "blocks_remaining": 5,
        "created_at": 1756460441
      }
    ]
  }
}
```

#### **3. Create Transaction**
```json
{
  "jsonrpc": "2.0",
  "method": "create_unsigned_transaction",
  "params": {
    "from": "1789sender...",
    "to": "1789recipient...", 
    "amount": 100.0,
    "data": "optional message"
  },
  "id": 3
}
```

#### **4. Sign Transaction**
```json
{
  "jsonrpc": "2.0",
  "method": "sign_transaction",
  "params": {
    "unsigned_transaction": "base64...",
    "dilithium_key": "private_key_base64",
    "falcon_key": "private_key_base64", 
    "sphincs_key": "private_key_base64"
  },
  "id": 4
}
```

#### **5. Submit Transaction**
```json
{
  "jsonrpc": "2.0",
  "method": "submit_transaction",
  "params": {"signed_transaction": "base64..."},
  "id": 5
}
```

#### **6. Get Node Info**
```json
{
  "jsonrpc": "2.0",
  "method": "get_info",
  "params": {},
  "id": 6
}
```

#### **7. Get Transaction**
```json
{
  "jsonrpc": "2.0",
  "method": "get_transaction", 
  "params": {"hash": "transaction_hash"},
  "id": 7
}
```

#### **8. Extract Keys (Dev/Test)**
```json
{
  "jsonrpc": "2.0",
  "method": "extract_keys_for_signing",
  "params": {
    "mnemonic": ["révolution", "liberté", "égalité", "fraternité", "justice", "tempête", "..."]
  },
  "id": 8
}
```

**Note**: The mnemonic can be provided as either an array of words (recommended) or a single space-separated string.

### Complete Transaction Example

**Windows (PowerShell):**
```powershell
# 1. Generate an address
$response1 = Invoke-RestMethod -Uri "http://localhost:8332/" -Method POST -ContentType "application/json" -Body '{"jsonrpc":"2.0","method":"generate_address","params":{},"id":1}'
$address = $response1.result.address
$mnemonic = $response1.result.mnemonic
Write-Host "Address: $address"

# 2. Check balance  
Invoke-RestMethod -Uri "http://localhost:8332/" -Method POST -ContentType "application/json" -Body "{`"jsonrpc`":`"2.0`",`"method`":`"get_balance`",`"params`":{`"address`":`"$address`"},`"id`":2}"

# 3. Create unsigned transaction
$createTxBody = "{`"jsonrpc`":`"2.0`",`"method`":`"create_unsigned_transaction`",`"params`":{`"from`":`"$address`",`"to`":`"f789recipient_address_here`",`"amount`":100.0,`"data`":`"Test payment`"},`"id`":3}"
$response3 = Invoke-RestMethod -Uri "http://localhost:8332/" -Method POST -ContentType "application/json" -Body $createTxBody

# 4. Extract keys for signing
$keysBody = "{`"jsonrpc`":`"2.0`",`"method`":`"extract_keys_for_signing`",`"params`":{`"mnemonic`":`"$mnemonic`"},`"id`":4}"
$keysResponse = Invoke-RestMethod -Uri "http://localhost:8332/" -Method POST -ContentType "application/json" -Body $keysBody

# 5. Sign transaction
$signBody = "{`"jsonrpc`":`"2.0`",`"method`":`"sign_transaction`",`"params`":{`"unsigned_transaction`":`"$($response3.result.unsigned_transaction)`",`"dilithium_key`":`"$($keysResponse.result.dilithium_private_key)`",`"falcon_key`":`"$($keysResponse.result.falcon_private_key)`",`"sphincs_key`":`"$($keysResponse.result.sphincs_private_key)`"},`"id`":5}"
$signResponse = Invoke-RestMethod -Uri "http://localhost:8332/" -Method POST -ContentType "application/json" -Body $signBody

# 6. Submit transaction
$submitBody = "{`"jsonrpc`":`"2.0`",`"method`":`"submit_transaction`",`"params`":{`"signed_transaction`":`"$($signResponse.result.signed_transaction)`"},`"id`":6}"
Invoke-RestMethod -Uri "http://localhost:8332/" -Method POST -ContentType "application/json" -Body $submitBody
```

**Linux/macOS (Bash with curl):**
```bash
# 1. Generate an address
RESPONSE=$(curl -s -X POST http://localhost:8332/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"generate_address","params":{},"id":1}')
ADDRESS=$(echo $RESPONSE | jq -r '.result.address')
MNEMONIC=$(echo $RESPONSE | jq -r '.result.mnemonic')
echo "Address: $ADDRESS"

# 2. Check balance  
curl -X POST http://localhost:8332/ \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"get_balance\",\"params\":{\"address\":\"$ADDRESS\"},\"id\":2}"

# 3. Create unsigned transaction
CREATE_RESPONSE=$(curl -s -X POST http://localhost:8332/ \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"create_unsigned_transaction\",\"params\":{\"from\":\"$ADDRESS\",\"to\":\"f789recipient_address_here\",\"amount\":100.0,\"data\":\"Test payment\"},\"id\":3}")
UNSIGNED_TX=$(echo $CREATE_RESPONSE | jq -r '.result.unsigned_transaction')

# 4. Extract keys for signing
KEYS_RESPONSE=$(curl -s -X POST http://localhost:8332/ \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"extract_keys_for_signing\",\"params\":{\"mnemonic\":\"$MNEMONIC\"},\"id\":4}")
DILITHIUM_KEY=$(echo $KEYS_RESPONSE | jq -r '.result.dilithium_private_key')
FALCON_KEY=$(echo $KEYS_RESPONSE | jq -r '.result.falcon_private_key')
SPHINCS_KEY=$(echo $KEYS_RESPONSE | jq -r '.result.sphincs_private_key')

# 5. Sign transaction
SIGN_RESPONSE=$(curl -s -X POST http://localhost:8332/ \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"sign_transaction\",\"params\":{\"unsigned_transaction\":\"$UNSIGNED_TX\",\"dilithium_key\":\"$DILITHIUM_KEY\",\"falcon_key\":\"$FALCON_KEY\",\"sphincs_key\":\"$SPHINCS_KEY\"},\"id\":5}")
SIGNED_TX=$(echo $SIGN_RESPONSE | jq -r '.result.signed_transaction')

# 6. Submit transaction
curl -X POST http://localhost:8332/ \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"submit_transaction\",\"params\":{\"signed_transaction\":\"$SIGNED_TX\"},\"id\":6}"
```

### Complete Response Examples

#### Generate Address Response
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "address": "f789a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0",
    "mnemonic": "révolution liberté égalité fraternité justice tempête bastille juillet peuple souverain nation république citoyen patriote tricolore marseillaise voltaire rousseau",
    "address_type": "test"
  }
}
```

#### Get Balance Response
```json
{
  "jsonrpc": "2.0", 
  "id": 2,
  "result": {
    "address": "f789a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0",
    "balance": "178900000000000000",
    "balance_bast": "1789.00000000000000",
    "nonce": 5
  }
}
```

#### Create Unsigned Transaction Response
```json
{
  "jsonrpc": "2.0",
  "id": 3, 
  "result": {
    "unsigned_transaction": "base64_encoded_transaction_data...",
    "transaction_data": {
      "from": "f789sender...",
      "to": "f789recipient...",
      "amount": "10000000000000000",
      "amount_bast": "100.00000000000000", 
      "fee": "2340000",
      "fee_bast": "0.02340000000000",
      "nonce": 6,
      "timestamp": 1756167890,
      "data": "Payment for services"
    }
  }
}
```

#### Node Info Response
```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "version": "1.0.0",
    "network": "testnet",
    "protocol_version": 1,
    "chain_height": 1245,
    "peer_count": 3,
    "mining_status": "active",
    "difficulty": 8,
    "target_block_time": 10000,
    "mempool_size": 12,
    "address_prefix": "f789",
    "consensus": {
      "algorithm": "blake3",
      "type": "proof_of_work",
      "current_difficulty": 8,
      "target_block_time": 10000
    }
  }
}
```

#### Error Response Format
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -1,
    "message": "Insufficient balance",
    "data": {
      "required": "100.00000000000000",
      "available": "50.00000000000000",
      "address": "f789..."
    }
  }
}
```


## 💰 Transaction Fee System

Bastille uses an **automatic fee calculation** based on transaction size and network rules.

### Fee Calculation Formula

```elixir
# Automatic fee calculation
transaction_size = byte_size(serialized_transaction)
fee_per_byte = 10_000 # juillet (0.0001 BAST per byte)
minimum_fee = 100_000 # juillet (0.001 BAST minimum)

final_fee = max(transaction_size × fee_per_byte, minimum_fee)
```

### Fee Examples

#### Small Transaction (~200 bytes)
```
Size: 200 bytes
Calculated: 200 × 10,000 = 2,000,000 juillet
Minimum: 100,000 juillet  
Final Fee: 2,000,000 juillet (0.02 BAST)
```

#### Large Transaction (~500 bytes)  
```
Size: 500 bytes
Calculated: 500 × 10,000 = 5,000,000 juillet
Minimum: 100,000 juillet
Final Fee: 5,000,000 juillet (0.05 BAST)
```

### Fee Structure Rationale

**Why Size-Based Fees?**
- Prevents spam attacks (larger data = higher cost)
- Fair pricing (pay for network resources used)
- Simple and predictable for developers

**Fee Distribution:**
- **100% to miners** (incentivizes mining)
- **No burning** (maintains utility token economics)
- **Minimum floor** (prevents zero-fee spam)

### Transaction Cost Breakdown
```
Total Cost = Amount + Fee
Example: Send 100 BAST
- Amount: 100 BAST
- Fee: ~0.02 BAST (typical small transaction)
- Total Deducted: 100.02 BAST
```


## 🏗️ Architecture

### 4-Database Storage
```
data/
├── test/                    # Test environment
│   ├── blocks202501.cubdb   # Time-partitioned blocks
│   ├── chain.cubdb         # Chain metadata  
│   ├── state.cubdb         # Account balances/nonces
│   ├── index.cubdb         # Transaction indexes
│   └── key_cache/          # Crypto key cache
└── prod/                    # Production environment
    └── (same structure)
```

### Core Modules
- **`Bastille.Features.*`** - Feature-oriented architecture with clean boundaries
  - **`Features.Api.RPC.*`** - JSON-RPC API endpoints and handlers
  - **`Features.Block.*`** - Block creation, validation, and management
  - **`Features.Chain.*`** - Blockchain state and chain management
  - **`Features.Consensus.*`** - Consensus algorithms and validation
  - **`Features.Mining.*`** - Blake3 PoW mining and difficulty adjustment
  - **`Features.P2P.*`** - Protobuf P2P networking, sync, peer management
  - **`Features.Tokenomics.*`** - Token economics, rewards, and conversions
  - **`Features.Transaction.*`** - Transaction processing and validation
- **`Bastille.Infrastructure.*`** - Core infrastructure services
  - **`Infrastructure.Crypto.*`** - Post-quantum cryptography (Dilithium, Falcon, SPHINCS+)
  - **`Infrastructure.Storage.CubDB.*`** - 4-database storage layer (blocks, chain, state, index)
- **`Bastille.Shared.*`** - Shared utilities and common functionality

## ⚡ Tokenomics

- **Name**: BAST (Bastille Token)
- **Decimals**: 14 (July 14th - Bastille Day)  
- **Smallest Unit**: "juillet" (July in French)
- **Block Reward**: 1789 BAST (fixed, no halving)
- **Total Supply**: Unlimited (utility token model like DOGE)
- **Address Format**: `1789...` (mainnet), `f789...` (testnet)

### Economic Model
```
1 BAST = 100,000,000,000,000 juillet (14 decimals)
Block Reward: 1789 BAST per block (protocol constant)
Genesis Supply: 1789 BAST (single genesis block)
Fee Distribution: 100% to miners (incentivizes network security)
Supply Model: Inflationary utility token (no cap, no halving)
```

## 🧪 Testing

### Run Test Suite

#### Windows (PowerShell):
```powershell
# All tests
$env:MIX_ENV="test"; mix test
```

#### Linux/macOS (Bash):
```bash
# All tests
MIX_ENV=test mix test
```

#### Cross-Platform Alternative:
```bash
# Set test environment and run tests
mix test
# Note: Tests automatically use test environment when no MIX_ENV is specified
```

### Test Results
- **300+ Tests**: Comprehensive coverage of all blockchain functionality
- **100% Success Rate**: All tests pass consistently
- **Performance**: 20,000+ addresses/sec, 4M+ Blake3 hashes/sec
- **Security**: Post-quantum cryptography verified with 2/3 threshold signatures

## 🔧 Configuration

### Environment Files
- **`config/config.exs`** - Base configuration and shared settings
- **`config/test.exs`** - Test environment (`data/test/`, `f789` prefix, 2s blocks, mining enabled)
- **`config/prod.exs`** - Production environment (`data/prod/`, `1789` prefix, 10s blocks, mining disabled by default)

### Multi-Node Configuration Files
- **`config/node1.exs`** - Node 1 Bootstrap (`data/multinode/node1/`, port 8101/8001, mining enabled)
- **`config/node2.exs`** - Node 2 Relay (`data/multinode/node2/`, port 8102/8002, mining disabled)  
- **`config/node3.exs`** - Node 3 Miner (`data/multinode/node3/`, port 8103/8003, mining enabled)

### Key Settings
```elixir
# Storage paths (auto-configured by environment)
storage_base_path: "data/test"  # or "data/prod"

# Address prefix (auto-configured by environment)
address_prefix: "f789"  # test: f789, prod: 1789

# Mining (test: enabled, prod: configure manually)
mining: [
  enabled: true,  # true in test, configure for prod
  address: "f7899257e171bdf0630deb199897401935b507520268"
]

# Consensus (environment-specific difficulty targets)
consensus: [
  module: Bastille.Features.Mining.ProofOfWork,
  config: %{
    initial_difficulty: 8,      # 8 for test, higher for prod
    target_block_time: 10000,   # 10s for test, 30s for multinode, 60s for prod  
    max_target: 0x00FF...       # Easy for test, harder for prod
  }
]
```

## 🐳 Docker Deployment

For complete Docker deployment instructions, see **[`docker/README.md`](docker/README.md)** *(to be tested)*.

## 🔍 Code Quality

### Static Analysis
```bash
# Run Credo (production code only)
MIX_ENV=test mix credo --strict

# Generate documentation
mix docs

# Type checking with Dialyzer
mix dialyzer
```

### Code Standards
- **Pattern Matching**: All function parameters use pattern matching for known types
- **English Only**: All comments and documentation in English
- **Emoji Logs**: Structured logging with emoji icons for clarity
- **Type Safety**: Strict struct validation and guards
- **Sequential Mining**: Elegant state machine pattern for robust operations

## 🛠️ Development


### Project Structure
```
lib/bastille/
├── features/                    # Feature-oriented architecture
│   ├── api/rpc/                # JSON-RPC API endpoints and handlers
│   ├── block/                  # Block creation, validation, and management
│   ├── chain/                  # Blockchain state and chain management
│   ├── consensus/              # Consensus algorithms and validation
│   ├── mining/                 # Blake3 PoW mining and difficulty adjustment
│   ├── p2p/                    # P2P networking, sync, peer management
│   ├── tokenomics/             # Token economics, rewards, conversions
│   └── transaction/            # Transaction processing and validation
├── infrastructure/             # Core infrastructure services
│   ├── crypto/                 # Post-quantum cryptography
│   └── storage/cubdb/          # 4-database storage layer
└── shared/                     # Shared utilities and common functionality
```


## 🧪 Multi-Node Local Testing

Run multiple isolated nodes locally with **separate ports and databases** for complete network simulation.

**Multi-node block timing**: 30 seconds per block (slower than test environment to simulate realistic network conditions)

### 🚀 Quick Start Commands

#### Windows (PowerShell):
```powershell
# Terminal 1: Node 1 (Bootstrap + Mining)
$env:MIX_ENV="node1"; mix run --no-halt

# Terminal 2: Node 2 (Relay Only)  
$env:MIX_ENV="node2"; mix run --no-halt

# Terminal 3: Node 3 (Mining + Relay)
$env:MIX_ENV="node3"; mix run --no-halt
```

#### Linux/macOS (Bash):
```bash
# Terminal 1: Node 1 (Bootstrap + Mining)
MIX_ENV=node1 mix run --no-halt

# Terminal 2: Node 2 (Relay Only)  
MIX_ENV=node2 mix run --no-halt

# Terminal 3: Node 3 (Mining + Relay)
MIX_ENV=node3 mix run --no-halt
```

### 📊 Node Configuration Matrix

| Node | RPC Port | P2P Port | Storage Path | Mining | Bootstrap Peers | Role |
|------|----------|----------|--------------|--------|----------------|------|
| **Node 1** | `8101` | `8001` | `data/multinode/node1/` | ✅ Enabled | None (Bootstrap) | Bootstrap + Miner |
| **Node 2** | `8102` | `8002` | `data/multinode/node2/` | ❌ Relay Only | Node 1 (`8001`) | Relay Node |
| **Node 3** | `8103` | `8003` | `data/multinode/node3/` | ✅ Enabled | Node 1 + 2 (`8001`, `8002`) | Miner + Relay |

### 🌐 Network Topology
```
Node 1 (Bootstrap/Miner) ←→ Node 2 (Relay) ←→ Node 3 (Miner/Relay)
    ↖                                           ↗
      ←────────── Direct Connection ──────────→
```

**Network Flow:**
- **Node 1**: Bootstrap node, creates initial blocks, accepts incoming connections
- **Node 2**: Pure relay, connects to Node 1, forwards messages between nodes  
- **Node 3**: Mining node, connects to both Node 1 and Node 2 for redundancy

### ✅ Verify Setup & Test Connectivity

#### 1. Check Node Startup (verify logs show correct paths):
```
Node 1: "Time-partitioned block storage initialized at data/multinode/node1"
Node 2: "Time-partitioned block storage initialized at data/multinode/node2"
Node 3: "Time-partitioned block storage initialized at data/multinode/node3"
```

#### 2. Test RPC Endpoints:
```bash
# Node 1 (Bootstrap + Mining)
curl -X POST http://localhost:8101/ -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"get_info","params":{},"id":1}'

# Node 2 (Relay Only)
curl -X POST http://localhost:8102/ -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"get_info","params":{},"id":1}'

# Node 3 (Mining + Relay)
curl -X POST http://localhost:8103/ -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"get_info","params":{},"id":1}'
```

#### 3. Expected Response (each node should show different peer counts):
```json
{
  "result": {
    "version": "1.0.0",
    "network": "testnet", 
    "chain_height": 1245,
    "peer_count": 2,  // Node 1: 2 peers, Node 2: 1-2 peers, Node 3: 2 peers
    "mining_status": "active", // Nodes 1&3: "active", Node 2: "disabled"
    "address_prefix": "f789"
  }
}
```

### 🔧 Node Configuration Details

Each node has its own configuration file in `config/`:
- **`config/node1.exs`**: Bootstrap node with mining enabled
- **`config/node2.exs`**: Relay-only node (no mining)
- **`config/node3.exs`**: Mining node with multiple bootstrap peers

**Key Configuration Differences:**
```elixir
# Node 1 (Bootstrap)
p2p: [bootstrap_peers: []]           # No peers (bootstrap)
mining: [enabled: true]              # Mining enabled

# Node 2 (Relay)  
p2p: [bootstrap_peers: ["127.0.0.1:8001"]]  # Connects to Node 1
mining: [enabled: false]             # No mining

# Node 3 (Mining + Relay)
p2p: [bootstrap_peers: ["127.0.0.1:8001", "127.0.0.1:8002"]]  # Both peers
mining: [enabled: true]              # Mining enabled
```

### 🧪 Testing Scenarios

#### 1. Block Propagation Test:
Start all 3 nodes and verify blocks created by Node 1 appear on Node 2 and Node 3.

#### 2. Network Resilience Test:
- Stop Node 2 (relay) → Nodes 1 & 3 should maintain direct connection
- Stop Node 1 (bootstrap) → Node 3 should continue via Node 2

#### 3. Mining Distribution Test:
Both Node 1 and Node 3 mine blocks. Verify blocks from both miners propagate correctly.

#### 4. Database Isolation Test:
Verify each node maintains completely separate blockchain state in its own directory.

**Each node uses completely isolated databases and unique ports to simulate a real distributed network on localhost.**


## 🤝 Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Follow code standards in `.cursorules` (yes, you can use AI - you'll use it anyway, right? 😉)
4. Write comprehensive tests
5. Ensure all tests pass: `mix test`
6. Run Credo: `MIX_ENV=test mix credo --strict`
7. Submit pull request

## 📄 License

This project is licensed under the MIT License - see LICENSE file for details.

## 🙏 Acknowledgments

- **French Revolution** - Inspiration for thematic design (1789, Bastille Day)
- **Elixir/OTP** - Robust foundation for distributed systems
- **Post-Quantum Cryptography** - Future-proof security standards
- **Blake3** - Modern, fast, and secure hashing algorithm

---

**🏰 Vive la Révolution ! Build the future of post-quantum blockchain with Bastille.**