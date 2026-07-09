#!/usr/bin/env bash
set -euo pipefail

# ragenix ships its own pinned nix binary; a foreign LD_LIBRARY_PATH (e.g.
# from nix-ld on NixOS hosts) can inject an incompatible glibc into it.
unset LD_LIBRARY_PATH

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="mindroom"
with_chat=0
non_interactive=0
values_dir=""

usage() {
  cat <<'USAGE'
Usage: bootstrap-secrets.sh [host] [--with-chat] [--non-interactive] [--values-dir DIR]

  --with-chat        Also bootstrap chat-runtime.env.age (only needed when
                     mindroom.runtime.chat.enable = true).
  --non-interactive  Never open an editor. Each secret is encrypted from its
                     template (or the matching file in --values-dir), the
                     registration token is generated automatically and synced
                     into lab-runtime.env, and existing secrets are kept.
  --values-dir DIR   Take secret contents from DIR instead of templates/.
                     File names (no .age suffix): agent-integrations.env,
                     agent-tooling.env, agent-runtime.env, lab-runtime.env,
                     chat-runtime.env, registration-token.
                     Missing files fall back to the template.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --with-chat) with_chat=1 ;;
    --non-interactive) non_interactive=1 ;;
    --values-dir)
      shift
      values_dir="${1:?--values-dir needs an argument}"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      usage >&2
      exit 1
      ;;
    *) host="$1" ;;
  esac
  shift
done

real_editor="${EDITOR:-vi}"
if [ "$non_interactive" = "1" ]; then
  real_editor="true"
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "Missing required command: nix" >&2
  echo "Bootstrap secrets from any machine with Nix installed, or from inside the target NixOS container." >&2
  exit 1
fi

if ! command -v ragenix >/dev/null 2>&1; then
  echo "Missing required command: ragenix" >&2
  echo "Run this via Nix from the repo root (uses the pinned ragenix):" >&2
  echo "  nix shell .#ragenix -c ./scripts/bootstrap-secrets.sh $host" >&2
  exit 1
fi

host_dir="$repo_root/hosts/$host"
host_rules="$host_dir/secrets/secrets.nix"
shared_rules="$repo_root/secrets/shared/secrets.nix"

if [ ! -d "$host_dir" ]; then
  echo "Unknown host: $host" >&2
  exit 1
fi

count_recipients() {
  local rules_path="$1"
  local secret_name="$2"

  nix eval --impure --raw --expr "
    let
      rules = import (builtins.toPath \"$rules_path\");
    in
      toString (builtins.length rules.\"$secret_name\".publicKeys)
  "
}

ensure_recipients() {
  local rules_path="$1"
  local secret_name="$2"
  local count

  if ! count="$(count_recipients "$rules_path" "$secret_name")"; then
    echo "Failed to evaluate recipients for $secret_name from $rules_path" >&2
    exit 1
  fi

  if [ "$count" -eq 0 ]; then
    echo "No recipients configured for $secret_name in $rules_path" >&2
    echo "Edit that file first and add at least one operator key and the host key." >&2
    exit 1
  fi
}

list_recipients() {
  local rules_path="$1"
  local secret_name="$2"

  nix eval --impure --raw --expr "
    let
      rules = import (builtins.toPath \"$rules_path\");
    in
      builtins.concatStringsSep \"\n\" rules.\"$secret_name\".publicKeys
  "
}

# The stale-secret check hashes and re-encodes recipient keys. Prefer GNU
# coreutils (sha256sum, basenc); fall back to openssl (present on macOS).
# Only when neither exists is the check skipped, with a warning.
tag_tool=""
if command -v sha256sum >/dev/null 2>&1 && command -v basenc >/dev/null 2>&1; then
  tag_tool="gnu"
elif command -v openssl >/dev/null 2>&1; then
  tag_tool="openssl"
fi

b64_decode() {
  if [ "$tag_tool" = "openssl" ]; then
    openssl base64 -d
  else
    base64 -d
  fi
}

# age header stanzas identify ssh-ed25519 recipients by a short tag: the
# unpadded base64 of the first 4 bytes of SHA-256 over the SSH wire-format
# public key (i.e. the decoded base64 field of the authorized_keys line).
recipient_tag() {
  local key_b64="$1"
  if [ "$tag_tool" = "openssl" ]; then
    printf '%s\n' "$key_b64" | openssl base64 -d 2>/dev/null |
      openssl dgst -sha256 -binary | head -c 4 | openssl base64 | tr -d '=\n' || true
  else
    printf '%s' "$key_b64" | base64 -d 2>/dev/null | sha256sum | cut -c1-8 |
      tr 'a-f' 'A-F' | basenc --base16 -d 2>/dev/null | basenc --base64 | tr -d '=' || true
  fi
}

file_recipient_tags() {
  sed -n '/^-----BEGIN AGE ENCRYPTED FILE-----$/,/^-----END AGE ENCRYPTED FILE-----$/p' "$1" |
    sed '1d;$d' | b64_decode 2>/dev/null | grep -a '^-> ssh-ed25519 ' | awk '{print $3}' || true
}

stale_secrets=()

# A kept secret that is not encrypted to the current recipient set would only
# fail much later, at activation time on the target host. Catch it here.
check_kept_secret() {
  local secret_path="$1"
  local rules_path="$2"
  local secret_name="$3"
  local tags key key_b64 tag missing=0

  if [ -z "$tag_tool" ]; then
    echo "WARNING: cannot verify recipients of existing ${secret_path#"$repo_root"/} (needs GNU sha256sum+basenc, or openssl)." >&2
    return 0
  fi

  tags="$(file_recipient_tags "$secret_path")"
  if [ -z "$tags" ]; then
    echo "WARNING: could not read recipients from existing ${secret_path#"$repo_root"/}; unable to verify it matches the current recipient list." >&2
    return 0
  fi

  while IFS= read -r key; do
    case "$key" in
      ssh-ed25519\ *) ;;
      *) continue ;;
    esac
    key_b64="$(printf '%s' "$key" | awk '{print $2}')"
    tag="$(recipient_tag "$key_b64")"
    [ -n "$tag" ] || continue
    if ! printf '%s\n' "$tags" | grep -qx -- "$tag"; then
      echo "ERROR: existing ${secret_path#"$repo_root"/} is NOT encrypted to current recipient: $key" >&2
      missing=1
    fi
  done <<<"$(list_recipients "$rules_path" "$secret_name")"

  if [ "$missing" = "1" ]; then
    stale_secrets+=("$secret_path")
  fi
}

# --- Prepare the plaintext content for every secret -------------------------
#
# Interactive mode uses these files to seed the editor buffer; non-interactive
# mode encrypts them as-is. Contents come from --values-dir when a matching
# file exists there, otherwise from templates/.

content_dir="$(mktemp -d)"
trap 'rm -rf "$content_dir"' EXIT

content_for() {
  local name="$1" template="$2"
  if [ -n "$values_dir" ] && [ -f "$values_dir/$name" ]; then
    cat "$values_dir/$name"
  else
    cat "$template"
  fi
}

# Registration token: taken from --values-dir when provided, otherwise
# generated. The same token is written into registration-token.age and
# lab-runtime.env so the two can never drift apart.
if [ -n "$values_dir" ] && [ -f "$values_dir/registration-token" ]; then
  registration_token="$(tr -d '[:space:]' <"$values_dir/registration-token")"
else
  registration_token="$(head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)"
fi
case "$registration_token" in
  *[!A-Za-z0-9._-]* | "")
    echo "Registration token must be non-empty and contain only [A-Za-z0-9._-]." >&2
    exit 1
    ;;
esac
printf '%s\n' "$registration_token" >"$content_dir/registration-token"

content_for agent-integrations.env "$repo_root/templates/agent-integrations.env.example" >"$content_dir/agent-integrations.env"
content_for agent-tooling.env "$repo_root/templates/agent-tooling.env.example" >"$content_dir/agent-tooling.env"
content_for agent-runtime.env "$repo_root/templates/agent-runtime.env.example" >"$content_dir/agent-runtime.env"
content_for lab-runtime.env "$repo_root/templates/lab-runtime.env.example" >"$content_dir/lab-runtime.env"
content_for chat-runtime.env "$repo_root/templates/chat-runtime.env.example" >"$content_dir/chat-runtime.env"

if grep -q '^MATRIX_REGISTRATION_TOKEN=$' "$content_dir/lab-runtime.env"; then
  # sed -i.bak (no space) works with both GNU and BSD sed.
  sed -i.bak "s|^MATRIX_REGISTRATION_TOKEN=\$|MATRIX_REGISTRATION_TOKEN=$registration_token|" "$content_dir/lab-runtime.env"
  rm -f "$content_dir/lab-runtime.env.bak"
elif ! grep -q "^MATRIX_REGISTRATION_TOKEN=$registration_token\$" "$content_dir/lab-runtime.env"; then
  echo "WARNING: MATRIX_REGISTRATION_TOKEN in lab-runtime.env differs from the" >&2
  echo "registration token; the lab runtime cannot register agents unless they match." >&2
fi

# --- Encrypt -----------------------------------------------------------------

edit_secret() {
  local secret_path="$1"
  local rules_path="$2"
  local content_path="$3"
  local wrapper values_name

  mkdir -p "$(dirname "$secret_path")"
  if [ -f "$secret_path" ] && grep -q '^PLACEHOLDER_RAGENIX_SECRET$' "$secret_path" 2>/dev/null; then
    rm -f "$secret_path"
  fi

  # Re-encrypting an existing secret would require the operator identity;
  # non-interactive runs keep whatever is already there instead — but verify
  # it is actually encrypted to the current recipients.
  if [ "$non_interactive" = "1" ] && [ -f "$secret_path" ]; then
    echo "Keeping existing secret: ${secret_path#"$repo_root"/}"
    values_name="$(basename "${secret_path%.age}")"
    if [ -n "$values_dir" ] && [ -f "$values_dir/$values_name" ]; then
      echo "NOTE: ignoring $values_dir/$values_name — the secret already exists." >&2
      echo "Delete ${secret_path#"$repo_root"/} and re-run to apply the new value." >&2
    fi
    check_kept_secret "$secret_path" "$rules_path" "$(basename "$secret_path")"
    return 0
  fi

  wrapper="$(mktemp)"
  trap 'rm -f "$wrapper"' RETURN

  cat >"$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="$1"

if [ ! -s "$target" ] && [ -n "${BOOTSTRAP_TEMPLATE:-}" ] && [ -f "$BOOTSTRAP_TEMPLATE" ]; then
  cat "$BOOTSTRAP_TEMPLATE" > "$target"
fi

exec "${BOOTSTRAP_REAL_EDITOR:-vi}" "$target"
EOF
  chmod +x "$wrapper"

  BOOTSTRAP_TEMPLATE="$content_path" \
    BOOTSTRAP_REAL_EDITOR="$real_editor" \
    ragenix --editor "$wrapper" --rules "$rules_path" --edit "$secret_path"

  trap - RETURN
  rm -f "$wrapper"
}

echo "Repo root: $repo_root"
echo "Target host: $host"
echo
echo "Add the host SSH public key to the recipient lists before editing secrets."
echo "Example command from the Incus host:"
echo "  incus exec mindroom -- /run/current-system/sw/bin/cat /etc/ssh/ssh_host_ed25519_key.pub"
echo

ensure_recipients "$shared_rules" "agent-integrations.env.age"
ensure_recipients "$shared_rules" "agent-tooling.env.age"
ensure_recipients "$host_rules" "agent-runtime.env.age"
ensure_recipients "$host_rules" "lab-runtime.env.age"
ensure_recipients "$host_rules" "registration-token.age"
if [ "$with_chat" = "1" ]; then
  ensure_recipients "$host_rules" "chat-runtime.env.age"
fi

edit_secret \
  "$repo_root/secrets/shared/agent-integrations.env.age" \
  "$shared_rules" \
  "$content_dir/agent-integrations.env"

edit_secret \
  "$repo_root/secrets/shared/agent-tooling.env.age" \
  "$shared_rules" \
  "$content_dir/agent-tooling.env"

edit_secret \
  "$host_dir/secrets/agent-runtime.env.age" \
  "$host_rules" \
  "$content_dir/agent-runtime.env"

edit_secret \
  "$host_dir/secrets/lab-runtime.env.age" \
  "$host_rules" \
  "$content_dir/lab-runtime.env"

edit_secret \
  "$host_dir/secrets/registration-token.age" \
  "$host_rules" \
  "$content_dir/registration-token"

if [ "$with_chat" = "1" ]; then
  edit_secret \
    "$host_dir/secrets/chat-runtime.env.age" \
    "$host_rules" \
    "$content_dir/chat-runtime.env"
else
  echo
  echo "Skipped chat-runtime.env.age (hosted runtime is disabled by default)."
  echo "Re-run with --with-chat if you enable mindroom.runtime.chat.enable."
fi

if [ "${#stale_secrets[@]}" -gt 0 ]; then
  echo >&2
  echo "FAILURE: the following existing secrets are not encrypted to the current" >&2
  echo "recipient set, so the target host would fail to decrypt them at activation:" >&2
  for s in "${stale_secrets[@]}"; do
    echo "  - ${s#"$repo_root"/}" >&2
  done
  echo "Fix by either deleting the listed files and re-running this script, or" >&2
  echo "re-encrypting them to the current recipients (needs an operator identity" >&2
  echo "that can decrypt them):" >&2
  echo "  ragenix --rules <secrets.nix> --rekey --identity /path/to/key" >&2
  exit 1
fi

echo
echo "Secrets bootstrapped for host '$host'."
echo "The Tuwunel registration token was written to registration-token.age and"
echo "synced into lab-runtime.env.age; there is nothing to keep aligned by hand."
if [ -n "$values_dir" ]; then
  echo "Reminder: $values_dir contains plaintext secrets; delete it when done."
fi
