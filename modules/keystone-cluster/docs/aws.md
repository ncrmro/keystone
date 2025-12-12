# AWS Integration

## Overview

Integrate your self-hosted Kubernetes cluster with AWS using OIDC federation. This allows Kubernetes service accounts to assume IAM roles without storing long-lived credentials.

## OIDC Authentication Flow

```
Pod with ServiceAccount
        │
        ▼
K3s generates signed JWT token
        │
        ▼
AWS STS validates token via OIDC endpoint
        │
        ▼
AWS returns temporary credentials
```

## Setup Steps

### 1. Create S3 Bucket for OIDC Discovery

```bash
aws s3 mb s3://my-cluster-oidc --region us-west-2

aws s3api put-public-access-block \
  --bucket my-cluster-oidc \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false"
```

### 2. Configure K3s with OIDC Issuer

```nix
{
  keystone.cluster = {
    enable = true;
    oidc = {
      enable = true;
      issuerUrl = "https://my-cluster-oidc.s3.us-west-2.amazonaws.com";
    };
  };
}
```

### 3. Upload Discovery Documents

After K3s starts:

```bash
# Extract OIDC documents
kubectl get --raw /.well-known/openid-configuration > openid-configuration
kubectl get --raw /openid/v1/jwks > jwks

# Upload to S3
aws s3 cp openid-configuration \
  s3://my-cluster-oidc/.well-known/openid-configuration \
  --content-type application/json --acl public-read

aws s3 cp jwks \
  s3://my-cluster-oidc/openid/v1/jwks \
  --content-type application/json --acl public-read
```

### 4. Create AWS OIDC Provider

```bash
# Get SSL thumbprint
THUMBPRINT=$(echo | openssl s_client \
  -servername my-cluster-oidc.s3.us-west-2.amazonaws.com \
  -connect my-cluster-oidc.s3.us-west-2.amazonaws.com:443 2>/dev/null | \
  openssl x509 -fingerprint -sha1 -noout | cut -d= -f2 | tr -d :)

# Create provider
aws iam create-open-id-connect-provider \
  --url https://my-cluster-oidc.s3.us-west-2.amazonaws.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list $THUMBPRINT
```

### 5. Create IAM Roles

Example trust policy for a service account:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/my-cluster-oidc.s3.us-west-2.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "my-cluster-oidc.s3.us-west-2.amazonaws.com:sub": "system:serviceaccount:NAMESPACE:SERVICE_ACCOUNT",
          "my-cluster-oidc.s3.us-west-2.amazonaws.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### 6. Annotate Service Accounts

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/MyAppRole
```

## AWS Operators

### Karpenter (Node Provisioning)

```nix
{
  keystone.cluster.operators.karpenter = {
    enable = true;
    iamRoleArn = "arn:aws:iam::123456789012:role/KarpenterRole";
    defaultNodePool = {
      instanceTypes = ["t3.medium" "t3.large"];
      capacityTypes = ["spot" "on-demand"];
    };
  };
}
```

### ACK (AWS Controllers for Kubernetes)

```nix
{
  keystone.cluster.operators.ack = {
    enable = true;
    controllers = ["ec2" "s3" "rds"];
    iamRoleArn = "arn:aws:iam::123456789012:role/ACKRole";
  };
}
```

## Troubleshooting

**"Token signature validation failed"**
- Verify JWKS is uploaded to correct S3 path
- Check OIDC provider thumbprint matches certificate

**"Unauthorized to assume role"**
- Verify service account name/namespace in trust policy
- Ensure audience is "sts.amazonaws.com"

## References

- [AWS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Karpenter](https://karpenter.sh/)
- [ACK](https://aws-controllers-k8s.github.io/community/)
