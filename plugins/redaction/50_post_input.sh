#!/usr/bin/env bash

. "$(dirname "${0}")/../../helpers/logging.sh";

# On most Linux systems, sed is GNU sed and supports the -z option since 4.2.2 (released on 2012-12-22). In case of OS X and busybox, the -z option is not supported.
if ! command -v sed >/dev/null 2>&1; then
  logging_info "sed is required for redaction";
  logging_info "GNU sed >= 4.2.2 is required for multiline redaction";
  cat;
fi

redact_high_entropy_strings() (
  while IFS= read -r line; do
    for word in ${line}; do
      # Minimum length to consider
      if [ "${#word}" -lt 16 ]; then
        continue;
      fi
      ENTROPY_THRESHOLD=4.0 # Threshold for high entropy (typical for encryption keys, tokens)
      # Calculate entropy using Shannon's formula
      entropy=$(echo "${word}" | awk '
        BEGIN { FS="" }
        {
          for(i=1; i<=NF; i++) freq[$i]++
          total=NF
        }
        END {
          entropy=0
          for(char in freq) {
              p = freq[char]/total
              entropy -= p * log(p)/log(2)
          }
          print entropy
        }
      ');
      # logging_debug "Entropy for ${word}: ${entropy}";
      if awk "BEGIN {exit !(${entropy} <= ${ENTROPY_THRESHOLD})}"; then
        continue;
      fi
      line=$(echo "${line}" | sed -E "s/$(printf '%s\n' "${word}" | sed -e 's/[]\/$*.^[+]/\\&/g')/[HIGH ENTROPY STRING REDACTED]/g");
    done
    echo "$line";
  done
) 

# multi-line pattern matches first
(
  # if sed support -z
  if sed -z '' </dev/null 2>/dev/null; then
    sed -z 's/-----BEGIN.*PRIVATE KEY-----.*-----END.*PRIVATE KEY-----/[PRIVATE KEY REDACTED]/g' `# Redact potential SSH private keys`;
  else
    logging_info "GNU sed > 4.2.2 is required for multiline redaction";
    cat;
  fi
) \
| while IFS= read -r line; do
  echo "${line}" \
  | sed -E 's/\b[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}\b/[UUID REDACTED]/g' `# Redact UUIDs (both with and without dashes)` \
  | sed -E 's/\b[0-9]{4}[-. ]?[0-9]{4}[-. ]?[0-9]{4}[-. ]?[0-9]{4}\b/[CREDIT CARD REDACTED]/g' `# Redact credit card numbers` \
  | sed -E 's/\b[A-Za-z0-9+\/]{44,}={0,2}\b/[BASE64 KEY REDACTED]/g' `# Redact base64 strings (44+ characters, typical for private keys)` \
  | sed -E 's/\b[0-9a-fA-F]{32,}\b/[POSSIBLE HEX KEY REDACTED]/g' `# Redact hex strings (32+ characters)` \
  | sed -E 's/\b[0-9]{3}[-]?[0-9]{2}[-]?[0-9]{4}\b/[SSN REDACTED]/g' `# Redact SSN` \
  | sed -E 's/\b(\+?1[-.]?)?\(?[0-9]{3}\)?[-. ]?[0-9]{3}[-. ]?[0-9]{4}\b/[PHONE REDACTED]/g' `# Redact phone numbers (various formats)` \
  | sed -E 's/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/[EMAIL REDACTED]/g' `# Redact email addresses` \
  | redact_high_entropy_strings;
done