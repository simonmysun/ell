#!/usr/bin/env bash

# Self-checking tests for plugins/redaction/50_post_input.sh.
#
# This plugin is a security control: it strips secrets (emails, phone numbers,
# card/SSN numbers, keys, UUIDs, high-entropy tokens) out of input before it is
# sent to the LLM. A regression here silently leaks sensitive data, so each case
# asserts BOTH that the secret is gone AND that it was replaced by the expected
# redaction marker. A few negative cases assert that ordinary text survives.
#
# Requires GNU sed >= 4.2.2 for the multiline private-key case (as documented in
# the plugin itself); on other seds that single case degrades to passthrough.

set -o posix;

DIR="$(dirname "${0}")";
. "${DIR}/../../tests/assert.sh";

# The redaction plugin ships disabled by default (it is a best-effort control
# and can mangle input), so its script carries a .disabled suffix and is not
# auto-discovered by list_plugin_hooks. We still exercise its behaviour
# directly by running the .disabled script, which is a normal executable.
REDACT="${DIR}/50_post_input.sh.disabled";

# redact <text>: run one line of input through the redaction plugin and print
# the result. stderr (plugin info logs) is discarded so it doesn't pollute the
# captured output.
redact() {
  printf '%s\n' "${1}" | "${REDACT}" 2>/dev/null;
}

echo "redaction tests";
echo "===============";

# --- Positive cases: the secret must be gone AND the marker present ----------

out="$(redact 'Contact us at test@example.com or a.b+tag@sub.domain.co.uk')";
assert_contains  "email replaced by marker"      "${out}" '[EMAIL REDACTED]';
assert_not_contains "email address removed"      "${out}" 'test@example.com';
assert_not_contains "second email removed"       "${out}" 'a.b+tag@sub.domain.co.uk';

out="$(redact 'Card: 4111-1111-1111-1111 and 4111111111111111')";
assert_contains  "credit card replaced"          "${out}" '[CREDIT CARD REDACTED]';
assert_not_contains "dashed card removed"        "${out}" '4111-1111-1111-1111';
assert_not_contains "bare card removed"          "${out}" '4111111111111111';

out="$(redact 'SSN: 123-45-6789')";
assert_contains  "ssn replaced"                  "${out}" '[SSN REDACTED]';
assert_not_contains "ssn digits removed"         "${out}" '123-45-6789';

out="$(redact 'API Key: 6060f9ce647bf7fae0e96534632f1acc666ebde3')";
assert_contains  "hex key replaced"              "${out}" '[POSSIBLE HEX KEY REDACTED]';
assert_not_contains "hex key removed"            "${out}" '6060f9ce647bf7fae0e96534632f1acc666ebde3';

out="$(redact 'Base64 key: VGhpcyBpcyBhIHZlcnkgbG9uZyBiYXNlNjQgc3RyaW5nIHRoYXQgc2hvdWxkIGJlIHJlZGFjdGVk')";
assert_contains  "base64 key replaced"           "${out}" '[BASE64 KEY REDACTED]';
assert_not_contains "base64 key removed"         "${out}" 'VGhpcyBpcyBhIHZlcnkgbG9uZyBiYXNlNjQ';

out="$(redact 'UUID: 550e8400-e29b-41d4-a716-446655440000')";
assert_contains  "uuid replaced"                 "${out}" '[UUID REDACTED]';
assert_not_contains "uuid removed"               "${out}" '550e8400-e29b-41d4-a716-446655440000';

# Phone: the regex intentionally does not swallow a leading "+1 (" prefix, so we
# assert the marker appears and the core digits are gone rather than an exact
# whole-line match.
out="$(redact 'Call: +1 (123) 456-7890')";
assert_contains  "phone replaced"                "${out}" '[PHONE REDACTED]';
assert_not_contains "phone digits removed"       "${out}" '456-7890';

# High-entropy token (no other pattern matches it) must be caught by the
# entropy pass.
out="$(redact 'High entropy: Th1S_i5_4_h!GH_EnTrOPy_s7R1N6')";
assert_contains  "high-entropy replaced"         "${out}" '[HIGH ENTROPY STRING REDACTED]';
assert_not_contains "high-entropy token removed" "${out}" 'Th1S_i5_4_h!GH_EnTrOPy_s7R1N6';

# --- Multiline private key --------------------------------------------------
# Only assert when the running sed supports -z (GNU sed >= 4.2.2); otherwise the
# plugin documents that it degrades to passthrough, so skip rather than fail.
if sed -z '' </dev/null 2>/dev/null; then
  # The plugin's final read loop needs a trailing newline, so build the input
  # with one.
  key_in="$(printf '%s\n' \
    '-----BEGIN RSA PRIVATE KEY-----' \
    'MIICXgIBAAKBgQC+fem/IyhjAsbaT3dEf9UwXBA9' \
    '-----END RSA PRIVATE KEY-----')";
  out="$(printf '%s\n' "${key_in}" | "${REDACT}" 2>/dev/null)";
  assert_contains     "private key replaced"     "${out}" '[PRIVATE KEY REDACTED]';
  assert_not_contains "private key body removed"  "${out}" 'MIICXgIBAAKBgQC';
else
  echo "SKIP: private key (sed -z unsupported)";
fi

# --- Negative cases: ordinary text must NOT be redacted ---------------------

out="$(redact 'Hello world! Regular text 123')";
assert_equals "plain sentence untouched" 'Hello world! Regular text 123' "${out}";

out="$(redact 'Short hex: a1b2c3')";
assert_equals "short hex untouched" 'Short hex: a1b2c3' "${out}";
assert_not_contains "no false hex redaction" "${out}" 'REDACTED';

out="$(redact 'The quick brown fox jumps over the lazy dog')";
assert_not_contains "ordinary words not redacted" "${out}" 'REDACTED';

assert_summary;
