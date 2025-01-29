#!/usr/bin/env bash

set -o posix;

export ELL_TEMPLATE_PATH='/ell/templates/';

echo "redaction test";

$(dirname "${0}")/../plugins/redaction/50_post_input.sh <<EOF
# Email addresses
Contact us at test@example.com or another.user+tag@sub.domain.co.uk

# Phone numbers
Call us at: +1 (123) 456-7890
Alternative: 123.456.7890
Direct line: 1234567890
International: +1-123-456-7890

# Credit card numbers
Card number: 4111-1111-1111-1111
Alternative: 4111111111111111
Spaced: 4111 1111 1111 1111

# Social Security Numbers
SSN: 123-45-6789
Without dashes: 123456789

# Hex strings (32+ characters)
API Key: 6060f9ce647bf7fae0e96534632f1acc666ebde3
Long hex: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2

# Base64 strings (44+ characters)
Base64 key: VGhpcyBpcyBhIHZlcnkgbG9uZyBiYXNlNjQgc3RyaW5nIHRoYXQgc2hvdWxkIGJlIHJlZGFjdGVk

# SSH private keys
-----BEGIN RSA PRIVATE KEY-----
MIICXgIBAAKBgQC+fem/IyhjAsbaT3dEf9UwXBA9
-----END RSA PRIVATE KEY-----

# UUIDs
UUID: 550e8400-e29b-41d4-a716-446655440000
Without dashes: 550e8400e29b41d4a716446655440000

# Normal text that should not be redacted
Hello world! Regular text 123
Short hex: a1b2c3
Short base64: VGVzdA==

# High entropy strings
High entropy: Th1S_i5_4_h!GH_EnTrOPy_s7R1N6
EOF
