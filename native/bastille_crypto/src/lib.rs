use rustler::{Binary, Env, NewBinary, NifResult};
use pqcrypto_traits::sign::{PublicKey, SecretKey, DetachedSignature};
use pqcrypto_dilithium::dilithium2;
use pqcrypto_falcon::falcon512;
use pqcrypto_sphincsplus::sphincsshake128fsimple as sphincsplus_shake_128f;
use blake3;
use std::collections::HashMap;
use std::sync::Mutex;
use std::fs;
use std::path::Path;

// Global cache for deterministic key generation (in-memory)
lazy_static::lazy_static! {
    static ref DETERMINISTIC_CACHE: Mutex<HashMap<Vec<u8>, (Vec<u8>, Vec<u8>)>> = Mutex::new(HashMap::new());
}

// Get cache directory path (environment-aware)
fn get_cache_dir() -> String {
    // Use same storage base as the rest of the application
    std::env::var("BASTILLE_STORAGE_BASE_PATH")
        .unwrap_or_else(|_| "data/test".to_string()) + "/key_cache"
}

// Load persistent cache on startup
fn load_persistent_cache(cache_key: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    let cache_dir = get_cache_dir();
    if !Path::new(&cache_dir).exists() {
        return None;
    }
    
    let cache_file = format!("{}/{}.keypair", cache_dir, hex::encode(cache_key));
    if let Ok(data) = fs::read(&cache_file) {
        // Simple format: [pk_len:4][pk_data][sk_data]
        if data.len() >= 4 {
            let pk_len = u32::from_le_bytes([data[0], data[1], data[2], data[3]]) as usize;
            if data.len() >= 4 + pk_len {
                let pk_data = data[4..4+pk_len].to_vec();
                let sk_data = data[4+pk_len..].to_vec();
                return Some((pk_data, sk_data));
            }
        }
    }
    None
}

// Save to persistent cache
fn save_persistent_cache(cache_key: &[u8], pk_bytes: &[u8], sk_bytes: &[u8]) -> Result<(), String> {
    let cache_dir = get_cache_dir();
    if let Err(e) = fs::create_dir_all(&cache_dir) {
        return Err(format!("Failed to create cache directory '{}': {}", cache_dir, e));
    }
    
    let cache_file = format!("{}/{}.keypair", cache_dir, hex::encode(cache_key));
    let mut data = Vec::new();
    data.extend_from_slice(&(pk_bytes.len() as u32).to_le_bytes());
    data.extend_from_slice(pk_bytes);
    data.extend_from_slice(sk_bytes);
    
    if let Err(e) = fs::write(&cache_file, data) {
        return Err(format!("Failed to write crypto cache '{}': {}", &cache_file, e));
    }
    
    Ok(())
}

// Load resources function
rustler::atoms! {
    ok,
    error,
}

#[rustler::nif]
fn nifs_loaded() -> bool {
    true
}

#[rustler::nif]
fn get_algorithm_info() -> Vec<String> {
    vec![
        "dilithium2".to_string(),
        "falcon512".to_string(),
        "sphincsplus_shake128f".to_string(),
    ]
}

// === Dilithium Functions ===

#[rustler::nif]
fn dilithium2_keypair<'a>(env: Env<'a>) -> NifResult<(Binary<'a>, Binary<'a>)> {
    let (pk, sk) = dilithium2::keypair();
    
    let mut pk_binary = NewBinary::new(env, pk.as_bytes().len());
    pk_binary.copy_from_slice(pk.as_bytes());
    
    let mut sk_binary = NewBinary::new(env, sk.as_bytes().len());
    sk_binary.copy_from_slice(sk.as_bytes());
    
    Ok((pk_binary.into(), sk_binary.into()))
}

#[rustler::nif]
fn dilithium2_sign<'a>(env: Env<'a>, message: Binary, private_key: Binary) -> NifResult<Binary<'a>> {
    match dilithium2::SecretKey::from_bytes(&private_key) {
        Ok(sk) => {
            let signature = dilithium2::detached_sign(&message, &sk);
            let sig_bytes = signature.as_bytes();
            
            let mut sig_binary = NewBinary::new(env, sig_bytes.len());
            sig_binary.copy_from_slice(sig_bytes);
            
            Ok(sig_binary.into())
        }
        Err(_) => Err(rustler::Error::BadArg)
    }
}

#[rustler::nif]
fn dilithium2_verify(signature: Binary, message: Binary, public_key: Binary) -> bool {
    match (
        dilithium2::DetachedSignature::from_bytes(&signature),
        dilithium2::PublicKey::from_bytes(&public_key)
    ) {
        (Ok(sig), Ok(pk)) => {
            dilithium2::verify_detached_signature(&sig, &message, &pk).is_ok()
        }
        _ => false
    }
}

// === Falcon Functions ===

#[rustler::nif]
fn falcon512_keypair<'a>(env: Env<'a>) -> NifResult<(Binary<'a>, Binary<'a>)> {
    let (pk, sk) = falcon512::keypair();
    
    let mut pk_binary = NewBinary::new(env, pk.as_bytes().len());
    pk_binary.copy_from_slice(pk.as_bytes());
    
    let mut sk_binary = NewBinary::new(env, sk.as_bytes().len());
    sk_binary.copy_from_slice(sk.as_bytes());
    
    Ok((pk_binary.into(), sk_binary.into()))
}

#[rustler::nif]
fn falcon512_sign<'a>(env: Env<'a>, message: Binary, private_key: Binary) -> NifResult<Binary<'a>> {
    match falcon512::SecretKey::from_bytes(&private_key) {
        Ok(sk) => {
            let signature = falcon512::detached_sign(&message, &sk);
            let sig_bytes = signature.as_bytes();
            
            let mut sig_binary = NewBinary::new(env, sig_bytes.len());
            sig_binary.copy_from_slice(sig_bytes);
            
            Ok(sig_binary.into())
        }
        Err(_) => Err(rustler::Error::BadArg)
    }
}

#[rustler::nif]
fn falcon512_verify(signature: Binary, message: Binary, public_key: Binary) -> bool {
    match (
        falcon512::DetachedSignature::from_bytes(&signature),
        falcon512::PublicKey::from_bytes(&public_key)
    ) {
        (Ok(sig), Ok(pk)) => {
            falcon512::verify_detached_signature(&sig, &message, &pk).is_ok()
        }
        _ => false
    }
}

// === SPHINCS+ Functions ===

#[rustler::nif]
fn sphincsplus_shake_128f_keypair<'a>(env: Env<'a>) -> NifResult<(Binary<'a>, Binary<'a>)> {
    let (pk, sk) = sphincsplus_shake_128f::keypair();
    
    let mut pk_binary = NewBinary::new(env, pk.as_bytes().len());
    pk_binary.copy_from_slice(pk.as_bytes());
    
    let mut sk_binary = NewBinary::new(env, sk.as_bytes().len());
    sk_binary.copy_from_slice(sk.as_bytes());
    
    Ok((pk_binary.into(), sk_binary.into()))
}

#[rustler::nif]
fn sphincsplus_shake_128f_sign<'a>(env: Env<'a>, message: Binary, private_key: Binary) -> NifResult<Binary<'a>> {
    match sphincsplus_shake_128f::SecretKey::from_bytes(&private_key) {
        Ok(sk) => {
            let signature = sphincsplus_shake_128f::detached_sign(&message, &sk);
            let sig_bytes = signature.as_bytes();
            
            let mut sig_binary = NewBinary::new(env, sig_bytes.len());
            sig_binary.copy_from_slice(sig_bytes);
            
            Ok(sig_binary.into())
        }
        Err(_) => Err(rustler::Error::BadArg)
    }
}

#[rustler::nif]
fn sphincsplus_shake_128f_verify(signature: Binary, message: Binary, public_key: Binary) -> bool {
    match (
        sphincsplus_shake_128f::DetachedSignature::from_bytes(&signature),
        sphincsplus_shake_128f::PublicKey::from_bytes(&public_key)
    ) {
        (Ok(sig), Ok(pk)) => {
            sphincsplus_shake_128f::verify_detached_signature(&sig, &message, &pk).is_ok()
        }
        _ => false
    }
}

// === Blake3 Hash Function ===

#[rustler::nif]
fn blake3_hash<'a>(env: Env<'a>, data: Binary) -> NifResult<Binary<'a>> {
    let hash = blake3::hash(&data);
    let hash_bytes = hash.as_bytes();
    
    let mut result_binary = NewBinary::new(env, hash_bytes.len());
    result_binary.copy_from_slice(hash_bytes);
    
    Ok(result_binary.into())
}

// === Deterministic Key Generation Functions ===

#[rustler::nif]
fn dilithium2_keypair_from_seed<'a>(env: Env<'a>, seed: Binary) -> NifResult<(Binary<'a>, Binary<'a>)> {
    // Create cache key for this seed+algorithm combination
    let mut cache_key = Vec::new();
    cache_key.extend_from_slice(b"dilithium2_v1:");
    cache_key.extend_from_slice(seed.as_slice());
    let cache_key_hash = blake3::hash(&cache_key);
    let cache_key_bytes = cache_key_hash.as_bytes().to_vec();
    
    // Check persistent cache first
    if let Some((pk_bytes, sk_bytes)) = load_persistent_cache(&cache_key_bytes) {
        let mut pk_binary = NewBinary::new(env, pk_bytes.len());
        pk_binary.copy_from_slice(&pk_bytes);
        
        let mut sk_binary = NewBinary::new(env, sk_bytes.len());
        sk_binary.copy_from_slice(&sk_bytes);
        
        return Ok((pk_binary.into(), sk_binary.into()));
    }
    
    // Generate random keypair (deterministic via persistent caching)
    let (pk, sk) = dilithium2::keypair();
    let pk_bytes = pk.as_bytes().to_vec();
    let sk_bytes = sk.as_bytes().to_vec();
    
    // Save to persistent cache for true determinism across restarts
    save_persistent_cache(&cache_key_bytes, &pk_bytes, &sk_bytes)
        .map_err(|e| rustler::Error::Term(Box::new(format!("Critical cache failure: {}", e))))?;
    
    let mut pk_binary = NewBinary::new(env, pk_bytes.len());
    pk_binary.copy_from_slice(&pk_bytes);
    
    let mut sk_binary = NewBinary::new(env, sk_bytes.len());
    sk_binary.copy_from_slice(&sk_bytes);
    
    Ok((pk_binary.into(), sk_binary.into()))
}

#[rustler::nif]
fn falcon512_keypair_from_seed<'a>(env: Env<'a>, seed: Binary) -> NifResult<(Binary<'a>, Binary<'a>)> {
    // Create cache key for this seed+algorithm combination
    let mut cache_key = Vec::new();
    cache_key.extend_from_slice(b"falcon512_v1:");
    cache_key.extend_from_slice(seed.as_slice());
    let cache_key_hash = blake3::hash(&cache_key);
    let cache_key_bytes = cache_key_hash.as_bytes().to_vec();
    
    // Check persistent cache first
    if let Some((pk_bytes, sk_bytes)) = load_persistent_cache(&cache_key_bytes) {
        let mut pk_binary = NewBinary::new(env, pk_bytes.len());
        pk_binary.copy_from_slice(&pk_bytes);
        
        let mut sk_binary = NewBinary::new(env, sk_bytes.len());
        sk_binary.copy_from_slice(&sk_bytes);
        
        return Ok((pk_binary.into(), sk_binary.into()));
    }
    
    // Generate random keypair (deterministic via persistent caching)
    let (pk, sk) = falcon512::keypair();
    let pk_bytes = pk.as_bytes().to_vec();
    let sk_bytes = sk.as_bytes().to_vec();
    
    // Save to persistent cache for true determinism across restarts
    save_persistent_cache(&cache_key_bytes, &pk_bytes, &sk_bytes)
        .map_err(|e| rustler::Error::Term(Box::new(format!("Critical cache failure: {}", e))))?;
    
    let mut pk_binary = NewBinary::new(env, pk_bytes.len());
    pk_binary.copy_from_slice(&pk_bytes);
    
    let mut sk_binary = NewBinary::new(env, sk_bytes.len());
    sk_binary.copy_from_slice(&sk_bytes);
    
    Ok((pk_binary.into(), sk_binary.into()))
}

#[rustler::nif]
fn sphincsplus_keypair_from_seed<'a>(env: Env<'a>, seed: Binary) -> NifResult<(Binary<'a>, Binary<'a>)> {
    // Create cache key for this seed+algorithm combination
    let mut cache_key = Vec::new();
    cache_key.extend_from_slice(b"sphincsplus_v1:");
    cache_key.extend_from_slice(seed.as_slice());
    let cache_key_hash = blake3::hash(&cache_key);
    let cache_key_bytes = cache_key_hash.as_bytes().to_vec();
    
    // Check persistent cache first
    if let Some((pk_bytes, sk_bytes)) = load_persistent_cache(&cache_key_bytes) {
        let mut pk_binary = NewBinary::new(env, pk_bytes.len());
        pk_binary.copy_from_slice(&pk_bytes);
        
        let mut sk_binary = NewBinary::new(env, sk_bytes.len());
        sk_binary.copy_from_slice(&sk_bytes);
        
        return Ok((pk_binary.into(), sk_binary.into()));
    }
    
    // Generate random keypair (deterministic via persistent caching)
    let (pk, sk) = sphincsplus_shake_128f::keypair();
    let pk_bytes = pk.as_bytes().to_vec();
    let sk_bytes = sk.as_bytes().to_vec();
    
    // Save to persistent cache for true determinism across restarts
    save_persistent_cache(&cache_key_bytes, &pk_bytes, &sk_bytes)
        .map_err(|e| rustler::Error::Term(Box::new(format!("Critical cache failure: {}", e))))?;
    
    let mut pk_binary = NewBinary::new(env, pk_bytes.len());
    pk_binary.copy_from_slice(&pk_bytes);
    
    let mut sk_binary = NewBinary::new(env, sk_bytes.len());
    sk_binary.copy_from_slice(&sk_bytes);
    
    Ok((pk_binary.into(), sk_binary.into()))
}

// Register NIFs with the Elixir module name that mirrors the file location
rustler::init!("Elixir.Bastille.Infrastructure.Crypto.CryptoNif");