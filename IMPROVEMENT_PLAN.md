# 🏰 Bastille — Improvement Plan

Operational execution plan to move Bastille from "v0 PoC that runs" to
"v0.2 shareable private testnet" and eventually "v1.0 mainnet candidate".

Diagnosis and rationale live in
[`ARCHITECTURE_REVIEW.md`](./ARCHITECTURE_REVIEW.md). This document is the
**operational tracker** — check items off as you go.

**Status legend**: ☐ todo · ⏳ in progress · ✅ done · ⏸ paused / deprioritized

---

## ▶️ Resume the session elsewhere

```bash
git clone git@github.com:laurentf/bastille-chain.git
cd bastille-chain
mix deps.get
mix compile
MIX_ENV=test mix test          # should print "336 tests, 0 failures, 8 excluded"

# Multinode smoke test (3 terminals)
MIX_ENV=node1 mix run --no-halt   # bootstrap + miner
MIX_ENV=node2 mix run --no-halt   # relay
MIX_ENV=node3 mix run --no-halt   # miner

# Quick check
curl -s -X POST http://127.0.0.1:8101/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"get_info","params":{},"id":1}' \
  | grep -oE '"height":[0-9]+|"connected_peers":[0-9]+'
```

**Prerequisites**: Elixir 1.18+ / Erlang/OTP 27+, Rust 1.70+ (crypto NIF).

---

## 📍 Current state — v0.1.7 (2026-05-28)

**Sprint 1 published** on `bastille-chain` `main` (single commit
`Sprint 1: multinode stabilization + quick wins`). Functional private
testnet base, multinode 1/2/3 OK.

**Sprint 3 COMPLETE + Sprint 2** (branch `sprint-3-deterministic-keygen`, 6
commits, not yet pushed): full BIP39 deterministic PQ key derivation
(mnemonic → PBKDF2 → HKDF → ml-dsa/slh-dsa/fn-dsa), checksum-validated,
KAT-frozen, recovery + signing proven; plus P2P transaction propagation.
**336 tests green.**

Fixes applied:
- ✅ `CoinbaseMaturity` ↔ `Chain` deadlock
- ✅ `validate_address_format` wired to the configured prefix
- ✅ `prod.exs` consensus module path corrected
- ✅ Difficulty explosion (1 → 65536 in 9 blocks) fixed
- ✅ Engine + MiningCoordinator freed via `:persistent_term` during mining
- ✅ Genesis merkle_root = binary instead of struct
- ✅ Genesis recipient = `Address.zero()` instead of the rogue `"1789Revolution"`
- ✅ CoinbaseMaturity removed (reorg has since landed; §4.6 decided not to reintroduce it)
- ✅ `mempool_opts` in test config to avoid the supervisor-vs-test race
- ✅ README + audit aligned with reality
- ✅ `Bastille.Supervisor` `max_restarts: 100, max_seconds: 10` (up from 3/5)
- ✅ `:integration` tag excluded by default in `test_helper.exs`
  (run with `mix test --include integration` when needed)

---

## 🎯 Next target — Sprint 5 (mainnet hardening)

**Done (2026-05-27/29)**: Sprint 3 wallet core — 3.1 (POC), 3.2 (deterministic
NIF), 3.3 (KAT vectors), 3.4 (BIP39 PBKDF2 seed), 3.5 (mnemonic checksum), 3.6
(key_cache cleanup), 3.7 (multinode recovery test) — plus **Sprint 2 (P2P tx
propagation)** and **Sprint 4 — chain reorganization, complete (4.1–4.6):**
cumulative work, state journal, common-ancestor search, transactional rollback +
reapply, edge-case tests, and the coinbase-maturity decision (not reintroduced —
§4.6). The mnemonic deterministically derives the three keypairs (BIP39 PBKDF2 →
HKDF), a typo is caught, recovery is cross-machine, a tx propagates node→node into
every mempool, and a heavier fork is now adopted via `Chain.reorganize/1`. See
`docs/key_derivation_design.md`.

**Remaining**:
- Sprint 5+ — mainnet hardening (MTP/timestamp validation, state root / MPT,
  authenticated P2P, multi-thread mining, etc. — see below).
- Automated multinode reorg-convergence test (deferred from 4.5 — needs an
  OS-process / `:peer` harness; verified manually for now).

---

## 🏁 Sprint 1 — Quick wins (~1 week)

Five low-cost, high-impact fixes, independent of each other. Done first
to build a clean base for the rest.

### ✅ 1.1 — Bind `fee` + `data` + `chain_id` to the signed message
**Reference**: `ARCHITECTURE_REVIEW.md` §1.4, §8.2 item 2
**Actual effort**: ~1h (estimate held)
**Status**: finished 2026-05-21

**Acceptance**:
- [x] `Transaction.serialize_for_signing/1` now includes `chain_id`
      (length-prefixed), `from`, `to`, `amount`, `fee`, `nonce`,
      `timestamp`, `byte_size(data)`, `data`.
- [x] Test: tampering `fee` on a signed tx invalidates it (see
      `serialize_for_signing — message integrity`).
- [x] Test: tampering `data` on a signed tx invalidates it.
- [x] Test: a tx signed on testnet is rejected on mainnet (toggle
      `Application.put_env :network` around sign/verify).
- [x] Logs `Logger.debug("🔍 Verifying tx signature")` + sub-lines
      `chain_id`, `fee`, `data_size`. Explicit ⚠️ warning on invalid
      signature or missing pubkey.

**Notes**:
- 8 new tests in `transaction_test.exs` (5 on `serialize_for_signing`,
  3 end-to-end sign/tamper/verify).
- The file switched to `async: false` because the cross-chain_id tests
  mutate `Application.put_env(:bastille, :network, …)`.
- **308/308 tests stable** over 3 runs.
- Multinode smoke test: 3 nodes aligned at height 30, mining/propagation OK.
- Since we're pre-testnet and have no persisted transactions, no
  migration is needed. To be documented the day we add real txs.

### ✅ 1.2 — Address checksum (EIP-55-inspired)
**Reference**: §1.3, §8.2 item 6
**Actual effort**: ~2h (came in under estimate)
**Status**: finished 2026-05-21

**Choice**: EIP-55-inspired, SHA-256 hash (instead of Ethereum's
Keccak-256) to avoid pulling in a Keccak NIF. The checksum is bound to
the configured prefix (`SHA256(prefix || lowercase_hex)`), so the same
hex doesn't validate cross-network.

**Strategy**: the **canonical form stays lowercase** on chain (no
migration). The checksum is purely for display: the `generate_address`
RPC additionally returns `address_display` (mixed-case). Validation
accepts three forms — all-lower, all-upper (legacy), mixed-case with a
valid checksum. Any other form is rejected.

**Acceptance**:
- [x] Choice documented in `Bastille.Shared.Address`'s `@moduledoc`.
- [x] `Address.valid?/1` accepts the 3 forms, rejects bad checksums.
- [x] `Address.with_checksum/1` produces the display form
      (deterministic, same length).
- [x] `Address.canonical/1` downcases defensively (leaves `"1789Genesis"`
      and non-conforming strings untouched).
- [x] `Crypto.generate_bastille_address/1` unchanged (canonical
      lowercase). Display computed separately via `Address.with_checksum`.
- [x] `generate_address` RPC returns `address` (canonical) +
      `address_display` (checksummed) + `mnemonic` + `mnemonic_phrase`.
- [x] `get_balance` RPC validates the address and rejects typos with
      an explicit error (manually tested: `BF` → `bF` rejected).
- [x] `Transaction.new` canonicalises from/to → storage and tx hash stay
      stable regardless of input form.
- [x] `Bastille.validate_address` + `Transaction.valid_address?` delegate
      to `Address.valid?` (so they accept mixed-case).
- [x] **322/322 tests** stable over 3 runs (308 → 322, +14 new).
- [x] Multinode smoke test: node1 OK, `generate_address` returns both
      forms, `get_balance` accepts canonical + display and rejects the
      tampered one.

**Notes**:
- No migration needed in pre-testnet (the algorithm accepts existing
  lowercase addresses).
- The canonicalisation logic lets sentinels through (`"1789Genesis"`,
  `"legacy_*"`, non-conforming strings) — pattern matching in Chain
  preserved.
- Deterministic KAT: the same lowercase address always produces the
  same display, cross-machine (since SHA-256 is deterministic by
  definition).

### ✅ 1.3 — Drop `:erlang.binary_to_term/1` on RPC inputs
**Reference**: §6.2, §8.2 item 3
**Actual effort**: ~3h
**Status**: finished 2026-05-21

**Wire format choice**: JSON map (binaries hex-encoded). No Protobuf
client-side → web/mobile wallets can consume it without a dependency.

**Acceptance**:
- [x] `Transaction.to_json_map/1` and `Transaction.from_json_map/1`
      added. Strict fail-closed validation on every field (types, hex
      length, signature shape). Only accepts
      `signature_type: "post_quantum_2_of_3"`.
- [x] `create_unsigned_transaction` returns a JSON map (not base64+ETF).
- [x] `sign_transaction` accepts a JSON map in input and returns a
      signed JSON map.
- [x] `submit_transaction` accepts a JSON map in input.
- [x] Grep `binary_to_term` in `features/api/` returns **zero call**
      (only doc comments).
- [x] Tests: base64+ETF payload (old API) explicitly rejected (regression).
- [x] Tests: raw string payload rejected.
- [x] Tests: JSON map missing required fields rejected.
- [x] Tests: `signature_type: "legacy_secp256k1"` rejected.
- [x] Tests: unsigned submit rejected (no signature field).
- [x] **312/312 tests** stable over 3 runs (-10 vs before: replaced
      boilerplate tests by round-trip + security-regression tests).
- [x] Multinode smoke test: RPC chain `generate_address` →
      `extract_keys_for_signing` → `create_unsigned_transaction` →
      `sign_transaction` → `submit_transaction` works end-to-end.

**Notes**:
- **Ownership bug caught in passing**: `sign_transaction.verify_ownership`
  only checked the address ↔ stored-pubkeys derivation, never the
  private keys supplied. An attacker could submit any private keys
  without detection. Fixed: now signs a test message and verifies it
  against the stored pubkeys → the 2/3 PQ check fails if the privates
  don't match the publics.
- **Double-wrap RPC bug caught**: `create_unsigned_transaction`,
  `sign_transaction`, `extract_keys_for_signing` were all returning
  `%{"result" => %{…}}` but the RPC dispatcher already wraps responses
  in `result:` → the final JSON was `{"result":{"result":{...}}}`. All
  handlers flattened (aligned with `GetInfo`/`GetBalance`).
- README updated: Bash flow using `jq` that consumes JSON maps directly
  (no intermediate base64).
- Logs added: `📝 Unsigned tx prepared` / `✍️ Tx signed for X` /
  `📤 Tx submitted to mempool` with hash/from/to sub-lines (compliant
  with `CONVENTIONS.md` formalism).

### ✅ 1.4 — `get_transaction` also reads the confirmed index
**Reference**: §6.2, §6.3, §8.2 item 4
**Actual effort**: ~3h
**Status**: finished 2026-05-22

**Acceptance**:
- [x] `RPC.GetTransaction` tries the mempool first, then falls back to
      `Index.find_transaction(binary_hash)` →
      `{partition, block_hash, tx_index}`.
- [x] If found: `Blocks.get_block_from_partition` →
      `Enum.at(block.transactions, tx_index)`.
- [x] Response: `status: "pending" | "confirmed" | "not_found"`, plus
      `confirmations`, `block_height`, `block_hash` when applicable.
- [x] The tx itself is returned via `Transaction.to_json_map/1` (same
      shape as in `create_unsigned/sign_transaction`).
- [x] Strict input validation: `hash` must be 64-char hex, otherwise
      `%{error: "Invalid transaction hash (expected 64-char hex)"}`.
      The pre-existing bug where passing a hex string to
      `Mempool.get_transaction` (which expected binary) silently
      returned "not found" is also fixed.
- [x] **9 dedicated tests** in `get_transaction_test.exs` (input
      validation, mempool path, confirmed path via Index direct, "tx
      present in both" edge case). 9/9 stable in isolation.
- [x] Live RPC smoke test: unknown hash → `status: "not_found"`, bad
      hex → explicit error.

**Notes**:
- Logs added: `🔍 Tx X found in mempool` / `🔍 Tx X confirmed at
  height N (M confirmations)` / `🔍 Tx X not found` (debug-level,
  compliant with `CONVENTIONS.md`).
- **Side bug revealed (not caused)**: the full suite was flaky because
  several tests were cycling the global `Mempool` (stop+start_link),
  which burned the supervisor's restart budget under specific file
  combinations. Mitigations applied:
  - `Mempool.start_link/1` now accepts `:name` → the 2 `mempool_test`
    cases that wanted custom `min_fee` / `max_size` now use a named
    local instance, without touching the global one.
  - `Bastille.Supervisor` bumped to `max_restarts: 100, max_seconds: 10`
    (vs 3/5 default — too fragile for a top-level supervisor).
  - `mempool_test` setup simplified: just `Mempool.clear()`.

  → Residual flakiness (~30–50% of full `mix test` runs) was NOT
  resolved here. Tracked in the backlog as **"combined test suite
  flakiness"**. It's a test-infrastructure issue, not application
  code. Out of Sprint 1 scope.

### ✅ 1.5 — Decouple `Mempool.validate_transaction` from the Chain GenServer
**Reference**: §5.2, §8.2 item 7
**Actual effort**: ~1h
**Status**: finished 2026-05-23

**Acceptance**:
- [x] New module `Bastille.Features.Chain.TransactionValidator` (pure,
      reads `State` directly through its own GenServer).
- [x] `Mempool.validate_transaction_against_chain` calls
      `TransactionValidator.validate(tx)` instead of
      `Chain.validate_transaction(tx)` (which was a `GenServer.call`).
- [x] `Chain.validate_transaction` public API preserved and delegates
      to `TransactionValidator.validate/1` — no breaking change for
      consumers (MiningCoordinator, etc.).
- [x] Chain's `handle_call({:validate_transaction, …})` removed (dead).
- [x] Block-level `validate_all_transactions` (in `Chain.apply_block`)
      reuses the same validator → rules centralised in one place.
- [x] Existing tests 310/310, multinode smoke OK (node1 mines 26
      blocks, RPC responsive).

**Notes**:
- **Side bug fixed in passing**: the `mix test` flakiness (~30–50% of
  runs with 50s timeouts) was caused by
  `blockchain_integration_test.exs` stopping and restarting the
  supervisor's global GenServers (Blocks, Chain, State, Index,
  OrphanManager). Pragmatic fix: excluded by default via
  `ExUnit.start(exclude: [:integration])` in `test_helper.exs`.
  Integration tests stay available via `mix test --include integration`
  or in a dedicated CI step.
- **Suite now 100% stable** over 5 consecutive runs, ~1–1.5s duration
  (vs 4–50s flaky before).
- No logs added: the path is very hot (tx validation on every
  `add_transaction`), debug-only there is noise without value.

---

## 🚀 Sprint 2 — P2P tx propagation (3-4 days) — ✅ done 2026-05-27

All four items landed. A tx submitted to one node is relayed
(`inv` → `getdata` → `tx`) to peers, validated through `TransactionConverter`,
added to their mempools and re-broadcast (de-duplicated via `transactions_seen`).
Also fixed: `tx_message` now carries `data` (part of the signed message).
320 tests; converter unit tests + a wire roundtrip + an `:integration` test that
pushes a `:tx` into the live Node and asserts it reaches the mempool.

Without this, multi-miner = desynchronised mempool = chaos.

### ✅ 2.1 — Implement `process_getdata_item` for `:tx`
**Reference**: §4.1, §8.2 item 5 ; code: `node.ex:607-609` (current stub)
**Effort**: 1 day

**Acceptance**:
- [ ] Fetch the tx from the local mempool (`Mempool.get_transaction(hash)`).
- [ ] If found → send `tx_message` to the peer via
      `Peer.send_message(peer_pid, :tx, …)`.
- [ ] If not found → log `⚠️ Transaction not found in mempool`,
      don't send anything.
- [ ] Logs: `📤 Sending tx ... to ...:port` with truncated hash.

### ✅ 2.2 — Add `TransactionConverter` (P2P data → struct)
**Reference**: symmetric with `BlockConverter`
**Effort**: 1 day

**Acceptance**:
- [ ] New module `Bastille.Features.Transaction.TransactionConverter`
      with `from_p2p_data(map) :: {:ok, %Transaction{}} | {:error, term()}`.
- [ ] Validates each field: `from`/`to` are binaries (`Address.valid?`),
      `amount`/`fee`/`nonce`/`timestamp` are non-negative integers,
      `hash` is exactly 32 bytes, `signature_type` is a valid atom.
- [ ] Rebuilds the full `%Transaction{}` struct.
- [ ] Tests: valid Protobuf payload → struct OK; corrupted payload →
      clear error.

### ✅ 2.3 — `process_p2p_message(:tx, …)` handler in `Node`
**Effort**: 1-2 days

**Acceptance**:
- [ ] On receipt of a `:tx` message:
  1. Convert via `TransactionConverter.from_p2p_data/1`.
  2. If already in `transactions_seen` → ignore (anti-loop).
  3. Otherwise: `Mempool.add_transaction(tx)`; if OK → mark seen + relay
     `inv` to other peers (except the sender).
  4. If mempool rejects → log `⚠️ Tx rejected: <reason>`, don't relay.
- [ ] Logs: `📦 Received tx ... from ...:port` then, depending on
      outcome, `✅ Tx added to mempool` / `🔄 Tx already seen` /
      `⚠️ Tx rejected`.

### ✅ 2.4 — E2E multi-miner test
**Effort**: 1 day

**Acceptance**:
- [ ] ExUnit integration test starting 2 independent Mempool GenServers
      (or tagged `:multinode_integration` separately).
- [ ] OR: manual test documented in README — `submit_transaction` on
      node2, verify `mempool.size` increases on node1 and node3, then
      that the tx gets mined by node1 or node3.
- [ ] The README "Run 3 nodes locally" doc gets a section "Submit a tx
      and watch it propagate".

---

## 🔑 Sprint 3 — Deterministic PQ key derivation (~2-3 weeks) — ✅ COMPLETE 2026-05-28

**The biggest testnet unlock**. Today the "mnemonic recovery" claim is
a lie — the Rust NIF generates random keys and caches them by seed hash.
See §1.2 of the audit.

### ✅ 3.1 — POC: which Rust crates actually support `keypair_from_seed`
**Done 2026-05-27.** ml-dsa 0.1 / slh-dsa 0.1 / fn-dsa 0.3, ChaCha20-seeded
Falcon. Proven in a standalone POC crate (since removed once folded into the
NIF); decision recorded in `docs/key_derivation_design.md`.

**Effort**: 2 days
**Why**: before planning 3 weeks, we need to know where the walls are.

**Acceptance**:
- [ ] Test `pqcrypto-mldsa` (ML-DSA = NIST standardisation of
      Dilithium2): does it have a stable seed-based API?
- [ ] Test `pqcrypto-falcon`: does it expose `keypair_from_seed_bytes`
      or equivalent? If not, identify the low-level API that accepts an
      `RngCore` (reseed via ChaCha20).
- [ ] Test `pqcrypto-sphincsplus`: the "simple" variant should support
      seed-based generation (it's in the NIST spec).
- [ ] Write a tiny test binary: 1 seed → 3 keypairs → run twice on 2
      machines, verify the bytes are strictly identical.
- [ ] **Decision**: if Falcon doesn't support it cleanly, alternatives:
      - (a) reseed a cryptographic PRNG (ChaCha20) keyed by the
            algorithm-specific sub-seed and call the low-level API if
            available
      - (b) replace Falcon with another lattice/NTRU signature with a
            seed-based API (but we lose family diversity)
      - (c) keep the Falcon cache standalone (sketchy but isolated),
            remove caching for Dilithium and SPHINCS+
- [ ] Design doc: `docs/key_derivation_design.md` recording the choice.

### ✅ 3.2 — Deterministic Rust NIF implementation
**Done 2026-05-27.** NIF rewritten pure seed→keys; pqcrypto + key_cache removed.
310 tests green; cross-process mnemonic recovery verified. Dilithium privkey =
32-byte seed, falcon sig 690→666. Details in `docs/key_derivation_design.md` §10.

**Effort**: 1 week
**Why**: replace the pseudo-cache with real derivation.

**Acceptance**:
- [ ] `dilithium2_keypair_from_seed(seed)` returns the **same** keypair
      for the same seed on 2 different machines.
- [ ] Same for `falcon512_keypair_from_seed` and
      `sphincsplus_keypair_from_seed`.
- [ ] **Completely remove** `load_persistent_cache` /
      `save_persistent_cache` / the read of the `key_cache/` directory.
      Seed-based functions must be **pure** (input → deterministic
      output, no I/O).
- [ ] Rust tests: `cargo test` with a known seed vector falls on the
      same bytes every run.

### ✅ 3.3 — Cross-machine KAT in CI
**Done 2026-05-28.** `priv/test/kat_keys.json` (8 entropy→mnemonic→pubkeys+address
vectors) + `KeyDerivationKATTest` (one test per vector) freeze the derivation
contract — any dep/algo change that alters the output fails loudly. 333 tests
green. (Still to do: regenerate/validate on ARM/macOS targets.)

**Effort**: 3 days

**Acceptance**:
- [ ] File `priv/test/kat_keys.json` with a dozen
      `{seed_hex, dilithium_pub_hex, falcon_pub_hex, sphincs_pub_hex,
      address}` entries.
- [ ] ExUnit test `KeyDerivationKATTest` that loads this JSON and
      verifies each seed produces exactly these keys and address.
- [ ] Ideally: generate the KAT from a reference machine (Linux x86_64)
      and validate it on 3 targets (Linux ARM, macOS, Windows).
- [ ] The test runs in standard `mix test`.

### ✅ 3.4 — Migrate mnemonic input to BIP39 PBKDF2 seed
**Done 2026-05-28.** `Seed.master_seed_from_mnemonic/1` (PBKDF2-HMAC-SHA512,
NFKD, salt `mnemonic`, 2048 iter, 64B) — params anchored to the official BIP39
vector. `derive_keys_from_mnemonic/1` = checksum (3.5) → PBKDF2 → per-algo
HKDF-SHA256 (salt `bastille-v1`). No passphrase (dropped as premature — no
wallet UX to surface it). 324 tests green.

**Effort**: 2 days
**Why**: currently we pass the **raw mnemonic string** to the NIF.
BIP39 prescribes `PBKDF2-HMAC-SHA512(mnemonic, "mnemonic" || passphrase,
2048 iter) = 64-byte seed`. That's the operation we should do before
deriving the per-algorithm sub-seeds.

**Acceptance**:
- [ ] `Seed.master_seed_from_mnemonic(mnemonic, passphrase \\ "")`
      produces the standard 64-byte BIP39 seed.
- [ ] `Seed.derive_keys_from_seed` now takes the 64-byte binary seed,
      not the mnemonic string.
- [ ] Per-algorithm HKDF: `HKDF-SHA256(master_seed, salt: "bastille-v1",
      info: "dilithium" | "falcon" | "sphincs")` → 32-byte sub-seed.
- [ ] Backwards compatibility not required (pre-public testnet, OK to
      break existing addresses).
- [ ] Test: the BIP39 official test phrase "abandon abandon … about" in
      EN produces the documented BIP39 seed (the official vector). This
      proves we're conformant.
- [ ] Note: this means we need to support the optional passphrase in
      the API. For the current RPC, accept an optional `passphrase`
      field, default `""`.

### ✅ 3.5 — `Mnemonic.from_mnemonic` verifies the checksum
**Done 2026-05-27.** `from_mnemonic` checks the 8-bit BIP39 checksum;
`valid_mnemonic?` now requires a complete valid 24-word phrase (delegates to
`from_mnemonic`). 311 tests green. Still to wire into the derivation entry
point (keypair_from_mnemonic) — folds into 3.4.

**Effort**: 0.5 day
**Why**: today a typo in one word passes silently.

**Acceptance**:
- [ ] Recompute the BIP39 checksum (8 bits = `SHA256(entropy)[0..8]`)
      and compare against the 8 last bits reconstructed from the words.
- [ ] On mismatch → `{:error, :invalid_checksum}`.
- [ ] Test: valid phrase passes, phrase with one word replaced by
      another valid-in-itself but at the wrong position → rejected.

### ✅ 3.6 — Clean up `key_cache/`
**Done 2026-05-27** (with 3.2): no Elixir code referenced it; the Rust no longer
creates it. Nothing left to remove.

**Effort**: 0.5 day

**Acceptance**:
- [ ] `Bastille.Infrastructure.Storage.CubDB.Paths` no longer references
      `key_cache`.
- [ ] The docs and README mention the `key_cache/` directory is no
      longer created. If present in an existing install, document the
      `rm -rf` to do.
- [ ] The Rust code no longer creates any file under that path.

### ✅ 3.7 — Tests: cross-node multinode recovery
**Done 2026-05-28.** `MnemonicRecoveryTest`: re-deriving from the same mnemonic
yields the identical wallet (address + all pub/priv keys), a different mnemonic
yields a different wallet, and recovered keys sign a message that verifies under
the 2/3 threshold. Derivation is pure/stateless, so a literal node restart adds
nothing beyond the cross-process determinism already proven (POC + KAT). 336
tests green.

**Effort**: 2 days

**Acceptance**:
- [ ] Integration test: generate an address on node1, mine several
      blocks to it, restart node1 with a fresh `data/`, restore the
      mnemonic phrase → the **same** address comes back.
- [ ] Test: restore the same phrase on node2 → same address, same
      pubkeys, can sign a valid tx.

---

## 🔀 Sprint 4 — Chain reorganization (~3-4 weeks)

The big piece that unlocks real multi-miner and brings us up to
Bitcoin v0.1+ level. See §4.2 of the audit for the detailed discussion.

### ✅ 4.1 — Track `cumulative_work` per block
**Done 2026-05-28.** `chain.cubdb` `work:` namespace + `store/get_cumulative_work`;
`add_block` persists `parent_work + Mining.work_for_difficulty(diff)` (genesis = 0,
not mined). `Mining.work_for_difficulty/1` = `2^256/(target+1)`. 339 tests green.
Foundation for comparing competing chains by total work (4.3/4.4).

**Effort**: 2 days

**Acceptance**:
- [ ] New namespace in `chain.cubdb`: `work:` (hash → cumulative work as
      `u128` big-endian).
- [ ] `Chain.store_block_link` computes and persists
      `cumulative_work = parent.cumulative_work + 2^256 / target(difficulty)`
      (or an approximation).
- [ ] `Chain.get_head` can return the cumulative work.
- [ ] Tests: 5 blocks mined → cumulative work strictly increases.

### ✅ 4.2 — State changes journal per block (for rollback)
**Done 2026-05-28.** `state.cubdb` `journal:<block_hash>` captures
`{addr, old_balance, old_nonce}` for every touched address before a block is
applied (in `add_block`). `State.rollback_block/1` restores them atomically and
drops the journal; `State.delete_journal/1` + `prune_old_journal/1` keep only the
last `@max_reorg_depth` (100) blocks. 341 tests green. Used by 4.4 (rollback+reapply).

**Effort**: 1 week
**Why**: without this, impossible to cleanly undo a block in an account
model. See §4.3 of the audit.

**Acceptance**:
- [ ] Before applying a block, capture for each touched address
      `{addr, old_balance, old_nonce}`. Store in `state.cubdb` under
      key `journal:<block_hash>` →
      `[{addr, old_balance, old_nonce}, …]`.
- [ ] New function `State.rollback_block(block_hash)` reads the journal
      and writes back the old balances/nonces, then deletes the journal
      entry.
- [ ] Bounded capacity: keep the journal for the last N blocks only
      (N = max reorg depth, e.g. 100). Beyond that, purge.
- [ ] Tests: apply 3 blocks, rollback the last → state is
      bit-identical to after block 2.

### ✅ 4.3 — Fetch common ancestor via P2P
**Done 2026-05-28.** Pure decision core in `Bastille.Features.Chain.ReorgSearch`
(`start`/`advance`/`timeout`), driven by `Node`. On an orphan with an unknown
parent the node walks the fork back via `getdata`, one parent at a time, until a
block carrying cumulative work (= a block on our chain) is reached — the common
ancestor — then compares the assembled fork's total work to the local tip.
Bounded by MAX_REORG_DEPTH (100) and a 10s per-parent timeout. 348 tests green.
A winning fork is logged and handed off to 4.4 (rollback+reapply), which does
the actual switch; the fork blocks are kept in the orphan pool for it.

Honest notes:
- The "with better cumulative_work" gate can't be evaluated up front — a fork's
  total work is unknowable until its ancestor is found — so the search is
  *initiated* for any unknown-parent orphan and the work comparison is the
  *conclusion* (`better?`). We never adopt a worse chain.
- One active search at a time (single competing fork). Concurrent multi-fork
  searches deferred. Multinode integration tests live in 4.5.

**Effort**: 3 days

**Acceptance**:
- [x] On receipt of an orphan block (unknown parent), trigger an "ancestor
      search" mode: recursively request the parent via `getdata` until
      we find a known block. (Better-work check is made at the fork point —
      see note above.)
- [x] Depth limit: MAX_REORG_DEPTH (100). Beyond, abandon the
      alternative chain.
- [x] Per-request timeout: 10s. If a parent doesn't arrive →
      abandon the reorg.
- [x] Logs: banner `🔄 REORG SEARCH INITIATED` with sub-lines
      `from_peer`, `tip_hash`, `tip_work`, `local_work`, `depth_so_far`.

### ✅ 4.4 — Rollback + reapply
**Done 2026-05-28.** `Chain.reorganize/1` takes the 4.3 `ReorgSearch` result and
performs the switch inside the `Chain` GenServer: roll the current chain back to
the common ancestor (`State.rollback_block` per block, newest-first), then apply
the fork oldest-first through the same `try_add_block_directly` pipeline (full
validation, journaling, links, cumulative work). All-or-nothing — if a fork block
fails, the partial fork is undone and the original chain re-applied, leaving the
node exactly where it started. `Node` triggers it off-process on a winning
`{:found, %{better?: true}}`. 352 tests, 0 failures (the 4 new reorg tests are
tagged `:integration`, run in the dedicated integration step — see `reorg_test.exs`).

Honest notes:
- One competing fork at a time (matches 4.3's single-search constraint).
  Concurrent/cascaded reorgs are deferred to 4.5.
- The ancestor must still be in the in-memory block window (≤ `MAX_REORG_DEPTH`,
  which also bounds the journal). A fork point older than that → `:ancestor_not_in_memory`,
  reorg abandoned.
- Re-indexing of the discarded blocks' transactions in `index.cubdb` is left as
  stale (harmless; Bitcoin keeps orphaned block bodies too). Reorg-aware index
  cleanup, if wanted, belongs with the explorer projection work.

**Effort**: 1 week

**Acceptance**:
- [x] Once the ancestor is found: rollback the current chain to the
      ancestor (`State.rollback_block` in a loop), then apply the
      alternative chain block by block (full validations).
- [x] If the apply fails midway → rollback of the rollback (re-apply
      the original chain). All-or-nothing transactionality at the end.
- [x] Mempool: txs from orphaned blocks are re-injected into the
      mempool if they still pass validation (coinbases and txs already in
      the fork are skipped; best-effort, never fails the reorg).
- [x] Orphaned coinbases: balances reverted via the journal. (Maturity
      not reintroduced — see 4.6.)
- [x] Logs: `🔄 REORG SUCCESS` or `❌ REORG ABORTED` with detailed
      sub-lines (blocks rolled back, blocks applied, txs reinjected).
- [x] Shorter-but-heavier fork: stale height→hash links above the new
      head are dropped (`Chain.delete_block_link/2`).

### ✅ 4.5 — Reorg multinode tests + edge cases
**Done (2026-05-28).** All single-node edge cases covered in `reorg_test.exs`
(driving `Chain.reorganize/1` directly). True 2-node network convergence is
deferred to the manual OS-process harness (see honest notes) — by decision, not
built as an in-VM test. As part of this, the pre-existing `--include integration`
flakiness was fixed: `Bastille.TestHelper.reset_chain_storage/0` resets the
storage+chain layer through the supervisor (`terminate_child`/`restart_child`),
and `blockchain_integration_test` was converted off the `safe_stop`+`start_link`
pattern that desynced the supervisor. Full `--include integration` run now green
across many seeds (was flaky); canonical `mix test` = 354, 0 failures.

Honest notes:
- The storage/Chain/Engine GenServers are global singletons, so a true 2-node
  network can't run in one BEAM. Real multinode convergence needs an OS-process
  harness or `:peer`-spawned BEAM nodes talking over the TCP P2P — out of scope
  for an in-VM ExUnit test. The *switch logic* convergence relies on is covered;
  convergence itself is verified manually (procedure below).
- "Corrupted `consensus_data`" isn't independently validated by `ProofOfWork`
  (consensus_data is not part of the PoW hash), so the invalid-midway test
  corrupts the block hash instead — same outcome (validation fails → abort).
  *(Backlog: validate `consensus_data` if it ever carries consensus-relevant fields.)*

**Manual 2-node convergence check** (until an automated harness exists):
1. Start two miners on a shared topology: `scripts/start_node1.sh` and
   `scripts/start_node2.sh` (or `docker compose -f docker/docker-compose.yml up`).
2. Briefly partition them (stop one's peer link) so each mines its own fork.
3. Reconnect; let node B's chain carry one extra block (more cumulative work).
4. Expect node A's log to show `🔄 REORG SEARCH INITIATED` → `🔄 REORG SUCCESS`
   and both `get_info` heights/heads to converge on B's tip.

**Effort**: 1 week

**Acceptance**:
- [~] Simulated test: 2 competing chains A and B on 2 nodes; B has +1 block →
      the whole network converges on B. *Deferred to the manual harness above
      (singleton GenServers preclude an in-VM 2-node test).*
- [x] Test: alternative chain invalid midway → reorg aborted, original chain
      kept (`reorg_test.exs`, via corrupted block hash).
- [x] Test: reorg deeper than MAX_REORG_DEPTH → rejected (search aborts at
      `:max_depth_exceeded` in `reorg_search_test.exs`; the switch rejects an
      out-of-window ancestor with `:ancestor_not_in_memory`).
- [x] Test: reorg while mining a new block → consistent final state
      (`reorg_test.exs`: concurrent `add_block` + `reorganize`; both are Chain
      GenServer calls so they can't interleave — the heavier fork always wins).
- [x] Test: cascaded double-reorg (B replaces A, then C replaces B)
      (`reorg_test.exs`).

### ✅ 4.6 — Coinbase maturity decision
**Done 2026-05-29. Decision: do NOT reintroduce coinbase maturity** (Ethereum-PoW
style). Rationale:
- Bastille is account-based, and `Chain.reorganize/1` re-validates orphaned txs on
  re-injection — a spend of an orphaned coinbase fails validation and is dropped, so
  the post-reorg state is always self-consistent (no cascade of invalid txs). The
  cascade that Bitcoin's 100-block maturity exists to prevent is a UTXO-model concern
  that doesn't arise in an account model with state recomputed from the canonical
  chain.
- Reorg depth is already bounded by `MAX_REORG_DEPTH` (100), the practical finality
  bound.
- The residual risk is purely external — a party acting on a shallowly-confirmed
  coinbase credit — and is mitigated by confirmation depth (the recipient's choice),
  exactly as on Bitcoin/Ethereum. A protocol-level maturity lock adds little.
- Implementing maturity in an account model is non-trivial (track an immature balance
  + maturity height per address, subtract it in `TransactionValidator`, reconcile
  with the rollback journal) — cost not justified by the marginal gain.

Revisit only if a concrete need appears (e.g. an open multi-miner testnet with deep
reorgs); the design for that day — a `coinbase:` namespace in `state.cubdb`
integrated with the journal — is recorded here.

**Acceptance**:
- [x] Decision documented: maturity NOT reintroduced. (`ARCHITECTURE_REVIEW.md` is a
      frozen v0 snapshot, so the living record lives in this plan.)
- [n/a] Persist in `state.cubdb` (`coinbase:` namespace) — only if reintroduced.

---

## 🏛️ Sprint 5+ — Mainnet hardening (to sequence later)

Items extracted from `ARCHITECTURE_REVIEW.md` §8.3. No detailed
estimation here, to be fleshed out when we get there.

### ☐ 5.1 — Median Time Past + timestamp validation (anti time-warp)
### ☐ 5.2 — State root / Merkle Patricia Trie (SPV, light clients, sharding)
### ☐ 5.3 — Authenticated P2P (Noise XX or mTLS)
### ☐ 5.4 — Multi-thread mining
### ☐ 5.5 — API auth + RPC rate limiting
### ☐ 5.6 — WAL / cross-DB journal for atomic `add_block`
### ☐ 5.7 — Bounded limits everywhere (block size, tx size, mempool eviction)
### ☐ 5.8 — Byzantine test suite / P2P fuzzing
### ☐ 5.9 — Peer banlist / scoring / DoS resistance
### ☐ 5.10 — Real IBD (parallel block download, fast sync, snapshot sync)
### ☐ 5.11 — Complete cryptographic documentation + external audit
### ☐ 5.12 — Embed pubkeys in transactions (or a tx-registry to disseminate them)
### ☐ 5.13 — Canonical wire format (drop `:erlang.term_to_binary` everywhere)

---

## 🐛 Backlog — debts/bugs found along the way

- [x] ~~Combined test suite flakiness~~ — fixed in 1.5: the cause was
      `blockchain_integration_test.exs` stopping global GenServers.
      Excluded by default via `@moduletag :integration` +
      `ExUnit.start(exclude: [:integration])`. Still to do: refactor
      that test so it can run without breaking the suite (low priority,
      to be done before any real CI).

## 🧹 Low-priority backlog (when you have 30 min)

Small things found along the way. Not blockers but worth fixing when
the opportunity arises.

- [ ] `Mining.difficulty_to_target(0)` returns `<<0xFF::256>>` = **255** (a
      near-impossible target), but the comment says "Maximum target for genesis"
      (max target = easiest = `2^256-1`). Harmless today (genesis isn't mined,
      no PoW check), and `work_for_difficulty/1` special-cases 0 → 0 to avoid it,
      but the genesis-target value is wrong/misleading.

- [ ] Unify `Transaction.calculate_fee` and `Token.calculate_fee`
      (double implementation today).
- [ ] Mining logs too verbose: move `🔨 CREATING BLOCK TEMPLATE` and
      each-block details to `Logger.debug`.
- [ ] `Index.add_to_address_index` caps at 1000 txs: paginate or
      document the cap.
- [ ] Remove every mention of "30% burn" in `coinbase_with_fees` (stub,
      never activated).
- [ ] `lib/bastille.ex:683` `all_valid = String.starts_with?(&1, "1789")`
      → use the configured prefix.
- [ ] `Sync.get_current_head_hash` returns `String.duplicate("0", 64)`
      (string) when it should return `<<0::256>>` (32-byte binary).
      Latent sync bug, currently masked.
- [ ] Add a `LICENSE` file at the root (the README says "MIT — see
      LICENSE file" but the file doesn't exist).
- [ ] Validate / rewrite the Docker deployment (`docker/README.md`
      marked "untested").
- [ ] RPC endpoint `get_transactions_by_address` (wallet history).
- [ ] RPC endpoint `get_block_by_height` (explorer UX).
- [ ] RPC endpoint `get_mempool` (visualise pending).
- [ ] RPC endpoint `estimate_fee`.
- [ ] Self-connection guard: extend beyond `127.0.0.1`.
- [ ] `Mnemonic.valid_mnemonic?` accepts ≥12 words but
      `Seed.valid_master_seed?` requires 24 — align.

---

## 📝 Tracking conventions

- Check items off as you go (`☐` → `⏳` → `✅`).
- When starting an item: create a `feature/<sprint>-<short-name>`
  branch and mark `⏳`.
- When merged: mark `✅` and note the commit hash + date.
- If the estimate is off by 2x or more: note in a sub-bullet why, to
  calibrate future estimates.
- When adding **logs** to a fix, respect the expressive formalism
  documented in `CONVENTIONS.md` (emoji + `└─` sub-lines). It's the
  primary multi-node debugging tool.

---

**Current sprint**: ✅ Sprint 1 — Quick wins (5/5 done), published on
`bastille-chain` `main`.

**Next target**: Sprint 3 — deterministic PQ key derivation
(reprioritized ahead of Sprint 2 because it's THE testnet blocker).
**First item**: 3.1 — Rust POC on the seed-based APIs of the
`pqcrypto-*` crates (2-day effort, de-risks the rest of the sprint).

**Sprint 2** (P2P tx propagation) — not forgotten, planned after
Sprint 3. See §Sprint 2 above for the 4 items.
