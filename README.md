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
- **348 unit tests** stable across consecutive runs (~1.5s).
- **4-database CubDB storage** (blocks time-partitioned by month, chain
  metadata, account state, fast lookups) with batch atomicity inside each
  DB.
- **PoW Blake3 mining** with dynamic difficulty adjustment. Hot loop and
  consensus state read via `:persistent_term` snapshot, so mining doesn't
  block the Engine GenServer or RPC reads.
- **2/3 post-quantum signatures** — ML-DSA-44 (Dilithium2) + FN-DSA-512
  (Falcon512) + SLH-DSA-SHAKE-128f (SPHINCS+) via Rust NIFs. Signed message
  binds `from`, `to`, `amount`, `fee`, `nonce`, `timestamp`, `data` length +
  bytes, and the network chain id — no silent fee/payload tampering, no
  cross-network replay.
- **Deterministic BIP39 mnemonic recovery.** 24-word French mnemonic →
  `PBKDF2-HMAC-SHA512` master seed → per-algorithm `HKDF-SHA256` sub-seeds →
  keypairs, purely (no disk cache). The same phrase restores the same address on
  any machine or a fresh data directory; a single mistyped word is caught by the
  BIP39 checksum. Dilithium/SPHINCS+ use the FIPS `keygen_internal` seed APIs,
  Falcon a ChaCha20-seeded generator; the whole chain is frozen by known-answer
  vectors (`priv/test/kat_keys.json`). See `docs/key_derivation_design.md`.
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
- **P2P transaction propagation.** A transaction submitted to one node is
  relayed (`inv` → `getdata` → `tx`) to its peers, added to their mempools and
  re-broadcast, so any miner can include it. Incoming txs are rebuilt through a
  validating `TransactionConverter` and de-duplicated via `transactions_seen`.
- **Chain reorganization.** A heavier competing fork is detected (cumulative
  work), its common ancestor found over P2P, and then *adopted*: the chain rolls
  back to the ancestor (per-block state journal) and the fork is applied block by
  block. The switch is all-or-nothing — a fork block that fails validation aborts
  the reorg and restores the original chain untouched. Orphaned coinbases revert
  via the journal; orphaned non-coinbase txs are re-injected into the mempool.

## What does NOT work yet

- **Chain reorganization is single-fork.** The switch works and its edge cases
  are tested (invalid-midway abort, depth limit, cascaded double-reorg, reorg
  racing a freshly-mined block — Sprint 4.5). But only one competing fork is
  chased at a time, the fork point must be within the last 100 blocks (the
  reorg/journal window), and true cross-node convergence is only checked
  manually on the 3-node topology — there's no automated multinode test
  (singleton GenServers preclude an in-VM 2-node network). Fine on a controlled
  topology; not yet proven on an open multi-miner testnet.
- **P2P is plaintext TCP.** No encryption, no peer authentication.
  Tolerable behind a whitelisted bootstrap topology, not OK for an open
  testnet.
- **No coinbase maturity — by decision (Sprint 4.6), Ethereum-PoW style.** Block
  rewards are spendable as soon as credited. A reorg that orphans a coinbase also
  drops any spend of it — orphaned txs are re-validated on re-injection and fail on
  insufficient balance — so the post-reorg state stays consistent (no cascade; the
  thing Bitcoin's 100-block maturity guards against is a UTXO-model concern). Reorg
  depth is bounded by `MAX_REORG_DEPTH` (100). The only residual risk is a recipient
  acting on a shallowly-confirmed credit, mitigated by confirmation depth as on any
  chain. Full rationale in `IMPROVEMENT_PLAN.md` §4.6.
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

### Submit a tx and watch it propagate

With the 3 nodes running, build and submit a signed transaction to **node1**
(RPC 8101) via the wallet flow (`generate_address` →
`create_unsigned_transaction` → `sign_transaction` → `submit_transaction`).

On `submit_transaction`, node1 advertises the tx to its peers (`inv`). Watch the
node2 and node3 logs for the relay handshake completing:

```
📦 Received tx from 127.0.0.1:8001
✅ Tx 1a2b3c4d... added to mempool
```

The transaction is now in every node's mempool, so any miner (node1 or node3)
can include it in the next block. A node that already holds the tx logs
`🔄 Tx ... already seen, not relaying` and stops — flooding stays loop-free via
`transactions_seen`.

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
└── index.cubdb           # tx hash → location, addr → tx list
```

Supervision tree is `Bastille.Application` (`one_for_one`,
`max_restarts: 100`, `max_seconds: 10`) supervising the 4 storage
GenServers, `Chain`, `Mempool`, `OrphanManager`, `Consensus.Engine`,
`MiningCoordinator`, `P2P.Node`, `P2P.Sync` and `RPC`.

---

## 🧪 Testing & quality

```bash
MIX_ENV=test mix test               # 350+ tests (add --include integration for the full set)
mix format --check-formatted        # formatting (.formatter.exs / .editorconfig)
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
- ✅ Deterministic PQ key derivation from mnemonic — ml-dsa / slh-dsa / fn-dsa, no cache (Sprint 3.2).
- ✅ P2P transaction relay (so multi-miner mempool actually works).
- ✅ Chain reorganization — cumulative work, state-rollback journal,
  common-ancestor search, transactional rollback + reapply, edge-case tests, and
  the coinbase-maturity decision (Sprint 4.1–4.6). Automated cross-node
  convergence test still open.

### v0.3 — "public testnet" — planned
- Canonical wire format (drop `erlang.term_to_binary` everywhere).
- Mempool sync, basic RBF.
- Parallel block download / IBD.
- DoS hardening, peer scoring, banlist.
- WebSocket subscription RPC.

### v1.0 — "mainnet candidate"
- Multinode reorg hardening (automated cross-node convergence test). The
  single-fork reorg core landed in v0.2 (Sprint 4.1–4.6); coinbase maturity was
  decided against for the account model (§4.6).
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
3. Follow `CONVENTIONS.md` — pattern matching in heads, `with` over nested
   `case`, English-only comments, no aspirational claims in code.
4. Tests must stay green: `MIX_ENV=test mix test`.
5. PR.

## 📄 License

MIT — see `LICENSE` if present (TODO: add the actual LICENSE file).

---

**🏰 Vive la révolution !**
