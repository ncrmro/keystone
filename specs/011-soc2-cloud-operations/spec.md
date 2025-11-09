# Feature Specification: SOC2-Compliant Bare-Metal Operations

**Feature Branch**: `011-soc2-cloud-operations`
**Created**: 2025-11-09
**Status**: Draft
**Input**: User requirement: "Outline a spec for operating 100% bare-metal or hybrid in a SOC2 manner using keystone"

## Executive Summary

This specification defines how to operate 100% bare-metal or hybrid (bare-metal + cloud) infrastructure in a SOC2 Type 2 compliant manner using the Keystone platform. It establishes architectural patterns, operational procedures, physical and logical security controls, and audit requirements necessary to achieve and maintain SOC2 certification for organizations using Keystone on self-owned or colocation hardware.

Keystone provides a strong foundation for SOC2 compliance through its security-first architecture (TPM2, LUKS encryption, Secure Boot, ZFS encryption), declarative configuration, and infrastructure-as-code approach. This specification maps Keystone's existing capabilities to SOC2 Trust Services Criteria and defines additional operational controls—particularly physical security controls—needed for full compliance with bare-metal deployments.

**Key Bare-Metal Considerations**: Unlike cloud-only deployments, bare-metal operations require physical security controls, hardware lifecycle management, physical asset tracking, data center or colocation facility management, and environmental controls. This specification addresses these requirements comprehensively.

## User Scenarios & Testing

### User Story 1 - Security Controls Implementation (Priority: P0)

As a security officer, I need to deploy Keystone infrastructure with all mandatory security controls enabled and verifiable, so that our organization can meet SOC2 security requirements.

**Why this priority**: Security is the only mandatory criterion for SOC2 compliance. Without proper security controls, certification is impossible.

**Independent Test**: Deploy a Keystone server and client configuration with full security stack. Verify TPM2 enrollment, LUKS encryption, Secure Boot, and audit logging are active and properly configured.

**Acceptance Scenarios**:

1. **Given** a Keystone deployment configuration, **When** deployed to hardware or cloud VM, **Then** it MUST enable full disk encryption with TPM2-backed key management.
2. **Given** a deployed system, **When** security controls are audited, **Then** all COSO framework requirements (access controls, encryption at rest/transit, audit logging) MUST be verifiable and operational.
3. **Given** a security event, **When** logged to the audit system, **Then** it MUST be immutable, timestamped, and retained per the defined policy.

---

### User Story 2 - Availability and Business Continuity (Priority: P1)

As an operations manager, I need automated failover, backup, and disaster recovery capabilities so that our services meet SOC2 availability requirements.

**Why this priority**: Most cloud services require availability guarantees as part of their SOC2 attestation scope.

**Independent Test**: Simulate server failure in hybrid deployment. Verify automatic failover to backup server, service restoration within defined RTO, and data recovery from ZFS snapshots.

**Acceptance Scenarios**:

1. **Given** a primary server failure, **When** the failure is detected, **Then** traffic MUST automatically failover to secondary infrastructure within the defined RTO (Recovery Time Objective).
2. **Given** a data loss event, **When** recovery is initiated, **Then** the system MUST restore to the last valid ZFS snapshot within the defined RPO (Recovery Point Objective).
3. **Given** a disaster scenario, **When** using the disaster recovery runbook, **Then** full system restoration MUST be achievable from configuration repository and encrypted backups.

---

### User Story 3 - Audit Trail and Compliance Reporting (Priority: P1)

As a compliance auditor, I need comprehensive, tamper-evident audit logs and configuration change tracking so that I can verify control effectiveness over time (Type 2 requirement).

**Why this priority**: SOC2 Type 2 requires demonstration of control effectiveness over a 3-12 month period.

**Independent Test**: Generate audit reports covering a test period. Verify all security events, configuration changes, access attempts, and system modifications are logged with timestamps, user attribution, and cryptographic verification.

**Acceptance Scenarios**:

1. **Given** a SOC2 audit period, **When** audit logs are requested, **Then** the system MUST provide complete, tamper-evident logs covering all control areas.
2. **Given** infrastructure configuration changes, **When** querying the Git repository, **Then** all changes MUST have timestamps, author attribution, and peer review evidence.
3. **Given** an access control event, **When** reviewing logs, **Then** it MUST show who accessed what resource, when, and what actions were performed.

---

### User Story 4 - Confidentiality Controls (Priority: P2)

As a data protection officer, I need to ensure sensitive customer data is encrypted at rest and in transit with proper access controls, so that our organization meets SOC2 confidentiality requirements.

**Why this priority**: Organizations handling sensitive customer data must implement confidentiality controls for SOC2.

**Independent Test**: Deploy a Keystone infrastructure handling confidential data. Verify encryption at rest (ZFS native encryption), encryption in transit (WireGuard VPN, TLS), and access controls limiting data access to authorized users only.

**Acceptance Scenarios**:

1. **Given** confidential data stored on Keystone infrastructure, **When** data is written to disk, **Then** it MUST be encrypted using ZFS native encryption with TPM2-protected keys.
2. **Given** data in transit between Keystone nodes, **When** network traffic is inspected, **Then** it MUST use encrypted channels (WireGuard, TLS) with strong cryptographic algorithms.
3. **Given** a user requesting access to confidential data, **When** access control is evaluated, **Then** access MUST be granted only if user has explicit authorization.

---

### User Story 5 - Processing Integrity (Priority: P2)

As a system architect, I need to ensure data processing is accurate, complete, and timely with verification mechanisms so that our organization meets SOC2 processing integrity requirements.

**Why this priority**: Organizations processing customer data or providing data processing services require processing integrity controls.

**Independent Test**: Process data through Keystone infrastructure with checksums and validation. Verify data integrity is maintained, processing is logged, and errors are detected and reported.

**Acceptance Scenarios**:

1. **Given** data being processed, **When** processing completes, **Then** the system MUST verify data integrity using checksums or cryptographic hashes.
2. **Given** a processing error, **When** detected, **Then** the system MUST log the error, alert operators, and prevent corrupt data from propagating.
3. **Given** processing operations, **When** audited, **Then** complete audit trail MUST show what data was processed, when, by what system, and verification of completeness.

---

### User Story 6 - Privacy Controls (Priority: P3)

As a privacy officer, I need controls for collecting, processing, storing, and disposing of PII in compliance with privacy regulations and SOC2 privacy criteria.

**Why this priority**: Organizations handling PII may need to include privacy criteria in their SOC2 scope.

**Independent Test**: Store PII on Keystone infrastructure. Verify consent tracking, data minimization, encryption, retention policies, and secure disposal mechanisms are operational.

**Acceptance Scenarios**:

1. **Given** PII collection, **When** data is stored, **Then** the system MUST record consent, purpose, and retention period.
2. **Given** PII retention period expiration, **When** disposal is triggered, **Then** the system MUST securely delete data using cryptographic erasure (ZFS dataset destruction with key deletion).
3. **Given** PII access request, **When** querying access logs, **Then** all PII access MUST be logged with user identity, timestamp, and purpose.

### Edge Cases

- **Physical hardware failure**: Disk, motherboard, or power supply failure requiring hardware replacement and recovery
- **TPM failure or hardware replacement**: Loss of TPM2 requiring recovery key usage and re-enrollment on new hardware
- **Physical security breach**: Unauthorized physical access to data center or colocation facility
- **Environmental failure**: Cooling, power, or environmental control system failure in data center
- **Natural disaster**: Flood, fire, or earthquake affecting physical infrastructure location
- **Hardware theft or loss**: Physical theft of servers containing encrypted data
- **Hybrid infrastructure split-brain**: Network partition between bare-metal and cloud backup infrastructure
- **Certificate expiration**: TLS/SSL certificate renewal in production without service disruption
- **Data center provider changes**: Colocation facility policy or security control changes
- **Decommissioning hardware**: Secure disposal of hardware containing encrypted data at end of lifecycle

## Requirements

### Functional Requirements

#### FR-001: Security Controls (Mandatory)

- **FR-001.1**: The system MUST implement multi-factor authentication for all administrative access
- **FR-001.2**: The system MUST enforce role-based access control (RBAC) with principle of least privilege
- **FR-001.3**: The system MUST encrypt all data at rest using LUKS and ZFS native encryption
- **FR-001.4**: The system MUST encrypt all data in transit using WireGuard VPN and TLS 1.3+
- **FR-001.5**: The system MUST maintain immutable audit logs for all security events
- **FR-001.6**: The system MUST perform automated security scanning and vulnerability management
- **FR-001.7**: The system MUST implement secure boot with TPM2 attestation
- **FR-001.8**: The system MUST support password complexity and rotation policies
- **FR-001.9**: The system MUST implement session timeout and automatic lockout policies

#### FR-002: Availability Controls

- **FR-002.1**: The system MUST support automated failover between infrastructure components
- **FR-002.2**: The system MUST implement health monitoring with automated alerting
- **FR-002.3**: The system MUST maintain ZFS snapshots at defined intervals
- **FR-002.4**: The system MUST support disaster recovery with defined RTO and RPO
- **FR-002.5**: The system MUST implement capacity monitoring and planning
- **FR-002.6**: The system MUST support infrastructure redundancy (network, storage, compute)
- **FR-002.7**: The system MUST maintain backup retention per defined policy

#### FR-003: Confidentiality Controls

- **FR-003.1**: The system MUST classify data based on sensitivity levels
- **FR-003.2**: The system MUST implement access controls based on data classification
- **FR-003.3**: The system MUST support secure data disposal with cryptographic erasure
- **FR-003.4**: The system MUST limit data access to authorized personnel only
- **FR-003.5**: The system MUST implement data loss prevention mechanisms
- **FR-003.6**: The system MUST encrypt confidential data with separate encryption keys

#### FR-004: Processing Integrity Controls

- **FR-004.1**: The system MUST validate data integrity using checksums or cryptographic hashes
- **FR-004.2**: The system MUST detect and report processing errors
- **FR-004.3**: The system MUST log all data processing operations
- **FR-004.4**: The system MUST implement transaction logging with rollback capability
- **FR-004.5**: The system MUST verify completeness of batch processing operations

#### FR-005: Privacy Controls

- **FR-005.1**: The system MUST record consent for PII collection and processing
- **FR-005.2**: The system MUST implement data minimization principles
- **FR-005.3**: The system MUST support data retention and disposal policies
- **FR-005.4**: The system MUST enable data subject access requests (DSAR)
- **FR-005.5**: The system MUST comply with GDPR, CCPA, and other privacy regulations
- **FR-005.6**: The system MUST support data portability and export

#### FR-006: Audit and Compliance

- **FR-006.1**: The system MUST generate audit logs in standardized format (syslog, CEF)
- **FR-006.2**: The system MUST support log forwarding to SIEM systems
- **FR-006.3**: The system MUST track all configuration changes in Git with attribution
- **FR-006.4**: The system MUST support compliance reporting and evidence collection
- **FR-006.5**: The system MUST implement log retention policies (minimum 1 year for SOC2)
- **FR-006.6**: The system MUST support automated compliance scanning

#### FR-007: Physical Security Controls (Bare-Metal Specific)

- **FR-007.1**: The organization MUST control physical access to server locations (data center, colocation, or on-premises)
- **FR-007.2**: The organization MUST maintain visitor logs for physical facility access
- **FR-007.3**: The organization MUST implement environmental controls (temperature, humidity, fire suppression)
- **FR-007.4**: The organization MUST provide physical security monitoring (cameras, motion detection) where appropriate
- **FR-007.5**: The organization MUST implement secure hardware disposal procedures (cryptographic erasure, physical destruction)
- **FR-007.6**: The organization MUST maintain hardware asset inventory with serial numbers and locations
- **FR-007.7**: The organization MUST protect against power failures (UPS, generator, or redundant power)
- **FR-007.8**: The organization MUST implement physical tamper detection where feasible
- **FR-007.9**: The organization MUST secure network equipment and cabling in physical spaces

### Architectural Requirements

#### AR-001: Deployment Architecture

**AR-001.1 - 100% Bare-Metal Deployment Pattern**: For organizations operating entirely on physical hardware:
- All Keystone servers MUST run on physical hardware owned or leased by the organization
- Hardware locations: on-premises data center, colocation facility, or secure server room
- Physical hardware MUST use hardware TPM2 for key management and boot attestation
- Redundant hardware RECOMMENDED for high availability (N+1 or active-active configurations)
- Physical security controls MUST be appropriate for the facility type (see AR-011)
- Hardware lifecycle management MUST include procurement, deployment, maintenance, and secure disposal
- Network connectivity MUST include redundant ISPs or network paths where availability is critical

**AR-001.2 - Hybrid Deployment Pattern**: For organizations using both bare-metal and cloud infrastructure:
- Primary Keystone servers MUST run on bare-metal hardware for performance and control
- Cloud infrastructure MAY be used for:
  - Disaster recovery and backup sites
  - Geographic distribution for availability
  - Burst capacity or development/testing environments
  - Cold storage for archival backups
- WireGuard VPN MUST interconnect all locations (bare-metal and cloud)
- Bare-metal infrastructure SHOULD use hardware TPM2
- Cloud infrastructure SHOULD use virtual TPM where available
- Data residency and sovereignty requirements MUST be enforced through configuration
- Cost optimization: Use bare-metal for sustained workloads, cloud for variable or backup capacity

**AR-001.3 - On-Premises Deployment**: For organizations hosting in owned facilities:
- Organization MUST control physical access to server locations
- Environmental controls (HVAC, fire suppression, power) MUST be maintained
- Physical security monitoring (cameras, alarms) MUST be implemented per risk assessment
- Hardware maintenance and replacement parts MUST be available within RTO requirements
- Network connectivity MUST include redundant paths to prevent single point of failure

**AR-001.4 - Colocation Deployment**: For organizations using colocation facilities:
- Colocation provider MUST have SOC2 report available for review
- Physical access controls MUST meet organizational security requirements
- SLA MUST guarantee uptime, power, cooling, and network connectivity appropriate for needs
- Remote hands service SHOULD be available for hardware maintenance
- Organization retains responsibility for logical security controls
- Cabinet/cage access logs MUST be maintained and reviewed

**AR-001.5 - Security Zone Segmentation**: All deployments MUST implement network segmentation:
- **Management Zone**: Administrative access, configuration management, audit logging
- **Application Zone**: Workloads and services
- **Data Zone**: Storage systems and databases
- **DMZ**: Internet-facing services with restricted backend access
- Physical network isolation (VLANs, separate switches) RECOMMENDED for critical zones

**Rationale**: Bare-metal deployments provide maximum control, performance, and cost efficiency for sustained workloads, but require comprehensive physical security controls. Hybrid approaches balance control with flexibility for disaster recovery and geographic distribution.

#### AR-002: Infrastructure as Code (IaC)

**AR-002.1 - Configuration Management**: ALL infrastructure configuration MUST be:
- Defined in NixOS configuration files
- Stored in Git version control
- Subject to code review before deployment
- Tagged with version numbers for releases
- Backed up to multiple geographic locations

**AR-002.2 - Change Control Process**: Infrastructure changes MUST follow:
1. Propose change via Git pull request
2. Peer review by qualified personnel
3. Automated testing in non-production environment
4. Approval by authorized personnel
5. Deployment to production with rollback plan
6. Post-deployment verification

**AR-002.3 - Environment Parity**: The system MUST maintain:
- Development environment for testing changes
- Staging environment mirroring production
- Production environment with full controls
- Configuration drift detection and remediation

**AR-002.4 - Secret Management**: Secrets MUST be:
- Encrypted at rest using age encryption or similar
- Never committed to Git in plaintext
- Rotated per defined policy
- Accessed only through secure mechanisms (systemd credentials, encrypted environment)
- Audited on access

**Rationale**: IaC provides change tracking, repeatability, and audit trail required for SOC2.

#### AR-003: Identity and Access Management (IAM)

**AR-003.1 - User Lifecycle Management**: The system MUST support:
- User provisioning with approval workflow
- Regular access reviews (quarterly minimum)
- Automated deprovisioning on termination
- Guest/contractor access with time limits
- Service accounts with documented ownership

**AR-003.2 - Authentication Requirements**:
- SSH key-based authentication for infrastructure access
- Multi-factor authentication (MFA) for administrative access
- Password policies enforcing complexity and rotation
- Failed login attempt lockout
- Session timeout policies

**AR-003.3 - Authorization Model**:
- Role-Based Access Control (RBAC) implementation
- Principle of least privilege
- Separation of duties for critical functions
- Regular privilege audits
- Emergency access procedures with logging

**AR-003.4 - Access Logging**: ALL access attempts MUST be logged:
- Successful authentications
- Failed authentication attempts
- Privilege escalation (sudo usage)
- SSH sessions with user, timestamp, source IP
- Configuration changes with attribution

**Rationale**: Strong IAM controls are central to SOC2 security and confidentiality criteria.

#### AR-004: Encryption Architecture

**AR-004.1 - Encryption at Rest**:
- Full disk encryption using LUKS on all storage devices
- ZFS native encryption for datasets with separate keys
- TPM2-based key management for automatic unlock
- Hardware security module (HSM) support for cloud deployments
- Regular key rotation (annually minimum)

**AR-004.2 - Encryption in Transit**:
- WireGuard VPN for inter-node communication
- TLS 1.3+ for all HTTP/API traffic
- SSH for administrative access
- Encrypted database connections
- Certificate management with automated renewal

**AR-004.3 - Key Management**:
- TPM2 stores unsealing keys for LUKS and ZFS
- Recovery keys stored in secure offline location
- Key escrow for business continuity
- Key rotation procedures documented
- Cryptographic algorithm selection (AES-256, ChaCha20)

**AR-004.4 - Cryptographic Standards**:
- NIST-approved algorithms only
- Minimum key lengths (AES-256, RSA-4096, Ed25519)
- Deprecated algorithm prohibition (MD5, SHA-1, DES, RC4)
- Regular cryptographic review

**Rationale**: Encryption is fundamental to SOC2 security and confidentiality requirements.

#### AR-005: Monitoring and Logging

**AR-005.1 - Centralized Logging**: The system MUST implement:
- Centralized log collection from all nodes
- Structured logging format (JSON, syslog)
- Log forwarding to SIEM or log management platform
- Log retention for minimum 1 year (SOC2 requirement)
- Log archival with compression and encryption

**AR-005.2 - Security Monitoring**:
- Failed authentication attempts
- Privilege escalation events
- Configuration changes
- Firewall rule changes
- Unauthorized access attempts
- Malware detection alerts

**AR-005.3 - Availability Monitoring**:
- Service health checks
- Resource utilization (CPU, memory, disk, network)
- ZFS pool status
- Backup job completion
- Certificate expiration warnings
- Disk failure prediction (SMART monitoring)

**AR-005.4 - Alerting**:
- Real-time alerts for critical events
- Alert routing based on severity
- On-call rotation for incident response
- Alert fatigue prevention (tuning, aggregation)
- Alert acknowledgment and resolution tracking

**AR-005.5 - Log Integrity**: Audit logs MUST be:
- Immutable (append-only)
- Cryptographically signed or hashed
- Protected from tampering
- Stored with restricted access
- Backed up independently

**Rationale**: Comprehensive logging and monitoring enables detection, investigation, and evidence for SOC2 audits.

#### AR-006: Backup and Disaster Recovery

**AR-006.1 - Backup Strategy**:
- ZFS snapshots every 15 minutes (local)
- Daily backups to secondary location
- Weekly backups to tertiary location
- Monthly archival backups
- Backup encryption with separate keys
- Backup integrity verification

**AR-006.2 - Backup Retention**:
- Hourly snapshots: 24 hours
- Daily backups: 30 days
- Weekly backups: 12 weeks
- Monthly backups: 7 years (for compliance)
- Configuration backups: indefinite (Git history)

**AR-006.3 - Disaster Recovery**:
- Documented disaster recovery plan (DRP)
- Recovery Time Objective (RTO): 4 hours maximum
- Recovery Point Objective (RPO): 15 minutes maximum
- Regular DR testing (quarterly minimum)
- DR runbooks with step-by-step procedures
- Alternate site availability

**AR-006.4 - Business Continuity**:
- Failover procedures for critical services
- Geographic redundancy for critical systems
- Automated failover testing
- Communication plan for incidents
- Vendor redundancy where possible

**Rationale**: Backup and DR capabilities are essential for SOC2 availability requirements.

#### AR-007: Vulnerability and Patch Management

**AR-007.1 - Vulnerability Scanning**:
- Weekly automated vulnerability scans
- Critical vulnerability remediation within 7 days
- High vulnerability remediation within 30 days
- Medium/Low vulnerability remediation within 90 days
- Scan result archival for audit trail

**AR-007.2 - Patch Management**:
- Security patches applied within defined SLA
- Regular NixOS channel updates
- Staging environment testing before production
- Rollback procedures for failed patches
- Patch exception process with risk acceptance

**AR-007.3 - Security Hardening**:
- CIS benchmark compliance where applicable
- Unnecessary services disabled
- Firewall rules following least privilege
- Secure default configurations
- Regular security configuration reviews

**Rationale**: Proactive vulnerability management prevents security incidents and demonstrates control effectiveness.

#### AR-008: Incident Response

**AR-008.1 - Incident Response Plan (IRP)**:
- Documented incident response procedures
- Incident classification and severity levels
- Roles and responsibilities
- Communication protocols
- Evidence preservation procedures
- Post-incident review process

**AR-008.2 - Incident Detection**:
- Security monitoring alerts
- Anomaly detection
- User-reported incidents
- Third-party notifications
- Automated threat detection

**AR-008.3 - Incident Response Workflow**:
1. Detection and reporting
2. Classification and prioritization
3. Containment
4. Investigation and analysis
5. Eradication and recovery
6. Post-incident review
7. Lessons learned documentation

**AR-008.4 - Incident Logging**: ALL incidents MUST be:
- Logged in incident tracking system
- Documented with timeline
- Reviewed by security team
- Reported to stakeholders as appropriate
- Used for continuous improvement

**Rationale**: Effective incident response minimizes impact and provides evidence of control effectiveness.

#### AR-009: Third-Party Risk Management

**AR-009.1 - Vendor Assessment**: Third-party vendors MUST be:
- Assessed for security controls
- Required to provide SOC2 reports where applicable
- Subject to contractual security requirements
- Monitored for security incidents
- Reviewed annually

**AR-009.2 - Cloud Provider Requirements**: When using cloud infrastructure:
- Select providers with SOC2 Type 2 certification
- Enable provider security features (encryption, logging, monitoring)
- Implement network isolation and firewalls
- Use provider IAM for access control
- Monitor provider security advisories

**AR-009.3 - Data Sharing**: When sharing data with third parties:
- Data Processing Agreement (DPA) required
- Encryption in transit and at rest
- Access limited to minimum necessary
- Audit logging of third-party access
- Regular access reviews

**Rationale**: Third-party risk management is a growing focus area for SOC2 audits in 2025.

#### AR-010: Documentation and Evidence

**AR-010.1 - Policy Documentation**: The following policies MUST be documented:
- Information Security Policy
- Access Control Policy
- Encryption Policy
- Backup and Disaster Recovery Policy
- Incident Response Policy
- Change Management Policy
- Risk Management Policy
- Privacy Policy (if applicable)
- Acceptable Use Policy
- Vendor Management Policy
- Physical Security Policy (for bare-metal deployments)

**AR-010.2 - Procedure Documentation**: Operational procedures MUST be documented:
- User provisioning/deprovisioning
- Patch management
- Backup and restore
- Disaster recovery
- Incident response
- Configuration changes
- Security monitoring
- Audit log review
- Physical access control (for bare-metal)
- Hardware maintenance and replacement (for bare-metal)
- Secure hardware disposal (for bare-metal)

**AR-010.3 - Evidence Collection**: For SOC2 Type 2, evidence MUST be collected:
- Access reviews (quarterly)
- Backup logs
- Vulnerability scan results
- Patch deployment records
- Incident response tickets
- Change management records
- Training completion records
- Security awareness communications
- DR test results
- Risk assessments
- Physical access logs (for bare-metal)
- Hardware inventory records (for bare-metal)
- Environmental monitoring logs (for bare-metal)
- Colocation facility SOC2 reports (if applicable)

**AR-010.4 - Annual Reviews**: The following MUST be reviewed annually:
- All policies and procedures
- Risk assessment
- Business continuity plan
- Disaster recovery plan
- Vendor assessments
- Access controls and permissions

**Rationale**: Comprehensive documentation provides evidence for auditors and ensures consistent operations.

#### AR-011: Physical Security Controls (Bare-Metal Specific)

**AR-011.1 - Physical Access Control**: Organizations operating bare-metal infrastructure MUST implement:
- Badge access systems or lock-and-key with access logs
- Visitor sign-in procedures with escort requirements
- Access lists maintained and reviewed quarterly
- Physical access provisioning/deprovisioning procedures
- Separation of physical and logical access (different personnel where feasible)
- Failed access attempt logging and investigation

**AR-011.2 - Facility Requirements by Deployment Type**:

**On-Premises Data Center**:
- Dedicated room or cage for server infrastructure
- Restricted access with badge reader or keypad
- Security cameras covering entry points
- Environmental controls (HVAC) appropriate for equipment
- Fire suppression system (clean agent or pre-action sprinkler)
- UPS and generator backup power
- Physical security monitoring and alarm system

**Colocation Facility**:
- Facility MUST have SOC2 Type 2 report available for review
- Cabinet or cage must be lockable with organization-controlled access
- Organization MUST maintain list of personnel authorized for physical access
- Remote hands service agreements MUST be documented
- Access logs MUST be obtained from facility and reviewed
- SLA MUST cover environmental controls, power, and physical security

**Secure Server Room** (for small deployments):
- Locked room with access limited to authorized personnel
- Environmental monitoring (temperature alerts)
- UPS for power protection
- Fire detection and suppression appropriate for space
- Access logging through badge system or manual log
- Physical security assessment appropriate to data classification

**AR-011.3 - Environmental Controls**:
- Temperature monitoring with alerting (typical range: 18-27°C / 64-80°F)
- Humidity monitoring with alerting (typical range: 40-60% RH)
- Fire detection and suppression systems tested annually
- Water leak detection in areas with plumbing near equipment
- HVAC redundancy or rapid repair SLA for critical environments
- Emergency power off (EPO) button accessible but protected from accidental activation

**AR-011.4 - Hardware Asset Management**:
- Asset inventory MUST include:
  - Serial numbers
  - Make and model
  - Physical location
  - Purchase date and warranty status
  - Assignment (which system/service)
  - TPM endorsement key (EK) certificate
- Asset inventory MUST be reviewed quarterly
- Asset disposition MUST be tracked (deployed, storage, decommissioned)
- Asset transfers between locations MUST be logged

**AR-011.5 - Hardware Lifecycle Management**:
- **Procurement**: Hardware MUST be ordered from authorized vendors with chain of custody
- **Receiving**: Hardware MUST be inspected for tampering upon receipt
- **Deployment**: Hardware MUST be tracked from receipt to production deployment
- **Maintenance**: Hardware repairs MUST be performed by authorized personnel with logging
- **Decommissioning**: Hardware MUST be securely wiped or destroyed per disposal policy

**AR-011.6 - Secure Hardware Disposal**:
- Storage devices MUST be cryptographically erased or physically destroyed
- Cryptographic erasure: ZFS dataset destruction with key deletion PLUS disk secure erase command
- Physical destruction: Shredding, degaussing, or crushing by certified disposal vendor
- Certificate of destruction MUST be obtained and retained
- Disposal logs MUST track serial number, disposal method, date, and approving personnel
- Hardware disposal MUST occur within 30 days of decommissioning to limit storage risk

**AR-011.7 - Physical Tamper Detection**:
- Server chassis intrusion detection enabled where hardware supports it
- Tamper-evident seals on critical equipment where appropriate
- Regular physical inspection of equipment for signs of tampering
- Investigation procedure for suspected physical tampering
- TPM boot attestation to detect firmware/bootloader tampering

**AR-011.8 - Network Infrastructure Physical Security**:
- Network equipment (switches, routers, firewalls) MUST be in secured locations
- Cabling MUST be protected from physical access where feasible
- Network jacks in unsecured areas MUST be disabled or on isolated VLAN
- Physical network taps and unauthorized devices MUST be detected through monitoring
- Wireless access points MUST be inventoried and monitored for rogue APs

**AR-011.9 - Power and Cooling Redundancy**:
- Critical systems MUST have UPS protection with sufficient runtime for graceful shutdown
- Generator backup RECOMMENDED for facilities requiring >4 hour uptime during power outages
- UPS battery testing MUST occur quarterly
- Generator testing MUST occur monthly (if present)
- Cooling failure MUST trigger alerts before equipment reaches shutdown temperature
- Redundant power supplies RECOMMENDED for critical servers

**AR-011.10 - Colocation Provider Assessment**:
When using colocation facilities, organizations MUST assess:
- Physical security controls (badge access, cameras, guards, mantraps)
- SOC2 Type 2 report covering physical security controls
- Environmental controls and SLAs
- Power redundancy and SLAs
- Fire suppression and detection systems
- Disaster recovery capabilities (e.g., geographic diversity)
- Access logging capabilities and retention
- Remote hands services and response times
- Network connectivity redundancy

**Rationale**: Physical security is often the weakest link in bare-metal deployments. While Keystone's encryption protects against data extraction from stolen hardware, physical access can enable attacks against running systems, firmware tampering, or denial of service. Comprehensive physical controls are essential for SOC2 compliance with bare-metal infrastructure.

### Key Entities

- **SOC2 Control**: A security or operational control mapped to one of the five Trust Services Criteria
- **Audit Evidence**: Documented proof of control operation over the audit period
- **Trust Services Criteria**: The five categories (Security, Availability, Confidentiality, Processing Integrity, Privacy)
- **Keystone Node**: A server or client system running Keystone with specific compliance controls
- **Audit Period**: The 3-12 month period during which control effectiveness is measured (Type 2)
- **Control Owner**: Individual responsible for implementing and maintaining a specific control
- **Compliance Configuration**: Keystone NixOS modules implementing SOC2 controls

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% of mandatory security controls (CC1-CC9) are implemented and verifiable in deployed infrastructure
- **SC-002**: All deployed infrastructure is defined in Git with 100% of changes having peer review
- **SC-003**: Automated compliance scanning shows 0 critical findings and <5 high findings
- **SC-004**: Backup and restore procedures achieve RTO <4 hours and RPO <15 minutes in DR tests
- **SC-005**: Audit logs are successfully collected and retained for 100% of security events over audit period
- **SC-006**: 0 security incidents result from missing or ineffective controls
- **SC-007**: Disaster recovery tests are completed quarterly with 100% success rate
- **SC-008**: All administrative access uses MFA with 100% compliance
- **SC-009**: Vulnerability remediation meets SLA for 95%+ of findings
- **SC-010**: SOC2 Type 2 audit is completed with no exceptions or qualified opinion

## Implementation Approach

### Phase 1: Foundation (Months 1-2)
- Implement core security controls (encryption, access control, logging)
- Establish Git-based configuration management
- Deploy centralized logging infrastructure
- Document security policies

### Phase 2: Operational Controls (Months 3-4)
- Implement backup and DR procedures
- Establish change management process
- Deploy monitoring and alerting
- Conduct initial vulnerability assessment
- Begin audit log collection for Type 2

### Phase 3: Compliance Evidence (Months 5-8)
- Collect evidence of control operation
- Conduct access reviews
- Perform DR testing
- Execute security training
- Perform quarterly vulnerability scans

### Phase 4: Audit Preparation (Months 9-10)
- Organize evidence for auditor
- Address any control gaps
- Conduct internal readiness assessment
- Update documentation
- Prepare control descriptions

### Phase 5: SOC2 Audit (Months 11-12)
- Engage SOC2 auditor
- Provide evidence and respond to inquiries
- Address any findings
- Receive SOC2 Type 2 report
- Implement continuous compliance program

## References

- AICPA Trust Services Criteria (2017)
- COSO Internal Control Framework
- NIST Cybersecurity Framework
- CIS Critical Security Controls
- ISO/IEC 27001 (for reference)
- GDPR and CCPA (for privacy controls)
- NixOS Security Documentation
- Keystone Architecture Documentation

## Appendix A: SOC2 Control Mapping

### Common Criteria (CC)

| Control | Description | Keystone Implementation |
|---------|-------------|------------------------|
| CC1 | Control Environment | NixOS declarative configuration, Git version control, change management |
| CC2 | Communication & Information | Documentation, policies, training programs |
| CC3 | Risk Assessment | Vulnerability scanning, threat modeling, risk register |
| CC4 | Monitoring Activities | Centralized logging, SIEM, alerting, security monitoring |
| CC5 | Control Activities | Technical controls (encryption, access control, etc.) |
| CC6 | Logical & Physical Access | SSH key auth, MFA, RBAC, Secure Boot, TPM2 |
| CC7 | System Operations | Change management, patch management, capacity planning |
| CC8 | Change Management | Git-based IaC, peer review, testing, rollback procedures |
| CC9 | Risk Mitigation | Incident response, business continuity, disaster recovery |

### Security (Mandatory)

All Common Criteria (CC1-CC9) apply to Security. Additional security-specific controls:
- **S1.1**: Encryption at rest and in transit
- **S1.2**: Multi-factor authentication
- **S1.3**: Password policies
- **S1.4**: Session management
- **S1.5**: Firewall and network security

### Availability (Optional)

- **A1.1**: Performance monitoring and capacity management
- **A1.2**: Backup and recovery procedures
- **A1.3**: Disaster recovery testing
- **A1.4**: Infrastructure redundancy
- **A1.5**: Service level agreements (SLAs)

### Confidentiality (Optional)

- **C1.1**: Data classification
- **C1.2**: Confidential data encryption
- **C1.3**: Access controls for confidential data
- **C1.4**: Secure data disposal
- **C1.5**: Data loss prevention

### Processing Integrity (Optional)

- **PI1.1**: Data integrity verification
- **PI1.2**: Error detection and handling
- **PI1.3**: Transaction logging
- **PI1.4**: Completeness checks
- **PI1.5**: Reconciliation procedures

### Privacy (Optional)

- **P1.1**: Consent management
- **P1.2**: Data minimization
- **P1.3**: Retention and disposal
- **P1.4**: Data subject access requests
- **P1.5**: Privacy compliance (GDPR, CCPA)

## Appendix B: Sample Keystone SOC2 Configuration

```nix
{
  # Base Keystone configuration with SOC2 controls
  keystone = {
    # Enable full security stack
    disko = {
      enable = true;
      device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB";
      enableEncryptedSwap = true;
    };

    # Enable TPM2 enrollment for automatic unlock
    tpm-enrollment.enable = true;

    # Server services (for cloud deployments)
    server = {
      enable = true;
      # VPN for secure inter-node communication
      vpn.enable = true;
      # DNS with logging for audit trail
      dns.enable = true;
    };
  };

  # SOC2-specific configurations
  services = {
    # Centralized audit logging
    journald = {
      extraConfig = ''
        Storage=persistent
        MaxRetentionSec=31536000  # 1 year retention
        Compress=yes
        Seal=yes  # Cryptographic sealing
      '';
    };

    # Failed login attempt limiting
    fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
    };

    # Automated security updates (with testing)
    system.autoUpgrade = {
      enable = true;
      allowReboot = false;  # Manual approval required
      channel = "https://nixos.org/channels/nixos-unstable";
    };
  };

  # Access control
  security = {
    sudo = {
      enable = true;
      wheelNeedsPassword = true;
      execWheelOnly = true;
    };

    # Enforce strong password policies
    pam.services.passwd.text = ''
      password requisite pam_pwquality.so minlen=14 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1
    '';
  };

  # User management
  users = {
    mutableUsers = false;  # Users defined in config only
    users = {
      admin = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];  # Admin privileges
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... admin@company.com"
        ];
      };
    };
  };

  # Network security
  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];  # SSH only, rest via VPN
      logRefusedConnections = true;  # Audit trail
    };

    # Enable nftables for better control
    nftables.enable = true;
  };

  # Monitoring and alerting (example with Prometheus)
  services.prometheus = {
    enable = true;
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [ "systemd" "processes" "filesystem" ];
      };
    };
  };
}
```

## Appendix C: Compliance Checklist

### Pre-Audit Readiness
- [ ] All policies documented and approved
- [ ] Procedures documented with screenshots/examples
- [ ] Evidence collection automated and tested
- [ ] Gap analysis completed and remediated
- [ ] Internal audit performed
- [ ] Management review completed

### Security Controls
- [ ] All infrastructure uses TPM2 and full disk encryption
- [ ] Multi-factor authentication enabled for all admin access
- [ ] Password policies enforced
- [ ] Role-based access control implemented
- [ ] Audit logging enabled and retained for 1 year
- [ ] Vulnerability scanning automated weekly
- [ ] Patch management process documented and followed

### Availability Controls
- [ ] Backup procedures documented and tested
- [ ] Disaster recovery plan documented
- [ ] DR testing completed quarterly
- [ ] RTO and RPO defined and achievable
- [ ] Monitoring and alerting operational
- [ ] Capacity planning performed

### Confidentiality Controls
- [ ] Data classification scheme defined
- [ ] Confidential data encrypted at rest and in transit
- [ ] Access controls based on data classification
- [ ] Secure disposal procedures documented
- [ ] Data loss prevention mechanisms in place

### Processing Integrity Controls
- [ ] Data validation procedures documented
- [ ] Error detection and handling implemented
- [ ] Transaction logging enabled
- [ ] Reconciliation procedures documented

### Privacy Controls
- [ ] Consent management implemented
- [ ] Data minimization practiced
- [ ] Retention policies documented and enforced
- [ ] DSAR procedures documented
- [ ] Privacy compliance verified (GDPR, CCPA)

### Audit Evidence
- [ ] Quarterly access reviews completed
- [ ] Backup logs collected
- [ ] Vulnerability scan results archived
- [ ] Patch deployment records maintained
- [ ] Incident tickets documented
- [ ] Change management records complete
- [ ] Training records current
- [ ] DR test results documented

## Appendix D: Continuous Compliance

SOC2 certification is not a one-time achievement but requires continuous operation of controls. Organizations using Keystone should:

1. **Maintain Control Operation**: All controls must continue operating throughout the year
2. **Collect Evidence Continuously**: Automate evidence collection where possible
3. **Review and Update**: Quarterly reviews of controls, annual policy updates
4. **Monitor Changes**: Any infrastructure changes must maintain compliance
5. **Plan for Re-Audit**: SOC2 reports typically valid for 12 months, plan for annual re-audit
6. **Respond to Findings**: Address any audit findings promptly
7. **Continuous Improvement**: Use audit feedback to strengthen controls

### Automation Opportunities

Keystone's declarative configuration approach enables automation of many compliance tasks:
- Configuration compliance scanning (compare deployed state to approved config)
- Automated backup verification
- Access review automation (compare current permissions to approved lists)
- Vulnerability scan scheduling and reporting
- Log retention enforcement
- Certificate renewal and monitoring
- Evidence collection and archival

Organizations should develop NixOS modules that codify compliance requirements, making compliance verification as simple as running `nixos-rebuild build` and comparing against expected state.
