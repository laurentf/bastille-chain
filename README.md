# 🏰 Bastille Blockchain

A **post-quantum blockchain** written in Elixir/OTP, with a French
Revolution theme: **`1789...`** addresses (`f789...` on testnet), **14
decimals** (Bastille Day, July 14th), **`juillet`** as the smallest unit,
and **Blake3 Proof-of-Work** mining.

> **Status: v0 — proof of concept that runs, not a production chain.**
> The core loop works (mining, propagation, RPC, multi-node sync) and a
> first round of stabilization + security fixes has landed. A few items
> still stand between this and a public testnet, and more before mainnet
> (see "What does NOT work yet" below).

## What works today

- **Multi-node local network** (`MIX_ENV=node1|node2|node3`) : 3 nodes, 2
  peers each, blocks propagate, RPC stays responsive while mining.
- **310 unit tests** stable across consecutive runs (~1.5s).
- **4-database CubDB storage** (blocks time-partitioned by month, chain
  metadata, account state, fast lookups) with batch atomicity inside each
  DB.
- **PoW Blake3 mining** with dynamic difficulty adjustment. Hot loop and
  consensus state read via `:persistent_term` snapshot, so mining doesn't
  block the Engine GenServer or RPC reads.
- **2/3 post-quantum signatures** (Dilithium2 + Falcon512 + SPHINCS+) via
  Rust NIFs. Signed message binds `from`, `to`, `amount`, `fee`, `nonce`,
  `timestamp`, `data` length + bytes, and the network chain id — no
  silent fee/payload tampering, no cross-network replay.
- **EIP-55-inspired address checksum** (SHA-256 based). Canonical form is
  lowercase; the RPC also returns a mixed-case `address_display` for
  wallets, and rejects mistyped mixed-case input via the embedded
  checksum.
- **JSON-RPC 2.0 API** (`localhost`-only) for wallet flow:
  `generate_address`, `create_unsigned_transaction`, `sign_transaction`,
  `submit_transaction`, `get_balance`, `get_info`, `get_transaction`,
  `extract_keys_for_signing` (dev/test only). Wire format is a strict
  JSON map (binaries hex-encoded) — the RPC never accepts
  `:erlang.binary_to_term/1` input (closes a hostile-deserialization
  vector).
- **`get_transaction`** resolves both pending (mempool) and confirmed
  (block index) transactions, with confirmations + block info.
- **Mempool validation** runs in the caller's process via a pure
  `Chain.TransactionValidator` — no `GenServer.call(Chain, …)` queueing
  behind a long `add_block`.

## What does NOT work yet

- **Mnemonic-based key derivation is not actually deterministic.** The
  Rust NIF generates fresh random keys and caches them on disk under a
  hash of the seed. Recovery from mnemonic on a different machine yields
  different keys. → Bloquant for any testnet with shared addresses.
- **No chain reorganization.** No cumulative work tracking, no rollback.
  Two miners producing in parallel can diverge silently (tolerable on a
  controlled topology, a blocker for an open multi-miner testnet).
- **Transactions do not propagate over P2P.** Only blocks do. Mempool is
  per-node ; multi-miner setups are de facto broken until this lands.
- **P2P is plaintext TCP.** No encryption, no peer authentication.
  Tolerable behind a whitelisted bootstrap topology, not OK for an open
  testnet.
- **No coinbase maturity.** Was implemented earlier as a Bitcoin copy,
  but the orphan-protection it provides has no teeth without chain
  reorganization (which Bastille doesn't have). Removed for simplicity
  — to be re-added or skipped Ethereum-PoW style once reorg lands.
  Balances are spendable as soon as they are credited.
- **Mining serialization and P2P header payloads still use
  `:erlang.term_to_binary`** — fine for an Elixir-only network, a
  blocker for any other-language client that needs to validate the
  chain. (RPC inputs no longer use it, since Sprint 1.3.)

---

## 🚀 Quick start

### Prerequisites
- Elixir 1.18+ / Erlang/OTP 27+
- Rust 1.70+ (for the crypto NIF)
- Git

### Install, compile, test

**PowerShell (Windows):**
```powershell
git clone https://github.com/your-org/bastille.git
cd bastille
mix deps.get
mix compile
$env:MIX_ENV="test"; mix test
```

**Bash (Linux/macOS):**
```bash
git clone https://github.com/your-org/bastille.git
cd bastille
mix deps.get
mix compile
MIX_ENV=test mix test
```

### Run a single node (testnet config)

**PowerShell:**
```powershell
$env:MIX_ENV="test"; mix run --no-halt
```

**Bash:**
```bash
MIX_ENV=test mix run --no-halt
```

That gives you:
- RPC on `http://localhost:8332`
- P2P on `localhost:18333` (test env, isolated)
- Storage in `data/test/`
- Mining enabled, address `f789...miner...` hardcoded for convenience

### Run 3 nodes locally (`node1` + `node2` + `node3`)

Three separate terminals.

**PowerShell:**
```powershell
# Terminal 1: bootstrap + miner
$env:MIX_ENV="node1"; mix run --no-halt

# Terminal 2: relay only (no mining)
$env:MIX_ENV="node2"; mix run --no-halt

# Terminal 3: second miner, peers with both above
$env:MIX_ENV="node3"; mix run --no-halt
```

**Bash:**
```bash
MIX_ENV=node1 mix run --no-halt   # terminal 1
MIX_ENV=node2 mix run --no-halt   # terminal 2
MIX_ENV=node3 mix run --no-halt   # terminal 3
```

| Node | RPC port | P2P port | Storage | Role |
|---|---|---|---|---|
| node1 | 8101 | 8001 | `data/multinode/node1/` | bootstrap + miner |
| node2 | 8102 | 8002 | `data/multinode/node2/` | relay only |
| node3 | 8103 | 8003 | `data/multinode/node3/` | miner + relay |

Verify they're talking to each other:
```bash
for p in 8101 8102 8103; do
  curl -s -X POST http://127.0.0.1:$p/ \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"get_info","params":{},"id":1}' \
    | grep -oE '"height":[0-9]+|"connected_peers":[0-9]+'
done
```

All three should report the same height and `connected_peers >= 1`.

---

## 🎯 RPC API

JSON-RPC 2.0 over `POST http://localhost:<rpc_port>/`. **Bound to
`127.0.0.1` only** — no remote access by design at this stage. Available
methods:

| Method | Purpose |
|---|---|
| `generate_address` | Create a new mnemonic + derive address |
| `get_balance` | Get balance (juillet) and nonce of an address |
| `get_info` | Node status (chain, mining, consensus, mempool, network) |
| `get_transaction` | Look up a tx by hash (mempool only at the moment) |
| `create_unsigned_transaction` | Prepare an unsigned tx ready for offline signing |
| `sign_transaction` | Sign an unsigned tx with the 3 private keys |
| `submit_transaction` | Broadcast a signed tx to the mempool / P2P |
| `extract_keys_for_signing` | **Dev/test only** — derive private keys from a mnemonic |

### Wallet flow

```
1. generate_address                → address (canonical + display) + 24-word French mnemonic
2. extract_keys_for_signing        → 3 private keys, base64 (dev/test only)
3. create_unsigned_transaction     → unsigned tx as a JSON map
4. sign_transaction                → signed tx as a JSON map (includes 2/3 PQ signature)
5. submit_transaction              → broadcast + add to mempool
6. Wait for a miner to include it in a block.

> **Wire format**: unsigned/signed transactions cross the RPC boundary as
> JSON objects (binaries hex-encoded). The RPC layer NEVER accepts
> `:erlang.binary_to_term/1` input — that's a hostile-deserialization
> vector. See `Bastille.Features.Transaction.Transaction.from_json_map/1`
> for the strict parser.
```

### Examples

#### Generate an address
```bash
curl -s -X POST http://localhost:8332/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"generate_address","params":{},"id":1}'
```

Response:
```json
{
  "jsonrpc": "2.0", "id": 1,
  "result": {
    "address": "f7891a2b3c...d8e9f0",
    "mnemonic": "révolution liberté égalité fraternité ...",
    "mnemonic_phrase": "..."
  }
}
```

#### Get balance
```bash
curl -s -X POST http://localhost:8332/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"get_balance","params":{"address":"f789..."},"id":2}'
```

Response:
```json
{
  "jsonrpc": "2.0", "id": 2,
  "result": { "address": "f789...", "balance": 178900000000000000, "nonce": 0 }
}
```
The balance is in `juillet` (1 BAST = 10¹⁴ juillet).

#### Get node info
```bash
curl -s -X POST http://localhost:8332/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"get_info","params":{},"id":3}'
```

The response contains `chain.height`, `chain.head_block`, `mining`,
`consensus.current_difficulty`, `mempool.size`, `network.connected_peers`,
etc.

#### Full transaction flow (Bash with `jq`)
```bash
# 1. Generate
GEN=$(curl -s -X POST http://localhost:8332/ -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"generate_address","params":{},"id":1}')
ADDR=$(echo "$GEN" | jq -r .result.address)
MNEMONIC=$(echo "$GEN" | jq -r .result.mnemonic_phrase)

# 2. Extract private keys (dev/test only)
KEYS=$(curl -s -X POST http://localhost:8332/ -H "Content-Type: application/json" \
  -d "$(jq -nc --arg m "$MNEMONIC" '{jsonrpc:"2.0",method:"extract_keys_for_signing",params:{mnemonic:$m},id:2}')")
DIL=$(echo "$KEYS" | jq -r '.result.sign_transaction_payload.dilithium_key')
FAL=$(echo "$KEYS" | jq -r '.result.sign_transaction_payload.falcon_key')
SPH=$(echo "$KEYS" | jq -r '.result.sign_transaction_payload.sphincs_key')

# 3. Create an unsigned transaction. The result is a JSON object — keep it as
#    a JSON value, don't try to decode/re-encode it.
RECIPIENT="f789$(printf 'aaaa%.0s' {1..10})"
UNSIGNED=$(curl -s -X POST http://localhost:8332/ -H "Content-Type: application/json" \
  -d "$(jq -nc --arg from "$ADDR" --arg to "$RECIPIENT" \
        '{jsonrpc:"2.0",method:"create_unsigned_transaction",
          params:{from:$from,to:$to,amount:1.0},id:3}')" \
  | jq '.result.unsigned_transaction')

# 4. Sign it. Pass the unsigned JSON object directly as the value of
#    `unsigned_transaction`.
SIGNED=$(curl -s -X POST http://localhost:8332/ -H "Content-Type: application/json" \
  -d "$(jq -nc --argjson tx "$UNSIGNED" --arg dil "$DIL" --arg fal "$FAL" --arg sph "$SPH" \
        '{jsonrpc:"2.0",method:"sign_transaction",
          params:{unsigned_transaction:$tx,dilithium_key:$dil,falcon_key:$fal,sphincs_key:$sph},
          id:4}')" \
  | jq '.result.signed_transaction')

# 5. Submit
curl -s -X POST http://localhost:8332/ -H "Content-Type: application/json" \
  -d "$(jq -nc --argjson tx "$SIGNED" \
        '{jsonrpc:"2.0",method:"submit_transaction",
          params:{signed_transaction:$tx},id:5}')"
```

---

## ⛏️ Mining

- Algorithm: **Blake3 single-hash** Proof-of-Work.
- Block reward: **1789 BAST per block, fixed, no halving** (utility token
  model).
- Target block time:
  - test : 10s
  - multinode (node1/2/3) : 30s
  - prod : 60s
- Difficulty adjustment is delegated to the consensus engine
  (Bitcoin-like 4× max change, configurable interval).
- Mining runs in `MiningCoordinator`'s handler but uses a snapshot of
  consensus state via `:persistent_term`, so the Engine and the RPC stay
  responsive during the hot loop.

### Production mining
The prod config (`config/prod.exs`) ships with mining **disabled**. To
enable, set your mining address and start:

```bash
BASTILLE_MINING_ADDRESS="1789youraddresshere..." MIX_ENV=prod mix run --no-halt
```

> **Note**: `config/prod.exs` has a fixed `max_target` for production that
> matches Bitcoin-style difficulty. The default `initial_difficulty: 4` is
> mostly symbolic — the dynamic adjustment will bring it to whatever the
> network needs.

---

## 💰 Tokenomics

- Name: **BAST** (Bastille Token)
- Smallest unit: **`juillet`** (July in French, for July 14th)
- Decimals: **14** → 1 BAST = 100 000 000 000 000 juillet
- Block reward: **1789 BAST** per block, fixed
- No halving, no max supply (utility token like DOGE)
- Address prefix: **`1789...`** (mainnet) / **`f789...`** (testnet)
- Transaction fee: `max(size * 10000, 100000)` juillet, auto-calculated.
  100% goes to the miner. Burn mechanism mentioned in some old code paths
  is currently a stub returning 0 — to be cleaned up.

---

## 🏗️ Architecture (1-pager)

```
lib/bastille/
├── features/
│   ├── api/rpc/                # JSON-RPC handlers
│   ├── block/                  # Block struct + genesis + merkle
│   ├── chain/                  # Chain GenServer + orphan manager
│   ├── consensus/              # Behaviour + Engine
│   ├── mining/                 # PoW + MiningCoordinator
│   ├── p2p/                    # codec, messages, peer, node, sync
│   ├── tokenomics/             # Token + conversions
│   └── transaction/            # Transaction + mempool
├── infrastructure/
│   ├── crypto/                 # Rust NIF wrapper
│   └── storage/cubdb/          # 4 CubDB GenServers (blocks/chain/state/index)
└── shared/                     # address, mnemonic, seed, crypto utils
```

Storage layout on disk:
```
data/<env>/
├── blocks202605.cubdb    # blocks for May 2026 (one file per month)
├── blocks202606.cubdb
├── chain.cubdb           # height ↔ hash mapping + metadata
├── state.cubdb           # balances, nonces, pubkeys per address
├── index.cubdb           # tx hash → location, addr → tx list
└── key_cache/            # ⚠️ Rust NIF random-key cache (cf. caveats)
```

Supervision tree is `Bastille.Application` (`one_for_one`,
`max_restarts: 100`, `max_seconds: 10`) supervising the 4 storage
GenServers, `Chain`, `Mempool`, `OrphanManager`, `Consensus.Engine`,
`MiningCoordinator`, `P2P.Node`, `P2P.Sync` and `RPC`.

---

## 🧪 Testing & quality

```bash
MIX_ENV=test mix test               # 300+ tests
MIX_ENV=test mix credo --strict     # static analysis
mix dialyzer                         # type checking
mix docs                             # generate ex_doc
```

---

## 🛣️ Roadmap

### v0.1 — "runs locally" — ✅ done
Multi-node sync, mining, RPC reactive while mining, tests green.

### v0.2 — "private testnet" — in progress
- ✅ Signed message binds `fee`, `data`, `chain_id` (Sprint 1.1)
- ✅ Address checksum, EIP-55-inspired (Sprint 1.2)
- ✅ JSON wire format on RPC, no `:erlang.binary_to_term/1` on input (Sprint 1.3)
- ✅ Confirmed-tx lookup in `get_transaction` (Sprint 1.4)
- ✅ Mempool decoupled from Chain GenServer (Sprint 1.5)
- ⬜ Real deterministic PQ key derivation from mnemonic (replace the random-cache NIF).
- ⬜ P2P transaction relay (so multi-miner mempool actually works).

### v0.3 — "public testnet" — planned
- Canonical wire format (drop `erlang.term_to_binary` everywhere).
- Mempool sync, basic RBF.
- Parallel block download / IBD.
- DoS hardening, peer scoring, banlist.
- WebSocket subscription RPC.

### v1.0 — "mainnet candidate"
- Chain reorganization (cumulative work + state rollback) — at which
  point we'll revisit whether coinbase maturity makes sense for an
  account-based model (Ethereum-PoW didn't have it).
- State root / Merkle Patricia Trie (for SPV, light clients, sharding).
- Authenticated P2P (Noise XX or mTLS).
- Multi-thread mining.
- WAL / journal for cross-DB atomic block-add.
- API auth + rate limiting.
- External crypto audit + months of running testnet without incident.

---

## 🐳 Docker

Docker assets live in `docker/`. They have **not been validated** against
the current code — treat them as a starting point, not a turnkey recipe.
See [`docker/README.md`](./docker/README.md).

---

## 🤝 Contributing

1. Fork.
2. Branch: `git checkout -b feature/whatever`.
3. Follow `.cursorrules` — pattern matching in heads, `with` over nested
   `case`, English-only comments, no aspirational claims in code.
4. Tests must stay green: `MIX_ENV=test mix test`.
5. PR.

## 📄 License

MIT — see `LICENSE` if present (TODO: add the actual LICENSE file).

---

**🏰 Vive la révolution !**
