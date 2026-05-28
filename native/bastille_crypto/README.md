# 🔐 Bastille Crypto NIF

Native Rust implementations for Bastille's post-quantum cryptography and Blake3
proof-of-work, exposed to Elixir via Rustler.

## 🚀 Overview

- **Post-quantum signatures**: Dilithium2 (ML-DSA-44), Falcon512 (FN-DSA-512),
  SPHINCS+ SHAKE-128f (SLH-DSA-128f).
- **Deterministic key derivation**: every keypair can be derived purely from a
  seed (`*_keypair_from_seed`), byte-identical across processes and machines —
  no OS RNG, no on-disk key cache. This is what makes BIP39 mnemonic recovery
  work; the derivation design is documented in `docs/key_derivation_design.md`.
- **Blake3 hashing**: `blake3_hash/1`, the hash behind Bastille's Blake3
  proof-of-work (a low-memory alternative to RandomX — Bastille does **not** use
  RandomX).

## 🛠️ Build requirements

- **Rust**: stable toolchain (via `rustup`).
- **Rustler**: Elixir ↔ Rust integration (declared in `mix.exs`).

No CMake / RandomX dependency.

## 🔧 Building

The NIF builds automatically with the project:

```bash
mix compile                 # development
MIX_ENV=prod mix compile    # production
mix clean && mix compile    # force rebuild
```

## 📋 Functions

### Post-quantum signatures

- `dilithium2_keypair/0`, `dilithium2_keypair_from_seed/1`
- `dilithium2_sign/2`, `dilithium2_verify/3`
- `falcon512_keypair/0`, `falcon512_keypair_from_seed/1`
- `falcon512_sign/2`, `falcon512_verify/3`
- `sphincsplus_shake_128f_keypair/0`, `sphincsplus_keypair_from_seed/1`
- `sphincsplus_shake_128f_sign/2`, `sphincsplus_shake_128f_verify/3`

### Hashing

- `blake3_hash/1` — single Blake3 hash, used for proof-of-work.

### Introspection

- `nifs_loaded/0`, `get_algorithm_info/0`

The Elixir side wraps these in `Bastille.Infrastructure.Crypto.CryptoNif` and the
higher-level `Bastille.Shared.Crypto` (which composes the three signatures into a
2-of-3 post-quantum scheme and derives `1789…` / `f789…` addresses).

## 🧪 Testing

```bash
mix test test/bastille/infrastructure/crypto/crypto_nif_test.exs
mix test test/bastille/shared/crypto_test.exs
mix test test/bastille/shared/key_derivation_kat_test.exs   # frozen KAT vectors
```

## 🏰 Vive la Révolution ! 🇫🇷
