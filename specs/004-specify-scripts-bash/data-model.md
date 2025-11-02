# Data Model: Secure Boot Key Management

**Feature**: Secure Boot Custom Key Enrollment
**Date**: 2025-11-01

## Overview

This document defines the key entities and their relationships for Secure Boot custom key management in Keystone. Unlike traditional data models with database schemas, this feature deals with cryptographic key files and UEFI firmware variables.

## Entities

### 1. SecureBootKeyPair

Represents a cryptographic key pair used in the UEFI Secure Boot trust chain.

**Attributes**:
- **Type** (enum): `PK` (Platform Key), `KEK` (Key Exchange Key), or `db` (Signature Database)
- **PrivateKeyPath** (filesystem path): Location of private key file (e.g., `/var/lib/sbctl/keys/PK/PK.key`)
- **PublicKeyPath** (filesystem path): Location of public certificate (e.g., `/var/lib/sbctl/keys/PK/PK.pem`)
- **AuthFilePath** (filesystem path): Location of authenticated update file (e.g., `/var/lib/sbctl/keys/PK/PK.auth`)
- **ESLFilePath** (filesystem path): Location of EFI Signature List file (e.g., `/var/lib/sbctl/keys/PK/PK.esl`)
- **OwnerGUID** (UUID): Unique identifier for the key owner (e.g., `8ec4b2c3-dc7f-4362-b9a3-0cc17e5a34cd`)
- **Algorithm** (string): Cryptographic algorithm (default: `RSA4096`)
- **CreatedAt** (timestamp): When the key was generated
- **Permissions** (octal): File permissions (private key: `600`, public: `644`)

**Validation Rules**:
- Private key file MUST have permissions `600` (root-only read/write)
- Public key file MUST be readable by all users (`644`)
- Owner GUID MUST be a valid RFC 4122 UUID
- Type MUST be one of: `PK`, `KEK`, `db`

**State Transitions**:
```
[Not Exist] --generate--> [Generated] --enroll--> [Enrolled in Firmware]
                            |
                            +--verify--> [Verified Present in Files]
```

**Example Instance**:
```json
{
  "type": "PK",
  "privateKeyPath": "/var/lib/sbctl/keys/PK/PK.key",
  "publicKeyPath": "/var/lib/sbctl/keys/PK/PK.pem",
  "authFilePath": "/var/lib/sbctl/keys/PK/PK.auth",
  "eslFilePath": "/var/lib/sbctl/keys/PK/PK.esl",
  "ownerGUID": "8ec4b2c3-dc7f-4362-b9a3-0cc17e5a34cd",
  "algorithm": "RSA4096",
  "createdAt": "2025-11-01T10:30:00Z",
  "permissions": "600"
}
```

---

### 2. FirmwareVariable

Represents a UEFI firmware variable that stores Secure Boot state or enrolled keys.

**Attributes**:
- **Name** (string): Variable name (e.g., `SetupMode`, `SecureBoot`, `PK`, `KEK`, `db`, `dbx`)
- **GUID** (UUID): Variable namespace (typically `8be4df61-93ca-11d2-aa0d-00e098032b8c` for EFI_GLOBAL_VARIABLE)
- **FilePath** (filesystem path): Path to variable in efivars (e.g., `/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c`)
- **Value** (bytes): Current variable value
- **Attributes** (bitfield): Variable attributes (NON_VOLATILE, BOOTSERVICE_ACCESS, RUNTIME_ACCESS)
- **ReadOnly** (boolean): Whether variable can be modified (depends on firmware state)

**Validation Rules**:
- GUID MUST be valid RFC 4122 UUID
- FilePath MUST exist in `/sys/firmware/efi/efivars/`
- Value format depends on variable type (integer for SetupMode/SecureBoot, signature list for PK/KEK/db)

**State-Critical Variables**:
1. **SetupMode**: `1` = Setup Mode (keys can be enrolled), `0` = User Mode (keys enrolled)
2. **SecureBoot**: `1` = Enforcing signatures, `0` = Not enforcing
3. **PK**: Contains enrolled Platform Key (empty in Setup Mode)
4. **KEK**: Contains enrolled Key Exchange Keys
5. **db**: Contains enrolled Signature Database
6. **dbx**: Contains forbidden signatures (revocation list)

**State Diagram**:
```
[Setup Mode: SetupMode=1, SecureBoot=0]
    |
    | (enroll PK)
    v
[User Mode: SetupMode=0, SecureBoot=1]
```

**Example Instance**:
```json
{
  "name": "SetupMode",
  "guid": "8be4df61-93ca-11d2-aa0d-00e098032b8c",
  "filePath": "/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c",
  "value": [7, 0, 0, 0, 1],
  "attributes": "NON_VOLATILE | BOOTSERVICE_ACCESS | RUNTIME_ACCESS",
  "readOnly": false
}
```

---

### 3. SecureBootStatus

Aggregates firmware state to represent overall Secure Boot status.

**Attributes**:
- **Mode** (enum): `Setup`, `User`, `Disabled`, `Unknown`
- **Enforcing** (boolean): Whether signature verification is active
- **FirmwareType** (string): UEFI firmware implementation (e.g., `EDK II 1.00`)
- **FirmwareVersion** (string): Version string (e.g., `2.70`)
- **PKEnrolled** (boolean): Platform Key is enrolled
- **KEKEnrolled** (boolean): Key Exchange Keys are enrolled
- **dbEnrolled** (boolean): Signature Database is enrolled
- **TPMAvailable** (boolean): TPM 2.0 support detected
- **VerifiedAt** (timestamp): When status was checked

**Derivation Logic**:
```
if SetupMode == 1 and SecureBoot == 0:
    Mode = Setup, Enforcing = false
elif SetupMode == 0 and SecureBoot == 1:
    Mode = User, Enforcing = true
elif SetupMode == 0 and SecureBoot == 0:
    Mode = Disabled, Enforcing = false
else:
    Mode = Unknown, Enforcing = unknown
```

**Validation Rules**:
- Mode MUST be one of: `Setup`, `User`, `Disabled`, `Unknown`
- If Mode == `User`, then PKEnrolled, KEKEnrolled, dbEnrolled MUST be true
- If Mode == `Setup`, then PKEnrolled SHOULD be false

**Example Instance** (Setup Mode):
```json
{
  "mode": "Setup",
  "enforcing": false,
  "firmwareType": "EDK II 1.00",
  "firmwareVersion": "2.70",
  "pkEnrolled": false,
  "kekEnrolled": false,
  "dbEnrolled": false,
  "tpmAvailable": true,
  "verifiedAt": "2025-11-01T10:25:00Z"
}
```

**Example Instance** (User Mode):
```json
{
  "mode": "User",
  "enforcing": true,
  "firmwareType": "EDK II 1.00",
  "firmwareVersion": "2.70",
  "pkEnrolled": true,
  "kekEnrolled": true,
  "dbEnrolled": true,
  "tpmAvailable": true,
  "verifiedAt": "2025-11-01T10:35:00Z"
}
```

---

### 4. KeyEnrollmentOperation

Represents a single key enrollment operation (transaction).

**Attributes**:
- **OperationID** (UUID): Unique identifier for this enrollment operation
- **KeysToEnroll** (array of SecureBootKeyPair): PK, KEK, db keys being enrolled
- **IncludeMicrosoft** (boolean): Whether to include Microsoft OEM certificates
- **PreEnrollmentStatus** (SecureBootStatus): Firmware state before enrollment
- **PostEnrollmentStatus** (SecureBootStatus): Firmware state after enrollment
- **Success** (boolean): Whether enrollment succeeded
- **ErrorMessage** (string): Error description if failed
- **StartedAt** (timestamp): When operation began
- **CompletedAt** (timestamp): When operation finished
- **DurationSeconds** (integer): Time taken for enrollment

**Validation Rules**:
- PreEnrollmentStatus.Mode MUST be `Setup` (cannot enroll in User Mode)
- If Success == true, then PostEnrollmentStatus.Mode MUST be `User`
- If Success == true, then PostEnrollmentStatus.PKEnrolled MUST be true
- DurationSeconds MUST be <= 60 (per SC-002 success criteria)

**State Transitions**:
```
[Initiated] --> [Validating Setup Mode] --> [Enrolling Keys] --> [Verifying] --> [Complete]
                         |                        |                    |
                         +--[Failed]              +--[Failed]          +--[Failed]
```

**Example Instance** (Success):
```json
{
  "operationID": "f3a5b8c2-1234-5678-9abc-def012345678",
  "keysToEnroll": [
    {"type": "PK", "ownerGUID": "8ec4b2c3-dc7f-4362-b9a3-0cc17e5a34cd"},
    {"type": "KEK", "ownerGUID": "8ec4b2c3-dc7f-4362-b9a3-0cc17e5a34cd"},
    {"type": "db", "ownerGUID": "8ec4b2c3-dc7f-4362-b9a3-0cc17e5a34cd"}
  ],
  "includeMicrosoft": false,
  "preEnrollmentStatus": {"mode": "Setup", "enforcing": false},
  "postEnrollmentStatus": {"mode": "User", "enforcing": true},
  "success": true,
  "errorMessage": null,
  "startedAt": "2025-11-01T10:30:00Z",
  "completedAt": "2025-11-01T10:30:08Z",
  "durationSeconds": 8
}
```

**Example Instance** (Failure):
```json
{
  "operationID": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
  "keysToEnroll": [...],
  "includeMicrosoft": false,
  "preEnrollmentStatus": {"mode": "User", "enforcing": true},
  "postEnrollmentStatus": null,
  "success": false,
  "errorMessage": "Firmware not in Setup Mode - cannot enroll keys",
  "startedAt": "2025-11-01T11:00:00Z",
  "completedAt": "2025-11-01T11:00:01Z",
  "durationSeconds": 1
}
```

---

## Relationships

```
SecureBootKeyPair (3 instances: PK, KEK, db)
        |
        | enrolled via
        v
KeyEnrollmentOperation
        |
        | updates
        v
FirmwareVariable (SetupMode, SecureBoot, PK, KEK, db)
        |
        | aggregated into
        v
SecureBootStatus
```

**Cardinality**:
- One KeyEnrollmentOperation enrolls exactly 3 SecureBootKeyPairs (PK, KEK, db)
- One KeyEnrollmentOperation updates multiple FirmwareVariables (SetupMode, PK, KEK, db)
- One SecureBootStatus aggregates 2+ FirmwareVariables (SetupMode, SecureBoot, at minimum)

---

## File System Storage Model

```
/var/lib/sbctl/                          # Key storage root
├── GUID                                 # Owner UUID file
├── keys/
│   ├── PK/                             # Platform Key directory
│   │   ├── PK.key      (600)          # Private key (root-only)
│   │   ├── PK.pem      (644)          # Public certificate
│   │   ├── PK.auth     (644)          # Authenticated update
│   │   └── PK.esl      (644)          # EFI Signature List
│   ├── KEK/                            # Key Exchange Key directory
│   │   ├── KEK.key     (600)
│   │   ├── KEK.pem     (644)
│   │   ├── KEK.auth    (644)
│   │   └── KEK.esl     (644)
│   └── db/                             # Signature Database directory
│       ├── db.key      (600)
│       ├── db.pem      (644)
│       ├── db.auth     (644)
│       └── db.esl      (644)
└── files.db                            # Signed files tracking (JSON)

/sys/firmware/efi/efivars/              # UEFI variables (kernel interface)
├── SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
├── SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
├── PK-8be4df61-93ca-11d2-aa0d-00e098032b8c
├── KEK-8be4df61-93ca-11d2-aa0d-00e098032b8c
├── db-8be4df61-93ca-11d2-aa0d-00e098032b8c
└── dbx-8be4df61-93ca-11d2-aa0d-00e098032b8c
```

---

## Data Flow

### Key Generation Flow

```
[User Request]
    --> Generate Owner GUID
    --> Create RSA4096 key pairs (PK, KEK, db)
    --> Convert to multiple formats (.key, .pem, .auth, .esl)
    --> Set file permissions (600 for .key, 644 for others)
    --> Write to /var/lib/sbctl/keys/
    --> Return SecureBootKeyPair instances
```

### Enrollment Flow

```
[KeyEnrollmentOperation Initiated]
    --> Read FirmwareVariable(SetupMode)
    --> Validate SetupMode == 1
    --> Load SecureBootKeyPair(PK).authFilePath
    --> Write to FirmwareVariable(PK)
    --> Load SecureBootKeyPair(KEK).authFilePath
    --> Write to FirmwareVariable(KEK)
    --> Load SecureBootKeyPair(db).authFilePath
    --> Write to FirmwareVariable(db)
    --> FirmwareVariable(SetupMode) automatically changes to 0
    --> FirmwareVariable(SecureBoot) automatically changes to 1
    --> Return updated SecureBootStatus
```

### Verification Flow

```
[Verification Request]
    --> Read FirmwareVariable(SetupMode)
    --> Read FirmwareVariable(SecureBoot)
    --> Read FirmwareVariable(PK) [check if populated]
    --> Read FirmwareVariable(KEK) [check if populated]
    --> Read FirmwareVariable(db) [check if populated]
    --> Aggregate into SecureBootStatus
    --> Return status with mode and enforcement state
```

---

## Success Criteria Mapping

This data model supports the following success criteria:

- **SC-001** (Key generation <30s): SecureBootKeyPair.createdAt timestamp tracking
- **SC-002** (Enrollment <60s): KeyEnrollmentOperation.durationSeconds tracking
- **SC-003** (100% verification accuracy): SecureBootStatus derived from authoritative FirmwareVariables
- **SC-004** (Test integration): SecureBootStatus can be queried programmatically
- **SC-005** (Clear error messages): KeyEnrollmentOperation.errorMessage provides context

---

## Implementation Notes

1. **No Traditional Database**: Entities are not stored in SQL/NoSQL - they represent filesystem state and UEFI firmware state
2. **Stateless Operations**: Scripts read current state, perform operations, verify new state
3. **Idempotency**: Verification scripts can be run multiple times without side effects
4. **Atomic Enrollment**: Firmware handles atomicity - PK enrollment triggers Setup Mode → User Mode transition
5. **Error Detection**: Missing key files, wrong permissions, or incorrect firmware state can be detected via validation rules

---

**Data Model Status**: ✅ Complete - Ready for contract generation
