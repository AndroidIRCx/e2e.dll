; ============================================================================
; e2e.mrc - AndroidIRCX-compatible E2E protocol for mIRC
; ============================================================================
; DM:
;   /sharekey <nick>     -> sends !enc-offer {bundle}
;   /requestkey <nick>   -> sends !enc-req
;   /enc-accept <nick>   -> sends !enc-accept {bundle}
;   /enc-reject <nick>   -> sends !enc-reject
;   /encmsg <nick> <msg> -> sends !enc-msg {payload}
;
; Channel:
;   /chankey generate            -> create key for active channel
;   /chankey share <nick>        -> send !chanenc-key {keyJson} via DM
;   /chankey request <nick>      -> request key from user (DM)
;   /chankey send <msg>          -> send !chanenc-msg {payload}
;   /chankey remove              -> delete stored channel key
;   /chanenc-on [#chan]          -> auto-encrypt channel input
;   /chanenc-off [#chan]         -> disable auto-encrypt
; ============================================================================

menu channel {
  E2E Encryption
  .Share DM Key...: e2e-menulog channel share dm key target=$$?="Nick:" | sharekey $1
  .Request DM Key...: e2e-menulog channel request dm key target=$$?="Nick:" | requestkey $1
  .Generate Channel Key: e2e-menulog channel generate channel key chan=$active | chankey generate $active
  .Share Channel Key...: e2e-menulog channel share channel key chan=$active target=$$?="Nick:" | chankey share $active $1
  .Request Channel Key...: e2e-menulog channel request channel key chan=$active target=$$?="Nick:" | chankey request $active $1
  .Send Encrypted Message...: e2e-menulog channel send encrypted msg chan=$active | chankey send $active $$?="Message:"
  .Enable Auto Encrypt: e2e-menulog channel enable auto encrypt chan=$active | chanenc-on $active
  .Disable Auto Encrypt: e2e-menulog channel disable auto encrypt chan=$active | chanenc-off $active
  .Auto Encrypt Status: e2e-menulog channel status chan=$active | e2e-chan-status $active
  .Show Raw Encrypted Lines: e2e-menulog channel show raw | e2e-showraw on
  .Hide Raw Encrypted Lines: e2e-menulog channel hide raw | e2e-showraw off
  E2E Storage
  .Persistence Off: e2e-menulog channel persist off | e2e-persist off
  .Persistence Password: e2e-menulog channel persist password | e2e-persist password
  .Persistence DPAPI: e2e-menulog channel persist dpapi | e2e-persist dpapi
  .Set Password...: e2e-menulog channel set password | e2e-setpass $$?="Password:"
  .Save Keys Now: e2e-menulog channel save keys | e2e-save
  .Load Keys Now: e2e-menulog channel load keys | e2e-load
}

menu nicklist {
  E2E Encryption
  .Request DM Key: e2e-menulog nicklist request dm key target=$1 | requestkey $1
  .Request Channel Key: e2e-menulog nicklist request channel key chan=$active target=$1 | chankey request $active $1
}

menu userlist {
  E2E Encryption
  .Request DM Key: e2e-menulog userlist request dm key target=$1 | requestkey $1
  .Request Channel Key: e2e-menulog userlist request channel key chan=$active target=$1 | chankey request $active $1
}

menu query {
  E2E Encryption
  .Share DM Key: e2e-menulog query share dm key target=$active | sharekey $active
  .Request DM Key: e2e-menulog query request dm key target=$active | requestkey $active
  .Send Encrypted Message...: e2e-menulog query send encrypted msg target=$active | encmsg $active $$?="Message:"
  .Enable Auto Encrypt: e2e-menulog query enable auto encrypt target=$active | dmenc-on $active
  .Disable Auto Encrypt: e2e-menulog query disable auto encrypt target=$active | dmenc-off $active
  .Show Raw Encrypted Lines: e2e-menulog query show raw | e2e-showraw on
  .Hide Raw Encrypted Lines: e2e-menulog query hide raw | e2e-showraw off
  E2E Storage
  .Persistence Off: e2e-menulog query persist off | e2e-persist off
  .Persistence Password: e2e-menulog query persist password | e2e-persist password
  .Persistence DPAPI: e2e-menulog query persist dpapi | e2e-persist dpapi
  .Set Password...: e2e-menulog query set password | e2e-setpass $$?="Password:"
  .Save Keys Now: e2e-menulog query save keys | e2e-save
  .Load Keys Now: e2e-menulog query load keys | e2e-load
}

on *:LOAD: {
  echo -a * Loading e2e.dll...
  e2e_tables
  e2e_opts_load
  e2e_store_load
  var %test = $dll(e2e.dll, Version, 0)
  if (%test) {
    echo -a * e2e.dll loaded: %test
    e2e_log e2e.dll loaded: %test
    var %selftest = $dll(e2e.dll, SelfTest, 0)
    if (%selftest != OK) {
      echo -a * ERROR: e2e.dll self-test failed: %selftest
      e2e_log e2e.dll self-test failed: %selftest
    }
  }
  else {
    echo -a * ERROR: Failed to load e2e.dll
    e2e_log Failed to load e2e.dll
  }
}

on *:ACTIVE:*: {
  set %e2e_active $active
  set %e2e_active_type $window($active).type
}

on *:UNLOAD: {
  if ($hget(e2e_self)) hfree e2e_self
  if ($hget(e2e_dm)) hfree e2e_dm
  if ($hget(e2e_chan)) hfree e2e_chan
  if ($hget(e2e_chan_enabled)) hfree e2e_chan_enabled
  if ($hget(e2e_dm_enabled)) hfree e2e_dm_enabled
  if ($hget(e2e_opts)) hfree e2e_opts
  dll -u e2e.dll
  echo -a * e2e.dll unloaded
}

; ============================================================================
; Helpers
; ============================================================================

alias e2e_tables {
  if (!$hget(e2e_self)) hmake e2e_self 50
  if (!$hget(e2e_dm)) hmake e2e_dm 500
  if (!$hget(e2e_chan)) hmake e2e_chan 200
  if (!$hget(e2e_chan_enabled)) hmake e2e_chan_enabled 200
  if (!$hget(e2e_dm_enabled)) hmake e2e_dm_enabled 200
  if (!$hget(e2e_opts)) hmake e2e_opts 20
}

alias e2e_log {
  if (!$1) return
  var %file = $+( $mircdir, e2e.logs )
  write -a %file $asctime(yyyy-mm-dd HH:nn:ss) $+  [SCRIPT]  $1-
}

alias e2e-menulog {
  if (!$1) return
  e2e_log_eval menu $1-
}

alias e2e_log_eval {
  if (!$1) return
  var %file = $+( $mircdir, e2e.logs )
  write -a %file $asctime(yyyy-mm-dd HH:nn:ss) $+  [SCRIPT]  $eval($1-,1)
}

alias e2e_tag_ok return $+($chr(3),03,[E2E],$chr(15))

alias e2e_tag_err return $+($chr(3),04,[E2E],$chr(15))

alias e2e_guard_should_send {
  e2e_tables
  var %scope = $1
  var %target = $2
  var %text = $3-
  var %key = $+(guard.,$e2e_norm(%scope),.,$e2e_norm(%target),.,$crc(%text,0))
  var %now = $ticks
  var %last = $hget(e2e_opts,%key)
  if (%last) {
    var %diff = $calc(%now - %last)
    if (%diff > 0 && %diff < 1500) return 0
  }
  hadd e2e_opts %key %now
  return 1
}

alias e2e_input_query {
  var %nick = $1
  var %text = $2-
  if ($left(%text,1) == /) return 0
  e2e_tables
  var %net = $e2e_net
  if (!%nick) %nick = $active
  if (!$e2e_dm_is_enabled(%net,%nick)) return 0
  if (($left(%text,5) == !enc-) || ($left(%text,9) == !chanenc-)) return 0
  if (!$e2e_guard_should_send(dm,%net $+ . $+ %nick,%text)) return 1
  encmsg %nick %text
  return 1
}

alias e2e_input_chan {
  var %chan = $1
  var %text = $2-
  if ($left(%text,1) == /) return 0
  e2e_tables
  var %net = $e2e_net
  if (!%chan) %chan = $target
  if (!$e2e_chan_is_enabled(%net,%chan)) return 0
  if (($left(%text,5) == !enc-) || ($left(%text,9) == !chanenc-)) return 0
  if (!$e2e_guard_should_send(chan,%net $+ . $+ %chan,%text)) return 1
  var %key = $e2e_chan_get(%net,%chan,key)
  if (!%key) {
    echo %chan $e2e_tag_err Missing channel key for %chan
    return 1
  }
  var %plain = %text
  var %input = %key $+ $chr(124) $+ %plain
  var %payload = $dll(e2e.dll, EncryptChan, %input)
  if ($left(%payload, 6) == ERROR:) {
    echo %chan $e2e_tag_err Encryption failed: %payload
    return 1
  }
  /.msg %chan !chanenc-msg %payload
  echo %chan $e2e_tag_ok $+(<,$me,>) %plain
  return 1
}

alias e2e_opts_load {
  e2e_tables
  var %file = $+( $mircdir, e2e_opts.hsh )
  if ($isfile(%file)) hload -s e2e_opts %file
  if (!$hget(e2e_opts, show_raw)) {
    hadd e2e_opts show_raw 1
    hsave -s e2e_opts %file
  }
  if (!$hget(e2e_opts, persist_mode)) {
    hadd e2e_opts persist_mode dpapi
    hsave -s e2e_opts %file
  }
  if (!$hget(e2e_opts, autosave)) {
    hadd e2e_opts autosave 0
    hsave -s e2e_opts %file
  }
}

alias e2e_opts_save {
  e2e_tables
  var %file = $+( $mircdir, e2e_opts.hsh )
  hsave -s e2e_opts %file
}

alias e2e_show_raw return $iif($hget(e2e_opts, show_raw),1,0)

alias e2e_persist_mode return $hget(e2e_opts, persist_mode)

alias e2e_autosave return $iif($hget(e2e_opts, autosave),1,0)

alias e2e-showraw {
  e2e_tables
  if ($1 == on) {
    e2e_log_eval cmd e2e-showraw on
    hadd e2e_opts show_raw 1
    e2e_opts_save
    echo -a * Raw encrypted lines are now visible
    return
  }
  if ($1 == off) {
    e2e_log_eval cmd e2e-showraw off
    hadd e2e_opts show_raw 0
    e2e_opts_save
    echo -a * Raw encrypted lines are now hidden
    return
  }
  echo -a * Usage: /e2e-showraw <on|off>
}

alias e2e-autosave {
  e2e_tables
  if ($1 == on) {
    e2e_log_eval cmd e2e-autosave on
    hadd e2e_opts autosave 1
    e2e_opts_save
    echo -a * Key autosave enabled
    return
  }
  if ($1 == off) {
    e2e_log_eval cmd e2e-autosave off
    hadd e2e_opts autosave 0
    e2e_opts_save
    echo -a * Key autosave disabled
    return
  }
  echo -a * Usage: /e2e-autosave <on|off>
}

alias e2e-chan-status {
  var %chan = $strip($1)
  if ($left(%chan,1) != $chr(35) && $left($strip($chan),1) == $chr(35)) %chan = $strip($chan)
  if ($left(%chan,1) != $chr(35) && $left($strip($active),1) == $chr(35)) %chan = $strip($active)
  if ($left(%chan,1) != $chr(35)) { /.echo -a * Channel command must be run in a channel | return }
  /.echo -a * Auto Encrypt is $iif($e2e_chan_is_enabled($e2e_net,%chan),ON,OFF) for %chan
}

alias e2e-persist {
  e2e_tables
  if ($1 == off) {
    e2e_log_eval cmd e2e-persist off
    hadd e2e_opts persist_mode off
    e2e_opts_save
    echo -a * Key persistence disabled
    return
  }
  if ($1 == dpapi) {
    e2e_log_eval cmd e2e-persist dpapi
    hadd e2e_opts persist_mode dpapi
    e2e_opts_save
    e2e_store_load
    echo -a * Key persistence set to DPAPI
    return
  }
  if ($1 == password) {
    e2e_log_eval cmd e2e-persist password
    hadd e2e_opts persist_mode password
    e2e_opts_save
    echo -a * Key persistence set to password mode. Use /e2e-setpass <password>
    return
  }
  echo -a * Usage: /e2e-persist <off|dpapi|password>
}

alias e2e-setpass {
  if (!$1) { echo -a * Usage: /e2e-setpass <password> | return }
  e2e_log_eval cmd e2e-setpass
  set %e2e_pass $1-
  echo -a * Password set for this session
  e2e_store_load
}

alias e2e-save { e2e_log_eval cmd e2e-save | e2e_store_save }

alias e2e-load { e2e_log_eval cmd e2e-load | e2e_store_load }

alias e2e_store_encrypt {
  var %mode = $e2e_persist_mode
  if (%mode == off) return $null
  var %input
  if (%mode == dpapi) {
    %input = %mode $+ $chr(124) $+ $1-
  }
  else {
    %input = %mode $+ $chr(124) $+ %e2e_pass $+ $chr(124) $+ $1-
  }
  return $dll(e2e.dll, StoreEncrypt, %input)
}

alias e2e_store_decrypt {
  var %mode = $e2e_persist_mode
  if (%mode == off) return $null
  var %input
  if (%mode == dpapi) {
    %input = %mode $+ $chr(124) $+ $1-
  }
  else {
    %input = %mode $+ $chr(124) $+ %e2e_pass $+ $chr(124) $+ $1-
  }
  return $dll(e2e.dll, StoreDecrypt, %input)
}

alias e2e_store_add {
  var %prefix = $1
  var %table = $2
  if (!$hget(%table)) return
  var %i = 1
  while (%i <= $hget(%table, 0).item) {
    var %item = $hget(%table, %i).item
    var %val = $hget(%table, %item)
    var %enc = $e2e_store_encrypt(%val)
    if ($left(%enc, 6) == ERROR:) { echo -a * %enc | e2e_log StoreEncrypt failed: %enc | set %e2e_store_err 1 | return }
    var %storekey = $+(%prefix,|,%item)
    hadd e2e_store %storekey %enc
    inc %i
  }
}

alias e2e_store_save {
  e2e_tables
  var %mode = $e2e_persist_mode
  if (%mode == off) return
  if (%mode == password && !%e2e_pass) {
    echo -a * Key persistence enabled but no password set. Use /e2e-setpass <password>.
    return
  }
  set %e2e_store_err 0
  var %file = $+( $mircdir, e2e_store.hsh )
  if ($hget(e2e_store)) hfree e2e_store
  hmake e2e_store 500
  e2e_store_add self e2e_self
  if (%e2e_store_err) { hfree e2e_store | echo -a * Key store save aborted | return }
  e2e_store_add dm e2e_dm
  if (%e2e_store_err) { hfree e2e_store | echo -a * Key store save aborted | return }
  e2e_store_add chan e2e_chan
  if (%e2e_store_err) { hfree e2e_store | echo -a * Key store save aborted | return }
  e2e_store_add chan_enabled e2e_chan_enabled
  if (%e2e_store_err) { hfree e2e_store | echo -a * Key store save aborted | return }
  e2e_store_add dm_enabled e2e_dm_enabled
  if (%e2e_store_err) { hfree e2e_store | echo -a * Key store save aborted | return }
  hsave -s e2e_store %file
  hfree e2e_store
  echo -a * Encrypted key store saved
}

alias e2e_store_load {
  e2e_tables
  var %mode = $e2e_persist_mode
  if (%mode == off) return
  if (%mode == password && !%e2e_pass) {
    echo -a * Enter password with /e2e-setpass <password> to load keys.
    return
  }
  var %file = $+( $mircdir, e2e_store.hsh )
  if (!$isfile(%file)) return

  if ($hget(e2e_store)) hfree e2e_store
  hmake e2e_store 500
  hload -s e2e_store %file

  if ($hget(e2e_self)) hfree e2e_self
  if ($hget(e2e_dm)) hfree e2e_dm
  if ($hget(e2e_chan)) hfree e2e_chan
  if ($hget(e2e_chan_enabled)) hfree e2e_chan_enabled
  if ($hget(e2e_dm_enabled)) hfree e2e_dm_enabled
  e2e_tables

  var %i = 1
  while (%i <= $hget(e2e_store, 0).item) {
    var %item = $hget(e2e_store, %i).item
    var %val = $hget(e2e_store, %item)
    var %dec = $e2e_store_decrypt(%val)
    if ($left(%dec, 6) == ERROR:) { echo -a * %dec | e2e_log StoreDecrypt failed: %dec | inc %i | continue }
    var %prefix = $gettok(%item, 1, 124)
    var %key = $gettok(%item, 2-, 124)
    if (%prefix == self) hadd e2e_self %key %dec
    if (%prefix == dm) hadd e2e_dm %key %dec
    if (%prefix == chan) hadd e2e_chan %key %dec
    if (%prefix == chan_enabled) hadd e2e_chan_enabled %key %dec
    if (%prefix == dm_enabled) hadd e2e_dm_enabled %key %dec
    inc %i
  }

  hfree e2e_store
  echo -a * Encrypted key store loaded
}

alias e2e_norm return $replace($lower($1),$chr(32),_)

alias e2e_net return $iif($network,$network,$server)

alias e2e_dm_prefix return $+(dm.,$e2e_norm($1),.,$e2e_norm($2))

alias e2e_chan_prefix return $+(chan.,$e2e_norm($1),.,$e2e_norm($2))

alias e2e_self_ensure {
  e2e_tables
  if ($hget(e2e_self, idPub)) return
  var %keys = $dll(e2e.dll, GenKeys, 0)
  if ($left(%keys, 6) == ERROR:) {
    echo -a * %keys
    return
  }
  hadd e2e_self idPub $gettok(%keys, 1, 124)
  hadd e2e_self encPub $gettok(%keys, 2, 124)
  hadd e2e_self idSec $gettok(%keys, 3, 124)
  hadd e2e_self encSec $gettok(%keys, 4, 124)
}

alias e2e_offer_create {
  e2e_self_ensure
  var %idPub = $hget(e2e_self, idPub)
  var %encPub = $hget(e2e_self, encPub)
  var %idSec = $hget(e2e_self, idSec)
  var %input = %idPub $+ $chr(124) $+ %encPub $+ $chr(124) $+ %idSec
  return $dll(e2e.dll, CreateOffer, %input)
}

alias e2e_dm_store {
  var %net = $1
  var %nick = $2
  var %idPub = $3
  var %encPub = $4
  var %sig = $5
  var %key = $6
  var %prefix = $e2e_dm_prefix(%net,%nick)
  hadd e2e_dm $+(%prefix,.idPub) %idPub
  hadd e2e_dm $+(%prefix,.encPub) %encPub
  hadd e2e_dm $+(%prefix,.sig) %sig
  if (%key) hadd e2e_dm $+(%prefix,.key) %key
}

alias e2e_dm_get {
  var %prefix = $e2e_dm_prefix($1,$2)
  return $hget(e2e_dm, $+(%prefix,.,$3))
}

alias e2e_dm_pick {
  return $hfind(e2e_dm, $+(dm.,*,.,$e2e_norm($1),.encPub), 1, w)
}

alias e2e_chan_store {
  var %net = $1
  var %chan = $2
  var %json = $3
  var %key = $4
  var %prefix = $e2e_chan_prefix(%net,%chan)
  hadd e2e_chan $+(%prefix,.json) %json
  hadd e2e_chan $+(%prefix,.key) %key
}

alias e2e_chan_get {
  var %prefix = $e2e_chan_prefix($1,$2)
  return $hget(e2e_chan, $+(%prefix,.,$3))
}

alias e2e_chan_enable {
  var %prefix = $e2e_chan_prefix($1,$2)
  hadd e2e_chan_enabled %prefix 1
}

alias e2e_chan_disable {
  var %prefix = $e2e_chan_prefix($1,$2)
  hdel e2e_chan_enabled %prefix
}

alias e2e_chan_is_enabled {
  var %prefix = $e2e_chan_prefix($1,$2)
  return $iif($hget(e2e_chan_enabled, %prefix),1,0)
}

alias e2e_dm_enable {
  e2e_tables
  var %prefix = $e2e_dm_prefix($1,$2)
  hadd e2e_dm_enabled %prefix 1
}

alias e2e_dm_disable {
  e2e_tables
  var %prefix = $e2e_dm_prefix($1,$2)
  hdel e2e_dm_enabled %prefix
}

alias e2e_dm_is_enabled {
  e2e_tables
  var %prefix = $e2e_dm_prefix($1,$2)
  return $iif($hget(e2e_dm_enabled, %prefix),1,0)
}

; ============================================================================
; DM commands
; ============================================================================

alias sharekey {
  if (!$1) { echo -a * Usage: /sharekey <nick> | return }
  e2e_log_eval cmd sharekey target=$1
  var %offer = $e2e_offer_create
  if ($left(%offer, 6) == ERROR:) { echo -a * %offer | return }
  /.msg $1 !enc-offer %offer
  echo -a * Encryption key offer sent to $1
}

alias requestkey {
  if (!$1) { echo -a * Usage: /requestkey <nick> | return }
  e2e_log_eval cmd requestkey target=$1
  /.msg $1 !enc-req
  echo -a * Encryption key requested from $1
}

alias enc-accept {
  if (!$1) { echo -a * Usage: /enc-accept <nick> | return }
  e2e_log_eval cmd enc-accept target=$1
  e2e_tables
  e2e_self_ensure
  var %net = $e2e_net
  var %prefix = $e2e_dm_prefix(%net,$1)
  var %pending = $hget(e2e_dm, $+(%prefix,.pending))
  var %pending_key = $hget(e2e_dm, $+(%prefix,.pending_key))
  if (!%pending) { echo -a * No pending offer from $1 | return }

  var %idPub = $json_extract(%pending, idPub)
  var %encPub = $json_extract(%pending, encPub)
  var %sig = $json_extract(%pending, sig)
  if ((%idPub == $null) || (%encPub == $null) || (%sig == $null)) {
    echo -a * Invalid pending offer data
    return
  }

  var %key = %pending_key
  if (!%key) {
    var %myEncSec = $hget(e2e_self, encSec)
    var %input = %idPub $+ $chr(124) $+ %encPub $+ $chr(124) $+ %sig $+ $chr(124) $+ %myEncSec
    %key = $dll(e2e.dll, DeriveSecret, %input)
    if ($left(%key, 6) == ERROR:) { echo -a * %key | return }
  }

  e2e_dm_store %net $1 %idPub %encPub %sig %key
  hdel e2e_dm $+(%prefix,.pending)
  hdel e2e_dm $+(%prefix,.pending_key)

  var %offer = $e2e_offer_create
  if ($left(%offer, 6) == ERROR:) { echo -a * %offer | return }
  /.msg $1 !enc-accept %offer
  echo -a * Accepted encryption key from $1
}

alias enc-reject {
  if (!$1) { echo -a * Usage: /enc-reject <nick> | return }
  e2e_log_eval cmd enc-reject target=$1
  e2e_tables
  var %net = $e2e_net
  var %prefix = $e2e_dm_prefix(%net,$1)
  hdel e2e_dm $+(%prefix,.pending)
  hdel e2e_dm $+(%prefix,.pending_key)
  /.msg $1 !enc-reject
  echo -a * Rejected encryption key from $1
}

alias encmsg {
  if ($2 == $null) { echo -a * Usage: /encmsg <nick> <message> | return }
  e2e_log_eval cmd encmsg target=$1
  e2e_tables
  e2e_self_ensure
  var %net = $e2e_net
  var %nick = $1
  var %idPub = $e2e_dm_get(%net,%nick,idPub)
  var %encPub = $e2e_dm_get(%net,%nick,encPub)
  var %sig = $e2e_dm_get(%net,%nick,sig)
  if (!%encPub) {
    var %item = $e2e_dm_pick(%nick)
    if (%item) {
      var %prefix = $left(%item, $calc($len(%item) - 7))
      %encPub = $hget(e2e_dm, %prefix $+ .encPub)
      %idPub = $hget(e2e_dm, %prefix $+ .idPub)
      %sig = $hget(e2e_dm, %prefix $+ .sig)
    }
  }
  if (!%encPub) { echo -a * No DM key for %nick. Use /sharekey or /requestkey first. | return }

  var %key = $e2e_dm_get(%net,%nick,key)
  if (!%key) {
    var %myEncSec = $hget(e2e_self, encSec)
    var %input = %idPub $+ $chr(124) $+ %encPub $+ $chr(124) $+ %sig $+ $chr(124) $+ %myEncSec
    %key = $dll(e2e.dll, DeriveSecret, %input)
    if ($left(%key, 6) == ERROR:) { echo -a * %key | return }
    var %storeprefix = $e2e_dm_prefix(%net,%nick)
    if (%prefix) %storeprefix = %prefix
    hadd e2e_dm %storeprefix $+ .key %key
  }

  var %myEncPub = $hget(e2e_self, encPub)
  var %plain = $2-
  var %input2 = %key $+ $chr(124) $+ %myEncPub $+ $chr(124) $+ %plain
  var %payload = $dll(e2e.dll, EncryptDM, %input2)
  if ($left(%payload, 6) == ERROR:) { echo -a * %payload | return }

  /.msg %nick !enc-msg %payload
  echo %nick $e2e_tag_ok $+(<,$me,>) %plain
}

alias dmenc-on {
  e2e_tables
  var %nick = $iif($1,$1,$active)
  if (!%nick) { echo -a * Usage: /dmenc-on <nick> | return }
  e2e_log_eval cmd dmenc-on target=%nick
  e2e_dm_enable $e2e_net %nick
  echo -a * DM auto-encrypt enabled for %nick
}

alias dmenc-off {
  e2e_tables
  var %nick = $iif($1,$1,$active)
  if (!%nick) { echo -a * Usage: /dmenc-off <nick> | return }
  e2e_log_eval cmd dmenc-off target=%nick
  e2e_dm_disable $e2e_net %nick
  echo -a * DM auto-encrypt disabled for %nick
}

; ============================================================================
; Channel commands
; ============================================================================

alias chankey {
  if (!$1) { echo -a * Usage: /chankey <generate|share|request|remove|send|help> [args] | return }
  e2e_log_eval cmd chankey raw=$1-
  e2e_tables
  var %net = $e2e_net
  var %action = $lower($1)

  if (%action == help) {
    echo -a Channel encryption:
    echo -a /chankey generate          Create key for active channel
    echo -a /chankey share <nick>     Send key to a user (DM)
    echo -a /chankey request <nick>   Ask a user for the channel key
    echo -a /chankey send <msg>       Send encrypted message to channel
    echo -a /chankey remove           Delete stored key for channel
    return
  }

  if (%action == generate) {
    var %chan = $null
    var %arg2 = $strip($2)
    var %achan = $strip($active)
    if ($left(%arg2,1) == $chr(35)) %chan = %arg2
    if ($left(%chan,1) != $chr(35) && $left($strip($chan),1) == $chr(35)) %chan = $strip($chan)
    if ($left(%chan,1) != $chr(35) && $left(%achan,1) == $chr(35)) %chan = %achan
    if ($left(%chan,1) != $chr(35)) {
      var %t2 = $strip($gettok($1-,2,32))
      if ($left(%t2,1) == $chr(35)) %chan = %t2
    }
    if ($left(%chan,1) != $chr(35) && $left($active,1) == $chr(35)) %chan = $active
    e2e_log $+(chankey generate raw=,$1-,$chr(32),active=,$active,$chr(32),achan=,%achan,$chr(32),arg2=,%arg2,$chr(32),chan=,%chan)
    if ($left(%chan,1) != $chr(35)) { /.echo -a * Channel command must be run in a channel | return }
    var %key = $dll(e2e.dll, GenChanKey, 0)
    e2e_log $+(chankey generate result=,%key)
    if ($left(%key, 6) == ERROR:) { /.echo -a * %key | return }
    var %created = $calc($ctime * 1000)
    var %json = $+({,"v":1,"channel":" ,%chan, ","network":" ,%net, ","key":" ,%key, ","createdAt":,%created, })
    e2e_chan_store %net %chan %json %key
    e2e_chan_enable %net %chan
    e2e_log $+(chankey generate stored chan=,%chan)
    /.echo -a * Channel key generated for %chan. Use /chankey share <nick> to share.
    return
  }

  if (%action == share) {
    var %chan = $null
    var %target = $null
    var %arg2 = $strip($2)
    var %arg3 = $strip($3)
    var %achan = $strip($active)
    if ($left(%arg2,1) == $chr(35)) {
      %chan = %arg2
      %target = %arg3
    }
    else {
      if ($left($strip($chan),1) == $chr(35)) %chan = $strip($chan)
      if ($left(%chan,1) != $chr(35) && $left(%achan,1) == $chr(35)) %chan = %achan
      %target = %arg2
    }
    if ($left(%chan,1) != $chr(35) || !$len(%target)) { /.echo -a * Usage: /chankey share <#chan> <nick> | return }
    var %json = $e2e_chan_get(%net,%chan,json)
    if (!%json) { /.echo -a * No channel key for %chan. Use /chankey generate first. | return }
    /.msg %target !chanenc-key %json
    /.echo -a * Channel key for %chan shared with %target
    return
  }

  if (%action == request) {
    var %chan = $null
    var %target = $null
    var %raw = $strip($1-)
    var %t2 = $strip($gettok(%raw,2,32))
    var %t3 = $strip($gettok(%raw,3,32))
    if ($left(%t2,1) == $chr(35)) {
      %chan = %t2
      %target = %t3
    }
    else if ($left(%t3,1) == $chr(35)) {
      %chan = %t3
      %target = %t2
    }
    else if ($left($strip($active),1) == $chr(35)) {
      %chan = $strip($active)
      %target = %t2
    }
    e2e_log $+(chankey request raw=,$1-,$chr(32),clean=,%raw,$chr(32),t2=,%t2,$chr(32),t3=,%t3,$chr(32),active=,$active,$chr(32),chan=,%chan,$chr(32),nick=,%target)
    if ($left(%chan,1) != $chr(35) || !$len(%target)) { /.echo -a * Usage: /chankey request <#chan> <nick> | return }
    /.msg %target Please share the channel key for %chan with /chankey share $me
    /.echo -a * Channel key requested from %target for %chan
    return
  }

  if (%action == remove) {
    var %chan = $null
    var %arg2 = $strip($2)
    var %achan = $strip($active)
    if ($left(%arg2,1) == $chr(35)) %chan = %arg2
    if ($left(%chan,1) != $chr(35) && $left($strip($chan),1) == $chr(35)) %chan = $strip($chan)
    if ($left(%chan,1) != $chr(35) && $left(%achan,1) == $chr(35)) %chan = %achan
    if ($left(%chan,1) != $chr(35)) { /.echo -a * Usage: /chankey remove <#chan> | return }
    hdel e2e_chan $+($e2e_chan_prefix(%net,%chan),.json)
    hdel e2e_chan $+($e2e_chan_prefix(%net,%chan),.key)
    e2e_chan_disable %net %chan
    /.echo -a * Channel key removed for %chan
    return
  }

  if (%action == send) {
    var %chan = $null
    var %msg = $null
    var %arg2 = $strip($2)
    var %achan = $strip($active)
    if ($left(%arg2,1) == $chr(35)) {
      %chan = %arg2
      %msg = $3-
    }
    else {
      if ($left(%achan,1) == $chr(35)) %chan = %achan
      %msg = $2-
    }
    e2e_log $+(chankey send raw=,$1-,$chr(32),active=,$active,$chr(32),chan=,%chan,$chr(32),msg=,%msg)
    if ($left(%chan,1) != $chr(35)) { /.echo -a * Channel command must be run in a channel | return }
    if (!$len(%msg)) { /.echo -a * Usage: /chankey send [#chan] <message> | return }
    var %key2 = $e2e_chan_get(%net,%chan,key)
    if (!%key2) { /.echo -a * No channel key for %chan. Use /chankey generate first. | return }
    var %plain2 = %msg
    var %input3 = %key2 $+ $chr(124) $+ %plain2
    var %payload2 = $dll(e2e.dll, EncryptChan, %input3)
    if ($left(%payload2, 6) == ERROR:) { /.echo -a * %payload2 | return }
    /.msg %chan !chanenc-msg %payload2
    echo %chan $e2e_tag_ok $+(<,$me,>) %plain2
    return
  }

  echo -a * Usage: /chankey <generate|share|request|remove|send|help> [args]
}

alias chanenc-on {
  var %chan = $strip($iif($1,$1,$active))
  var %achan = $strip($active)
  if ($left(%chan,1) != $chr(35) && $left($strip($chan),1) == $chr(35)) %chan = $strip($chan)
  if ($left(%chan,1) != $chr(35) && $left(%achan,1) == $chr(35)) %chan = %achan
  e2e_log $+(chanenc-on raw=,$1-,$chr(32),active=,$active,$chr(32),chanvar=,$chan,$chr(32),final=,%chan)
  e2e_log $+(chanenc-on check ascii=,$asc($left(%chan,1)))
  if ($left(%chan,1) != $chr(35)) { /.echo -a * Usage: /chanenc-on [#chan] | return }
  e2e_chan_enable $e2e_net %chan
  /.echo -a * Auto-encrypt enabled for %chan
}

alias chanenc-off {
  var %chan = $strip($iif($1,$1,$active))
  var %achan = $strip($active)
  if ($left(%chan,1) != $chr(35) && $left($strip($chan),1) == $chr(35)) %chan = $strip($chan)
  if ($left(%chan,1) != $chr(35) && $left(%achan,1) == $chr(35)) %chan = %achan
  e2e_log $+(chanenc-off raw=,$1-,$chr(32),active=,$active,$chr(32),chanvar=,$chan,$chr(32),final=,%chan)
  e2e_log $+(chanenc-off check ascii=,$asc($left(%chan,1)))
  if ($left(%chan,1) != $chr(35)) { /.echo -a * Usage: /chanenc-off [#chan] | return }
  e2e_chan_disable $e2e_net %chan
  /.echo -a * Auto-encrypt disabled for %chan
}

; ============================================================================
; DM receive handlers
; ============================================================================

on *:TEXT:!enc-req:?: {
  var %offer = $e2e_offer_create
  if ($left(%offer, 6) == ERROR:) { echo -a * %offer | return }
  /.msg $nick !enc-offer %offer
  echo -a * Sent encryption key offer to $nick
}

on *:TEXT:!enc-offer *:?: {
  e2e_tables
  e2e_self_ensure
  var %net = $e2e_net
  var %offer = $2-
  var %idPub = $json_extract(%offer, idPub)
  var %encPub = $json_extract(%offer, encPub)
  var %sig = $json_extract(%offer, sig)

  if ((%idPub == $null) || (%encPub == $null) || (%sig == $null)) {
    echo -a * Invalid key offer from $nick
    return
  }

  var %myEncSec = $hget(e2e_self, encSec)
  var %input = %idPub $+ $chr(124) $+ %encPub $+ $chr(124) $+ %sig $+ $chr(124) $+ %myEncSec
  var %key = $dll(e2e.dll, DeriveSecret, %input)
  if ($left(%key, 6) == ERROR:) {
    echo -a * Invalid key offer from $nick
    return
  }

  var %existing = $e2e_dm_get(%net,$nick,encPub)
  if (%existing == %encPub) {
    echo -a * Key offer from $nick matches existing key
    return
  }

  var %prefix = $e2e_dm_prefix(%net,$nick)
  hadd e2e_dm $+(%prefix,.pending) %offer
  hadd e2e_dm $+(%prefix,.pending_key) %key
  echo -a * Key offer received from $nick. Use /enc-accept $nick or /enc-reject $nick
}

on *:TEXT:!enc-accept *:?: {
  e2e_tables
  e2e_self_ensure
  var %net = $e2e_net
  var %offer = $2-
  var %idPub = $json_extract(%offer, idPub)
  var %encPub = $json_extract(%offer, encPub)
  var %sig = $json_extract(%offer, sig)

  if ((%idPub == $null) || (%encPub == $null) || (%sig == $null)) {
    echo -a * Invalid acceptance from $nick
    return
  }

  var %myEncSec = $hget(e2e_self, encSec)
  var %input = %idPub $+ $chr(124) $+ %encPub $+ $chr(124) $+ %sig $+ $chr(124) $+ %myEncSec
  var %key = $dll(e2e.dll, DeriveSecret, %input)
  if ($left(%key, 6) == ERROR:) { echo -a * %key | return }

  e2e_dm_store %net $nick %idPub %encPub %sig %key
  e2e_dm_enable %net $nick
  echo -a * $nick accepted your encryption key. DM encryption enabled.
}

on *:TEXT:!enc-reject:?: {
  echo -a * $nick rejected your encryption key offer.
}

on ^*:INPUT:?: {
  if (%e2e_input_handled) return
  if ($e2e_input_query($iif($target,$target,$active),$1-)) {
    set -u1 %e2e_input_handled 1
    haltdef
    halt
  }
}

on ^*:TEXT:!enc-msg *:?: {
  e2e_tables
  e2e_self_ensure
  if ($lower($nick) == $lower($me)) { if (!$e2e_show_raw) halt | return }
  var %net = $e2e_net
  var %payload = $2-
  var %from = $json_extract(%payload, from)
  var %nonce = $json_extract(%payload, nonce)
  var %cipher = $json_extract(%payload, cipher)

  if ((%from == $null) || (%nonce == $null) || (%cipher == $null)) {
    echo -a * Invalid encrypted DM from $nick
    return
  }

  var %encPub = $e2e_dm_get(%net,$nick,encPub)
  if (!%encPub) {
    echo -a * No DM key for $nick. Use /sharekey or /requestkey.
    return
  }

  if (%from != %encPub) {
    echo -a * Encrypted DM from $nick has mismatched sender key
    return
  }

  var %key = $e2e_dm_get(%net,$nick,key)
  if (!%key) {
    var %idPub = $e2e_dm_get(%net,$nick,idPub)
    var %sig = $e2e_dm_get(%net,$nick,sig)
    var %myEncSec = $hget(e2e_self, encSec)
    var %input = %idPub $+ $chr(124) $+ %encPub $+ $chr(124) $+ %sig $+ $chr(124) $+ %myEncSec
    %key = $dll(e2e.dll, DeriveSecret, %input)
    if ($left(%key, 6) == ERROR:) { echo -a * %key | return }
    hadd e2e_dm $+($e2e_dm_prefix(%net,$nick),.key) %key
  }

  var %input2 = %key $+ $chr(124) $+ %nonce $+ $chr(124) $+ %cipher
  var %plain = $dll(e2e.dll, DecryptDM, %input2)
  if ($left(%plain, 6) == ERROR:) { echo -a * %plain | return }

  echo $nick $e2e_tag_ok $+(<,$nick,>) %plain
  if (!$e2e_show_raw) halt
}

on ^*:TEXT:*:?: {
  if ($lower($nick) != $lower($me)) return
  e2e_tables
  if (!$e2e_dm_is_enabled($e2e_net,$target)) return
  if (($left($1,5) == !enc-) || ($left($1,9) == !chanenc-)) return
  halt
}

; ============================================================================
; Channel receive handlers
; ============================================================================

on *:TEXT:!chanenc-key *:?: {
  e2e_tables
  var %net = $e2e_net
  var %json = $2-
  var %chan = $json_extract(%json, channel)
  var %key = $json_extract(%json, key)
  var %network = $json_extract(%json, network)
  if (%network == $null) %network = %net
  if (!%chan || !%key) {
    echo -a * Invalid channel key from $nick
    return
  }
  e2e_chan_store %network %chan %json %key
  e2e_chan_enable %network %chan
  echo -a * Received channel key for %chan from $nick
}

on ^*:INPUT:#: {
  if (%e2e_input_handled) return
  if ($e2e_input_chan($iif($target,$target,$active),$1-)) {
    set -u1 %e2e_input_handled 1
    haltdef
    halt
  }
}

on ^*:TEXT:!chanenc-msg *:#: {
  e2e_tables
  if ($lower($nick) == $lower($me)) { if (!$e2e_show_raw) halt | return }
  var %net = $e2e_net
  var %chan = $chan
  var %payload = $2-
  var %nonce = $json_extract(%payload, nonce)
  var %cipher = $json_extract(%payload, cipher)
  if ((%nonce == $null) || (%cipher == $null)) {
    echo %chan $e2e_tag_err Invalid encrypted message from $nick
    return
  }

  var %key = $e2e_chan_get(%net,%chan,key)
  if (!%key) {
    echo %chan $e2e_tag_err Missing channel key for %chan
    return
  }

  var %input = %key $+ $chr(124) $+ %nonce $+ $chr(124) $+ %cipher
  var %plain = $dll(e2e.dll, DecryptChan, %input)
  if ($left(%plain, 6) == ERROR:) {
    echo %chan $e2e_tag_err Decryption failed: %plain
    return
  }

  echo %chan $e2e_tag_ok $+(<,$nick,>) %plain
  if (!$e2e_show_raw) halt
}

on ^*:TEXT:*:#: {
  if ($lower($nick) != $lower($me)) return
  e2e_tables
  if (!$e2e_chan_is_enabled($e2e_net,$chan)) return
  if (($left($1,5) == !enc-) || ($left($1,9) == !chanenc-)) return
  halt
}

; ============================================================================
; Auto-encrypt channel input
; ============================================================================

alias say {
  /.say $1-
}

alias msg {
  /.msg $1-
}

; ============================================================================
; JSON helper
; ============================================================================

alias json_extract {
  var %json = $1
  var %key = $2
  if ($regex(%json, $+(/",%key,"\s*:\s*"([^"]*)"/))) return $regml(1)
  if ($regex(%json, $+(/",%key,"\s*:\s*([0-9]+)/))) return $regml(1)
  return $null
}

; ============================================================================
; EOF
; ============================================================================




