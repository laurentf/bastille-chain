//! Post-quantum signature NIFs for Bastille.
//!
//! Deterministic key derivation: every `*_keypair_from_seed` is a pure function
//! of the 32-byte per-algorithm sub-seed (derived in Elixir from the mnemonic).
//! No disk cache, no hidden OS entropy on the seeded paths — the same seed
//! yields the same keypair on any machine.
//!
//!   - Dilithium2  → ML-DSA-44 (FIPS 204), seed = the 32-byte private key
//!   - SPHINCS+128f → SLH-DSA-SHAKE-128f (FIPS 205), 32-byte seed expanded to 3x16
//!   - Falcon512   → FN-DSA-512, 32-byte seed drives a ChaCha20 CSPRNG

use rustler::{Binary, Env, NewBinary, NifResult};

use ml_dsa::{
    B32, EncodedSignature, EncodedVerifyingKey, Keypair, MlDsa44, Signature as MlSignature,
    SigningKey as MlSigningKey, VerifyingKey as MlVerifyingKey,
};
use slh_dsa::{
    Shake128f, Signature as SlhSignature, SigningKey as SlhSigningKey,
    VerifyingKey as SlhVerifyingKey,
};
use slh_dsa::signature::{Signer as SlhSigner, Verifier as SlhVerifier};

use fn_dsa::{
    DOMAIN_NONE, FN_DSA_LOGN_512, HASH_ID_RAW, KeyPairGenerator, KeyPairGeneratorStandard,
    SigningKey as FnSigningKey, SigningKeyStandard, VerifyingKey as FnVerifyingKey,
    VerifyingKeyStandard, sign_key_size, signature_size, vrfy_key_size,
};
use rand::RngCore;
use rand::rngs::OsRng;
use rand_chacha::ChaCha20Rng;
use rand_chacha::rand_core::SeedableRng;

// === helpers ===

fn to_bin<'a>(env: Env<'a>, data: &[u8]) -> Binary<'a> {
    let mut bin = NewBinary::new(env, data.len());
    bin.copy_from_slice(data);
    bin.into()
}

fn random_bytes<const N: usize>() -> [u8; N] {
    let mut buf = [0u8; N];
    OsRng.fill_bytes(&mut buf);
    buf
}

/// Expand an arbitrary-length sub-seed to 48 bytes (3 SLH-DSA n=16 seeds).
fn expand_48(seed: &[u8]) -> [u8; 48] {
    let mut h = blake3::Hasher::new();
    h.update(b"bastille-slh-dsa-v1");
    h.update(seed);
    let mut out = [0u8; 48];
    h.finalize_xof().fill(&mut out);
    out
}

fn seed32(seed: &[u8]) -> NifResult<[u8; 32]> {
    seed.try_into().map_err(|_| rustler::Error::BadArg)
}

// === status ===

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

// === Dilithium2 / ML-DSA-44 ===
// Private key = the 32-byte seed (ML-DSA's canonical FIPS private-key form).

#[rustler::nif]
fn dilithium2_keypair<'a>(env: Env<'a>) -> NifResult<(Binary<'a>, Binary<'a>)> {
    dilithium2_from_seed_bytes(env, &random_bytes::<32>())
}

#[rustler::nif]
fn dilithium2_keypair_from_seed<'a>(env: Env<'a>, seed: Binary) -> NifResult<(Binary<'a>, Binary<'a>)> {
    dilithium2_from_seed_bytes(env, &seed32(seed.as_slice())?)
}

fn dilithium2_from_seed_bytes<'a>(env: Env<'a>, seed: &[u8; 32]) -> NifResult<(Binary<'a>, Binary<'a>)> {
    let sk = MlSigningKey::<MlDsa44>::from_seed(&B32::from(*seed));
    let pk = sk.verifying_key().encode();
    Ok((to_bin(env, &pk[..]), to_bin(env, seed)))
}

#[rustler::nif]
fn dilithium2_sign<'a>(env: Env<'a>, message: Binary, private_key: Binary) -> NifResult<Binary<'a>> {
    let seed = seed32(private_key.as_slice())?;
    let sk = MlSigningKey::<MlDsa44>::from_seed(&B32::from(seed));
    let sig = sk
        .expanded_key()
        .sign_deterministic(message.as_slice(), b"")
        .map_err(|_| rustler::Error::BadArg)?;
    Ok(to_bin(env, &sig.encode()[..]))
}

#[rustler::nif]
fn dilithium2_verify(signature: Binary, message: Binary, public_key: Binary) -> bool {
    let Ok(vk_enc) = EncodedVerifyingKey::<MlDsa44>::try_from(public_key.as_slice()) else {
        return false;
    };
    let vk = MlVerifyingKey::<MlDsa44>::decode(&vk_enc);
    let Ok(sig_enc) = EncodedSignature::<MlDsa44>::try_from(signature.as_slice()) else {
        return false;
    };
    let Some(sig) = MlSignature::<MlDsa44>::decode(&sig_enc) else {
        return false;
    };
    vk.verify_with_context(message.as_slice(), b"", &sig)
}

// === Falcon512 / FN-DSA-512 ===
// Private key = 1281-byte fn-dsa signing key; signatures are randomized.

#[rustler::nif]
fn falcon512_keypair<'a>(env: Env<'a>) -> NifResult<(Binary<'a>, Binary<'a>)> {
    let mut rng = OsRng;
    let mut sk = vec![0u8; sign_key_size(FN_DSA_LOGN_512)];
    let mut vk = vec![0u8; vrfy_key_size(FN_DSA_LOGN_512)];
    KeyPairGeneratorStandard::default().keygen(FN_DSA_LOGN_512, &mut rng, &mut sk, &mut vk);
    Ok((to_bin(env, &vk), to_bin(env, &sk)))
}

#[rustler::nif]
fn falcon512_keypair_from_seed<'a>(env: Env<'a>, seed: Binary) -> NifResult<(Binary<'a>, Binary<'a>)> {
    let mut rng = ChaCha20Rng::from_seed(seed32(seed.as_slice())?);
    let mut sk = vec![0u8; sign_key_size(FN_DSA_LOGN_512)];
    let mut vk = vec![0u8; vrfy_key_size(FN_DSA_LOGN_512)];
    KeyPairGeneratorStandard::default().keygen(FN_DSA_LOGN_512, &mut rng, &mut sk, &mut vk);
    Ok((to_bin(env, &vk), to_bin(env, &sk)))
}

#[rustler::nif]
fn falcon512_sign<'a>(env: Env<'a>, message: Binary, private_key: Binary) -> NifResult<Binary<'a>> {
    let mut sk =
        SigningKeyStandard::decode(private_key.as_slice()).ok_or(rustler::Error::BadArg)?;
    let mut sig = vec![0u8; signature_size(FN_DSA_LOGN_512)];
    let mut rng = OsRng;
    sk.sign(&mut rng, &DOMAIN_NONE, &HASH_ID_RAW, message.as_slice(), &mut sig);
    Ok(to_bin(env, &sig))
}

#[rustler::nif]
fn falcon512_verify(signature: Binary, message: Binary, public_key: Binary) -> bool {
    match VerifyingKeyStandard::decode(public_key.as_slice()) {
        Some(vk) => vk.verify(signature.as_slice(), &DOMAIN_NONE, &HASH_ID_RAW, message.as_slice()),
        None => false,
    }
}

// === SPHINCS+ / SLH-DSA-SHAKE-128f ===
// Private key = 64-byte SLH-DSA signing key; deterministic signing.

#[rustler::nif]
fn sphincsplus_shake_128f_keypair<'a>(env: Env<'a>) -> NifResult<(Binary<'a>, Binary<'a>)> {
    sphincs_from_seed48(env, &random_bytes::<48>())
}

#[rustler::nif]
fn sphincsplus_keypair_from_seed<'a>(env: Env<'a>, seed: Binary) -> NifResult<(Binary<'a>, Binary<'a>)> {
    sphincs_from_seed48(env, &expand_48(seed.as_slice()))
}

fn sphincs_from_seed48<'a>(env: Env<'a>, s: &[u8; 48]) -> NifResult<(Binary<'a>, Binary<'a>)> {
    let sk = SlhSigningKey::<Shake128f>::slh_keygen_internal(&s[0..16], &s[16..32], &s[32..48]);
    let vk: &SlhVerifyingKey<Shake128f> = sk.as_ref();
    Ok((to_bin(env, &vk.to_bytes()[..]), to_bin(env, &sk.to_bytes()[..])))
}

#[rustler::nif]
fn sphincsplus_shake_128f_sign<'a>(env: Env<'a>, message: Binary, private_key: Binary) -> NifResult<Binary<'a>> {
    let sk = SlhSigningKey::<Shake128f>::try_from(private_key.as_slice())
        .map_err(|_| rustler::Error::BadArg)?;
    let sig = SlhSigner::try_sign(&sk, message.as_slice()).map_err(|_| rustler::Error::BadArg)?;
    Ok(to_bin(env, &sig.to_bytes()[..]))
}

#[rustler::nif]
fn sphincsplus_shake_128f_verify(signature: Binary, message: Binary, public_key: Binary) -> bool {
    let (Ok(vk), Ok(sig)) = (
        SlhVerifyingKey::<Shake128f>::try_from(public_key.as_slice()),
        SlhSignature::<Shake128f>::try_from(signature.as_slice()),
    ) else {
        return false;
    };
    SlhVerifier::verify(&vk, message.as_slice(), &sig).is_ok()
}

// === Blake3 ===

#[rustler::nif]
fn blake3_hash<'a>(env: Env<'a>, data: Binary) -> NifResult<Binary<'a>> {
    let hash = blake3::hash(data.as_slice());
    Ok(to_bin(env, hash.as_bytes()))
}

rustler::init!("Elixir.Bastille.Infrastructure.Crypto.CryptoNif");
