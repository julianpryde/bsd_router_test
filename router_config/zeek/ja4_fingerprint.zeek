##! JA4 TLS Client Fingerprinting for BSD Router
##!
##! Implements the JA4 specification from FoxIO:
##!   https://github.com/FoxIO-LLC/ja4
##!
##! Logs a ja4.log with hashed (ja4) and raw (ja4_r) fingerprints for every
##! TLS ClientHello seen on the monitored interface.  The fingerprint lets you
##! track and profile individual client applications across connections.
##!
##! JA4 format:
##!   <proto><tls_ver><sni><n_ciphers><n_exts><alpn>_<cipher_hash>_<ext_hash>
##!
##!   proto       : 't' (TLS) or 'q' (QUIC) – always 't' here
##!   tls_ver     : negotiated version (13, 12, 11, 10, s3, 00)
##!   sni         : 'd' if SNI domain present, 'i' otherwise
##!   n_ciphers   : 2-digit count of non-GREASE cipher suites
##!   n_exts      : 2-digit count of non-GREASE extensions
##!   alpn        : first 2 chars of first ALPN value, or "00"
##!   cipher_hash : SHA256[:12] of sorted hex cipher suites
##!   ext_hash    : SHA256[:12] of sorted hex extensions (excl. SNI & ALPN)

@load base/protocols/ssl

module JA4;

export {
    redef enum Log::ID += { LOG };

    ## Record written to ja4.log for each TLS ClientHello.
    type Info: record {
        ## Timestamp when the ClientHello was captured.
        ts:     time    &log;
        ## Unique connection identifier (matches ssl.log / conn.log).
        uid:    string  &log;
        ## IP/port 4-tuple of the connection.
        id:     conn_id &log;
        ## JA4 fingerprint with hashed cipher and extension components.
        ja4:    string  &log &optional;
        ## JA4_r raw fingerprint with plaintext cipher and extension lists,
        ## useful for manual inspection and rule writing.
        ja4_r:  string  &log &optional;
    };

    ## Raised each time a JA4 record is written; hook for downstream scripts.
    global log_ja4: event(rec: Info);
}

## GREASE values (RFC 8701) – excluded from all fingerprint computations.
const GREASE: set[count] = {
    0x0a0a, 0x1a1a, 0x2a2a, 0x3a3a, 0x4a4a, 0x5a5a,
    0x6a6a, 0x7a7a, 0x8a8a, 0x9a9a, 0xaaaa, 0xbaba,
    0xcaca, 0xdada, 0xeaea, 0xfafa
} &redef;

## Per-connection accumulator populated across multiple SSL events.
type ConnState: record {
    ## TLS version from ClientHello record header; may be overridden by
    ## the supported_versions extension (for TLS 1.3 detection).
    version:    count           &default=0x0303;
    ## True when the ClientHello contained a non-empty SNI hostname.
    has_sni:    bool            &default=F;
    ## Cipher suites in order as they appear in the ClientHello.
    ciphers:    vector of count &default=vector();
    ## Extension type codes in order as they appear in the ClientHello.
    extensions: vector of count &default=vector();
    ## First two characters of the first ALPN protocol, or "00".
    alpn:       string          &default="00";
    ## Set once emit_ja4() has written the log record.
    logged:     bool            &default=F;
};

## State table indexed by connection uid; entries expire after 5 minutes.
global conn_state: table[string] of ConnState &create_expire=5min;

## ---------------------------------------------------------------------------
## Helpers
## ---------------------------------------------------------------------------

## Return the two-character JA4 TLS version string for a numeric version.
function tls_ver_str(ver: count): string
    {
    if ( ver == 0x0304 ) return "13";
    if ( ver == 0x0303 ) return "12";
    if ( ver == 0x0302 ) return "11";
    if ( ver == 0x0301 ) return "10";
    if ( ver == 0x0300 ) return "s3";
    return "00";
    }

## Build and write the JA4 log record for connection *c*.
## Safe to call multiple times – only the first call writes.
function emit_ja4(c: connection)
    {
    if ( c$uid !in conn_state )
        return;

    local s = conn_state[c$uid];

    if ( s$logged )
        return;

    s$logged = T;

    local tls_ver  = tls_ver_str(s$version);
    local sni_char = s$has_sni ? "d" : "i";

    # --- Cipher suites: filter GREASE and TLS_EMPTY_RENEGOTIATION_INFO_SCSV ---
    local ciphers: vector of count = vector();
    for ( i in s$ciphers )
        {
        if ( s$ciphers[i] !in GREASE && s$ciphers[i] != 0x00ff )
            ciphers += s$ciphers[i];
        }
    local n_c     = |ciphers|;
    local c_count = n_c < 100 ? fmt("%02d", n_c) : "99";

    # --- Extensions: filter GREASE ---
    local exts: vector of count = vector();
    for ( i in s$extensions )
        {
        if ( s$extensions[i] !in GREASE )
            exts += s$extensions[i];
        }
    local n_e     = |exts|;
    local e_count = n_e < 100 ? fmt("%02d", n_e) : "99";

    # --- JA4_a component ---
    local ja4_a = cat("t", tls_ver, sni_char, c_count, e_count, s$alpn);

    # --- JA4_b: sorted cipher suite hex string, then SHA256[:12] ---
    local sorted_c = ciphers;
    sort(sorted_c, function(a: count, b: count): int
        { return a < b ? -1 : ( a > b ? 1 : 0 ); });
    local c_parts: vector of string = vector();
    for ( i in sorted_c )
        c_parts += fmt("%04x", sorted_c[i]);
    local c_raw  = join_string_vec(c_parts, ",");
    local c_hash = sha256(c_raw)[0:12];

    # --- JA4_c: sorted extensions (excl. SNI=0 and ALPN=16), then SHA256[:12] ---
    local exts_for_hash: vector of count = vector();
    for ( i in exts )
        {
        if ( exts[i] != 0 && exts[i] != 16 )
            exts_for_hash += exts[i];
        }
    sort(exts_for_hash, function(a: count, b: count): int
        { return a < b ? -1 : ( a > b ? 1 : 0 ); });
    local e_parts: vector of string = vector();
    for ( i in exts_for_hash )
        e_parts += fmt("%04x", exts_for_hash[i]);
    local e_raw  = join_string_vec(e_parts, ",");
    local e_hash = sha256(e_raw)[0:12];

    local rec = Info(
        $ts    = network_time(),
        $uid   = c$uid,
        $id    = c$id,
        $ja4   = cat(ja4_a, "_", c_hash, "_", e_hash),
        $ja4_r = cat(ja4_a, "_", c_raw,  "_", e_raw)
    );

    Log::write(JA4::LOG, rec);
    }

## ---------------------------------------------------------------------------
## Event handlers
## ---------------------------------------------------------------------------

event zeek_init() &priority=5
    {
    Log::create_stream(JA4::LOG, [$columns=Info, $ev=log_ja4, $path="ja4"]);
    }

## Capture cipher suites and record-layer version from the ClientHello.
event ssl_client_hello(c: connection, version: count, record_version: count,
                       possible_ts: time, client_random: string,
                       session_id: string, ciphers: index_vec,
                       comp_methods: index_vec)
    {
    local s: ConnState;
    s$version = version;
    for ( i in ciphers )
        s$ciphers += ciphers[i];
    conn_state[c$uid] = s;
    }

## Accumulate extension type codes and parse ALPN values.
event ssl_extension(c: connection, is_orig: bool, code: count, val: string)
    {
    if ( !is_orig || c$uid !in conn_state )
        return;

    conn_state[c$uid]$extensions += code;

    # ALPN extension (type 16) – RFC 7301
    # Wire format: [2-byte list-len][1-byte proto-len][proto-bytes]...
    if ( code == 16 && |val| >= 4 )
        {
        local proto_len = bytestring_to_count(val[2:3]);
        if ( proto_len >= 2 && |val| >= 3 + proto_len )
            conn_state[c$uid]$alpn = val[3:5];
        else if ( proto_len == 1 && |val| >= 4 )
            conn_state[c$uid]$alpn = cat(val[3:4], "0");
        }
    }

## Mark SNI present when the server_name extension is seen.
event ssl_extension_server_name(c: connection, is_orig: bool,
                                names: string_vec)
    {
    if ( !is_orig || c$uid !in conn_state )
        return;
    if ( |names| > 0 && names[0] != "" )
        conn_state[c$uid]$has_sni = T;
    }

## Override TLS version to 1.3 when the supported_versions extension
## advertises 0x0304 – the ClientHello record layer still shows 0x0303.
event ssl_extension_supported_versions(c: connection, is_orig: bool,
                                       versions: index_vec)
    {
    if ( !is_orig || c$uid !in conn_state )
        return;
    for ( i in versions )
        {
        if ( versions[i] == 0x0304 )
            {
            conn_state[c$uid]$version = 0x0304;
            break;
            }
        }
    }

## Write the fingerprint once the TLS handshake completes successfully.
event ssl_established(c: connection)
    {
    emit_ja4(c);
    }

## Fallback: write the fingerprint on connection teardown for incomplete
## or failed TLS sessions (e.g. ClientHello not followed by ServerHello).
event connection_state_remove(c: connection)
    {
    if ( c$uid in conn_state )
        {
        emit_ja4(c);
        delete conn_state[c$uid];
        }
    }
