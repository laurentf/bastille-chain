# Deterministic PQ Key Derivation — Design (Sprint 3.1 outcome)

**Date:** 2026-05-27
**Status:** POC validated → **Sprint 3.2 implemented and green** (see §10).
**Implementation:** `native/bastille_crypto/src/lib.rs` (the Rust NIF). The approach
was first proven in a standalone `native/keygen_poc/` crate, since removed once
folded into the NIF.

---

## 1. Problem (what we are replacing)

`native/bastille_crypto/src/lib.rs` exposes `*_keypair_from_seed(seed)` whose
name and comment (`// deterministic via persistent caching`) claim determinism,
but the body calls the **non-deterministic** PQClean API and uses `seed` only
as a disk-cache filename:

```rust
let (pk, sk) = dilithium2::keypair();   // OS RNG — seed is ignored
save_persistent_cache(blake3("dilithium2_v1:" ++ seed), pk, sk);
```

Consequences:
- Same mnemonic + empty `data/` (new machine, or `rm -rf key_cache/`) ⇒ **new
  random keys ⇒ different address ⇒ funds unrecoverable**. Mnemonic recovery is
  a lie.
- Secret keys are written **in clear** to `data/<env>/key_cache/*.keypair`.
- The whole `pqcrypto-*` family (PQClean wrappers) **cannot** do seed-based
  keygen: PQClean's `crypto_sign_keypair` calls `randombytes()` internally and
  exposes no seeded entry point in the public API. This is structural, not a
  bug we can patch around cleanly.

The Elixir side is actually correct: `Seed.derive_keys_from_seed/1` →
`Crypto.derive_algorithm_seed/2` = `HMAC-SHA256(master_seed, algo)` produces a
sound 32-byte per-algorithm sub-seed. The seed simply dies at the NIF boundary.

## 2. Decision

Replace the PQClean wrappers with **pure-Rust, FIPS-aligned crates that derive
keys from bytes/seed**, and derive each algorithm's sub-seed deterministically.

| Algorithm (Bastille name) | Standard | Crate (pinned) | Keygen entry point | Determinism source |
|---|---|---|---|---|
| Dilithium2  | ML-DSA-44 (FIPS 204)        | `ml-dsa = "0.1.0"`  | `SigningKey::<MlDsa44>::from_seed(&B32)` | 32-byte seed, **FIPS keygen_internal — portable across any conformant impl** |
| SPHINCS+-SHAKE-128f | SLH-DSA-SHAKE-128f (FIPS 205) | `slh-dsa = "0.1.0"` | `SigningKey::<Shake128f>::slh_keygen_internal(sk_seed, sk_prf, pk_seed)` | 3×16-byte seeds, **FIPS keygen_internal — portable** |
| Falcon-512  | FN-DSA-512 (FIPS 206 draft) | `fn-dsa = "0.3.0"`  | `kg.keygen(LOGN_512, &mut rng, sk, vk)` | seeded **ChaCha20** CSPRNG → **impl-locked to `fn-dsa`** (see §6) |

Verifying-key sizes (confirmed by POC, identical to the current PQClean keys, so
addresses keep the same shape): **ML-DSA-44 = 1312 B, SLH-DSA-128f = 32 B,
FN-DSA-512 = 897 B**.

Backward compatibility is **not** preserved — all existing addresses change.
This is acceptable per the plan (pre-public-testnet).

## 3. Dependency hazards (POC findings — important)

The RustCrypto PQ crates are early (0.1.0) and drag pre-release transitive deps.
The lockfile must pin around three traps:

1. **`signature` pre-release drift.** `slh-dsa 0.1.0` requires
   `signature = "2.3.0-pre.4"`. Cargo greedily resolves to `2.3.0-pre.7`, which
   bumped its `rand_core` 0.6→0.9 and **removed `CryptoRngCore`**, so `slh-dsa`
   fails to compile (`cannot find trait CryptoRngCore`). **Fix: pin
   `signature = "=2.3.0-pre.4"`.**
2. **Three `rand_core` versions coexist** (0.6.4 for slh-dsa/fn-dsa, 0.9.5 for
   ml-dsa, 0.10.1 transitive). We **avoid** the RNG-trait version war by using
   the **byte-seed** APIs for ml-dsa and slh-dsa (no RNG at all).
3. **Falcon needs an RNG at the `rand_core 0.6` ABI.** `fn-dsa::keygen` is
   generic over `CryptoRng + RngCore` (rand_core 0.6). Its internal
   `keygen_from_seed` is private, so we feed it a deterministic CSPRNG:
   **`rand_chacha = "0.3"`** (ChaCha20Rng implements rand_core 0.6). Do **not**
   use `rand_chacha 0.10` (rand_core 0.9 → trait mismatch).

Exact versions validated: `ml-dsa 0.1.0`, `slh-dsa 0.1.0`, `fn-dsa 0.3.0`,
`signature =2.3.0-pre.4`, `rand_chacha 0.3.1`, `rand_core 0.6.4`, `hkdf 0.13.0`,
`sha2 0.11.0`, `hybrid-array 0.2.3`.

## 4. Derivation pipeline

```
mnemonic (24 FR words)
  └─ [3.4] PBKDF2-HMAC-SHA512(mnemonic, "mnemonic", 2048) = master_seed (64 B)   # BIP39
       └─ HKDF-SHA256(ikm=master_seed, salt="bastille-v1", info=<algo>) = sub_seed
            ├─ "dilithium" → 32 B → ml-dsa  SigningKey::from_seed
            ├─ "sphincs"   → 48 B → slh-dsa slh_keygen_internal(0..16, 16..32, 32..48)
            └─ "falcon"    → 32 B → ChaCha20Rng::from_seed → fn-dsa keygen
```

No disk I/O, no OS RNG. `key_cache/` is removed entirely (Sprint 3.6).

> **Implemented in 3.4 (2026-05-28).** `Seed.master_seed_from_mnemonic/1` does
> the BIP39 PBKDF2 step (salt `mnemonic`, no passphrase — dropped as premature);
> `Crypto.derive_algorithm_seed/2` is now HKDF-SHA256(salt `bastille-v1`, info
> = algo). These salt/info strings are the canonical Bastille domain separators
> and must be frozen by the KAT (3.3).

## 5. POC evidence

From the standalone POC (since removed), `cargo test` (3/3) + a cross-process run:

```
dilithium pub = 1312 bytes
sphincs   pub = 32 bytes
falcon    pub = 897 bytes
address       = 178930e9520d3aef3490a51f8cfaf1084a549d0364be
DETERMINISM (two derivations, same seed) = IDENTICAL
RUN#1 == RUN#2  (identical across fresh OS processes)
```

Tests: `deterministic_across_derivations`, `different_seed_different_keys`
(seed actually drives output), `key_sizes`.

## 6. Determinism guarantee — a sharp asymmetry to record

- **Dilithium (ML-DSA) and SPHINCS+ (SLH-DSA):** keygen is defined by the FIPS
  `keygen_internal` function of the seed bytes. Output is portable across **any**
  conformant implementation. A wallet built on these can be recovered with a
  different library. KAT is a conformance check.
- **Falcon (FN-DSA):** there is no portable "seed → key" standard. Our keys are
  defined by `(ChaCha20 seed bytes) + (fn-dsa 0.3.0 keygen algorithm, incl. its
  NTRU rejection-sampling RNG consumption)`. They are **not** reproducible by a
  different Falcon implementation or, potentially, a different `fn-dsa` version.

**Implication:** Falcon recovery is locked to the pinned `fn-dsa` version + our
ChaCha construction. We MUST: pin `fn-dsa` exactly, freeze the ChaCha-seeding
convention, and capture Falcon KATs (3.3). A future `fn-dsa` bump requires
re-validating the KAT before shipping. Documented here so it is a conscious
choice, not an accident.

(Alternative considered and rejected for now: option (c) "keep Falcon cache" —
reintroduces the disk-cache anti-pattern. Option (b) "swap Falcon for another
NTRU sig" — loses signature-family diversity, which is the point of 2/3.)

## 7. Format / size impact + a latent bug found

- Addresses change (new key bytes). Acceptable pre-testnet.
- **Bug to fix regardless of Sprint 3:** `Crypto.sphincs_signature_size/0`
  returns `7856`, the **128s** signature size, but the code uses
  `sphincsshake128fsimple` (**128f**), whose signature is **17088** bytes.
  Currently only used in a test with random bytes, so masked — but wrong.
  → tracked in the quick-fixes task.

## 7b. Exact format impact for 3.2 (verified against crate sources)

sign/verify must migrate to the same crates as keygen (new key bytes are not
parseable by PQClean). Verified sizes:

| | pub | priv | sig | vs current Bastille constant |
|---|---|---|---|---|
| ML-DSA-44 | 1312 ✓ | **32 (seed)** or 2560 (expanded) | 2420 ✓ | `dilithium_private_key_size = 2560` — **decision** |
| SLH-DSA-128f | 32 ✓ | 64 ✓ | 17088 ✓ (constant already fixed) | clean |
| FN-DSA-512 | 897 ✓ | 1281 ✓ | **666** | `falcon_signature_size = 690` → **change to 666** |

APIs: ML-DSA sign via `SigningKey::sign` (deterministic, no RNG); verify via
`VerifyingKey::verify`. SLH-DSA sign/verify via its `signature` traits. FN-DSA
sign is **randomized** (`SigningKey::sign(rng, …)`) — needs an RNG at sign time
(signatures need not be deterministic, only keys).

**Open decision — Dilithium private-key representation:**
- (a) **32-byte seed** (ml-dsa `to_bytes -> Seed`, idiomatic): simplest; sign =
  `from_seed(seed).sign()`. Since the key is HKDF-derived anyway, the seed *is*
  the natural private key. Requires `dilithium_private_key_size 2560 → 32` + test
  updates.
- (b) **2560-byte expanded** (`to_expanded`/`from_expanded`, **deprecated** in
  0.1.0): keeps the current size constant, no test churn, but uses a deprecated
  API.

## 8. Plan for 3.2 – 3.7 (now de-risked)

- **3.2 Deterministic NIF.** Rewrite `native/bastille_crypto/src/lib.rs`:
  `dilithium2_keypair_from_seed`, `falcon512_keypair_from_seed`,
  `sphincsplus_keypair_from_seed` become **pure** (seed in → keys out), backed
  by ml-dsa / slh-dsa / fn-dsa as above. Delete `load/save_persistent_cache`,
  `get_cache_dir`, the unused `DETERMINISTIC_CACHE` lazy_static, and the `rand`
  dep. Keep sign/verify on the same crates (sizes already match). Decide whether
  to keep PQClean wrappers for verify-only or migrate fully (prefer full migrate
  for format consistency).
- **3.3 Cross-machine KAT.** `priv/test/kat_keys.json` of
  `{seed_hex → dil_pub, falcon_pub, sphincs_pub, address}`; `KeyDerivationKATTest`
  in ExUnit. Generate from this Linux x86_64 reference; validate on ARM/macOS.
- **3.4 BIP39 PBKDF2 front-end** (Elixir `Seed`), per §4. Anchor params to the
  official BIP39 EN test vector. (No passphrase — dropped as premature.)
- **3.5 Mnemonic checksum** in `Mnemonic.from_mnemonic` + align
  `valid_mnemonic?` (≥12) with `valid_master_seed?` (==24).
- **3.6 Remove `key_cache/`** from `Paths` + Rust; document `rm -rf` for old
  installs.
- **3.7 Multinode recovery test:** generate on node1, wipe `data/`, restore
  mnemonic → same address; restore on node2 → same address, can sign.

## 9. Open questions

- Confirm `ml-dsa`/`slh-dsa` **signing** APIs and sizes match the current
  consumers (sig sizes: ML-DSA-44 2420, SLH-DSA-128f **17088**, FN-DSA-512 ~666).
- Rustler NIF must expose pure functions; ensure no `rand`/OS entropy leaks into
  the seeded paths.
- Pin strategy: add a CI check that the lockfile keeps `signature =2.3.0-pre.4`
  and `fn-dsa 0.3.0` (a silent bump breaks Falcon recovery — §6).

## 10. Sprint 3.2 — implemented (2026-05-27)

`native/bastille_crypto/src/lib.rs` fully rewritten. `keypair_from_seed` is now
pure (seed → keys); `keypair`/`sign`/`verify` migrated to ml-dsa/slh-dsa/fn-dsa.
The disk cache (`load/save_persistent_cache`, `get_cache_dir`) and the unused
in-memory cache are gone. `pqcrypto-*` dropped from `Cargo.toml`.

Verified:
- `mix test` → **310 tests, 0 failures** (stable over repeated runs).
- Cross-process recovery: same mnemonic → same address in two fresh BEAMs
  (`f7890e064493eaec664a0292e900356bdcdd92160378`), no `key_cache/` created.

Wire formats / decisions as implemented:
- **Dilithium private key = 32-byte ML-DSA seed** (`dilithium_private_key_size`
  2560 → 32). Sign = `from_seed(seed).expanded_key().sign_deterministic(msg, "")`.
- **Falcon signature = 666 bytes** (`falcon_signature_size` 690 → 666). Falcon
  signing is randomized (`OsRng`); keygen-from-seed is deterministic (ChaCha20).
- **SPHINCS+**: sign/verify use the `Signer`/`Verifier` (pure external) pair.
  GOTCHA found in testing: `slh_sign_internal` (FIPS *internal*) does **not**
  verify against the `Verifier` (*pure*) variant — they must be paired.
- SPHINCS sub-seed: 32-byte Elixir sub-seed expanded to 3×16 via
  `blake3 XOF(key="bastille-slh-dsa-v1")`. Freeze this for the KAT (3.3).
- Per-algo sub-seed derivation still happens in Elixir
  (`Crypto.derive_algorithm_seed` = HMAC-SHA256); BIP39 PBKDF2 front-end is 3.4.

Sprint 3.6 (remove `key_cache/`) is effectively done: no Elixir code referenced
it, and the Rust no longer creates it.

Update: 3.4 (BIP39 PBKDF2) and 3.5 (mnemonic checksum) are now done too.
Remaining: 3.3 (cross-machine KAT) and 3.7 (multinode recovery integration test).
