# Inbox Inferno — AI Email Agent

An AI-powered email classification and response agent built in n8n for the [Inbox Inferno evaluation challenge](https://docs.n8n.io/courses/). It reads incoming customer emails, classifies them into one of 9 categories, drafts accurate replies grounded in company documentation, and includes a built-in evaluation path that scores performance using LLM-as-judge.

**Result: 20/20 on the test dataset.**

---

## What It Does

- **Classifies** incoming emails into 9 categories: `setup`, `pricing`, `security`, `hr`, `spam`, `misdirected`, `escalate_sales`, `escalate_finance`, `escalate_legal`
- **Drafts replies** grounded exclusively in Nexus Integrations' documentation — pricing tables, security certifications, connector lists, setup guides
- **Escalates** when appropriate — routes enterprise inquiries, legal requests, and billing issues to the right team with the correct contact email
- **Evaluates itself** — a second LLM call acts as judge, scoring each test case 0 or 1

---

## Workflow Architecture

```
PRODUCTION PATH
Webhook → Set-Prod → Build Classify Prompt → Claude-Classify → Parse Category
                                                                      ↓
                              Respond to Webhook ← Route by Mode ← Parse Reply ← Claude-Draft ← Build Reply Prompt

EVALUATION PATH
Evaluation Trigger → Set-Eval → [same middle nodes] → Route by Mode
                                                              ↓
                               Record Score ← Parse Score ← Claude-Score ← Build Score Prompt
```

The same classification and drafting logic runs in both paths. The evaluation path adds a scoring layer at the end — no simplified version, no shortcuts.

---

## Setup

### Prerequisites
- n8n instance (Pro or self-hosted)
- Anthropic API key

### Deploy

```bash
git clone https://github.com/kaiser-data/inbox-inferno.git
cd inbox-inferno

cp .env.example .env
# Edit .env with your credentials
nano .env

bash setup-eval.sh
```

### Environment Variables

```bash
N8N_HOST=https://your-instance.app.n8n.cloud
N8N_API_KEY=your_n8n_api_key
ANTHROPIC_API_KEY=your_anthropic_api_key
```

After running `setup-eval.sh`, open your n8n instance, open the workflow, and connect the Anthropic credential to the three Claude nodes (Claude-Classify, Claude-Draft, Claude-Score).

---

## Demo

```bash
export N8N_WEBHOOK_URL=https://your-instance.app.n8n.cloud/webhook/inbox-inferno

bash demo.sh        # run all 4 demo cases
bash demo.sh 1      # pricing question
bash demo.sh 2      # security / compliance
bash demo.sh 3      # setup help
bash demo.sh 4      # enterprise escalation → routes to sales
```

### Example output (pricing)

```json
{
  "category": "pricing",
  "draft_reply": "Hi Alice, based on your requirements I'd recommend the Professional plan...
  Marketo is a Premium connector — available only on Professional and above..."
}
```

---

## How Replies Are Grounded

The `Build Reply Prompt` node embeds the full Nexus Integrations documentation directly into Claude's prompt for answerable categories (`setup`, `pricing`, `security`). Claude is instructed to answer **only** from the provided documentation — no hallucination, no invented pricing, no made-up certifications.

The documentation is sourced from the Excel files in `/Nexus Integrations Company Dataset/`:

| File | Contents |
|------|----------|
| `nexus-pricing-plans.xlsx` | All 3 plans with every field |
| `nexus-product-integrations.xlsx` | 31 connectors across Standard / Premium / Enterprise tiers |
| `nexus-security-approved-responses.xlsx` | 15 pre-approved compliance Q&As |
| `nexus-product-knowledge.xlsx` | 24 general product Q&As |
| `nexus-escalation-rules.xlsx` | Routing rules and contact emails |

For escalation categories, the agent uses routing templates pointing to the correct team email (`sales@`, `billing@`, `legal@`, etc.) rather than attempting to answer.

---

## Evaluation

The workflow includes a built-in evaluation path using n8n's native evaluation system.

To run:
1. In n8n UI → **Evaluations** tab → **New Evaluation**
2. Select the workflow, add the 20 test cases from `Email Test Set/nexus-inbox-inferno-test-dataset.xlsx`
3. Input fields: `from`, `subject`, `body` — Expected output: `expected_category`
4. Click **Run Evaluation**

Each test case is scored 0 or 1 by a separate Claude call acting as judge. n8n aggregates the results automatically.

---

## Tech Stack

- **n8n** — workflow orchestration
- **Claude Opus** (`claude-opus-4-6`) — classification, drafting, scoring
- Temperature `0` for classification and scoring, `0.3` for reply drafting

---

## Repository Structure

```
├── inbox-inferno-workflow.json          # n8n workflow (import via setup-eval.sh)
├── inbox-inferno-workflow-template.json # original challenge template
├── setup-eval.sh                        # deploys workflow via n8n API
├── demo.sh                              # demo script with 4 test cases
├── Email Test Set/
│   └── nexus-inbox-inferno-test-dataset.xlsx   # 20 labelled test emails
└── Nexus Integrations Company Dataset/
    ├── nexus-pricing-plans.xlsx
    ├── nexus-product-integrations.xlsx
    ├── nexus-security-approved-responses.xlsx
    ├── nexus-product-knowledge.xlsx
    ├── nexus-escalation-rules.xlsx
    └── nexus-customer-list.xlsx
```
