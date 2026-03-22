#!/bin/bash
# Inbox Inferno - Demo Script
# Usage: bash demo.sh [1|2|3|4]  or just  bash demo.sh  for all

WEBHOOK="https://kaiser-data.app.n8n.cloud/webhook/inbox-inferno"

run_test() {
  local label="$1"
  local file="$2"
  echo ""
  echo "=== $label ==="
  curl -s "$WEBHOOK" -H "Content-Type: application/json" -d "@$file" | python3 -m json.tool
  echo ""
}

# Create email files
mkdir -p /tmp/inbox_demo

cat > /tmp/inbox_demo/pricing.json << 'EOF'
{"from":"alice@acmecorp.com","subject":"Starter vs Professional - help me decide","body":"Hi, we have 5 integrations to set up and need real-time sync between Salesforce and Marketo. Our monthly volume is around 30k API calls. Budget is flexible. Which plan do you recommend?"}
EOF

cat > /tmp/inbox_demo/security.json << 'EOF'
{"from":"compliance@healthtech.io","subject":"SOC 2 report for vendor assessment","body":"We are onboarding Nexus as a vendor and our security team requires a copy of your SOC 2 Type II report and information about your HIPAA compliance and data residency options."}
EOF

cat > /tmp/inbox_demo/setup.json << 'EOF'
{"from":"admin@retailco.com","subject":"Salesforce custom fields not showing up","body":"I connected our Salesforce account but several custom fields we created last week are missing from the field mapping screen. How do I get them to appear?"}
EOF

cat > /tmp/inbox_demo/escalate.json << 'EOF'
{"from":"cfo@bigcorp.com","subject":"Enterprise pricing for 200 users","body":"We are a 200-person company looking to deploy Nexus across all departments. We need custom SLAs, EU data residency, SSO, and a dedicated account manager. Can you send pricing?"}
EOF

CASE="${1:-all}"

case "$CASE" in
  1) run_test "PRICING QUESTION" /tmp/inbox_demo/pricing.json ;;
  2) run_test "SECURITY / COMPLIANCE" /tmp/inbox_demo/security.json ;;
  3) run_test "SETUP HELP" /tmp/inbox_demo/setup.json ;;
  4) run_test "ENTERPRISE ESCALATION" /tmp/inbox_demo/escalate.json ;;
  all)
    run_test "1/4 PRICING QUESTION" /tmp/inbox_demo/pricing.json
    run_test "2/4 SECURITY / COMPLIANCE" /tmp/inbox_demo/security.json
    run_test "3/4 SETUP HELP" /tmp/inbox_demo/setup.json
    run_test "4/4 ENTERPRISE ESCALATION" /tmp/inbox_demo/escalate.json
    ;;
  *)
    echo "Usage: bash demo.sh [1|2|3|4]"
    echo "  1 = Pricing question"
    echo "  2 = Security/compliance"
    echo "  3 = Setup help"
    echo "  4 = Enterprise escalation"
    echo "  (no arg) = run all 4"
    ;;
esac
