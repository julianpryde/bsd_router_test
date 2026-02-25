##! BSD Router – Zeek site policy
##!
##! Loaded by ZeekControl from every worker/standalone node.
##! Enables JA4 TLS fingerprinting plus baseline SSL/TLS logging.

# Core SSL/TLS analysis (cipher negotiation, certificate logging, etc.)
@load base/protocols/ssl

# Validate server certificates against the system trust store.
@load policy/protocols/ssl/validate-certs

# Log only the leaf (host) certificate rather than the full chain,
# keeping x509.log concise on a busy router.
@load policy/protocols/ssl/log-hostcerts-only

# JA4 TLS client fingerprinting – produces ja4.log.
@load ./ja4_fingerprint
