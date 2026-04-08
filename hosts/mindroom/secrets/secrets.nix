let
  operatorRecipients = [
    # Add the operator key(s) that should be able to edit host-local secrets.
    # Example:
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... you@example"
  ];

  hostRecipients = [
    # Add the target host SSH public key.
    # Example:
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... root@mindroom"
  ];

  recipients = operatorRecipients ++ hostRecipients;
in
{
  "agent-runtime.env.age".publicKeys = recipients;
  "lab-runtime.env.age".publicKeys = recipients;
  "chat-runtime.env.age".publicKeys = recipients;
  "registration-token.age".publicKeys = recipients;
}
