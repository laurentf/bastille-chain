# 🏰 Bastille — Deep technical review (v0)

> **Context**: hands-on audit performed on branch `v0`, after the
> bloquant fixes (CoinbaseMaturity deadlock, hardcoded
> `validate_address_format`, difficulty explosion, RPC blocked during
> mining, broken `prod.exs`, genesis `merkle_root` being a struct
> instead of a binary, removal of the premature coinbase maturity —
> see §4.3). Goal: state of the base, what holds, what does not, and
> the path toward **v1 testnet ready** then **v1 mainnet ready**.
>
> **Note (2026-05): this audit is a snapshot at v0. Several blockers
> listed here have since been fixed in Sprint 1 — see
> `IMPROVEMENT_PLAN.md` for the up-to-date status. The structure of the
> review (per-feature analysis, severities, effort estimates) is kept
> as-is for reference.**
>
> **Overall verdict**: the OTP / architectural layer is sound, the
> project **works** locally with 1/2/3 nodes (mining, P2P, RPC,
> maturity). But several critical pillars for a real public testnet —
> and a fortiori a mainnet — are **missing or silently broken**:
> deterministic post-quantum key derivation is actually a local random
> cache (cross-machine mnemonic recovery is impossible), block
> serialization uses `:erlang.term_to_binary` (cross-language
> incompatible and a hostile-input vector), there is no chain
> reorganization (no deep fork resolution), fees have a burn mechanism
> declared but stubbed to 0, and the P2P link is neither encrypted nor
> authenticated.
>
> **Estimated maturity**: **~50% testnet ready**, **~25% mainnet ready** —
> detailed per feature below.

---

## 0. Overview

### 0.1 Stack
- **Runtime**: Elixir 1.18 / OTP 27, single-node BEAM per process
- **Persistence**: CubDB (4 databases: `blocks*.cubdb` partitioned by
  month, `chain.cubdb`, `state.cubdb`, `index.cubdb`)
- **Crypto**: Rust NIF via Rustler; Dilithium2 + Falcon512 +
  SPHINCS+-SHAKE-128f-simple; Blake3 for PoW; SHA-256 elsewhere;
  RIPEMD-160 available but unused
- **P2P**: raw TCP + big-endian 4-byte framing + Protobuf via
  `:protobuf`
- **Consensus**: Blake3 single-hash PoW, adjustable difficulty
  (Bitcoin-like)
- **API**: JSON-RPC 2.0 over HTTP via Plug/Cowboy, bound to
  `127.0.0.1` only

### 0.2 Process architecture
Flat `:one_for_one` supervision tree (cf. `application.ex`):

```
Bastille.Supervisor
├── RPC (Plug.Cowboy)
├── Blocks         ──► CubDB time-partitioned
├── ChainStorage   ──► CubDB chain.cubdb
├── State          ──► CubDB state.cubdb (balances/nonces/pubkeys)
├── Index          ──► CubDB index.cubdb (tx hash, addr→txs, block→partition)
├── CoinbaseMaturity (GenServer, in-memory)
├── Chain          (GenServer, in-memory head + 100-block ring buffer)
├── Mempool        (GenServer, :gb_trees fee-priority)
├── OrphanManager  (GenServer, in-memory)
├── Consensus.Engine (GenServer, PoW state, :persistent_term cache)
├── MiningCoordinator (GenServer, mines inline)
├── P2P.Node       (GenServer, accept loop + monitor peers)
└── P2P.Sync       (GenServer, headers-first stub)
```

### 0.3 Boundary checks
- No dependency cycles between `Features.*` (grep-verified).
- `Infrastructure.Storage.CubDB.*` depends only on
  `Features.Tokenomics.Token` (for the `amount_juillet` types). Minor
  inversion but acceptable.
- `Features.Chain.Chain` depends on everything (normal for a
  coordinator).
- `Shared.*` has no dependency on `Features.*`. ✓

### 0.4 LOC
`lib/bastille/`: ~9,500 LOC Elixir + ~350 LOC Rust (NIF). Test suite:
**315 tests, 0 failure stable** over 3 consecutive runs after fixes.

---

## 1. Cryptography & identity management

### 1.1 French BIP39 mnemonic

**Status**: 🟠 Works, but NON-conformant to BIP39 on derivation and
checksum not verified.

**What works**:
- French wordlist (`priv/bip39_french.txt`), NFC normalization,
  entropy ↔ mnemonic conversion over 24 words (256 bits + 8 bits of
  checksum), classic.
- `Mnemonic.to_mnemonic/1` produces structurally valid BIP39.

**What doesn't work**:
- **`Mnemonic.from_mnemonic/1` does not verify the checksum**: it
  decodes 264 bits, takes the first 256 as entropy and throws the
  checksum away. A phrase with a corrupted or reordered word passes
  silently → we get a *different* entropy with no error. For BIP39,
  **8 bits of checksum = 1/256 probability of false acceptance** on a
  typo, and **any accidental valid permutation** passes.
- **`Mnemonic.valid_mnemonic?/1`** says OK from 12 words onwards, but
  `Seed.valid_master_seed?/1` requires 24. Inconsistency: the former
  can be used as a validation oracle that accepts BIP12.
- **No BIP39 passphrase ("mnemonic password")**: no parameter, no
  support → no way to separate multiple accounts per phrase.

### 1.2 Key derivation from the seed

**Status**: 🔴 **BROKEN by design — major security bug**.

On the Elixir side, `Seed.derive_keys_from_seed/1` receives the **raw
mnemonic string** (not its entropy, nor a BIP39 PBKDF2 seed). It is
passed to `Crypto.generate_*_keypair_from_seed/1`, which derives a
per-algorithm sub-seed via `HMAC-SHA256(master_seed, "dilithium" |
"falcon" | "sphincs")`. So far this could look like a homebrew
"HKDF-like" scheme.

**But the Rust NIF** (`native/bastille_crypto/src/lib.rs:233-345`)
does **not** do deterministic derivation:

```rust
// Generate random keypair (deterministic via persistent caching)
let (pk, sk) = dilithium2::keypair();        // ← keypair() = random
let pk_bytes = pk.as_bytes().to_vec();
let sk_bytes = sk.as_bytes().to_vec();
save_persistent_cache(&cache_key_bytes, &pk_bytes, &sk_bytes)
```

The "cache_key" is `blake3("dilithium2_v1:" || seed)`. The logic is:
1. If a file `data/<env>/key_cache/<cache_key>.keypair` exists → read it.
2. Otherwise generate a **fully random** keypair and write it to that
   file indexed by hash of the seed.

**Consequences**:
- The mnemonic derives **no** keys: it is only used to retrieve a
  random binary written on first use.
- **Cross-machine recovery is impossible**: if you restore your phrase
  on another node, you get 3 brand-new unrelated keypairs → a new
  address, the funds remain inaccessible.
- **Private keys are written in plaintext on disk**, indexed by a hash
  easily reproducible if someone knows a neighbor's phrase (info-leak
  via timing/cache_dir).
- The code comment ("deterministic via persistent caching") **lies**:
  it's exactly the opposite — randomness is preserved locally, it's
  not a derivation.

**What's needed**:
- The `pqcrypto-*` libs expose the standard non-deterministic
  `keypair()` API. For real derivation we need to use their NIST
  seed-based variants (Dilithium and SPHINCS+ have a
  `keypair_from_seed` API in the standard; Falcon doesn't trivially).
  If not available in the crate, we'll have to reseed a ChaCha20 RNG
  keyed by the sub-seed and call a low-level API accepting an
  `RngCore` (e.g. `pqcrypto-mldsa`, which has a more modern API and
  supports this pattern via `keypair_with_rng`).
- Wipe the cache file entirely and write a **real** HD wallet:
  BIP39 seed (entropy → PBKDF2-HMAC-SHA512 64 bytes) → per-algorithm
  HKDF sub-seeds → KAT-stable.

> **Severity**: blocking for mainnet, highly annoying for a public
> testnet (impossible to share an "official" address if it can't be
> replayed by another node).

### 1.3 Address generation

**Status**: 🟢 Correct.

- `Crypto.generate_bastille_address/1`: `SHA256(dilithium.pub ||
  falcon.pub || sphincs.pub)`, take the first 20 bytes, hex-lowercase,
  prefix with `address_prefix` (config). 44 characters total. Clean
  format.
- Validation: `Shared.Address.valid?/1` (prefix + 40 hex) — used
  everywhere now (post-fix).
- The prefix is *configurable per env* (`f789` testnet, `1789`
  mainnet). It's a functional/branding choice, but worth noting:
  **a mainnet node cannot read testnet addresses**, which is actually
  healthy.

**Weaknesses**:
- 160 bits only → collision resistance = 80 bits. That's the
  Bitcoin/Ethereum industry standard (same 20 bytes), so not a
  disaster, but to be documented.
- No checksum in the address (unlike BTC bech32, ETH EIP-55, Cosmos
  bech32). **A silent typo loses funds.**
- Validation regex `^prefix[0-9a-f]{40}$` but no case-insensitivity on
  input → if a user pastes in uppercase, it silently refuses.

### 1.4 2/3 post-quantum signature

**Status**: 🟢 Sound architecture, 🟠 a few blind spots.

Scheme: for each tx, three signatures Dilithium2 + Falcon512 +
SPHINCS+. Validation = `Enum.count(valid) >= 2` (cf. `Crypto.verify/3`).

**Strengths**:
- Family diversity: lattice (Dilithium), NTRU (Falcon), hash-based
  (SPHINCS+). If one falls to a PQ attack, the other two hold.
- Consistent sizes:
  - Dilithium2: sig ~2420 B, pk 1312 B, sk 2560 B
  - Falcon512: sig ~690 B, pk 897 B, sk 1281 B
  - SPHINCS+-128f: sig **~7856 B**, pk 32 B, sk 64 B
  - **Total signature** per tx: ~10.9 KB. Huge vs ECDSA (64 B) but
    that's the cost of PQ.
- Pubkeys stored per address in `State` (`pubkey:` prefix), retrieved
  for verification. Clean pattern.

**Issues**:
- **Strong sender ↔ node coupling**: `verify_signature/1` requires
  `State.get_public_keys(tx.from)`; if the address has never done
  `generate` on **this node**, the verification returns `false`. So
  an external wallet pushing a tx to a node that doesn't know its
  pubkey → rejected. For Bitcoin/ETH this isn't a problem because the
  pubkey is embedded in the tx; here it is *referenced by address*.
  → **Production solution**: embed the 3 pubkeys in the transaction
  (cost: ~2.2 KB more), OR disseminate via a dedicated tx-meta on
  first use.
- **2/3 signature vs. threats**: the 2/3 verification happens *on
  mempool admission*. If an attacker can forge 2 valid PQ sigs out of
  3, they pass. As long as the PQ libs aren't broken, fine; but the
  "post-quantum" marketing argument assumes **all 3** are attacked in
  parallel before an attacker can break an account with a single one.
- **Replay protection**: per-account nonce (cf. State), linearly
  incremented. ✓. But no `chain_id` in the signed message → a
  signature valid on testnet is valid on mainnet for the same address
  (which will be different, so weakly exploitable, but worth fixing
  cleanly).
- **Signed message** (`Transaction.serialize_for_signing/1`):
  ```elixir
  <<from, to, amount::64, nonce::64, timestamp::64>>
  ```
  **No `fee`, no `data`!** → a MITM can modify the fee or the data
  payload without breaking the signature. **This is a medium
  severity flaw**:
  - data: tamper with the relevant content (memo, contract) without
    breaking the sig.
  - fee: an attacker can transform a tx-fee=0.001 into a tx-fee=1 BAST
    to push it to the front of the mempool and have it consumed.

  **Required fix**: include `fee::64`, `byte_size(data)::32`, `data`
  (and ideally `chain_id`, `signature_type`) in the signed message.

### 1.5 `extract_keys_for_signing` RPC endpoint

**Status**: 🟠 Blocked in prod (correct), but exposes the
mnemonic → private keys pattern.

- Bypassed in `:prod` (`Mix.env() != :prod`). Good.
- But on testnet, **the RPC returns the 3 base64 private keys** in
  the JSON response. A user can use them to sign offline
  (MetaMask-like pattern), which is explicit and reasonable for dev —
  provided the public testnet is "fake-value", otherwise we'd need at
  minimum rate-limiting + audit logging + IP restriction (already
  localhost-only, so OK for solo dev use).

---

## 2. Storage (4-DB CubDB)

### 2.1 Architecture

**Status**: 🟢 Solid for single-node, 🟡 lacks operational robustness.

4 CubDB databases under `data/<env>/[node_prefix/]`:

| DB | Role | Keys (prefixes) |
|---|---|---|
| `blocks<YYYYMM>.cubdb` | Block storage, **monthly time-partitioned** | `{:block, hash}` → block binary |
| `chain.cubdb` | Chain metadata | `h2h:`, `hash2h:`, `meta:`, `diff:`, `pc:` |
| `state.cubdb` | Accounts | `bal:`, `nonce:`, `pubkey:`, `meta:` |
| `index.cubdb` | Fast lookups | `tx:`, `addr:`, `bhash:`, `time:` |

**Strengths**:
- Clean separation of concerns. Each DB has its own GenServer with
  `put_multi`/`delete_multi` for batches.
- Time-partitioning of blocks: each month = a new file
  `blocks202605.cubdb`. Good for open/snapshot/backup costs.
- hash→partition index to avoid scanning every file on each
  `get_block`.

**Weaknesses**:
- **No cross-DB atomicity**: adding a block does `Blocks.store_block`,
  then `Chain.store_block_link`, then `Chain.update_head`, then
  `Index.index_block`, then `Chain.update_head`. If the process
  crashes between two, the chain is **desynchronized** (block present
  but not indexed, or vice versa). No WAL / journal for rollback.
  → Not critical in single-node honest mode, but a power cut during
  a block add may require manual fsck.
- **`get_all_balances/0` and `get_total_supply/0` scan the whole
  DB**. It's a full-prefix range select. At 10k accounts it's fine,
  at 10M it dies. RPC `get_info` doesn't call it, but it's exposed.
  For a mainnet we need an incremental counter in `meta:total_supply`.
- **No Merkle/Patricia trie**. `state.cubdb` is a simple kv store; we
  can't produce a **state root** for a block header. Without it:
  - No light-client SPV.
  - No sharding or inclusion proofs.
  - No way to detect a state divergence (fork) other than by
    re-playing every block.
  → **For a mainnet this is a 3-6 week standalone job** (porting an
  MPT or a Sparse Merkle binary trie).
- **`tx_index`** in `Index.TransactionIndex`: the `addr:` list is
  capped at 1000 recent txs (cf. `add_to_address_index/3`). Sufficient
  for UX but **silently lossy**: we lose history beyond. To document,
  or replace with a `(addr, height) → tx_hash` paginated scheme.
- **Plaintext private key storage** (Rust cache + `state.cubdb`
  pubkeys are OK, but `data/<env>/key_cache/*.keypair` contains
  **private keys**; cf. §1.2). To wipe before any public testnet.
- **No pruning**: every block is kept indefinitely, no archive vs full
  mode. For a chain at 60s/block and 1789 BAST/block it grows modestly
  (~a few KB/block) but is unbounded.

### 2.2 Partition rotation
`maybe_rotate_partition` checks on every write whether we've changed
month and opens a new file. **Good**, but:
- The rotation happens *at the first write* after the 1st of the
  month. If the node runs 24/7 with no new block at midnight (unlikely),
  no concern. Otherwise the 23:59:59 block goes in the old file and
  00:00:01 in the new one. OK.
- `Index.find_block_partition` relies on the index to map hash →
  partition. **Before indexing** (fallback to
  `find_block_in_partitions`), we scan every open partition in O(n)
  → used for older non-indexed blocks. For a 5-year mainnet at 60s =
  ~2.6M blocks over 60 partitions, the scan stays fast.

---

## 3. Consensus & mining

### 3.1 Blake3 PoW

**Status**: 🟢 Correct but minimal, 🟠 coarse difficulty control.

- Single Blake3 hash (vs Bitcoin's double SHA-256). Blake3 has a good
  cryptographic margin, this choice is defensible and much faster
  (3-5M H/s single-thread vs ~100k for SHA-256 single-thread in
  Erlang/C).
- `serialize_block_for_mining/1`: `<<index::32, prev_hash, merkle,
  ts::64, diff::32>>` + transactions serialized via
  `:erlang.term_to_binary`.
  ⚠️ **`erlang.term_to_binary` in the mining serialization**: it's
  an Erlang-specific, non-standardized format, **non reproducible
  cross-language**. A Rust/Go/Python client will **never** be able to
  verify a block hash without implementing ETF. For a public testnet
  open to alternative implementations, this is a showstopper.
- **`difficulty` is encoded as 32 bits in the header but bounded by
  `consensus.config.max_target`** (testnet: `0x00FF...`, prod:
  `0x0000000FFFF0...`). There are **two different difficulty
  conventions depending on the env**:
  - testnet: `target = max_target / difficulty`
  - prod: `target = bitcoin_max_target / difficulty` (via
    `Mining.difficulty_to_target/1`)
  Weird and opaque. **The validation code uses the right path based
  on `max_target > 0`**, which lets a testnet attacker produce blocks
  that won't validate in prod (and vice versa, which is healthy). But
  this dual logic makes the code harder to read.

### 3.2 Dynamic difficulty

**Status**: 🟠 Works after the fix we applied, but coarse.

- Algorithm (post-fix in `MiningCoordinator`): delegates to
  `Engine.adjust_difficulty_fast`, which calls
  `ProofOfWork.adjust_difficulty/2`:
  ```
  ratio = actual_time / expected_time
  adjustment = clamp(ratio, 1/4, 4)
  new_diff = current_diff / adjustment
  ```
- Interval: configurable (3 in test, 5 in multinode, 10 in prod).
- Genesis block (index 0) excluded from the computation (post-fix).

**Remaining issues**:
- The computation uses the **newest-oldest timestamp delta** of the
  last 10 blocks. Sensitive to miners with desynced clocks (a miner
  with a timestamp 1h in the future skews the measurement).
- No **median time past (MTP)** à la Bitcoin (anti time-warp).
- No cap on a new block's timestamp (Bitcoin: timestamp must be >
  median of the last 11 AND < now + 2h). **A malicious miner can
  publish a block with a timestamp 50 years in the future**; every
  maturity/fee/difficulty computation breaks.
  → **Required for public testnet**: add MTP and an upper bound on
  the timestamp.

### 3.3 Mining architecture

- **Engine** (`consensus/engine.ex`): pure state holder, publishes a
  snapshot `{module, consensus_state}` into `:persistent_term`
  (post-fix). Mining runs in the caller process (MiningCoordinator),
  not in the Engine GenServer → the Engine stays free for
  `validate_block`, `info`, `get_difficulty` during mining. ✓
- **MiningCoordinator**: runs sync in its `handle_info`, publishes its
  status into `:persistent_term`. RPC stays responsive.
- **No internal parallelization of the nonce search**: the
  `find_nonce_batch` loop is single-threaded, blocking on a single
  core. At 3M H/s we cap at ~1 vCPU. **For a serious mainnet,
  multi-threading is mandatory** (spawn N tasks, partitioned nonce
  range, first one wins).
- No `getblocktemplate`-style aggregation → no pool mining possible.

### 3.4 Mining economics
- Fixed reward 1789 BAST/block, no halving. Perpetual inflation
  decaying in proportion (525,600 blocks/year at the 1min target).
  DOGE-like utility model, consistent with the theme.
- 100% of fees to the miner (the `coinbase_with_fees` code mentions
  "30% burn" but `Token.calculate_burn_amount/1` returns **0** —
  feature stub, explicitly disabled). README and code diverge.

---

## 4. Block reception/propagation & fork handling

### 4.1 P2P propagation (happy path)

**Status**: 🟢 Works, 🟡 simplistic protocol.

Bitcoin-like flow:
1. Miner creates a block → `Chain.add_block` success →
   `Node.broadcast_block` → `inv` (hash) sent to all peers.
2. Peer receives `inv` → checks `blocks_seen` → if new, `getdata` to
   the sender.
3. Sender replies with `block` (the full block).
4. Peer receives `block` → `BlockConverter.from_p2p_data` →
   `Chain.add_block`.
5. If OK → local add + relay `inv` to the other peers (excluding the
   sender).
6. If orphan → local storage + `getdata` for the parent.

**Strengths**:
- Typed Protobuf for the wire (except headers/consensus_data/signature
  which still go through `:erlang.term_to_binary`, see below).
- `blocks_seen`/`transactions_seen` MapSets → no infinite loop.
- `requested_blocks` to avoid re-requesting an orphan in a loop.

**Weaknesses**:
- **No P2P auth/encryption**: raw TCP, no cryptographic handshake. A
  MITM can inject/modify blocks and messages. **Not a blocker as long
  as we keep a whitelisted topology** (fixed `bootstrap_peers`, no
  open discovery): that's exactly the current node1/2/3 config, and
  also how plenty of chains have run their alpha testnet.
  - Short-term mitigations without rewriting the transport:
    1. Force `discovery_enabled: false` (already the case on testnet).
    2. Document an IP/peer_id whitelist for the v0.2-v0.3 phases.
    3. Reject blocks/txs whose signatures don't validate — already
       done on the validation side (since the transport layer is
       insecure, it's the signature layer that carries integrity,
       which is OK as long as the signature scheme covers all
       critical fields — see §1.4 on the unsigned fee/data, which is
       more urgent).
  - **Mainnet**: add Noise XX (libp2p-noise) or mutual TLS 1.3, peer
    scoring, banlist. Clean, well-scoped work.
- **No rate-limiting, no banlist, no peer scoring**. A malicious peer
  can spam `getdata` or send 1000 orphans.
- **`headers` message encodes each header in
  `:erlang.term_to_binary`** (cf. codec.ex:119-120). Same portability
  problem as mining.
- **No real `getblocks`/IBD sync**: `Sync.handle_getheaders_request`
  returns at most 200 headers, headers-first stub.
  `process_headers_from` sends `getdata` one at a time with no
  batching / parallelism.
  → Bootstrapping a node from scratch on a 100k-block chain will take
  > 10 minutes instead of a few seconds with an efficient IBD.
- **No real tx-relay**: `process_getdata_item` for `:tx` returns
  `Transaction #{hash} requested (not implemented yet)`. Concretely
  transactions **do not propagate via the mempool** between nodes
  today: only blocks (which contain confirmed txs) move around.
- **Incomplete self-connection guard**: `from_ip == "127.0.0.1"`
  filters loopbacks, but not a LAN node that would connect to itself
  via its public IP.

### 4.2 Orphan handling

**Status**: 🟡 Basic implementation present, enough for short forks.

`OrphanManager` (in-memory):
- Stores up to 500 orphans, expire after 10 min.
- Indexed by `parent_hash → [child_hash]` to wake up the children
  when a parent arrives.
- `Chain.post_add_success` re-calls `add_block` on the rescued
  orphans via a Task → good practice not to block.

**Strengths**:
- Anti-spam via bounded capacity + TTL.
- Automatic parent request (`request_parent_if_needed`) with
  deduplication (`requested_blocks` MapSet).

**Weaknesses**:
- **No reorganization**: if a competing longer chain arrives, nothing
  happens. `Chain.add_block` requires
  `block.header.index == state.height + 1`; any other case falls
  into the orphan bucket. No cumulative-work comparison, no state
  rollback, no re-injection of orphaned txs into the mempool.
- **Important nuance**: we're saying no reorganization, NOT no
  longest-chain rule. Bitcoin v0.1 already had the "longest wins"
  rule from day one (it's the heart of Nakamoto consensus, not a
  later refinement). Bastille is today **below Bitcoin v0.1** on
  this specific point: no cumulative-work tracking at all, and a
  block that doesn't extend the current tip is flat-out rejected.
- Concretely, two miners producing in parallel create a permanent
  fork: each side refuses the other's blocks, no reconciliation. On
  the local 3-node testnet it doesn't show because one of the two
  miners "wins" the race on each round and the other sees its block
  arrive systematically later — but that's topological luck, not a
  protocol guarantee.
- The history of live chains has plenty of examples that ran without
  fork-resolution hardening during their first months (Bitcoin early
  days, early versions of several L1s post-2017). So it's not a
  philosophical blocker for a private/controlled testnet.
- Minimum needed to reconcile competing miners:
  1. Track `cumulative_work` in `chain.cubdb` (a `u128` per block hash).
  2. On receipt of an orphan block, fetch the chain up to the common
     ancestor.
  3. If `total_work(alt) > total_work(current)` → rollback + reapply.
- Rollback is less trivial than in Bitcoin UTXO (where you just put
  the outputs back): with an account model we need either a **journal
  of state changes per block** in `state.cubdb` (`{block_hash →
  [{addr, old_balance, old_nonce}, …]}`), or replay from the common
  ancestor (slower but simple and viable for a testnet).
- `MINING_REWARD_IMPLEMENTATION.md` documents this absence as
  `HIGH_PRIORITY` — confirmed.

> **Tolerable**: private testnet / single miner / controlled
> bootstrap+relay topology where we accept that forks block dissident
> nodes.
> **Blocking**: public multi-miner testnet (two competing miners can
> silently diverge) and the whole path to mainnet.

### 4.3 Coinbase maturity — **REMOVED**

**Status**: 🟢 No maturity. Balances spendable on credit.

A Bitcoin-style maturity (5 blocks testnet / 89 blocks prod) had been
implemented in an earlier version (`CoinbaseMaturity` in-memory
GenServer, `get_immature_coinbases` RPC, total/mature/immature
breakdown in `get_balance`). It was **intentionally removed**.

**Reason**: maturity protects against reorgs (a miner spends a reward,
their block becomes orphan, the money never existed). But Bastille
has no reorg (cf. §4.2). The `block_still_in_chain?` check of the old
`CoinbaseMaturity` was based on `Blocks.has_block?`, but no code ever
removes a block from `Blocks` → in practice no reward was ever flagged
as orphaned. So maturity was an **arbitrary timer with no real
security property**, but with a definite operational cost (GenServer
↔ Chain deadlock, in-memory state lost on restart, etc.).

**References**:
- Bitcoin (UTXO + PoW): has maturity, 100 blocks.
- **Ethereum PoW (pre-Merge): did NOT have maturity.** Account model +
  state rollback on reorg = no need for the Bitcoin belt-and-suspenders.
  That's exactly Bastille's model.
- PoS / BFT chains (Cosmos, Polkadot, Solana, Algorand): replaced by
  bonding/unbonding or instant finality. Obsolete concept.

**Decision**: no maturity in Bastille v0/v0.1/v0.2. When
reorganization lands (v1.0), we'll evaluate whether to:
- Option A: add it to align with Bitcoin (useful if certain light
  SPV wallets can't track reorgs properly).
- Option B: align with Ethereum-PoW and skip it (state rollback on
  reorg does the job alone).

Likely choice: B (simpler, and Ethereum PoW history proves it holds).

**Impact on current code**: none. The `get_balance` RPC simply
returns `{address, balance, nonce}`. Tx validation against state uses
`State.get_balance` directly.

---

## 5. Transaction validation & mempool

### 5.1 Mempool

**Status**: 🟢 Solid Bitcoin-like implementation.

- `:gb_trees` indexed by `{fee, -timestamp, hash}` → fee priority
  desc, timestamp asc, hash for uniqueness.
- `tx_by_hash` map for O(1) lookup.
- Capacity 4000 (config), min_fee 1000 juillet, periodic cleanup
  (5 min, drops > 24h).
- `skip_signature_validation` / `skip_chain_validation` for tests
  (post-fix passed via `mempool_opts` in config).

**Strengths**:
- Fee-first priority, simple and effective.
- Periodic cleanup avoids accumulation.
- Bounded capacity → no OOM.

**Weaknesses**:
- **No RBF/CPFP replacement**: impossible to re-broadcast the same
  tx with a higher fee.
- **No package validation**: no evaluation of dependent tx chains.
- **No P2P propagation** (cf. §4.1) → the mempool is NOT shared
  between nodes. Consequence: only the node that mines includes its
  own tx; the others have nothing. For a single-miner testnet OK, for
  multi-miner unacceptable.
- **No priority eviction** when the mempool is full: we reject the
  new tx (cf. `check_mempool_capacity`). Bitcoin evicts the least
  profitable one.

### 5.2 Tx validation

3 layers:
1. **Structural** (`Transaction.valid?`): structure, addresses,
   signature, hash.
2. **Mempool**: structure + min fee + chain check + capacity + dedupe.
3. **Chain** (on block add): sufficient balance (mature only),
   sequential nonce, address format.

**Strengths**:
- Atomic validation with `with` pipeline.
- Clean validation/application separation (cf. cursorrules).
- Coinbase and "1789Genesis" cleanly short-circuited.

**Weaknesses**:
- **The hash is included in the `valid_hash?` check which
  recomputes**: OK for integrity, but it prevents a wallet from
  submitting a tx without a pre-computed hash. Friction for external
  clients.
- **`Mempool.validate_transaction_against_chain` calls
  `Chain.validate_transaction` GenServer.call**: while Chain
  processes an add_block, this call can timeout. Less critical since
  our fixes, but still a potential friction point.
- **No validation that `to` is a "real" address**: we accept any
  address that matches the format (= 40 hex after the prefix). No
  notion of "create new account requires gas" (vs ETH) nor "dust
  limit" (vs BTC). Address spam to inflate `state.cubdb` is possible.

### 5.3 Fee model

**Status**: 🟠 Coherent but double-implementation, and unsigned fee
(cf. §1.4).

- `Transaction.calculate_fee/1`: `max(size * 10_000, 100_000)` juillet.
- `Token.calculate_fee/2`: `(1000 + size * 10) * priority_multiplier`.
- **The two coexist and are not reconciled**. The core
  (`Transaction.new`) uses the first (size-based, ignores the `fee`
  opt). The `create_unsigned_transaction` RPC can accept a custom
  `fee`, but `Transaction.new` systematically ignores and
  recomputes.
- Min mempool fee: 1000 juillet. So the computed fee is always
  >= 100,000 >> 1000 → no rejection by insufficient_fee possible in
  normal flow.

**To clean up**: pick one implementation, drop the other, document.

---

## 6. RPC API

### 6.1 Endpoints
8 methods (cf. `api/rpc.ex`):
- `generate_address`: creates mnemonic + derives keypair + returns
  address.
- `get_balance`: total/mature/immature breakdown.
- `get_immature_coinbases`: detail of immature rewards.
- `get_transaction`: by hash (mempool only, **not in confirmed
  blocks!**).
- `get_info`: node state.
- `create_unsigned_transaction`: for wallet flow.
- `sign_transaction`: signs with 3 private keys + retrieves pubkeys
  from local storage.
- `submit_transaction`: decodes base64 → adds to mempool →
  broadcasts.
- `extract_keys_for_signing` (dev/test only): returns the 3 priv
  keys from a mnemonic.

### 6.2 Endpoint audit

**Strengths**:
- Localhost-only (`{127, 0, 0, 1}`) hardcoded in the child_spec →
  no network exposure.
- Structured JSON-RPC 2.0, consistent error codes (-32601, -32602).
- MetaMask-like workflow (`create_unsigned` → `sign` → `submit`).

**Weaknesses**:
- **No auth at all**. Anyone with localhost access (another user on
  the server, co-tenant container) can sign and submit tx with
  `extract_keys_for_signing`. Fine on testnet, **unacceptable in
  prod** without at least an API key.
- **`get_transaction` only reads the mempool** — not the confirmed
  index. The `tx:` index in `index.cubdb` exists but is never read
  from the RPC side. → A confirmed tx becomes invisible once it
  leaves the mempool.
- **Non-uniform errors**: some endpoints return
  `%{"error" => %{"code" => -32602, "message" => ...}}`, others
  `%{error: ...}` (atom keys). The client has to guess.
- **No pagination, no filters**: `get_transactions_for_address` is
  not exposed via RPC.
- **No WebSocket / subscription**: to follow blocks live, you have
  to poll `get_info` → bad wallet UX.
- **`submit_transaction` uses `:erlang.binary_to_term`** on the
  base64-decoded input. **DESERIALIZATION VULNERABILITY**: a
  malicious payload can inject atoms, fun closures, refs → potential
  atom-exhaustion or worse. Should be refactored to decode via
  Protobuf or pure JSON, never ETF. Same in `sign_transaction` (the
  base64 unsigned_tx also goes through `binary_to_term`).

**CRITICAL RECOMMENDATION**:
replace the binary_to_term flows with structured JSON; ETF is **not**
a serialization format you can trust from external sources.

### 6.3 Endpoints missing for a wallet
- `get_transactions_by_address` (user history)
- `get_block_by_height` (explorer UX)
- `get_mempool` (view pending)
- `estimate_fee`
- `broadcast_raw_transaction` (raw hex/binary)
- `get_chain_tip` (hash + height + work)
- `subscribe_blocks` / WebSocket

---

## 7. Tokenomics

**Status**: 🟢 Coherent on constants, 🟠 burn declared but stubbed.

- 14 decimals (`juillet`), 1789 BAST/block, no halving. ✓
- `total_supply_at_block(h) = 1789 + h * 1789` (juillet). Linear.
- No cap. Consistent with the "utility token" theme.
- **Burn**: `Token.calculate_burn_amount/1 = 0` and
  `track_fee_burn/1 = :ok` — fully stubbed. But `coinbase_with_fees/3`
  mentions 30% burn and reports "30% burned: 0 BAST" in the logs
  (always 0 because burn off). The README mentions the possibility
  of governed burns. **To reconcile**: either remove all mentions of
  burn, or implement it.
- **Inflation**: at 1 min/block, ~940M BAST/year. Year 1 = 940M
  added to the 1789 genesis → 525,200% inflation. Year 10 = 10%/year.
  Year 100 = 1%/year. It's a utility scheme, but to be clearly
  documented (the current whitepaper doesn't do the math).

---

## 8. Wrap-up: strengths / weaknesses / v1 priorities

### 8.1 What holds well
1. ✓ Clean OTP architecture, minimal supervision tree.
2. ✓ Feature separation, unidirectional dependencies, little
   architectural debt.
3. ✓ Partitioned CubDB storage, atomic intra-DB batches.
4. ✓ Local multi-node working (post-fixes).
5. ✓ 300 tests stable (post-maturity-removal).
6. ✓ Clean Bitcoin-style fee-priority mempool.
7. ✓ Original and defensive 2/3 PQ-sig scheme (pending the
   derivation fix).
8. ✓ Mining no longer blocks Engine or RPC (post-fixes).
9. ✓ No premature maturity complexity (removed in v0.1) — balances
   directly spendable, we'll handle this with reorg.
10. ✓ Protobuf wire for transport (at least the skeleton).

### 8.2 Public-testnet blockers
Sorted by severity. Anything touching the cryptographic integrity of
transactions is at the top because it doesn't depend on the topology.

| # | Subject | Impact | Effort |
|---|---|---|---|
| 1 | **Non-deterministic key derivation** (Rust NIF = random + disk cache) | Cross-node recovery impossible. Blocks shared addresses. | 1-2 weeks (use `pqcrypto-mldsa` or reseed `RngCore`) |
| 2 | **Fee + data not included in the signed message** | MITM can tamper fee/payload without breaking sig | 1h + tests |
| 3 | **`binary_to_term` on base64 RPC input** | Deserialization vulnerability, atom-exhaustion DoS | 1-2 days |
| 4 | **`get_transaction` doesn't read the confirmed index** | Confirmed tx invisible. Broken UX | 1-2 days |
| 5 | **No P2P tx propagation** | Desynced mempools → multi-miner broken | 3-4 days |
| 6 | **No address checksum** | Silent typo = funds lost | 1 day (CRC32 or EIP-55-like) |
| 7 | **Mempool.validate_transaction → Chain.validate_transaction GenServer.call** in the mempool handler | Cascading timeout risk | 1 day (move chain check async or inline) |

### 8.3 Mainnet blockers (in addition to 8.2)

Includes items demoted from 8.2 (cf. annotations).

| # | Subject | Effort | Note |
|---|---|---|---|
| A | **Chain reorganization** (cumulative work + state rollback + reapply) | 3-4 weeks | Tolerable on controlled testnet. Bitcoin v0.1 already had this: Bastille is below that bar. |
| B | **Median Time Past + timestamp validation** | 2-3 days | Time-warp hardening |
| C | **State root / Merkle Patricia Trie** | 4-6 weeks | Real state-storage rewrite. Blocks SPV, light clients, sharding. |
| D | **P2P authentication (Noise XX or mutual TLS)** | 1-2 weeks | Tolerable testnet with a peer whitelist (current config). Mainnet: required. |
| E | **Multi-thread mining** | 1 week | |
| F | **API key / RPC rate limiting** | 2-3 days | Localhost-only is enough in dev/test |
| G | **WAL / cross-DB journal for add_block atomicity** | 1 week | |
| H | **Bounded limits on everything**: block size, tx size, signature count, prioritized mempool eviction | 1 week | |
| I | **Byzantine suite / P2P fuzz** | 2-3 weeks | |
| J | **Peer banlist / scoring / DoS resistance** | 1-2 weeks | |
| K | **Real IBD (parallel block download, fast sync, snapshot sync)** | 3-4 weeks | |
| L | **Complete cryptographic documentation** (specs, KAT, external audit) | 4+ weeks | |
| M | **Embed pubkeys in the tx** (or a tx registry to disseminate) | 1 week | |
| N | **Canonical wire format** (replace `erlang.term_to_binary` in mining/headers/signature) | 1 week | Tolerable while we're an Elixir-only implementation. Blocks any Rust/Go/JS client wanting to validate an external chain. |

### 8.4 Useful technical cleanups (low-hanging fruit)
- `Mnemonic.from_mnemonic`: verify the BIP39 checksum.
- `Mnemonic.valid_mnemonic?` should require 24 words (consistent with
  `Seed`).
- Unify `Transaction.calculate_fee` vs `Token.calculate_fee`.
- Mining logs too verbose: move `🔨 CREATING BLOCK TEMPLATE` etc. to
  `debug`.
- `addr:` index capped at 1000 txs: doc + paginate.
- Remove/align the burn mentions in `coinbase_with_fees`.
- `lib/bastille.ex:683`:
  `all_valid = Enum.all?(addresses, &String.starts_with?(&1, "1789"))`
  → use the configured prefix.
- `decode_address/1`: also use the configured prefix (already OK via
  `Application.get_env`).
- `Node`'s `handle_info({:p2p_message, :pong, ...})` updates
  `last_pong` but not via the standard `process_p2p_message` → odd,
  to unify.
- `Sync.get_current_head_hash` returns `String.duplicate("0", 64)`
  (a 64-char string), not a `<<0::256>>` binary → the `^prev_hash`
  comparison will never match the genesis since `prev_hash` is binary.
  Latent sync bug, masked because that path is almost never taken.

---

## 9. Suggested trajectory

### Phase v0.1 (where we are) — "runs locally"
✅ Multi-node sync, stable mining, responsive RPC, green tests. **Done.**

### Phase v0.2 — "closed private testnet" (~3 weeks)
- Fix post-quantum key derivation (item 1)
- Include fee + data + chain_id in the signed message (item 2)
- Replace `binary_to_term` on external input (item 3)
- `get_transaction` also reads confirmed blocks (item 4)
- P2P tx propagation (item 5)
- Address checksum (item 6)
- Decouple `Mempool.validate_transaction` from the Chain GenServer
  (item 7)
- Cleanup of logs and inconsistent docs

### Phase v0.3 — "open public testnet" (~2 additional months)
- Canonical wire format (item N) — JSON or strict Protobuf everywhere
- Mempool sync + basic RBF
- Parallel sync IBD
- DoS / banlist / scoring hardening
- WebSocket subscription RPC
- Missing API endpoints (mempool, history, etc.)

### Phase v1.0 — "mainnet candidate" (~4-6 months)
- Chain reorganization (A)
- State root + MPT (C)
- Encrypted P2P (D)
- Multi-thread mining (E)
- RPC auth + rate limiting (F)
- Cross-DB WAL (G)
- External cryptographic audit (L)
- Continuous stress-test suite, 3+ months of alpha testnet without
  incidents

---

## 10. Technical conclusion

The project has a **good Elixir/OTP architectural base**: the
separation of concerns is clear, the storage and P2P framing choices
are defensible, the code is readable and well-tested. **Mining, basic
propagation, maturity and RPC all work.**

But under the hood, **two design decisions undermine the post-quantum
promise**:
1. Derivation from the mnemonic is a **random-key cache**, not a
   reproducible cryptographic derivation. Until this is rewritten, the
   wallet has no recovery property at all.
2. **The signed content does not cover fee+data**; a 2/3 PQ signature
   that does not protect the fee is a signature that can be
   trivially mauled.

Added to the absence of fork resolution and a canonical wire format,
these points put the project **firmly in pre-testnet** territory:
it's a **solid PoC that runs blocks across multiple nodes**, not yet
a **chain implementation** ready to receive real funds.

The good news: most issues have fixes of **a few days to 2 weeks
each**. None requires a massive rewrite except the state root
(mainnet only) and the PQ derivation (testnet-blocking but well
contained in `Crypto` + the Rust NIF).

**Suggested sequence**: attack items 1, 2 and 4 of Table 8.2 first —
these are the three fixes that take the chain from "nice local
prototype" status to "shareable testnet where the addresses mean
something". The rest can follow incrementally.
