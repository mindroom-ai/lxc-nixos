#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="${1:-mindroom}"
real_editor="${EDITOR:-vi}"

required_commands=(nix ragenix)
for cmd in "${required_commands[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

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

edit_secret() {
  local secret_path="$1"
  local rules_path="$2"
  local template_path="$3"
  local wrapper

  mkdir -p "$(dirname "$secret_path")"
  if [ -f "$secret_path" ] && grep -q '^PLACEHOLDER_RAGENIX_SECRET$' "$secret_path" 2>/dev/null; then
    rm -f "$secret_path"
  fi
  wrapper="$(mktemp)"
  trap 'rm -f "$wrapper"' RETURN

  cat > "$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="$1"

if [ ! -s "$target" ] && [ -n "${BOOTSTRAP_TEMPLATE:-}" ] && [ -f "$BOOTSTRAP_TEMPLATE" ]; then
  cat "$BOOTSTRAP_TEMPLATE" > "$target"
fi

exec "${BOOTSTRAP_REAL_EDITOR:-vi}" "$target"
EOF
  chmod +x "$wrapper"

  BOOTSTRAP_TEMPLATE="$template_path" \
    BOOTSTRAP_REAL_EDITOR="$real_editor" \
    ragenix --editor "$wrapper" --rules "$rules_path" --edit "$secret_path"

  trap - RETURN
  rm -f "$wrapper"
}

echo "Repo root: $repo_root"
echo "Target host: $host"
echo
echo "Add the host SSH public key to the recipient lists before editing secrets."
echo "Example command on the target container:"
echo "  sudo cat /etc/ssh/ssh_host_ed25519_key.pub"
echo

ensure_recipients "$shared_rules" "agent-integrations.env.age"
ensure_recipients "$shared_rules" "agent-tooling.env.age"
ensure_recipients "$host_rules" "agent-runtime.env.age"
ensure_recipients "$host_rules" "registration-token.age"

edit_secret \
  "$repo_root/secrets/shared/agent-integrations.env.age" \
  "$shared_rules" \
  "$repo_root/templates/agent-integrations.env.example"

edit_secret \
  "$repo_root/secrets/shared/agent-tooling.env.age" \
  "$shared_rules" \
  "$repo_root/templates/agent-tooling.env.example"

edit_secret \
  "$host_dir/secrets/agent-runtime.env.age" \
  "$host_rules" \
  "$repo_root/templates/agent-runtime.env.example"

edit_secret \
  "$host_dir/secrets/registration-token.age" \
  "$host_rules" \
  "$repo_root/templates/registration-token.example"

echo
echo "Secrets bootstrapped for host '$host'."
