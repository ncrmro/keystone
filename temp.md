After ssh'ing in and manually rebooting, secure boot is enabled, but it looks like the VM doesn't want to boot (saying failed to load Boot00002 "UDEFI Misc Device").

I'm guessing we need lanzeboot to be enableded and to have signed the keys at this point.

This means we need to somehow be able to say to the nixos-anywhere to use the nix flake host without lanzeboot enabled and then after
we generate and enroll the keys lanzeboot works.

We document the above only as a fllback though because the following is the ideal situation that we should try first.


Ideally we would generate and enroll the keys as a disko post hook, in this way the keys are generated before nixos-anywhere installs, lanzeboote can be enabled from
the start and can enroll it's keys from the get go. Then on next reboot we can proceed to enroll the TPM keys automatically (out of scope for now thought so just document this)  
