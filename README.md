# e2e.dll - End-to-End Encryption for mIRC

Encrypted messaging for IRC channels and private queries using modern cryptography.

## Algorithms

- **Identity (signature)**: Ed25519
- **Key exchange**: X25519 (Diffie-Hellman)
- **Encryption**: XChaCha20-Poly1305 (AEAD)
- **Base64**: URL-safe, no padding (JSON-friendly)
- **Key persistence**: optional (DPAPI or password-encrypted store)

## Build

### Prerequisites

- Visual Studio 2026 (v145 toolset)
- libsodium 1.0.20 (already in `libsodium/`)

### Build command

```cmd
MSBuild e2e.vcxproj /p:Configuration=Release /p:Platform=Win32
```

Or simply:
```cmd
build.bat
```

**Important**: mIRC is 32-bit only, so you must build Win32.

### Auto-copy

`copy_to_mirc.bat` copies `e2e.dll` and `e2e.mrc` into `C:\mIRC\`.

## mIRC Usage

### Load script

```
/load -rs C:\mIRC\e2e.mrc
```

### DM encryption flow

1. Share or request a DM key:
   ```
   /sharekey <nick>
   /requestkey <nick>
   ```
2. When you receive `!enc-offer`, accept or reject:
   ```
   /enc-accept <nick>
   /enc-reject <nick>
   ```
3. Send encrypted DM:
   ```
   /encmsg <nick> <message>
   ```
4. Optional auto-encrypt for a DM:
   ```
   /dmenc-on <nick>
   /dmenc-off <nick>
   ```

### Key persistence (optional)

You can persist keys securely using DPAPI or a password-encrypted store.

```
/e2e-persist off
/e2e-persist dpapi
/e2e-persist password
/e2e-setpass <password>
/e2e-save
/e2e-load
```

- **DPAPI**: automatic per-Windows-user encryption, no password needed.
- **Password**: requires `/e2e-setpass` each session to load/save.
- Keys are stored in `C:\mIRC\e2e_store.hsh` (encrypted).

### Channel encryption flow

1. Generate a channel key (from inside the channel):
   ```
   /chankey generate
   ```
2. Share the key (DM) or request it:
   ```
   /chankey share <nick>
   /chankey request <nick>
   ```
   Outside a channel:
   ```
   /chankey share <#chan> <nick>
   /chankey request <#chan> <nick>
   ```
3. Send encrypted channel message:
   ```
   /chankey send <message>
   ```
4. Optional auto-encrypt for a channel:
   ```
   /chanenc-on [#chan]
   /chanenc-off [#chan]
   ```

## Right-click menus

- **Channel window** -> E2E Encryption:
  - Share/Request DM Key
  - Generate/Share/Request Channel Key
  - Send Encrypted Message
  - Enable/Disable Auto Encrypt
- **Query window** -> E2E Encryption:
  - Share/Request DM Key
  - Send Encrypted Message
  - Enable/Disable DM Auto Encrypt
  - Storage options (persistence mode, set password, save/load)
- **User list / Nick list** -> E2E Encryption:
  - Request DM Key
  - Request Channel Key

## Protocol

### DM key offer

```
!enc-offer {"v":1,"idPub":"...","encPub":"...","sig":"..."}
```

- `sig` is a signature over `encPub` using Ed25519.

### DM encrypted message

```
!enc-msg {"v":1,"from":"<encPub>","nonce":"...","cipher":"..."}
```

### Channel key share (DM only)

```
!chanenc-key {"v":1,"channel":"#chan","network":"NetworkName","key":"...","createdAt":123}
```

### Channel encrypted message

```
!chanenc-msg {"v":1,"nonce":"...","cipher":"..."}
```

## DLL Functions

| Function | Input | Output |
|----------|-------|--------|
| `GenKeys` | `0` | `idPub|encPub|idSec|encSec` |
| `CreateOffer` | `idPub|encPub|idSec` | JSON offer |
| `DeriveSecret` | `idPub|encPub|sig|myEncSec` | 32-byte key (base64) |
| `EncryptDM` | `key|myEncPub|plaintext` | JSON payload |
| `DecryptDM` | `key|nonce|cipher` | plaintext |
| `GenChanKey` | `0` | key (base64) |
| `EncryptChan` | `key|plaintext` | JSON payload |
| `DecryptChan` | `key|nonce|cipher` | plaintext |
| `StoreEncrypt` | `mode|password|plaintext` | base64 blob |
| `StoreDecrypt` | `mode|password|b64blob` | plaintext |
| `Version` | `0` | Version string |

## Security Notes

### What is strong

- Authenticated encryption (AEAD)
- Signature verification (Ed25519)
- Random nonces per message
- libsodium (audited, widely used)

### Known limitations

- No perfect forward secrecy (no ratcheting)
- Keys live in memory only (no persistence)
- Encrypted persistence is optional (DPAPI or password)
- Channel key is shared by all users in the channel
- No replay protection

## Troubleshooting

### Logs

The DLL and script write diagnostic lines to:

```
C:\mIRC\e2e.logs
```

This includes load/self-test results and any DLL error returns. Use this file when reporting crashes or unexpected errors.

### DLL does not load

```
//echo -a $dll(e2e.dll, Version, 0)
```

If it returns empty:
- Ensure `e2e.dll` is in `C:\mIRC\`
- Ensure Win32 build
- Reload: `/dll -u e2e.dll` then `/load -rs e2e.mrc`

### Encryption does not work

- Confirm you exchanged DM keys (offer + accept)
- Confirm the channel key exists (`/chankey generate` or received via `!chanenc-key`)
- For auto-encrypt, verify it is enabled

## Files

```
e2e.c           - Main DLL (test functions)
e2e_keyex.c     - Key exchange and crypto functions
e2e.def         - Export list
e2e.mrc         - mIRC script
e2e.vcxproj     - Visual Studio project
libsodium/      - Crypto library
```

## License

Open source for educational use. Uses libsodium (ISC license).

**Disclaimer**: Experimental code, use at your own risk.
