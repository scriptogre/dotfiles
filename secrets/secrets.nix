let
  # ThinkCenter host key
  thinkcentre = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKkvTm9lsulSpgGRme+nYWQPhyIHxawpGjFAPUZ9x2W3";

  # Personal key (home_network_key_2) — allows editing secrets from your Mac
  chris = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINLGEYgN5pbs2u1eMfTnpKUqHCm8fPuC/vSeV4Ht0KyL";
in {
  "op-service-account-token.age".publicKeys = [ thinkcentre chris ];
}
