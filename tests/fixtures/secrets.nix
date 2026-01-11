# Agenix secrets configuration for cluster-primer testing
#
# WARNING: This configuration uses a TEST-ONLY age key.
# The private key (test-age-key.txt) is committed to the repo for CI/testing.
# DO NOT use this pattern for production secrets!
#
let
  # Test VM age public key (from test-age-key.txt)
  # This key is only for testing - the private key is committed to the repo
  testVM = "age1u3f3r3h7m4rrl5dw97ee65fde38tfq0xk9ljdh5strf3z6a0js7q9g8hkj";
in
{
  "headscale-private.age".publicKeys = [ testVM ];
  "headscale-noise.age".publicKeys = [ testVM ];
  "headscale-derp.age".publicKeys = [ testVM ];
}
