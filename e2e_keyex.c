/*
 * e2e_keyex.c - Key Exchange Functions
 *
 * Protocol:
 * - Identity keypair: Ed25519 (signing)
 * - Encryption keypair: X25519 (key exchange)
 * - Shared secret: X25519 DH, hashed to 32 bytes (crypto_generichash)
 * - Message encryption: XChaCha20-Poly1305
 */

#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <sodium.h>
#include <wincrypt.h>

#pragma comment(lib, "Crypt32.lib")

static int safe_copy(char *dst, size_t dst_sz, const char *src)
{
    size_t n = strnlen(src, dst_sz);
    if (n >= dst_sz) {
        if (dst_sz > 0) dst[0] = '\0';
        return 0;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
    return 1;
}

static INIT_ONCE g_log_once = INIT_ONCE_STATIC_INIT;
static SRWLOCK g_log_lock = SRWLOCK_INIT;
static char g_log_path[MAX_PATH];

static BOOL CALLBACK e2e_log_init(PINIT_ONCE once, PVOID param, PVOID *context)
{
    char path[MAX_PATH];
    DWORD len = GetModuleFileNameA(NULL, path, (DWORD)sizeof(path));
    if (len == 0 || len >= sizeof(path)) {
        g_log_path[0] = '\0';
        return TRUE;
    }

    for (DWORD i = len; i > 0; i--) {
        if (path[i - 1] == '\\' || path[i - 1] == '/') {
            path[i - 1] = '\0';
            break;
        }
    }

    snprintf(g_log_path, sizeof(g_log_path), "%s\\e2e.logs", path);
    return TRUE;
}

static void e2e_log_line(const char *level, const char *msg)
{
    InitOnceExecuteOnce(&g_log_once, e2e_log_init, NULL, NULL);
    if (g_log_path[0] == '\0') return;

    SYSTEMTIME st;
    GetLocalTime(&st);

    char line[1024];
    int n = snprintf(line, sizeof(line),
                     "%04d-%02d-%02d %02d:%02d:%02d [%s] %s\r\n",
                     (int)st.wYear, (int)st.wMonth, (int)st.wDay,
                     (int)st.wHour, (int)st.wMinute, (int)st.wSecond,
                     level ? level : "INFO", msg ? msg : "");
    if (n <= 0) return;

    AcquireSRWLockExclusive(&g_log_lock);
    HANDLE h = CreateFileA(g_log_path, FILE_APPEND_DATA,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        WriteFile(h, line, (DWORD)strlen(line), &written, NULL);
        CloseHandle(h);
    }
    ReleaseSRWLockExclusive(&g_log_lock);
}

static int e2e_return_error(char *data, const char *msg)
{
    e2e_log_line("ERROR", msg);
    safe_copy(data, 900, msg);
    return 3;
}

/* ============================================================================
 * Key Generation
 * ============================================================================ */

/**
 * GenKeys - Generate identity (Ed25519) and encryption (X25519) keypairs
 *
 * mIRC: $dll(e2e.dll, GenKeys, 0)
 * Returns: idPub|encPub|idSec|encSec (base64, pipe-separated)
 */
__declspec(dllexport)
int __stdcall GenKeys(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    unsigned char id_pk[crypto_sign_PUBLICKEYBYTES];
    unsigned char id_sk[crypto_sign_SECRETKEYBYTES];
    unsigned char enc_pk[crypto_box_PUBLICKEYBYTES];
    unsigned char enc_sk[crypto_box_SECRETKEYBYTES];

    // Generate Ed25519 identity keypair (for signing)
    crypto_sign_keypair(id_pk, id_sk);

    // Generate X25519 encryption keypair (for key exchange)
    crypto_box_keypair(enc_pk, enc_sk);

    // Base64 encode all keys
    char id_pk_b64[100], enc_pk_b64[100], id_sk_b64[150], enc_sk_b64[100];

    sodium_bin2base64(id_pk_b64, sizeof(id_pk_b64), id_pk, sizeof(id_pk),
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);
    sodium_bin2base64(enc_pk_b64, sizeof(enc_pk_b64), enc_pk, sizeof(enc_pk),
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);
    sodium_bin2base64(id_sk_b64, sizeof(id_sk_b64), id_sk, sizeof(id_sk),
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);
    sodium_bin2base64(enc_sk_b64, sizeof(enc_sk_b64), enc_sk, sizeof(enc_sk),
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);

    // Return: idPub|encPub|idSec|encSec
    if (snprintf(data, 900, "%s|%s|%s|%s", id_pk_b64, enc_pk_b64, id_sk_b64, enc_sk_b64) >= 900) {
        return e2e_return_error(data, "ERROR: Output too large");
    }

    return 3;
}

/* ============================================================================
 * Create Key Offer
 * ============================================================================ */

/**
 * CreateOffer - Create signed key offer
 *
 * mIRC: $dll(e2e.dll, CreateOffer, idPub|encPub|idSec)
 * Returns: {"v":1,"idPub":"...","encPub":"...","sig":"..."}
 */
__declspec(dllexport)
int __stdcall CreateOffer(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    char input[500];
    if (!safe_copy(input, sizeof(input), data)) {
        return e2e_return_error(data, "ERROR: Input too long");
    }

    // Parse: idPub|encPub|idSec
    char *id_pk_b64 = strtok(input, "|");
    char *enc_pk_b64 = strtok(NULL, "|");
    char *id_sk_b64 = strtok(NULL, "|");

    if (!id_pk_b64 || !enc_pk_b64 || !id_sk_b64) {
        return e2e_return_error(data, "ERROR: Invalid input format");
    }

    // Decode keys
    unsigned char id_pk[crypto_sign_PUBLICKEYBYTES];
    unsigned char enc_pk[crypto_box_PUBLICKEYBYTES];
    unsigned char id_sk[crypto_sign_SECRETKEYBYTES];
    size_t len;

    if (sodium_base642bin(id_pk, sizeof(id_pk), id_pk_b64, strlen(id_pk_b64),
                          NULL, &len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        len != sizeof(id_pk)) {
        return e2e_return_error(data, "ERROR: Invalid idPub");
    }
    if (sodium_base642bin(enc_pk, sizeof(enc_pk), enc_pk_b64, strlen(enc_pk_b64),
                          NULL, &len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        len != sizeof(enc_pk)) {
        return e2e_return_error(data, "ERROR: Invalid encPub");
    }
    if (sodium_base642bin(id_sk, sizeof(id_sk), id_sk_b64, strlen(id_sk_b64),
                          NULL, &len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        len != sizeof(id_sk)) {
        return e2e_return_error(data, "ERROR: Invalid idSec");
    }

    // Sign only encPub (AndroidIRCX protocol)
    unsigned char signature[crypto_sign_BYTES];
    crypto_sign_detached(signature, NULL, enc_pk, sizeof(enc_pk), id_sk);

    // Base64 encode signature
    char sig_b64[150];
    sodium_bin2base64(sig_b64, sizeof(sig_b64), signature, sizeof(signature),
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);

    // Create JSON offer
    if (snprintf(data, 900, "{\"v\":1,\"idPub\":\"%s\",\"encPub\":\"%s\",\"sig\":\"%s\"}",
                 id_pk_b64, enc_pk_b64, sig_b64) >= 900) {
        return e2e_return_error(data, "ERROR: Output too large");
    }

    return 3;
}

/* ============================================================================
 * Derive Shared Secret
 * ============================================================================ */

/**
 * DeriveSecret - Verify offer and derive shared secret (hashed)
 *
 * mIRC: $dll(e2e.dll, DeriveSecret, their_idPub|their_encPub|their_sig|my_encSec)
 * Returns: shared_key (base64, 32 bytes) or ERROR
 */
__declspec(dllexport)
int __stdcall DeriveSecret(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    char input[800];
    if (!safe_copy(input, sizeof(input), data)) {
        return e2e_return_error(data, "ERROR: Input too long");
    }

    // Parse input
    char *their_id_pk_b64 = strtok(input, "|");
    char *their_enc_pk_b64 = strtok(NULL, "|");
    char *sig_b64 = strtok(NULL, "|");
    char *my_enc_sk_b64 = strtok(NULL, "|");

    if (!their_id_pk_b64 || !their_enc_pk_b64 || !sig_b64 || !my_enc_sk_b64) {
        return e2e_return_error(data, "ERROR: Invalid input");
    }

    // Decode
    unsigned char their_id_pk[crypto_sign_PUBLICKEYBYTES];
    unsigned char their_enc_pk[crypto_box_PUBLICKEYBYTES];
    unsigned char signature[crypto_sign_BYTES];
    unsigned char my_enc_sk[crypto_box_SECRETKEYBYTES];
    size_t len;

    if (sodium_base642bin(their_id_pk, sizeof(their_id_pk), their_id_pk_b64, strlen(their_id_pk_b64),
                          NULL, &len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        len != sizeof(their_id_pk)) {
        return e2e_return_error(data, "ERROR: Invalid idPub");
    }
    if (sodium_base642bin(their_enc_pk, sizeof(their_enc_pk), their_enc_pk_b64, strlen(their_enc_pk_b64),
                          NULL, &len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        len != sizeof(their_enc_pk)) {
        return e2e_return_error(data, "ERROR: Invalid encPub");
    }
    if (sodium_base642bin(signature, sizeof(signature), sig_b64, strlen(sig_b64),
                          NULL, &len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        len != sizeof(signature)) {
        return e2e_return_error(data, "ERROR: Invalid signature");
    }
    if (sodium_base642bin(my_enc_sk, sizeof(my_enc_sk), my_enc_sk_b64, strlen(my_enc_sk_b64),
                          NULL, &len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        len != sizeof(my_enc_sk)) {
        return e2e_return_error(data, "ERROR: Invalid encSec");
    }

    // Verify signature over encPub only
    if (crypto_sign_verify_detached(signature, their_enc_pk, sizeof(their_enc_pk), their_id_pk) != 0) {
        return e2e_return_error(data, "ERROR: Invalid signature");
    }

    // Derive shared secret using X25519
    unsigned char shared_secret[crypto_scalarmult_BYTES];
    if (crypto_scalarmult(shared_secret, my_enc_sk, their_enc_pk) != 0) {
        return e2e_return_error(data, "ERROR: Key agreement failed");
    }

    // Hash to 32-byte key (AndroidIRCX protocol)
    unsigned char key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    crypto_generichash(key, sizeof(key), shared_secret, sizeof(shared_secret), NULL, 0);

    // Base64 encode key
    if (sodium_base64_ENCODED_LEN(sizeof(key), sodium_base64_VARIANT_URLSAFE_NO_PADDING) > 899) {
        return e2e_return_error(data, "ERROR: Output too large");
    }
    sodium_bin2base64(data, 900, key, sizeof(key),
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);

    return 3;
}

/* ============================================================================
 * DM Encrypt/Decrypt (uses derived key)
 * ============================================================================ */

/**
 * EncryptDM - Encrypt message for DM
 *
 * mIRC: $dll(e2e.dll, EncryptDM, key|my_encPub|plaintext)
 * Returns: {"v":1,"from":"...","nonce":"...","cipher":"..."}
 */
__declspec(dllexport)
int __stdcall EncryptDM(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    char input[2048];
    if (!safe_copy(input, sizeof(input), data)) {
        return e2e_return_error(data, "ERROR: Input too long");
    }

    // Parse: key|my_encPub|plaintext
    char *key_b64 = strtok(input, "|");
    char *from_enc_pub = strtok(NULL, "|");
    char *plaintext = strtok(NULL, "");

    if (!key_b64 || !from_enc_pub || !plaintext) {
        return e2e_return_error(data, "ERROR: Invalid input");
    }

    // Decode key
    unsigned char key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    size_t len;
    if (sodium_base642bin(key, sizeof(key), key_b64, strlen(key_b64),
                          NULL, &len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        len != sizeof(key)) {
        return e2e_return_error(data, "ERROR: Invalid key");
    }

    // Generate random nonce
    unsigned char nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES];
    randombytes_buf(nonce, sizeof(nonce));

    // Encrypt
    unsigned char ciphertext[2048];
    unsigned long long clen;
    size_t pt_len = strlen(plaintext);
    if (pt_len > sizeof(ciphertext) - crypto_aead_xchacha20poly1305_ietf_ABYTES) {
        return e2e_return_error(data, "ERROR: Input too long");
    }
    if (crypto_aead_xchacha20poly1305_ietf_encrypt(
        ciphertext, &clen,
        (unsigned char*)plaintext, pt_len,
        NULL, 0, NULL, nonce, key) != 0) {
        return e2e_return_error(data, "ERROR: Encryption failed");
    }
    if (clen > sizeof(ciphertext)) {
        return e2e_return_error(data, "ERROR: Output too large");
    }

    // Base64 encode nonce and ciphertext
    char nonce_b64[100], cipher_b64[3000];
    sodium_bin2base64(nonce_b64, sizeof(nonce_b64), nonce, sizeof(nonce),
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);
    sodium_bin2base64(cipher_b64, sizeof(cipher_b64), ciphertext, (size_t)clen,
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);

    // Create JSON
    if (snprintf(data, 900, "{\"v\":1,\"from\":\"%s\",\"nonce\":\"%s\",\"cipher\":\"%s\"}",
                 from_enc_pub, nonce_b64, cipher_b64) >= 900) {
        return e2e_return_error(data, "ERROR: Output too large");
    }

    return 3;
}

/**
 * DecryptDM - Decrypt DM message
 *
 * mIRC: $dll(e2e.dll, DecryptDM, key|nonce|cipher)
 * Returns: plaintext or ERROR
 */
__declspec(dllexport)
int __stdcall DecryptDM(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    char input[4096];
    if (!safe_copy(input, sizeof(input), data)) {
        return e2e_return_error(data, "ERROR: Input too long");
    }

    // Parse: key|nonce|cipher
    char *key_b64 = strtok(input, "|");
    char *nonce_b64 = strtok(NULL, "|");
    char *cipher_b64 = strtok(NULL, "");

    if (!key_b64 || !nonce_b64 || !cipher_b64) {
        return e2e_return_error(data, "ERROR: Invalid input");
    }

    // Decode
    unsigned char key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    unsigned char nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES];
    unsigned char ciphertext[2048];
    size_t secret_len, nonce_len, cipher_len;

    if (sodium_base642bin(key, sizeof(key), key_b64, strlen(key_b64),
                          NULL, &secret_len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        secret_len != sizeof(key)) {
        return e2e_return_error(data, "ERROR: Invalid key");
    }
    if (sodium_base642bin(nonce, sizeof(nonce), nonce_b64, strlen(nonce_b64),
                          NULL, &nonce_len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        nonce_len != sizeof(nonce)) {
        return e2e_return_error(data, "ERROR: Invalid nonce");
    }
    if (sodium_base642bin(ciphertext, sizeof(ciphertext), cipher_b64, strlen(cipher_b64),
                          NULL, &cipher_len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0) {
        return e2e_return_error(data, "ERROR: Invalid cipher");
    }

    // Decrypt
    unsigned char plaintext[2048];
    unsigned long long plen;

    if (crypto_aead_xchacha20poly1305_ietf_decrypt(
            plaintext, &plen, NULL,
            ciphertext, cipher_len,
            NULL, 0, nonce, key) != 0) {
        return e2e_return_error(data, "ERROR: Decryption failed");
    }

    // Return plaintext
    if (plen >= 900) {
        return e2e_return_error(data, "ERROR: Output too large");
    }
    plaintext[plen] = '\0';
    memcpy(data, plaintext, (size_t)plen + 1);

    return 3;
}

/* ============================================================================
 * Channel Key Helpers
 * ============================================================================ */

/**
 * GenChanKey - Generate 32-byte channel key (base64)
 *
 * mIRC: $dll(e2e.dll, GenChanKey, 0)
 * Returns: key (base64)
 */
__declspec(dllexport)
int __stdcall GenChanKey(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    unsigned char key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    randombytes_buf(key, sizeof(key));

    if (sodium_base64_ENCODED_LEN(sizeof(key), sodium_base64_VARIANT_URLSAFE_NO_PADDING) > 899) {
        return e2e_return_error(data, "ERROR: Output too large");
    }
    sodium_bin2base64(data, 900, key, sizeof(key),
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);

    return 3;
}

/* ============================================================================
 * Encrypt/Decrypt Channel Messages
 * ============================================================================ */

/**
 * EncryptChan - Encrypt message for channel
 *
 * mIRC: $dll(e2e.dll, EncryptChan, key|plaintext)
 * Returns: {"v":1,"nonce":"...","cipher":"..."}
 */
__declspec(dllexport)
int __stdcall EncryptChan(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    char input[2048];
    if (!safe_copy(input, sizeof(input), data)) {
        return e2e_return_error(data, "ERROR: Input too long");
    }

    // Parse: key|plaintext
    char *secret_b64 = strtok(input, "|");
    char *plaintext = strtok(NULL, "");

    if (!secret_b64 || !plaintext) {
        return e2e_return_error(data, "ERROR: Invalid input");
    }

    // Decode key
    unsigned char key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    size_t len;
    if (sodium_base642bin(key, sizeof(key), secret_b64, strlen(secret_b64),
                          NULL, &len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        len != sizeof(key)) {
        return e2e_return_error(data, "ERROR: Invalid key");
    }

    // Generate random nonce
    unsigned char nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES];
    randombytes_buf(nonce, sizeof(nonce));

    // Encrypt
    unsigned char ciphertext[2048];
    unsigned long long clen;
    size_t pt_len = strlen(plaintext);
    if (pt_len > sizeof(ciphertext) - crypto_aead_xchacha20poly1305_ietf_ABYTES) {
        return e2e_return_error(data, "ERROR: Input too long");
    }
    if (crypto_aead_xchacha20poly1305_ietf_encrypt(
        ciphertext, &clen,
        (unsigned char*)plaintext, pt_len,
        NULL, 0, NULL, nonce, key) != 0) {
        return e2e_return_error(data, "ERROR: Encryption failed");
    }
    if (clen > sizeof(ciphertext)) {
        return e2e_return_error(data, "ERROR: Output too large");
    }

    // Base64 encode nonce and ciphertext
    char nonce_b64[100], cipher_b64[3000];
    sodium_bin2base64(nonce_b64, sizeof(nonce_b64), nonce, sizeof(nonce),
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);
    sodium_bin2base64(cipher_b64, sizeof(cipher_b64), ciphertext, (size_t)clen,
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);

    // Create JSON
    if (snprintf(data, 900, "{\"v\":1,\"nonce\":\"%s\",\"cipher\":\"%s\"}",
                 nonce_b64, cipher_b64) >= 900) {
        return e2e_return_error(data, "ERROR: Output too large");
    }

    return 3;
}

/**
 * DecryptChan - Decrypt channel message
 *
 * mIRC: $dll(e2e.dll, DecryptChan, key|nonce|cipher)
 * Returns: plaintext or ERROR
 */
__declspec(dllexport)
int __stdcall DecryptChan(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    char input[4096];
    if (!safe_copy(input, sizeof(input), data)) {
        return e2e_return_error(data, "ERROR: Input too long");
    }

    // Parse: key|nonce|cipher
    char *secret_b64 = strtok(input, "|");
    char *nonce_b64 = strtok(NULL, "|");
    char *cipher_b64 = strtok(NULL, "");

    if (!secret_b64 || !nonce_b64 || !cipher_b64) {
        return e2e_return_error(data, "ERROR: Invalid input");
    }

    // Decode
    unsigned char key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    unsigned char nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES];
    unsigned char ciphertext[2048];
    size_t secret_len, nonce_len, cipher_len;

    if (sodium_base642bin(key, sizeof(key), secret_b64, strlen(secret_b64),
                          NULL, &secret_len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        secret_len != sizeof(key)) {
        return e2e_return_error(data, "ERROR: Invalid key");
    }
    if (sodium_base642bin(nonce, sizeof(nonce), nonce_b64, strlen(nonce_b64),
                          NULL, &nonce_len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0 ||
        nonce_len != sizeof(nonce)) {
        return e2e_return_error(data, "ERROR: Invalid nonce");
    }
    if (sodium_base642bin(ciphertext, sizeof(ciphertext), cipher_b64, strlen(cipher_b64),
                          NULL, &cipher_len, NULL, sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0) {
        return e2e_return_error(data, "ERROR: Invalid cipher");
    }

    // Decrypt
    unsigned char plaintext[2048];
    unsigned long long plen;

    if (crypto_aead_xchacha20poly1305_ietf_decrypt(
            plaintext, &plen, NULL,
            ciphertext, cipher_len,
            NULL, 0, nonce, key) != 0) {
        return e2e_return_error(data, "ERROR: Decryption failed");
    }

    // Return plaintext
    if (plen >= 900) {
        return e2e_return_error(data, "ERROR: Output too large");
    }
    plaintext[plen] = '\0';
    memcpy(data, plaintext, (size_t)plen + 1);

    return 3;
}

/* ============================================================================
 * Key Storage Helpers (Password or DPAPI)
 * ============================================================================ */

static int dpapi_protect(const unsigned char *in, DWORD in_len, unsigned char **out, DWORD *out_len)
{
    DATA_BLOB input;
    DATA_BLOB output;
    input.pbData = (BYTE *)in;
    input.cbData = in_len;

    if (!CryptProtectData(&input, L"e2e", NULL, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        return 0;
    }

    *out = output.pbData;
    *out_len = output.cbData;
    return 1;
}

static int dpapi_unprotect(const unsigned char *in, DWORD in_len, unsigned char **out, DWORD *out_len)
{
    DATA_BLOB input;
    DATA_BLOB output;
    input.pbData = (BYTE *)in;
    input.cbData = in_len;

    if (!CryptUnprotectData(&input, NULL, NULL, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        return 0;
    }

    *out = output.pbData;
    *out_len = output.cbData;
    return 1;
}

/**
 * StoreEncrypt - Encrypt data for storage
 *
 * mIRC: $dll(e2e.dll, StoreEncrypt, mode|password|plaintext)
 * mode: "dpapi" or "password"
 * Returns: base64 blob
 */
__declspec(dllexport)
int __stdcall StoreEncrypt(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    char input[4096];
    size_t in_len = strnlen(data, sizeof(input) - 1);
    memcpy(input, data, in_len);
    input[in_len] = '\0';

    char *mode = strtok(input, "|");
    char *pass = strtok(NULL, "|");
    char *plaintext = strtok(NULL, "");

    if (!mode || !plaintext) {
        if (mode && _stricmp(mode, "dpapi") == 0 && pass && !plaintext) {
            plaintext = pass;
            pass = NULL;
        } else {
            return e2e_return_error(data, "ERROR: Invalid input");
        }
    }

    if (_stricmp(mode, "dpapi") == 0) {
        unsigned char *out = NULL;
        DWORD out_len = 0;
        if (!dpapi_protect((unsigned char *)plaintext, (DWORD)strlen(plaintext), &out, &out_len)) {
            return e2e_return_error(data, "ERROR: DPAPI encrypt failed");
        }

        if (sodium_base64_ENCODED_LEN(out_len, sodium_base64_VARIANT_URLSAFE_NO_PADDING) > 899) {
            LocalFree(out);
            return e2e_return_error(data, "ERROR: Output too large");
        }

        sodium_bin2base64(data, 900, out, out_len,
                          sodium_base64_VARIANT_URLSAFE_NO_PADDING);
        LocalFree(out);
        return 3;
    }

    if (_stricmp(mode, "password") == 0) {
        if (!pass || strlen(pass) == 0) {
            return e2e_return_error(data, "ERROR: Missing password");
        }

        unsigned char salt[crypto_pwhash_SALTBYTES];
        unsigned char nonce[crypto_secretbox_NONCEBYTES];
        unsigned char key[crypto_secretbox_KEYBYTES];
        randombytes_buf(salt, sizeof(salt));
        randombytes_buf(nonce, sizeof(nonce));

        if (crypto_pwhash(key, sizeof(key), pass, strlen(pass),
                          salt, crypto_pwhash_OPSLIMIT_INTERACTIVE,
                          crypto_pwhash_MEMLIMIT_INTERACTIVE,
                          crypto_pwhash_ALG_ARGON2ID13) != 0) {
            return e2e_return_error(data, "ERROR: Key derivation failed");
        }

        unsigned char cipher[4096];
        unsigned long long clen = 0;
        crypto_secretbox_easy(cipher, (unsigned char *)plaintext, strlen(plaintext), nonce, key);
        clen = strlen(plaintext) + crypto_secretbox_MACBYTES;

        unsigned char combined[4096];
        size_t combined_len = sizeof(salt) + sizeof(nonce) + (size_t)clen;
        if (combined_len > sizeof(combined)) {
            return e2e_return_error(data, "ERROR: Data too large");
        }

        memcpy(combined, salt, sizeof(salt));
        memcpy(combined + sizeof(salt), nonce, sizeof(nonce));
        memcpy(combined + sizeof(salt) + sizeof(nonce), cipher, (size_t)clen);

        if (sodium_base64_ENCODED_LEN(combined_len, sodium_base64_VARIANT_URLSAFE_NO_PADDING) > 899) {
            sodium_memzero(key, sizeof(key));
            return e2e_return_error(data, "ERROR: Output too large");
        }

        sodium_bin2base64(data, 900, combined, combined_len,
                          sodium_base64_VARIANT_URLSAFE_NO_PADDING);
        sodium_memzero(key, sizeof(key));
        return 3;
    }

    return e2e_return_error(data, "ERROR: Invalid mode");
}

/**
 * StoreDecrypt - Decrypt stored data
 *
 * mIRC: $dll(e2e.dll, StoreDecrypt, mode|password|b64blob)
 * mode: "dpapi" or "password"
 * Returns: plaintext
 */
__declspec(dllexport)
int __stdcall StoreDecrypt(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    char input[4096];
    size_t in_len = strnlen(data, sizeof(input) - 1);
    memcpy(input, data, in_len);
    input[in_len] = '\0';

    char *mode = strtok(input, "|");
    char *pass = strtok(NULL, "|");
    char *b64 = strtok(NULL, "");

    if (!mode || !b64) {
        if (mode && _stricmp(mode, "dpapi") == 0 && pass && !b64) {
            b64 = pass;
            pass = NULL;
        } else {
            return e2e_return_error(data, "ERROR: Invalid input");
        }
    }

    if (_stricmp(mode, "dpapi") == 0) {
        unsigned char buf[4096];
        size_t bin_len = 0;
        if (sodium_base642bin(buf, sizeof(buf), b64, strlen(b64),
                              NULL, &bin_len, NULL,
                              sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0) {
            return e2e_return_error(data, "ERROR: Invalid base64");
        }

        unsigned char *out = NULL;
        DWORD out_len = 0;
        if (!dpapi_unprotect(buf, (DWORD)bin_len, &out, &out_len)) {
            return e2e_return_error(data, "ERROR: DPAPI decrypt failed");
        }

        if (out_len >= 900) {
            LocalFree(out);
            return e2e_return_error(data, "ERROR: Output too large");
        }

        memcpy(data, out, out_len);
        data[out_len] = '\0';
        LocalFree(out);
        return 3;
    }

    if (_stricmp(mode, "password") == 0) {
        if (!pass || strlen(pass) == 0) {
            return e2e_return_error(data, "ERROR: Missing password");
        }

        unsigned char combined[4096];
        size_t combined_len = 0;
        if (sodium_base642bin(combined, sizeof(combined), b64, strlen(b64),
                              NULL, &combined_len, NULL,
                              sodium_base64_VARIANT_URLSAFE_NO_PADDING) != 0) {
            return e2e_return_error(data, "ERROR: Invalid base64");
        }

        if (combined_len < crypto_pwhash_SALTBYTES + crypto_secretbox_NONCEBYTES + crypto_secretbox_MACBYTES) {
            return e2e_return_error(data, "ERROR: Invalid data");
        }

        unsigned char *salt = combined;
        unsigned char *nonce = combined + crypto_pwhash_SALTBYTES;
        unsigned char *cipher = combined + crypto_pwhash_SALTBYTES + crypto_secretbox_NONCEBYTES;
        size_t cipher_len = combined_len - crypto_pwhash_SALTBYTES - crypto_secretbox_NONCEBYTES;

        unsigned char key[crypto_secretbox_KEYBYTES];
        if (crypto_pwhash(key, sizeof(key), pass, strlen(pass),
                          salt, crypto_pwhash_OPSLIMIT_INTERACTIVE,
                          crypto_pwhash_MEMLIMIT_INTERACTIVE,
                          crypto_pwhash_ALG_ARGON2ID13) != 0) {
            return e2e_return_error(data, "ERROR: Key derivation failed");
        }

        unsigned char plain[4096];
        if (crypto_secretbox_open_easy(plain, cipher, cipher_len, nonce, key) != 0) {
            sodium_memzero(key, sizeof(key));
            return e2e_return_error(data, "ERROR: Decryption failed");
        }

        sodium_memzero(key, sizeof(key));
        if (cipher_len - crypto_secretbox_MACBYTES >= 900) {
            return e2e_return_error(data, "ERROR: Output too large");
        }

        memcpy(data, plain, cipher_len - crypto_secretbox_MACBYTES);
        data[cipher_len - crypto_secretbox_MACBYTES] = '\0';
        return 3;
    }

    return e2e_return_error(data, "ERROR: Invalid mode");
}
