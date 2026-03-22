#!/usr/bin/env bash
# setup-eval.sh — Import and configure the Inbox Inferno evaluation in n8n
# Usage: bash setup-eval.sh

set -euo pipefail

# ─────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
step()    { echo -e "\n${BOLD}${CYAN}>>> $*${NC}"; }

# ─────────────────────────────────────────────
# Locate script directory and load .env
# ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  error ".env file not found at $ENV_FILE"
  exit 1
fi

# Load .env (ignore comment lines and blank lines)
set -a
# shellcheck disable=SC2046
eval $(grep -v '^\s*#' "$ENV_FILE" | grep -v '^\s*$' | sed 's/[[:space:]]*$//')
set +a

# ─────────────────────────────────────────────
# Validate required env vars
# ─────────────────────────────────────────────
step "Validating configuration"

if [[ -z "${N8N_HOST:-}" ]]; then
  error "N8N_HOST is not set in .env"
  exit 1
fi

if [[ -z "${N8N_API_KEY:-}" ]]; then
  error "N8N_API_KEY is not set in .env"
  exit 1
fi

if [[ "$N8N_HOST" == "https://your-instance.app.n8n.cloud" ]]; then
  error "N8N_HOST is still set to the placeholder value. Please update .env with your real n8n URL."
  exit 1
fi

# Strip trailing slash from host
N8N_HOST="${N8N_HOST%/}"

success "N8N_HOST: $N8N_HOST"
success "N8N_API_KEY: ${N8N_API_KEY:0:20}..."

# ─────────────────────────────────────────────
# Check for JSON parsing tool
# ─────────────────────────────────────────────
step "Checking for JSON parsing tools"

JSON_TOOL=""
if command -v jq &>/dev/null; then
  JSON_TOOL="jq"
  success "Using jq for JSON parsing"
elif command -v python3 &>/dev/null; then
  JSON_TOOL="python3"
  success "Using python3 for JSON parsing"
else
  error "Neither jq nor python3 found. Please install one of them."
  exit 1
fi

# Helper: extract a JSON field from stdin
json_get() {
  local field="$1"
  if [[ "$JSON_TOOL" == "jq" ]]; then
    jq -r ".$field // empty"
  else
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$field','') or '')"
  fi
}

# ─────────────────────────────────────────────
# Locate workflow JSON
# ─────────────────────────────────────────────
WORKFLOW_FILE="$SCRIPT_DIR/inbox-inferno-workflow.json"
if [[ ! -f "$WORKFLOW_FILE" ]]; then
  error "Workflow file not found at $WORKFLOW_FILE"
  exit 1
fi
success "Workflow file found: $WORKFLOW_FILE"

# ─────────────────────────────────────────────
# Step 1: Import workflow via n8n API
# ─────────────────────────────────────────────
step "Importing workflow to n8n"

# Strip fields not accepted by the API (pinData, meta, active, tags)
WORKFLOW_PAYLOAD=$(python3 -c "
import json, sys
d = json.load(open('$WORKFLOW_FILE'))
clean = {k: d[k] for k in ('name', 'nodes', 'connections', 'settings') if k in d}
print(json.dumps(clean))
")

IMPORT_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$WORKFLOW_PAYLOAD" \
  "$N8N_HOST/api/v1/workflows")

HTTP_STATUS=$(echo "$IMPORT_RESPONSE" | tail -1)
IMPORT_BODY=$(echo "$IMPORT_RESPONSE" | head -n -1)

if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "201" ]]; then
  error "Failed to import workflow (HTTP $HTTP_STATUS)"
  echo "$IMPORT_BODY" >&2
  exit 1
fi

WORKFLOW_ID=$(echo "$IMPORT_BODY" | json_get "id")

if [[ -z "$WORKFLOW_ID" ]]; then
  error "Could not extract workflow ID from response"
  echo "$IMPORT_BODY" >&2
  exit 1
fi

success "Workflow imported successfully. ID: $WORKFLOW_ID"

# ─────────────────────────────────────────────
# Step 2: Activate the workflow
# ─────────────────────────────────────────────
step "Activating workflow"

ACTIVATE_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "$N8N_HOST/api/v1/workflows/$WORKFLOW_ID/activate")

HTTP_STATUS=$(echo "$ACTIVATE_RESPONSE" | tail -1)
ACTIVATE_BODY=$(echo "$ACTIVATE_RESPONSE" | head -n -1)

if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "201" ]]; then
  warn "Could not activate workflow (HTTP $HTTP_STATUS) — activate it manually in the UI"
  echo "$ACTIVATE_BODY" >&2
else
  success "Workflow activated"
fi

# ─────────────────────────────────────────────
# Step 3: Instructions for evaluation setup
# (n8n does not expose test-definitions via public REST API)
# ─────────────────────────────────────────────
step "Evaluation setup — complete in n8n UI"

warn "n8n's evaluation API is not exposed via the public REST API."
warn "Complete these steps in the UI (takes ~2 minutes):"
echo ""
echo -e "  ${BOLD}1.${NC} Open your workflow:"
echo -e "     ${CYAN}$N8N_HOST/workflow/$WORKFLOW_ID${NC}"
echo ""
echo -e "  ${BOLD}2.${NC} Connect an LLM credential to the 3 OpenAI nodes"
echo -e "     (OpenAI - Classify, OpenAI - Draft, OpenAI - Score)"
echo -e "     → click each node → select your model credential"
echo ""
echo -e "  ${BOLD}3.${NC} Create the evaluation:"
echo -e "     → Click ${BOLD}Evaluations${NC} tab at the top of the workflow editor"
echo -e "     → Click ${BOLD}New evaluation${NC}"
echo -e "     → Name it: ${BOLD}Inbox Inferno Evaluation${NC}"
echo -e "     → Save"
echo ""
echo -e "  ${BOLD}4.${NC} Add test cases — import the dataset:"
echo -e "     ${CYAN}$SCRIPT_DIR/Email Test Set/nexus-inbox-inferno-test-dataset.xlsx${NC}"
echo -e "     → In the evaluation, click ${BOLD}Add test cases${NC}"
echo -e "     → Upload the Excel file or paste the 20 rows manually"
echo ""
echo -e "  ${BOLD}5.${NC} Run the evaluation:"
echo -e "     → Click ${BOLD}Run evaluation${NC} in the Evaluations tab"
echo ""

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  CLI Setup Complete!${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Workflow imported & activated${NC}"
echo -e "  ${CYAN}Workflow ID:${NC} $WORKFLOW_ID"
echo -e "  ${CYAN}Workflow URL:${NC} ${BOLD}$N8N_HOST/workflow/$WORKFLOW_ID${NC}"
echo ""
echo -e "  ${YELLOW}Next:${NC} Open the workflow, connect your LLM, then create"
echo -e "  the evaluation in the Evaluations tab (step 3-5 above)."
echo ""
exit 0

# ─────────────────────────────────────────────
# (dead code below — kept for reference if API becomes available)
# ─────────────────────────────────────────────
add_test_case() {
  local payload="$1"
  local label="$2"
  echo "Skipped: $label"
}

# ── Test Case 1.1 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "sarah.mitchell@brighthorizonltd.com",
    "subject": "Help connecting Salesforce",
    "body": "Hi there,\n\nI just signed up for Nexus and I'\''m trying to connect our Salesforce account. When I click \"Connect Salesforce\" it redirects me to login, but then I get an error saying \"Authentication Failed\".\n\nI'\''m using my admin credentials and I'\''m sure the password is correct. Is there something else I need to enable in Salesforce first?\n\nThanks,\nSarah Mitchell\nBright Horizon Consulting"
  },
  "expectedOutput": {
    "expected_category": "setup",
    "expected_action": "Answer using documentation: Salesforce requires a Connected App with OAuth 2.0 and API Enabled permission"
  }
}' "1.1 - Salesforce auth (setup)"

# ── Test Case 1.2 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "michael.obrien@dataflowsolutions.com",
    "subject": "Question about sync timing",
    "body": "Hello,\n\nWe'\''re on the Professional plan and I noticed our Salesforce contacts are syncing to Marketo, but there'\''s about a 10-minute delay. The documentation says Professional plans get real-time sync within 5 minutes.\n\nIs this normal? Do I need to configure something differently to get faster syncing?\n\nBest regards,\nMichael O'\''Brien\nDataFlow Solutions Inc."
  },
  "expectedOutput": {
    "expected_category": "setup",
    "expected_action": "Answer using documentation: Professional plan uses real-time sync via webhooks, typically under 5 minutes"
  }
}' "1.2 - Sync timing (setup)"

# ── Test Case 1.3 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "alex.rivera@horizonecom.com",
    "subject": "Custom field mapping not working",
    "body": "Hi support team,\n\nI'\''m trying to map our custom field \"Customer_Lifetime_Value__c\" from Salesforce to a field in our email platform, but I can'\''t find it in the field mapping dropdown. The field definitely exists in Salesforce and I have access to it.\n\nHow do I get custom fields to show up in Nexus?\n\nThanks,\nAlex Rivera\nHorizon E-commerce Platform"
  },
  "expectedOutput": {
    "expected_category": "setup",
    "expected_action": "Answer using documentation: Settings > Integrations > Refresh Fields, check field-level security in source system"
  }
}' "1.3 - Custom field mapping (setup)"

# ── Test Case 1.4 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "rkim@prismdesign.co",
    "subject": "Just started trial - where do I begin?",
    "body": "Hello,\n\nI just signed up for the 14-day trial and I'\''m feeling a bit overwhelmed. We want to connect HubSpot and Mailchimp, but I'\''m not sure where to start or what the steps are.\n\nIs there a quick start guide or video I can follow?\n\nThanks!\nRebecca Kim\nPrism Design Studios"
  },
  "expectedOutput": {
    "expected_category": "setup",
    "expected_action": "Answer using documentation: 14-day trial info, HubSpot and Mailchimp are supported connectors"
  }
}' "1.4 - Getting started (setup)"

# ── Test Case 2.1 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "margaret.chen@pinnaclefinancial.com",
    "subject": "Encryption standards question",
    "body": "Hi,\n\nOur compliance team is asking about your encryption standards. Specifically:\n1. Is data encrypted at rest and in transit?\n2. What encryption protocols do you use?\n\nWe need this for our internal security review.\n\nThanks,\nMargaret Chen\nCTO, Pinnacle Financial Services"
  },
  "expectedOutput": {
    "expected_category": "security",
    "expected_action": "Answer using documentation: TLS 1.3 in transit, AES-256 at rest, all plans"
  }
}' "2.1 - Encryption standards (security)"

# ── Test Case 2.2 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "aramirez@fortresscyber.com",
    "subject": "SOC 2 report for vendor assessment",
    "body": "Hello Nexus team,\n\nWe'\''re evaluating your platform as part of our vendor assessment process. Can you provide your most recent SOC 2 Type II report? We'\''re prepared to sign an NDA if required.\n\nAlso, do you have ISO 27001 certification?\n\nBest regards,\nAngela Ramirez\nFortress Cybersecurity"
  },
  "expectedOutput": {
    "expected_category": "security",
    "expected_action": "Answer using documentation: SOC 2 Type II available under NDA (security@nexusintegrations.com), ISO 27001 certification pending"
  }
}' "2.2 - SOC 2 report (security)"

# ── Test Case 2.3 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "samantha.lee@odysseyhealthcare.com",
    "subject": "HIPAA compliance verification",
    "body": "Hi,\n\nWe'\''re a healthcare organization and we need to verify that Nexus is HIPAA compliant. We already have an Enterprise plan with you, but we need to ensure our BAA is up to date.\n\nCan someone confirm our HIPAA compliance status and send us the current BAA?\n\nThanks,\nDr. Samantha Lee\nCIO, Odyssey Healthcare Systems"
  },
  "expectedOutput": {
    "expected_category": "security",
    "expected_action": "Answer using documentation: HIPAA available on Enterprise plan, BAA available"
  }
}' "2.3 - HIPAA compliance (security)"

# ── Test Case 2.4 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "mpark@dynastyretail.com",
    "subject": "Quick question about data storage",
    "body": "Hi there,\n\nWhere are your servers located? We'\''re based in California and need to know if our data stays in the US or if it'\''s stored internationally.\n\nAlso, can we choose which region our data is stored in?\n\nThanks,\nMichelle Park\nDynasty Retail Group"
  },
  "expectedOutput": {
    "expected_category": "security",
    "expected_action": "Answer using documentation: US-East Virginia and US-West Oregon primary; Enterprise can request EU or APAC data residency"
  }
}' "2.4 - Data storage location (security)"

# ── Test Case 3.1 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "jordan.taylor@velocitysports.com",
    "subject": "Starter vs Professional - help me decide",
    "body": "Hi,\n\nWe'\''re currently on the Starter plan but we'\''re growing fast. I'\''m trying to understand what we get if we upgrade to Professional.\n\nSpecifically, we need to connect more than 3 integrations soon, and we want faster syncing. What'\''s the real difference between the plans?\n\nJordan Taylor\nVelocity Sports Management"
  },
  "expectedOutput": {
    "expected_category": "pricing",
    "expected_action": "Answer using documentation: Starter 3 integrations vs Professional 10; Starter scheduled sync vs Professional real-time"
  }
}' "3.1 - Plan comparison (pricing)"

# ── Test Case 3.2 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "emily.rodriguez@coastalhealth.org",
    "subject": "Nonprofit pricing?",
    "body": "Hello,\n\nWe'\''re a nonprofit healthcare clinic and we'\''re interested in your Professional plan. Do you offer any discounts for nonprofit organizations?\n\nIf so, what documentation do you need from us?\n\nBest,\nDr. Emily Rodriguez\nCoastal Healthcare Services"
  },
  "expectedOutput": {
    "expected_category": "pricing",
    "expected_action": "Answer using documentation: 25% nonprofit discount available, requires 501(c)(3) documentation"
  }
}' "3.2 - Nonprofit discount (pricing)"

# ── Test Case 3.3 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "bthompson@redrockip.com",
    "subject": "Enterprise pricing for large deployment",
    "body": "Hi Nexus team,\n\nWe'\''re a 500-person investment firm evaluating your platform. We'\''d need:\n- 20+ integrations\n- Around 500,000 API calls per month\n- SSO with our Okta setup\n- Dedicated support\n\nCan you provide Enterprise pricing for this scope? We'\''re also evaluating two competitors, so timeline matters.\n\nBradley Thompson\nManaging Partner, RedRock Investment Partners"
  },
  "expectedOutput": {
    "expected_category": "escalate_sales",
    "expected_action": "Escalate to sales@nexusintegrations.com - do not quote custom pricing"
  }
}' "3.3 - Enterprise pricing (escalate_sales)"

# ── Test Case 3.4 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "jwu@apextech.com",
    "subject": "Question about API limits",
    "body": "Hello,\n\nWe'\''re on Professional plan (50,000 API calls/month) but we'\''re consistently hitting 55,000-60,000 calls. I got an email saying we'\''ll be charged overage fees.\n\nHow much is the overage cost per 1,000 calls? And would it be cheaper to just upgrade to Enterprise?\n\nThanks,\nJennifer Wu\nApex Technologies Group"
  },
  "expectedOutput": {
    "expected_category": "pricing",
    "expected_action": "Answer using documentation: Professional overage is $20 per 1,000 calls; Enterprise is custom pricing"
  }
}' "3.4 - API overage costs (pricing)"

# ── Test Case 4.1 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "danielchen.dev@gmail.com",
    "subject": "Application for Senior Software Engineer position",
    "body": "Dear Hiring Manager,\n\nI am writing to express my interest in the Senior Software Engineer position I saw posted on LinkedIn. I have 8 years of experience in full-stack development with a focus on integration platforms and APIs.\n\nI'\''ve attached my resume and portfolio for your consideration. I'\''m particularly excited about Nexus'\''s mission to simplify business integrations.\n\nLooking forward to hearing from you.\n\nBest regards,\nDaniel Chen\ndanielchen.dev@gmail.com"
  },
  "expectedOutput": {
    "expected_category": "hr",
    "expected_action": "Route to people@nexusintegrations.com"
  }
}' "4.1 - Job application (hr)"

# ── Test Case 4.2 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "thomas.warren@techconsult.io",
    "subject": "Partnership opportunity",
    "body": "Hi Nexus team,\n\nI run a technology consulting firm that works with mid-size businesses. We'\''re always looking for integration solutions to recommend to our clients.\n\nI'\''d like to explore a referral partnership or reseller arrangement. Who should I speak with about this?\n\nThanks,\nThomas Warren\nCEO, Warren Tech Consulting"
  },
  "expectedOutput": {
    "expected_category": "escalate_sales",
    "expected_action": "Escalate to sales@nexusintegrations.com - reseller/partnership inquiry"
  }
}' "4.2 - Partnership (escalate_sales)"

# ── Test Case 4.3 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "sarah.student@university.edu",
    "subject": "Summer internship opportunities",
    "body": "Hello,\n\nI'\''m a computer science student at State University graduating in 2026. I'\''m very interested in API development and integration platforms. Do you offer summer internships?\n\nI'\''d love to learn more about opportunities at Nexus.\n\nThank you,\nSarah Martinez\nsarah.student@university.edu"
  },
  "expectedOutput": {
    "expected_category": "hr",
    "expected_action": "Route to people@nexusintegrations.com"
  }
}' "4.3 - Internship inquiry (hr)"

# ── Test Case 4.4 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "jason@talentscout.com",
    "subject": "Top software engineers available now",
    "body": "Hi there,\n\nI'\''m a technical recruiter with access to amazing software engineering talent. We specialize in placing senior engineers, architects, and engineering managers.\n\nAre you currently hiring? I have 3 excellent candidates available immediately. Let me know if you'\''d like to schedule a call.\n\nBest,\nJason Miller\nTalentScout Recruiting"
  },
  "expectedOutput": {
    "expected_category": "spam",
    "expected_action": "No response needed or brief dismissal"
  }
}' "4.4 - Recruiting spam (spam)"

# ── Test Case 5.1 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "rjameson@summitfinancial.com",
    "subject": "Missing invoice for December",
    "body": "Hi,\n\nOur accounting department is asking about the December invoice. We'\''re on the Starter Annual plan and we should have been billed on December 15th, but we haven'\''t received an invoice yet.\n\nCan you resend it to accounting@summitfinancial.com?\n\nThanks,\nRobert Jameson\nSummit Financial Advisors"
  },
  "expectedOutput": {
    "expected_category": "escalate_finance",
    "expected_action": "Escalate to billing@nexusintegrations.com - invoice request"
  }
}' "5.1 - Missing invoice (escalate_finance)"

# ── Test Case 5.2 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "wfoster@spectrumtelecom.com",
    "subject": "Enterprise contract renewal",
    "body": "Hello,\n\nOur Enterprise contract is up for renewal in March. We'\''d like to discuss renewal terms and potentially adding more integrations.\n\nWho should I contact about this? Should I reach out to our account manager directly?\n\nWilliam Foster\nVP Technology, Spectrum Telecom Group"
  },
  "expectedOutput": {
    "expected_category": "escalate_sales",
    "expected_action": "Escalate to sales@nexusintegrations.com - contract renewal"
  }
}' "5.2 - Contract renewal (escalate_sales)"

# ── Test Case 5.3 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "customer.service@randombank.com",
    "subject": "Your checking account statement",
    "body": "Dear Customer,\n\nYour monthly checking account statement is now available. Please log in to view your statement and recent transactions.\n\nIf you have questions about your account, please contact us at 1-800-BANK-123.\n\nSincerely,\nRandom Bank Customer Service"
  },
  "expectedOutput": {
    "expected_category": "misdirected",
    "expected_action": "Brief reply that email reached wrong company"
  }
}' "5.3 - Bank statement (misdirected)"

# ── Test Case 5.4 ──────────────────────────────────────────────────────────────
add_test_case '{
  "input": {
    "from": "nfoster@clearwaterpharma.com",
    "subject": "Data Processing Agreement needed",
    "body": "Hi Nexus,\n\nWe'\''re in final stages of evaluation and our legal team needs a signed Data Processing Agreement (DPA) that covers GDPR requirements. We'\''re a pharmaceutical company with EU operations.\n\nCan you provide this? We'\''d also need any relevant privacy documentation.\n\nThanks,\nDr. Nathan Foster\nClearwater Pharmaceuticals"
  },
  "expectedOutput": {
    "expected_category": "escalate_legal",
    "expected_action": "Escalate to legal@nexusintegrations.com - DPA/GDPR documentation request"
  }
}' "5.4 - DPA request (escalate_legal)"

echo ""
success "All 20 test cases added"

# ─────────────────────────────────────────────
# Step 5: Trigger evaluation run
# ─────────────────────────────────────────────
step "Triggering evaluation run"

RUN_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "$N8N_HOST/api/v1/test-definitions/$TEST_DEF_ID/run")

HTTP_STATUS=$(echo "$RUN_RESPONSE" | tail -1)
RUN_BODY=$(echo "$RUN_RESPONSE" | head -n -1)

if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "201" && "$HTTP_STATUS" != "202" ]]; then
  warn "Could not trigger evaluation run automatically (HTTP $HTTP_STATUS)"
  warn "You can trigger it manually from the n8n UI."
  echo "$RUN_BODY" >&2
else
  success "Evaluation run triggered"
fi

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Setup Complete!${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Workflow ID:${NC}       $WORKFLOW_ID"
echo -e "  ${CYAN}Test Definition ID:${NC} $TEST_DEF_ID"
echo ""
echo -e "  ${CYAN}View results in n8n:${NC}"
echo -e "  ${BOLD}$N8N_HOST/home/workflows${NC}"
echo ""
echo -e "  ${CYAN}Workflow direct link:${NC}"
echo -e "  ${BOLD}$N8N_HOST/workflow/$WORKFLOW_ID${NC}"
echo ""
echo -e "  ${CYAN}Test Definitions:${NC}"
echo -e "  ${BOLD}$N8N_HOST/settings/test-definitions${NC}"
echo ""
echo -e "  To re-run the evaluation, use:"
echo -e "  ${BOLD}curl -X POST -H 'X-N8N-API-KEY: \$N8N_API_KEY' \\"
echo -e "    $N8N_HOST/api/v1/test-definitions/$TEST_DEF_ID/run${NC}"
echo ""
