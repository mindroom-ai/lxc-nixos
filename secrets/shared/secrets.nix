let
  operatorRecipients = [
    # Add the operator key(s) that should be able to edit shared secrets.
    # Example:
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... you@example"
  ];

  hostRecipients = [
    # Add each host SSH public key that should be able to decrypt the shared
    # secrets at activation time.
    # Example:
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... root@mindroom"
  ];

  recipients = operatorRecipients ++ hostRecipients;
in
{
  "agent-integrations.env.age".publicKeys = recipients;
  "agent-tooling.env.age".publicKeys = recipients;
}
