# Phase 15: Interview Preparation — Mock Interview & Study Lab Exercises

---

## Lab 1: Timed System Design Drill

**Objective**: Practice the 6-part framework under time pressure.

Pick one of these prompts and give yourself exactly 20 minutes total (5 min requirements/architecture, 15 min deep-dive):
1. Design a pipeline ingesting IoT sensor data (high volume, near-real-time) into a Lakehouse for anomaly detection.
2. Design a customer 360 pipeline combining CRM, support tickets, and web analytics data.
3. Design a pipeline supporting both nightly batch reporting and ad hoc analyst SQL queries on the same underlying data.

### Deliverable
- [ ] Write a 1-page architecture summary covering all 6 framework sections (requirements, architecture, reliability, CI/CD, cost/performance, security).
- [ ] Identify the 2 areas you'd expect an interviewer to probe deepest, and pre-write your deep-dive answer for those.

---

## Lab 2: Rapid-Fire Concept Explanations (60-Second Drill)

Set a timer for 60 seconds per concept and explain out loud (record yourself if possible) without notes:
- [ ] Lakehouse architecture
- [ ] Control plane vs data plane
- [ ] Delta Lake transaction log & ACID
- [ ] Medallion architecture
- [ ] Shuffle and why it's expensive
- [ ] Unity Catalog grant hierarchy
- [ ] Jobs vs DLT
- [ ] Watermarking
- [ ] Photon
- [ ] Asset Bundles / CI/CD flow
- [ ] MLflow Tracking + Registry

### Deliverable
- [ ] Note which explanations felt shaky or ran over time — go back to that phase's notes.md and re-read before your next drill session.

---

## Lab 3: Debug-This Scenario Practice

For each symptom below, verbally walk through your diagnostic steps as if explaining to an interviewer:
1. "Our Spark job that processes 10GB daily suddenly started taking 3x longer with no data volume change."
2. "A user with SELECT granted on a table still gets 'table or view not found.'"
3. "Our monthly Databricks bill doubled but our data volume only grew 10%."
4. "A retried Job run created duplicate rows in the target table."
5. "A streaming job's processing is falling further behind every hour."

### Deliverable
- [ ] For each scenario, write down the specific commands/UI locations you'd check first (e.g., `system.billing.usage`, Spark UI Stages tab, `SHOW GRANTS`).

---

## Lab 4: Build Your Own Question Bank

**Objective**: Consolidate the interview-qa.md files from all 15 phases into a personal weak-spots list.

1. Skim through every `interview-qa.md` file across Phase 01-14.
2. For each ⭐ question, self-rate your confidence (1-5) answering it cold, without looking.
3. List the bottom 10 lowest-confidence questions.

### Deliverable
- [ ] A prioritized list of 10 questions to specifically restudy before your next mock interview session.
- [ ] Re-attempt those same 10 questions 3-4 days later and re-rate confidence — track improvement.

---

## Lab 5: Behavioral Story Bank (STAR Format)

Prepare 4 stories in Situation-Task-Action-Result format covering:
1. A production incident you diagnosed and resolved.
2. A time you improved pipeline cost or performance with measurable impact.
3. A disagreement about technical approach that you helped resolve.
4. A time you had to explain a technical concept to a non-technical stakeholder.

### Deliverable
- [ ] Write each story in under 90 seconds of spoken length (roughly 200-230 words).
- [ ] Ensure each story includes a concrete, ideally quantified, result (e.g., "reduced job runtime from 2 hours to 20 minutes," "cut monthly compute cost by $4,000").

---

## Lab 6: Full Mock Interview Simulation

**Objective**: Simulate a complete interview loop in one sitting (~90 minutes).

1. Technical screen (15 min): 3-4 rapid Q&A from Phases 1-4.
2. Deep-dive technical (25 min): 1 system design question (Phase 15 Lab 1 style) + 2-3 debugging scenarios.
3. Behavioral (20 min): 2 STAR stories from your bank (Lab 5).
4. Reverse interview (10 min): Prepare 3 thoughtful questions to ask your interviewer about their data platform/team.
5. Self-review (20 min): Write down what went well and what needs more work.

### Deliverable
- [ ] A completed self-review with at least 3 specific action items for continued study before a real interview.
