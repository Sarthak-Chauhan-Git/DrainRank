export const drainRankKnowledge = `
Verified DrainRank product and workflow reference:

PRODUCT PURPOSE
DrainRank is a municipal drainage operations dashboard that tracks drainage complaints and assets from report intake through prioritization, field work, evidence review, and recorded outcomes. It supports staff decisions; it does not dispatch crews, inspect drains, or change real-world conditions by itself.

CURRENT APPLICATION STATE
This version uses seeded sample records and browser local storage. It is not connected to Supabase, a production backend, authenticated roles, or database row-level security. Do not claim the current application has those capabilities. The local Qwen assistant receives only an allowlisted subset of drainage work fields through the local development API.

NAVIGATION AND PURPOSE
- Overview (/overview): operational summary and dashboard measures.
- Drain Map (/map): geographic view of drainage records and reports.
- Work Queues (/queues): inspection and cleaning queues; staff can assign available work to crews.
- Work Orders (/work-orders): view and track assigned work items and deadlines.
- Evidence Review (/evidence): manual reviewer workflow for completion evidence. The AI does not approve or verify evidence.
- Drain Intelligence (/monitoring): ranked drainage case list, explanations, follow-up recommendations, case history, and status tracking.
- Reports (/reports): issue-mix and report-lifecycle charts; the lifecycle categories are Open, Duplicate, and Resolved. Ward and submission-date filters apply to the report list. The report table shows report ID, issue, ward, priority, and submission time. “Export reports CSV” includes drain ID, reporter name, issue type, ward, location, priority, and submission time; that identity field is private, and the local sample app currently has no role/auth checks for exports. A separate log area exports activity-log CSV. Do not claim the report table contains work-order or outcome detail.
- Crew Management (/crew-management): sample crew and worker management.
- Logs (/logs): recorded operational activity and credit audit information.
- Administration (/administration): local sample-data reset and clear controls.

CASE PROCESS
1. A complaint/report is recorded with a drainage asset, issue type, location/ward, description and provisional priority. Reporter identity and free-text description are private and must not be sent to the AI.
2. A case is prioritized using the existing score and available asset/complaint history. The monitoring intelligence view applies a recurrence adjustment of up to 18 points (3 per additional linked non-duplicate complaint plus 6 per prior persistent outcome); it clamps the displayed score to 0..100. This displayed score is a prioritization aid, not a probability or guaranteed response time.
3. Cleaning/inspection work is assigned through the work queues. A recorded deadline can identify overdue work.
4. Evidence is reviewed manually in the Evidence Review page. AI recommendations are advisory and must never be described as evidence approval.
5. Outcome records capture observed before/after and post-rain results and may recommend a future follow-up.

CASE STATUS MEANINGS
- Cleaning Recommended: available information supports routing to cleaning; verify the condition in the field.
- Inspection Required: gather field evidence before deciding the appropriate work.
- Assigned: a work item is assigned; the status alone does not prove the work is complete.
- Pending Review: completion evidence is awaiting manual review; it is not yet reviewer-approved.
- Rework Required: submitted work or evidence needs correction and another review.
- Monitoring: continue observation; it does not mean the asset can never recur.
- Reviewed: a reviewer accepted the recorded evidence.
- Resolved: the case is marked resolved in the app; a later observation can still reveal recurrence.
These are the complete DrainStatus values in this application. Report statuses are a separate set: Open, Duplicate, and Resolved. Outcome labels are also separate historical observations (Resolved, Partially Resolved, Persisted, or Not Observed) and do not replace the current case status.

PRIORITY DISPLAY
Scores are bounded from 0 to 100. In Drain Intelligence, 80+ is red/high, 60 through 79 is yellow/medium, and below 60 is green/low. The displayed Drain Intelligence score equals the existing base priority plus a recurrence adjustment, capped at 100; the adjustment is up to 18 points (3 per additional linked non-duplicate complaint plus 6 per prior persistent outcome). Higher scores indicate higher relative operational priority in the current records, not a probability, guaranteed severity, or response time. Do not apply these Drain Intelligence color bands to other screens unless their own UI explicitly does so.

ASSISTANT LIMITS
Answer DrainRank product/workflow questions using this reference and the supplied records. Distinguish verified product behavior from case-specific records and recommendations. Exact counts come from the current supplied application data, not model memory; count questions are answered deterministically from that data. If a detail is not covered here or in supplied records, explicitly say it is not available rather than guessing. Never reveal, infer, or request reporter/citizen/worker personal data or claim an AI action was performed.
`.trim();
