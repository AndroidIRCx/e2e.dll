/*
 * e2e.dll - mIRC End-to-End Encryption DLL
 *
 * Platform: Win32 (x86) - mIRC is 32-bit only
 * Dependencies: libsodium
 * Encryption: XChaCha20-Poly1305 (AEAD)
 *
 * Build: Visual Studio, /MT (static CRT), Win32
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tchar.h>
#include <stdio.h>
#include <string.h>
#include <sodium.h>

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
 * DLL Entry Point
 * ============================================================================ */

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved)
{
    if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
        // Initialize libsodium
        if (sodium_init() < 0) {
            return FALSE; // Failed to initialize
        }
    }
    return TRUE;
}

/* ============================================================================
 * mIRC LoadDll - Called when DLL is first loaded
 * ============================================================================ */

typedef struct {
    DWORD  mVersion;
    HWND   mHwnd;
    BOOL   mKeep;
    BOOL   mUnicode;
    DWORD  mBeta;
    DWORD  mBytes;
} LOADINFO;

__declspec(dllexport)
void __stdcall LoadDll(LOADINFO *loadinfo)
{
    loadinfo->mKeep = TRUE; // Keep DLL loaded
    loadinfo->mUnicode = FALSE; // Use ANSI, not Unicode
}

/* ============================================================================
 * Helper Functions
 * ============================================================================ */

/**
 * Base64 encode using libsodium
 * @param in Input binary data
 * @param inlen Input length
 * @param out Output buffer (must be large enough)
 * @param outlen Output buffer size
 */
void b64_encode(const unsigned char *in, size_t inlen, char *out, size_t outlen)
{
    sodium_bin2base64(
        out,
        outlen,
        in,
        inlen,
        sodium_base64_VARIANT_ORIGINAL
    );
}

/**
 * Base64 decode using libsodium
 * @param in Input base64 string
 * @param out Output buffer
 * @param outlen Output buffer size
 * @return Number of bytes decoded, or -1 on error
 */
int b64_decode(const char *in, unsigned char *out, size_t outlen)
{
    size_t bin_len;
    if (sodium_base642bin(
            out,
            outlen,
            in,
            strlen(in),
            NULL,
            &bin_len,
            NULL,
            sodium_base64_VARIANT_ORIGINAL) != 0) {
        return -1;
    }
    return (int)bin_len;
}

/* ============================================================================
 * mIRC DLL Exports
 *
 * mIRC očekuje ovaj potpis (iz zvanične dokumentacije):
 * int __stdcall procname(HWND mWnd, HWND aWnd, TCHAR *data, TCHAR *parms,
 *                        BOOL show, BOOL nopause);
 *
 * Parametri:
 *   mWnd    - mIRC main window handle
 *   aWnd    - mIRC script window handle
 *   data    - Output buffer (return data to mIRC)
 *   parms   - Input parameters from mIRC
 *   show    - FALSE if . prefix (quiet), TRUE otherwise
 *   nopause - TRUE if mIRC is in critical routine
 *
 * Return values:
 *   0 - /halt processing
 *   1 - continue processing
 *   2 - filled data with command for mIRC to perform
 *   3 - filled data with result for $dll() to return
 * ============================================================================ */

/**
 * E2EEncrypt - Šifruje plaintext (TEST VERSION)
 *
 * Trenutno koristi random key za testiranje DLL komunikacije.
 *
 * mIRC usage: $dll(e2e.dll, E2EEncrypt, plaintext message)
 *
 * Output format: +E2E1 <base64_ciphertext>
 *
 * @note Ovo je TEST verzija - nema key exchange još!
 */
__declspec(dllexport)
int __stdcall E2EEncrypt(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    char plaintext[1024];

    // INPUT je u 'data' parametru!
    if (!safe_copy(plaintext, sizeof(plaintext), data)) {
        return e2e_return_error(data, "ERROR: Input too long");
    }

    // Check if empty
    if (strlen(plaintext) == 0) {
        return e2e_return_error(data, "ERROR: Empty plaintext");
    }

    // Crypto buffers
    unsigned char key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    unsigned char nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES];
    unsigned char ciphertext[1200];
    unsigned long long clen;

    // Generate random key and nonce (TEST - later from KX)
    randombytes_buf(key, sizeof(key));
    randombytes_buf(nonce, sizeof(nonce));

    // Encrypt with XChaCha20-Poly1305
    size_t pt_len = strlen(plaintext);
    if (pt_len > sizeof(ciphertext) - crypto_aead_xchacha20poly1305_ietf_ABYTES) {
        return e2e_return_error(data, "ERROR: Input too long");
    }
    int result = crypto_aead_xchacha20poly1305_ietf_encrypt(
        ciphertext,
        &clen,
        (unsigned char *)plaintext,
        pt_len,
        NULL,  // No additional authenticated data yet
        0,
        NULL,  // Not used (secret nonce)
        nonce,
        key
    );

    if (result != 0) {
        return e2e_return_error(data, "ERROR: Encryption failed");
    }

    // Prepare output with nonce + ciphertext combined
    unsigned char combined[1250];
    memcpy(combined, nonce, sizeof(nonce));
    memcpy(combined + sizeof(nonce), ciphertext, clen);

    // Base64 encode
    char b64[1800];
    size_t combined_len = sizeof(nonce) + (size_t)clen;
    if (sodium_base64_ENCODED_LEN(combined_len, sodium_base64_VARIANT_ORIGINAL) >= sizeof(b64)) {
        return e2e_return_error(data, "ERROR: Output too large");
    }
    b64_encode(combined, combined_len, b64, sizeof(b64));

    // Format output: +E2E1 <base64>
    if (snprintf(data, 900, "+E2E1 %s", b64) >= 900) {
        return e2e_return_error(data, "ERROR: Output too large");
    }

    return 3; // Replace command with result
}

/**
 * E2EDecrypt - Dešifruje ciphertext (TEST VERSION)
 *
 * mIRC usage: $dll(e2e.dll, E2EDecrypt, +E2E1 <base64>)
 *
 * @note TEST verzija - koristi isti random key (NEĆE RADITI u realnosti!)
 *       Samo demonstrira format. Pravi Decrypt dolazi sa KX.
 */
__declspec(dllexport)
int __stdcall E2EDecrypt(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    char input[2048];

    // INPUT je u 'data'!
    if (!safe_copy(input, sizeof(input), data)) {
        return e2e_return_error(data, "ERROR: Input too long");
    }

    // Check for +E2E1 prefix
    if (strncmp(input, "+E2E1 ", 6) != 0) {
        return e2e_return_error(data, "ERROR: Invalid E2E format");
    }

    // Extract base64 part
    char *b64 = input + 6;

    // Decode base64
    unsigned char combined[1250];
    int combined_len = b64_decode(b64, combined, sizeof(combined));
    if (combined_len < 0) {
        return e2e_return_error(data, "ERROR: Invalid base64");
    }

    if (combined_len < crypto_aead_xchacha20poly1305_ietf_NPUBBYTES) {
        return e2e_return_error(data, "ERROR: Invalid ciphertext length");
    }

    // Extract nonce and ciphertext
    unsigned char nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES];
    memcpy(nonce, combined, sizeof(nonce));

    unsigned char *ciphertext = combined + sizeof(nonce);
    size_t clen = combined_len - sizeof(nonce);

    // Generate same random key (TEST - later from KX)
    // NOTE: Ovo NEĆE raditi jer je key random svaki put!
    // Samo pokazuje format - pravi Decrypt koristi saved keys
    unsigned char key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    randombytes_buf(key, sizeof(key));

    // Decrypt
    unsigned char plaintext[1024];
    unsigned long long plen;

    int result = crypto_aead_xchacha20poly1305_ietf_decrypt(
        plaintext,
        &plen,
        NULL,
        ciphertext,
        clen,
        NULL,  // No AAD yet
        0,
        nonce,
        key
    );

    if (result != 0) {
        return e2e_return_error(data, "ERROR: Decryption failed (wrong key or corrupted)");
    }

    // Null-terminate and return
    if (plen >= 900) {
        return e2e_return_error(data, "ERROR: Output too large");
    }
    plaintext[plen] = '\0';
    memcpy(data, plaintext, (size_t)plen + 1);

    return 3;
}

/**
 * Version - Vraća verziju DLL-a
 *
 * mIRC usage: $dll(e2e.dll, Version, 0)
 */
__declspec(dllexport)
int __stdcall Version(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    snprintf(data, 900, "e2e.dll v0.1 TEST (libsodium %s)", sodium_version_string());
    return 3;
}

/**
 * SelfTest - Basic safety checks
 *
 * mIRC usage: $dll(e2e.dll, SelfTest, 0)
 */
__declspec(dllexport)
int __stdcall SelfTest(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    unsigned char key[32];
    char b64[128];
    randombytes_buf(key, sizeof(key));
    if (sodium_base64_ENCODED_LEN(sizeof(key), sodium_base64_VARIANT_URLSAFE_NO_PADDING) >= sizeof(b64)) {
        return e2e_return_error(data, "ERROR: SelfTest failed");
    }
    sodium_bin2base64(b64, sizeof(b64), key, sizeof(key),
                      sodium_base64_VARIANT_URLSAFE_NO_PADDING);
    snprintf(data, 900, "OK");
    return 3;
}

/**
 * Test - Provera da li DLL radi
 *
 * mIRC usage: $dll(e2e.dll, Test, hello)
 */
__declspec(dllexport)
int __stdcall Test(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    // INPUT je u 'data', ne u 'parms'!
    char input[900];
    if (!safe_copy(input, sizeof(input), data)) {
        return e2e_return_error(data, "ERROR: Input too long");
    }
    snprintf(data, 900, "RECEIVED: %s", input); // Vrati output
    return 3;
}

/**
 * Debug - Pokazuje SVE parametre koje mIRC šalje
 *
 * mIRC usage: $dll(e2e.dll, Debug, test)
 */
__declspec(dllexport)
int __stdcall Debug(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    snprintf(data, 900, "mWnd=%p aWnd=%p data=%p parms=%p show=%d nopause=%d str='%s' len=%d",
            mWnd, aWnd, data, parms, show, nopause,
            parms ? parms : "NULL", parms ? (int)strlen(parms) : -1);
    return 3;
}

/**
 * Enc - Identičan Test-u, samo drugo ime
 *
 * mIRC usage: $dll(e2e.dll, Enc, hello)
 */
__declspec(dllexport)
int __stdcall Enc(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL show, BOOL nopause)
{
    snprintf(data, 900, "Enc OK - received: %s", parms);
    return 3;
}
