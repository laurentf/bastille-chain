# 🔐 Bastille Crypto NIF

Native Rust implementations for Bastille blockchain cryptography.

## 🚀 Overview

This NIF (Native Implemented Function) provides high-performance Rust implementations for:

- **Post-Quantum Cryptography**: Dilithium, Falcon, SPHINCS+ signatures
- **Real RandomX Mining**: Authentic RandomX algorithm with ~2GB memory requirement
- **Address Generation**: "1789..." revolutionary address format
- **Multi-signature Support**: 2/3 threshold post-quantum signatures

## 🛠️ Build Requirements

- **Rust**: Latest stable version
- **CMake**: For RandomX compilation  
- **Visual C++ Build Tools 2022**: Windows compilation
- **Rustler**: Elixir-Rust integration

## 🔧 Building

The NIF builds automatically with the Bastille project:

```bash
# Development build
mix compile

# Production build
MIX_ENV=prod mix compile

# Force rebuild
mix clean && mix compile
```

## 📋 Functions

### Post-Quantum Cryptography
- `generate_keypair/1` - Generate Dilithium/Falcon/SPHINCS+ keys
- `sign/3` - Create post-quantum signatures
- `verify/4` - Verify post-quantum signatures
- `multi_sign/3` - 2/3 threshold signatures
- `multi_verify/4` - Verify threshold signatures

### RandomX Mining  
- `randomx_init_cache/1` - Initialize RandomX cache (~2GB)
- `randomx_hash/2` - Compute RandomX hash
- `randomx_mine/5` - Complete mining with nonce search
- `randomx_verify/4` - Verify RandomX proof-of-work

### Address System
- `generate_address/1` - Create "1789..." addresses
- `validate_address/1` - Validate address format and checksum

## 🧪 Testing

Tests are integrated with the main Bastille test suite:

```bash
# Test post-quantum crypto NIFs
mix test test/bastille/core/crypto_test.exs

# Test RandomX NIFs
mix test test/bastille/core/randomx_nif_test.exs

# Performance benchmarks
mix test test/performance/benchmark_test.exs --include performance
```

## ⚡ Performance

- **RandomX**: Optimized for modern CPUs with ~2GB memory requirement
- **Post-Quantum**: Hardware-accelerated where available
- **Memory**: Efficient allocation and deallocation
- **Threading**: Multi-threaded RandomX mining support

## 🏰 Vive la Révolution !

Revolutionary cryptography for the people! 🇫🇷
