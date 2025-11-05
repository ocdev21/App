# Cost Control Guide - 4-Hour Session Usage

**Your AWS Account**: 012351853258  
**Target Usage**: Maximum 4 hours per session  
**Goal**: Minimize AWS costs by stopping everything after each session

---

## 💰 Cost Breakdown

### Per 4-Hour Session
| Service | Cost |
|---------|------|
| EKS Control Plane | $0.40 |
| 2× t3.large EC2 nodes | $0.67 |
| Application Load Balancer | $0.09 |
| ClickHouse (in EKS) | $0.00 (uses existing nodes) |
| Bedrock Nova Pro (AI) | $0.50-2.00 (usage-based) |
| **Total per session** | **~$2.00-3.00** |

### Monthly Costs (Weekly Usage)
| Scenario | Cost |
|----------|------|
| 4 sessions/month (weekly) | ~$10/month |
| EFS storage (app files) | ~$2/month |
| EBS storage (ClickHouse, always on) | ~$5/month |
| ECR images (always on) | ~$1/month |
| **Total** | **~$18/month** ✅ |

### ⚠️ If You Forget to Stop
| State | Daily Cost | Monthly Cost |
|-------|------------|--------------|
| Idle (cluster on, no pods) | $2.40/day | ~$87/month ❌ |
| Running 24/7 | $8.33/day | ~$250/month ❌❌ |

**Note**: EBS volumes for ClickHouse (~$5/month) persist even when cluster is stopped. This is necessary for data persistence but adds to idle costs.

---

## 🔄 Complete Workflow

### 1️⃣ Starting Your Session

**From your EC2 console:**
```bash
cd ~/l1-troubleshooting-system/aws/scripts

# Quick start (after previous quick stop) - 5 minutes
./start-all-services.sh quick

# OR full start (first time or after full stop) - 25 minutes
./start-all-services.sh full
```

**Wait for startup:**
- Quick start: ~5 minutes
- Full start: ~25 minutes

**Get your application URL:**
```bash
kubectl get ingress -n l1-troubleshooting
```

Access: `http://<ALB-URL>`

---

### 2️⃣ During Your Session (Max 4 Hours)

**Use the application:**
- Upload PCAP/DLF network capture files
- Analyze anomalies with ML detection
- Get AI-powered recommendations (Bedrock Nova Pro)
- Review real-time dashboard
- Export any important results

**Monitor costs (optional):**
```bash
cd ~/l1-troubleshooting-system/aws/scripts
./check-costs.sh
```

---

### 3️⃣ Stopping After Session (CRITICAL!)

**⏰ Set a 4-hour timer reminder!**

**Option A: Quick Stop (Recommended for regular use)**
```bash
cd ~/l1-troubleshooting-system/aws/scripts
./stop-all-services.sh quick
```
- ✅ Idle cost: $2.40/day (~$72/month)
- ✅ Next startup: 5 minutes
- ✅ Best for: Weekly/regular usage

**Option B: Full Stop (Best for long breaks)**
```bash
cd ~/l1-troubleshooting-system/aws/scripts
./stop-all-services.sh full
```
- ✅ Idle cost: $0.60/day (~$18/month) - near zero!
- ⏱️ Next startup: 25 minutes
- ✅ Best for: Not using for weeks

---

## 📊 Cost Control Scripts

### Check Current Costs
```bash
cd ~/l1-troubleshooting-system/aws/scripts
./check-costs.sh
```

**Shows:**
- What's currently running
- Estimated hourly/daily/monthly costs
- Recommendations for stopping

---

## 🎯 Best Practices

### ✅ DO
- Start services only when you need to analyze files
- Stop immediately after your session
- Run `./check-costs.sh` weekly to verify nothing is running
- Use "quick stop" for regular weekly usage
- Use "full stop" if not using for 2+ weeks

### ❌ DON'T
- Leave cluster running overnight
- Forget to stop after session
- Run 24/7 (costs $250/month!)
- Skip the cost check script

---

## 📅 Recommended Schedule

**Weekly Usage Example:**

| Day | Action | Cost |
|-----|--------|------|
| Monday 9am | `./start-all-services.sh quick` | - |
| Monday 9am-1pm | Use application (4 hours) | $2.50 |
| Monday 1pm | `./stop-all-services.sh quick` | - |
| Rest of week | Services stopped | $2.40/day × 6 = $14.40 |
| **Weekly Total** | | **~$17** |

**Monthly Cost**: 4 weeks × $17 = **~$68/month**

**To reduce to $18/month base cost**: Use `./stop-all-services.sh full` instead of quick

**Note**: ClickHouse EBS storage (~$5/month) persists regardless of stop mode. To completely eliminate this cost, you must manually delete the ClickHouse PVCs (this deletes all historical data).

---

## 🚨 Emergency Stop (If You Forgot to Stop)

**From your EC2 console:**
```bash
# Quick check - what's running?
cd ~/l1-troubleshooting-system/aws/scripts
./check-costs.sh

# Stop everything NOW!
./stop-all-services.sh full
```

---

## 🔔 Set Up Billing Alerts (Highly Recommended)

**AWS Console → Billing → Budgets → Create Budget**

1. Budget amount: $20/month
2. Alert at 50% ($10)
3. Alert at 80% ($16)
4. Alert at 100% ($20)

This prevents surprise charges!

---

## 📋 Session Checklist

**Before each session:**
- [ ] SSH into EC2 instance
- [ ] Navigate to `~/l1-troubleshooting-system/aws/scripts`
- [ ] Run `./start-all-services.sh quick` (or `full` if first time)
- [ ] Wait 5-25 minutes for startup
- [ ] Get URL: `kubectl get ingress -n l1-troubleshooting`
- [ ] Open application in browser

**During session:**
- [ ] Upload network files
- [ ] Analyze anomalies
- [ ] Get AI recommendations
- [ ] Export/save important results

**After session:**
- [ ] Run `./stop-all-services.sh quick` (or `full` for max savings)
- [ ] Verify stopped: `./check-costs.sh`
- [ ] Log out of EC2

**Weekly:**
- [ ] Check costs: `./check-costs.sh`
- [ ] Review AWS billing dashboard

---

## 🆘 Troubleshooting

### "Scripts not found"
```bash
cd ~/l1-troubleshooting-system/aws/scripts
ls -la *.sh
# If missing, re-clone repository
```

### "Cluster not found"
```bash
# First time setup - use full start
./start-all-services.sh full
```

### "High costs detected"
```bash
# Stop everything immediately
./stop-all-services.sh full

# Check AWS billing dashboard
# Review what was running with ./check-costs.sh logs
```

---

## 📞 Quick Reference

| Task | Command | Time |
|------|---------|------|
| Start (quick) | `./start-all-services.sh quick` | 5 min |
| Start (full) | `./start-all-services.sh full` | 25 min |
| Stop (quick) | `./stop-all-services.sh quick` | 2 min |
| Stop (full) | `./stop-all-services.sh full` | 15 min |
| Check costs | `./check-costs.sh` | 10 sec |
| Get URL | `kubectl get ingress -n l1-troubleshooting` | 5 sec |

---

**Remember**: The #1 cost saver is stopping services after each session!

Set a 4-hour timer when you start. ⏰
