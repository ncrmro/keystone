# Implementation Tasks: ZFS User Module

**Feature**: 007-zfs-user-module
**Branch**: `007-zfs-user-module`
**Total Tasks**: 19
**Parallelizable**: 10 tasks
**Validation**: All tasks validated by `bin/test-deployment` script

---

## Task Format

All tasks follow this format:
```
- [X] [T###] [P?] Description with file path
```

- **T###**: Sequential task ID
- **[P]**: Parallelizable (can run independently)
- File paths are absolute or relative to repository root

---

## Phase 1: Setup & Module Scaffolding

**Goal**: Create module structure and establish foundation for ZFS user management

### Tasks

- [X] T001 Create module directory at modules/users/
- [X] T002 [P] Add users module export to flake.nix in nixosModules section
- [X] T003 [P] Create test user configuration in vms/test-server/configuration.nix with testuser in keystone.users
- [X] T004 Implement module skeleton in modules/users/default.nix with imports, options, and config sections
- [X] T005 [P] Add module options schema for keystone.users.<name> submodule with uid, description, extraGroups
- [X] T006 [P] Add zfsProperties submodule (quota, compression, recordsize, atime) to keystone.users.<name>

**Completion Criteria**: Module structure exists, options defined, exported in flake

---

## Phase 2: Core Implementation - User Management

**Goal**: Implement complete user dataset provisioning with ZFS delegation

### Module Options

- [X] T007 [P] Add password options (initialPassword, hashedPassword) to keystone.users.<name> submodule in modules/users/default.nix

### Assertions & Validation

- [X] T008 Add assertion for ZFS filesystem support in boot.supportedFilesystems in modules/users/default.nix
- [X] T009 [P] Add assertion for UID uniqueness across all configured users in modules/users/default.nix

### User Integration

- [X] T010 Implement users.users generation from keystone.users with createHome=false in modules/users/default.nix

### Systemd Service

- [X] T011 Implement systemd.services.zfs-user-datasets service with proper ordering (after zfs-mount.service, before display-manager.service) in modules/users/default.nix
- [X] T012 Add pool and parent dataset validation checks in systemd service script in modules/users/default.nix
- [X] T013 Implement idempotent dataset creation loop using zfs create -p in systemd service script in modules/users/default.nix
- [X] T014 Add ZFS property setting (compression, quota, recordsize, atime) using zfs set in systemd service script in modules/users/default.nix
- [X] T015 Implement ZFS delegation permissions (create, snapshot, send, receive, etc.) using zfs allow in systemd service script in modules/users/default.nix
- [X] T016 Add descendants-only destroy permission using zfs allow -d in systemd service script in modules/users/default.nix

**Completion Criteria**: Users created with ZFS datasets, permissions delegated, service runs at boot

---

## Phase 3: Test Integration & Validation

**Goal**: Add comprehensive ZFS user verification to bin/test-deployment script

### Test Function Implementation

- [X] T017 Implement verify_zfs_user_permissions() function in bin/test-deployment with all 8 verification checks from spec
- [X] T018 Add ZFS user verification step to main() workflow in bin/test-deployment after verify_deployment() step
- [X] T019 Update total_steps counter and test configuration to include testuser with ZFS properties in vms/test-server/configuration.nix

**Verification Checks** (implemented in T017):
1. Dataset exists at rpool/crypt/home/testuser
2. Dataset is mounted at /home/testuser
3. User can create child datasets (zfs create)
4. User can create snapshots (zfs snapshot)
5. User can list their dataset (zfs list)
6. User can send snapshots (zfs send)
7. User can delete child datasets and snapshots (zfs destroy)
8. User CANNOT destroy parent dataset (security check)

**Completion Criteria**: All functional requirements validated by bin/test-deployment

---

## Dependencies & Execution Order

### Sequential Dependencies

```
Phase 1 (Setup)
  ↓
Phase 2 (Core Implementation)
  T005-T007 (Options) → T008-T009 (Assertions) → T010 (User Integration)
  T011 (Service Creation) → T012-T016 (Service Implementation)
  ↓
Phase 3 (Test Integration)
  T017 (Test Function) → T018-T019 (Integration)
```

### Parallel Opportunities

**Within Phase 1**:
- T002, T003, T005, T006 can run in parallel after T001

**Within Phase 2**:
- T005, T006, T007 (options) can run in parallel
- T009 (assertions) can run in parallel after T008
- T012-T016 must run sequentially (build on each other)

---

## Implementation Strategy

### MVP Scope (Phases 1-2)

Delivers core functionality:
- Module structure and options
- User creation with ZFS datasets
- Delegation permissions
- systemd service automation

**Estimated**: 16 tasks

### Full Feature (All Phases)

Adds automated testing:
- Integration with bin/test-deployment
- Comprehensive permission verification
- Security isolation testing

**Estimated**: 19 tasks (all)

---

## Testing Notes

**Manual Testing** (during development):
```bash
# Build module
nix build .#nixosConfigurations.test-server.config.system.build.toplevel

# Check service configuration
nix eval .#nixosConfigurations.test-server.config.systemd.services.zfs-user-datasets.script

# Deploy to test VM
./bin/test-deployment
```

**Automated Testing** (after Phase 3):
```bash
# Full deployment test with ZFS verification
./bin/test-deployment

# Expected output:
# [11/11] Verifying ZFS user permissions
#   ✓ Dataset exists: rpool/crypt/home/testuser
#   ✓ Dataset mounted at /home/testuser
#   ✓ User can create child dataset
#   ✓ User can create snapshot
#   ✓ User can list dataset
#   ✓ User can send snapshot
#   ✓ User can destroy snapshot
#   ✓ User can destroy child dataset
#   ✓ User cannot destroy parent dataset (security check)
```

---

## File Paths Reference

**Implementation Files**:
- `modules/users/default.nix` - Main module (T001-T019)
- `flake.nix` - Module exports (T002)
- `vms/test-server/configuration.nix` - Test config (T003, T022)
- `bin/test-deployment` - Test integration (T020-T021)

**Documentation Files** (already complete):
- `specs/007-zfs-user-module/spec.md` - Feature specification
- `specs/007-zfs-user-module/plan.md` - Implementation plan
- `specs/007-zfs-user-module/research.md` - Technical research
- `specs/007-zfs-user-module/data-model.md` - Module options schema
- `specs/007-zfs-user-module/quickstart.md` - Usage guide

---

## Key Technical Decisions

From research.md, implemented in tasks:

1. **Systemd Service** (T014): NOT activation scripts - proper ordering and error handling
2. **Idempotent Operations** (T016): Use `zfs create -p` for native idempotency
3. **Property Updates** (T017): Always run `zfs set` - safe and idempotent
4. **Permissions** (T018-T019): Full delegation with descendants-only destroy for security
5. **Testing** (T020-T022): Comprehensive integration tests in bin/test-deployment

---

## Success Criteria

**Module Complete When**:
- ✅ All 19 tasks completed
- ✅ `nix build` succeeds
- ✅ `bin/test-deployment` passes all checks
- ✅ Users can manage their ZFS datasets
- ✅ Security isolation verified (cannot access other users' datasets)
- ✅ Documentation updated

**User Can**:
- Create child datasets within home directory
- Create and manage snapshots
- Send/receive snapshots for backup
- Set dataset properties (compression, quota)
- Monitor disk usage with `zfs list`

**Security Verified**:
- Users cannot destroy their parent home dataset
- Users cannot access other users' datasets
- All operations use ZFS delegation (no sudo required)

---

## Notes

- All ZFS operations use full paths (${pkgs.zfs}/bin/zfs) for reliability
- Service uses `set -euo pipefail` for proper error handling
- Properties set with `-o` flag during creation, then updated with `zfs set`
- Delegation uses two commands: standard permissions + descendants-only destroy
- Test user has 10G quota and lz4 compression for quick testing

---

## Next Steps

After completing all tasks:

1. Run `./bin/test-deployment` to validate full implementation
2. Test manual user workflows from quickstart.md
3. Document any issues or edge cases discovered
4. Consider future enhancements (permission sets, quota monitoring)

---

**Generated**: 2025-11-04
**Based on**: spec.md, plan.md, research.md, data-model.md
**Validated by**: bin/test-deployment script
