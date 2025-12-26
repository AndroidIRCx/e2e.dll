; ============================================================================
; e2e.dll Test Script za mIRC
; ============================================================================
;
; Instalacija:
;   1. Otvori mIRC
;   2. Pritisni ALT+R (Script Editor)
;   3. File → Load... → odaberi ovaj fajl
;   ili samo copy/paste u Remotes tab
;
; ============================================================================

; Test 1: Provera da li DLL radi
alias e2e.test {
  echo -a ===== E2E DLL TEST =====
  echo -a

  var %result = $dll(e2e.dll, Test, hello from mIRC)
  if (%result) {
    echo -a ✓ Test: %result
  }
  else {
    echo -a ✗ Test failed - DLL not loaded or missing
    halt
  }
  echo -a
}

; Test 2: Provera verzije
alias e2e.version {
  var %ver = $dll(e2e.dll, Version, 0)
  echo -a Version: %ver
}

; Test 3: Encrypt test
alias e2e.encrypt {
  if (!$1-) {
    echo -a Usage: /e2e.encrypt <message>
    halt
  }

  echo -a ===== ENCRYPT TEST =====
  echo -a Original: $1-

  var %encrypted = $dll(e2e.dll, Encrypt, $1-)
  echo -a Encrypted: %encrypted
  echo -a

  ; Kopiraj u clipboard za lako slanje
  clipboard %encrypted
  echo -a ✓ Copied to clipboard
}

; Test 4: Decrypt test (NAPOMENA: neće raditi dok nema proper KX!)
alias e2e.decrypt {
  if (!$1-) {
    echo -a Usage: /e2e.decrypt +E2E1 <base64>
    halt
  }

  echo -a ===== DECRYPT TEST =====
  echo -a Encrypted: $1-

  var %decrypted = $dll(e2e.dll, Decrypt, $1-)
  echo -a Decrypted: %decrypted
  echo -a
}

; Test 5: Round-trip test (encrypt → decrypt)
; NAPOMENA: Ovo NEĆE raditi u trenutnoj verziji jer je key random!
; Samo demonstrira format - pravi round-trip radi sa KX
alias e2e.roundtrip {
  if (!$1-) {
    echo -a Usage: /e2e.roundtrip <message>
    halt
  }

  echo -a ===== ROUND-TRIP TEST =====
  echo -a Original: $1-

  var %encrypted = $dll(e2e.dll, Encrypt, $1-)
  echo -a Encrypted: %encrypted

  var %decrypted = $dll(e2e.dll, Decrypt, %encrypted)
  echo -a Decrypted: %decrypted

  if ($1- == %decrypted) {
    echo -a ✓ SUCCESS - Round-trip works!
  }
  else {
    echo -a ✗ FAIL - Decryption failed (expected - needs KX!)
  }
  echo -a
}

; Pokreni sve testove odjednom
alias e2e.testall {
  e2e.test
  e2e.version
  echo -a
  echo -a --- Encrypt test ---
  e2e.encrypt Hello World!
  echo -a
  echo -a --- Round-trip test (will fail until KX is implemented) ---
  e2e.roundtrip Test Message
}

; Auto-send encrypted message to active window
alias e2e.send {
  if (!$1-) {
    echo -a Usage: /e2e.send <message>
    halt
  }

  var %encrypted = $dll(e2e.dll, Encrypt, $1-)

  ; Pošalji u trenutni chat
  msg $active %encrypted

  ; Prikaži lokalno (kao da smo poslali plaintext)
  echo $active < $+ $me $+ > $1-
  echo $active  → Sent encrypted: %encrypted
}

; Interceptuj incoming poruke sa +E2E1 prefix
on *:TEXT:+E2E1 *:#: {
  ; Dešifruj
  var %decrypted = $dll(e2e.dll, Decrypt, $1-)

  ; Prikaži dešifrovanu poruku
  echo $chan < $+ $nick $+ > [E2E] %decrypted

  ; Zaustavi normalnu obradu (da ne prikazuje šifrovanu)
  haltdef
}

; Isto za private poruke
on *:TEXT:+E2E1 *:?: {
  var %decrypted = $dll(e2e.dll, Decrypt, $1-)
  echo $nick < $+ $nick $+ > [E2E] %decrypted
  haltdef
}

; ============================================================================
; Quick commands
; ============================================================================

; /e - Pošalji enkriptovanu poruku
alias e {
  if (!$1-) {
    echo -a Usage: /e <message>
    echo -a Example: /e Hello, this is encrypted!
    halt
  }
  e2e.send $1-
}

; ============================================================================
; Menu
; ============================================================================

menu channel,query {
  E2E Encryption
  .Send encrypted: e2e.send $$?="Enter message to encrypt:"
  .Test DLL: e2e.testall
  .Version: e2e.version
  -
  .Unload DLL: dll -u e2e.dll
}

; ============================================================================
; Startup check
; ============================================================================

on *:START: {
  ; Proveri da li DLL postoji
  if ($isfile($mircdir $+ e2e.dll)) {
    echo -a ✓ e2e.dll found
    ; Opciono: auto-test
    ; .timer 1 2 e2e.test
  }
  else {
    echo -a ✗ WARNING: e2e.dll not found in mIRC directory
    echo -a   Copy e2e.dll to: $mircdir
  }
}

; ============================================================================
; Help
; ============================================================================

alias e2e.help {
  echo -a ===== E2E DLL Commands =====
  echo -a
  echo -a /e2e.test       - Test DLL connection
  echo -a /e2e.version    - Show DLL version
  echo -a /e2e.encrypt <text>  - Encrypt a message
  echo -a /e2e.decrypt <cipher> - Decrypt a message
  echo -a /e2e.send <text>     - Send encrypted to active window
  echo -a /e2e.testall    - Run all tests
  echo -a
  echo -a Quick commands:
  echo -a /e <text>       - Send encrypted message
  echo -a
  echo -a Note: Current version uses random keys (TEST)
  echo -a       Real E2E requires key exchange implementation
  echo -a
}

echo -a ===== e2e.dll loaded =====
echo -a Type /e2e.help for commands
echo -a Type /e2e.testall to run tests
