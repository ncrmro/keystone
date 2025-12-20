# Research: AWS Kubernetes Operator + OIDC Integration

**Feature**: 006-clusters
**Date**: 2024-12-20
**Phase**: 0 - Research & Discovery

## Overview

This document captures research findings for integrating AWS cloud provider capabilities with Keystone Clusters using OIDC federation. The goal is to enable the Primer Server to provision and manage AWS resources (EC2 instances, S3 buckets, EBS volumes) without storing long-lived API credentials.

## Research Areas

### 1. OIDC Identity Provider Architecture

**Decision**: Primer Server acts as an OIDC Identity Provider (IdP) that AWS trusts

**Rationale**:
- Eliminates static AWS credentials stored in the cluster
- Short-lived tokens (15 minutes to 12 hours) reduce blast radius of compromise
- Standard OpenID Connect protocol supported by all major cloud providers
- Enables fine-grained permission scoping per workload

**Architecture**:
```
┌─────────────────┐     OIDC Trust     ┌─────────────┐
│  Primer Server  │◄──────────────────►│   AWS IAM   │
│  (OIDC IdP)     │                    │   Identity  │
│                 │                    │   Provider  │
└────────┬────────┘                    └──────┬──────┘
         │                                    │
         │ Issues JWT                         │ Validates JWT
         ▼                                    ▼
┌─────────────────┐                    ┌─────────────┐
│  Kubernetes     │───AssumeRole───────►│  IAM Role   │
│  Service Account│   with WebIdentity │             │
└─────────────────┘                    └─────────────┘
```

**Implementation Notes**:
- OIDC discovery endpoint: `https://primer.cluster.local/.well-known/openid-configuration`
- JWKS endpoint for key rotation: `https://primer.cluster.local/keys`
- Tokens include `sub` (service account), `iss` (primer), `aud` (AWS)
- AWS IAM role trust policy validates issuer and subject claims

### 2. AWS IAM OIDC Identity Provider Setup

**Decision**: Create IAM OIDC provider pointing to Primer's discovery endpoint

**AWS Configuration**:
```json
{
  "Url": "https://primer.cluster.local",
  "ClientIdList": ["sts.amazonaws.com"],
  "ThumbprintList": ["<primer-certificate-thumbprint>"]
}
```

**Trust Policy for IAM Role**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/primer.cluster.local"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "primer.cluster.local:sub": "system:serviceaccount:keystone-system:node-provisioner",
        "primer.cluster.local:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```

**Alternatives Considered**:
- **IAM Users with Access Keys**: Long-lived credentials, rotation burden, security risk
- **EC2 Instance Roles**: Only works if Primer runs on EC2, not self-hosted
- **AWS SSO/Identity Center**: Enterprise feature, overkill for self-hosted clusters

### 3. Service Account Token Volume Projection

**Decision**: Use Kubernetes projected service account tokens for OIDC

**Rationale**:
- Native Kubernetes feature (1.21+)
- Automatic token rotation
- Audience-scoped tokens prevent misuse
- No custom token issuance logic needed

**Pod Spec Configuration**:
```yaml
serviceAccountName: node-provisioner
volumes:
  - name: aws-token
    projected:
      sources:
        - serviceAccountToken:
            path: token
            expirationSeconds: 3600
            audience: sts.amazonaws.com
volumeMounts:
  - name: aws-token
    mountPath: /var/run/secrets/aws
    readOnly: true
```

**AWS SDK Configuration**:
```bash
export AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/aws/token
export AWS_ROLE_ARN=arn:aws:iam::ACCOUNT:role/KeystoneNodeProvisioner
```

### 4. Pod Identity vs IRSA Patterns

**Decision**: Use IRSA (IAM Roles for Service Accounts) pattern, not EKS Pod Identity

**Rationale**:
- IRSA works with any Kubernetes cluster (not EKS-specific)
- Pod Identity requires EKS Pod Identity Agent (EKS-only)
- IRSA uses standard OIDC, aligns with multi-cloud goals
- Pod Identity is simpler but locks us to EKS

**Comparison**:

| Feature | IRSA | Pod Identity |
|---------|------|--------------|
| Cluster Type | Any K8s | EKS only |
| Token Source | Projected SA | Pod Identity Agent |
| Setup Complexity | Medium | Low (EKS) |
| Multi-cloud | Yes | No |
| Credential Caching | Application | Agent |

### 5. Operator Framework Selection

**Decision**: Use kubebuilder for custom Keystone operator

**Rationale**:
- Official Kubernetes SIG project
- Generates controller-runtime scaffolding
- Strong typing with Go
- Better IDE support than operator-sdk
- Smaller binary size

**Alternatives Considered**:
- **operator-sdk**: Higher-level, more opinionated, larger footprint
- **Metacontroller**: Webhook-based, simpler but less flexible
- **KUDO**: Declarative operators, limited for complex workflows
- **Rust (kube-rs)**: Performance benefits, smaller ecosystem

**Operator Responsibilities**:
1. Watch `NodePool` custom resources
2. Provision EC2 instances via AWS SDK
3. Configure instance with cloud-init (join cluster)
4. Monitor instance health
5. Handle scaling and replacement

### 6. EC2 Node Provisioning Patterns

**Decision**: Use EC2 Launch Templates with cloud-init for node bootstrap

**Architecture**:
```yaml
apiVersion: keystone.systems/v1alpha1
kind: NodePool
metadata:
  name: workers
spec:
  provider: aws
  region: us-west-2
  instanceType: m5.large
  minNodes: 1
  maxNodes: 10
  rootVolume:
    size: 100
    type: gp3
  cloudInit:
    joinToken: $(SECRET_REF)
    headscaleUrl: https://primer.cluster.local:8080
```

**Bootstrap Flow**:
1. Operator creates EC2 Launch Template
2. Auto Scaling Group provisions instance
3. Cloud-init installs NixOS configuration
4. Node registers with Headscale
5. Node joins Kubernetes cluster
6. Operator updates NodePool status

**Instance Lifecycle**:
- **Spot Instances**: Supported for cost savings (with interruption handling)
- **On-Demand**: Default for control plane and stateful workloads
- **Reserved**: Can be used if pre-purchased

### 7. Security Considerations

**Token Security**:
- Tokens expire after 1 hour (configurable)
- Tokens are audience-scoped (cannot be reused for other services)
- Token files are read-only mounted

**Network Security**:
- OIDC endpoint should be accessible only via Headscale network
- AWS STS endpoint accessed via NAT (no inbound required)
- Instance metadata service (IMDS) disabled on provisioned nodes

**IAM Permissions** (Least Privilege):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:DescribeInstances",
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/keystone-cluster": "${cluster-name}"
        }
      }
    }
  ]
}
```

## Integration Points

### With Headscale
- Provisioned nodes register with Headscale using pre-auth key
- OIDC endpoint exposed only on Headscale network
- kubectl access via Headscale tunnel

### With ZFS/Storage
- EBS volumes attached and formatted with ZFS
- Snapshots synced to S3 for offsite backup

### With Observability
- Node exporter deployed via cloud-init
- Prometheus scrapes new nodes automatically

## Key Findings Summary

1. **OIDC is the right approach** - eliminates credential management, industry standard
2. **IRSA over Pod Identity** - works with self-hosted clusters, multi-cloud ready
3. **kubebuilder for operator** - well-supported, generates clean code
4. **Launch Templates + cloud-init** - proven pattern, supports NixOS
5. **Token projection** - native Kubernetes feature, automatic rotation
6. **Least privilege IAM** - tag-based restrictions, resource-level permissions

## Open Questions Resolved

- **Q**: How does the Primer advertise its OIDC endpoint to AWS?
  - **A**: Via Cloudflare tunnel or public DNS (AWS needs HTTPS with valid cert)

- **Q**: Can OIDC work if Primer is behind NAT?
  - **A**: Yes, AWS only needs outbound HTTPS to validate tokens; can use Cloudflare tunnel for OIDC discovery

- **Q**: What happens if Primer goes offline?
  - **A**: Existing tokens continue to work until expiry; new tokens cannot be issued; cluster operates autonomously

- **Q**: How do we handle token refresh in long-running pods?
  - **A**: Kubernetes rotates projected tokens automatically; AWS SDK reads fresh token on each request

## Next Steps

1. Implement OIDC issuer on Primer Server (Go service or Dex)
2. Create kubebuilder scaffolding for NodePool operator
3. Define NodePool CRD schema
4. Implement EC2 provisioning logic
5. Test end-to-end with single node provision
