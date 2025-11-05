# ClickHouse Security Hardening Guide

## Current Configuration (Development/Testing)

The default deployment uses:
- **Password**: "foo" (SHA256 hashed)
- **Network Access**: VPC only (10.0.0.0/8) + NetworkPolicy
- **Access Control**: Application pods only

⚠️ **This is suitable for development/testing but NOT production!**

---

## Production Hardening Steps

### 1. Generate Strong Password

```bash
# Generate a random password
NEW_PASSWORD=$(openssl rand -base64 32)
echo "Generated password: $NEW_PASSWORD"

# Generate SHA256 hash
PASSWORD_HASH=$(echo -n "$NEW_PASSWORD" | sha256sum | awk '{print $1}')
echo "SHA256 hash: $PASSWORD_HASH"
```

### 2. Update Configuration

**Edit `aws/kubernetes/clickhouse-config.yaml`:**
```xml
<users>
    <default>
        <password_sha256_hex>YOUR_HASH_HERE</password_sha256_hex>
        ...
    </default>
</users>
```

**Update `aws/kubernetes/secrets.yaml`:**
```yaml
stringData:
  CLICKHOUSE_PASSWORD: "YOUR_PASSWORD_HERE"
```

### 3. Strengthen NetworkPolicy

**Edit `aws/kubernetes/clickhouse-networkpolicy.yaml` to restrict by namespace:**
```yaml
spec:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: l1-troubleshooting
    - podSelector:
        matchLabels:
          app: l1-integrated
```

### 4. Use AWS Secrets Manager (Recommended)

For production, use External Secrets Operator:

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
   external-secrets/external-secrets \
    -n external-secrets-system \
    --create-namespace

# Create secret in AWS Secrets Manager
aws secretsmanager create-secret \
    --name l1/clickhouse/password \
    --secret-string '{"password":"your-strong-password"}'

# Create ExternalSecret resource
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: clickhouse-password
  namespace: l1-troubleshooting
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: l1-app-secrets
  data:
  - secretKey: CLICKHOUSE_PASSWORD
    remoteRef:
      key: l1/clickhouse/password
      property: password
EOF
```

### 5. Enable TLS (Optional)

For encrypted connections:

1. Generate certificates
2. Update ClickHouse config with TLS settings
3. Update client connections to use HTTPS

---

## Security Checklist

**Before deploying to production:**

- [ ] Change default password "foo"
- [ ] Store passwords in AWS Secrets Manager (not Git)
- [ ] Review NetworkPolicy rules
- [ ] Restrict ClickHouse networks to specific CIDRs
- [ ] Enable audit logging in ClickHouse
- [ ] Set up monitoring for unauthorized access attempts
- [ ] Configure backup/restore procedures
- [ ] Test disaster recovery

---

## Current Risk Assessment

**Development/Testing (Current Config):**
- ✅ Safe for internal 4-hour sessions
- ✅ NetworkPolicy prevents cross-namespace access
- ⚠️ Default password is weak but isolated
- ⚠️ Credentials visible in Git (development only)

**Production Deployment:**
- ❌ Default password "foo" is unacceptable
- ❌ Secrets in Git create audit issues
- ❌ Manual secret rotation is error-prone
- ❌ No audit trail for access

---

## Quick Security Upgrade

For immediate improvement without AWS Secrets Manager:

```bash
# 1. Generate strong password
NEW_PASS=$(openssl rand -base64 32)
NEW_HASH=$(echo -n "$NEW_PASS" | sha256sum | awk '{print $1}')

# 2. Update ConfigMap
kubectl patch configmap clickhouse-config -n l1-troubleshooting \
  --type='json' -p="[{'op': 'replace', 'path': '/data/users.xml', 'value': '<password_sha256_hex>$NEW_HASH</password_sha256_hex>'}]"

# 3. Update Secret
kubectl create secret generic l1-app-secrets \
  --from-literal=CLICKHOUSE_PASSWORD="$NEW_PASS" \
  -n l1-troubleshooting \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Restart ClickHouse
kubectl delete pod clickhouse-0 -n l1-troubleshooting

# 5. Save password securely (NOT in Git!)
echo "ClickHouse Password: $NEW_PASS" >> ~/.clickhouse-credentials
chmod 600 ~/.clickhouse-credentials
```

---

## Conclusion

The current deployment provides basic security adequate for:
- Development environments
- Internal testing
- 4-hour isolated sessions
- Single-user/team scenarios

For production or sensitive data, implement the hardening steps above.
