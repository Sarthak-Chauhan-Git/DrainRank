# DrainRank Municipal Corporation Dashboard — Build Plan for AI Coding Agents

> **Purpose:** Use this file as the implementation brief and source of truth when building the DrainRank municipal operations dashboard. Build a clean, usable prototype first, with working flows and synthetic demo data. Do not imply integrations, AI capabilities, or municipal actions are real unless they have actually been implemented.

## 1. Product Summary

DrainRank is a civic-tech platform that helps municipal teams manage drainage complaints, prioritise inspections and cleaning, assign field crews, review completion evidence, and track outcomes after rainfall.

The municipal dashboard is the internal operations workspace. It must let an authorised officer move from a complaint to a decision, work order, evidence review, and follow-up without losing context.

### Core operating loop

**Citizen report → incident review and grouping → evidence assessment → separate inspection/cleaning prioritisation → work order and crew assignment → field updates → evidence review → monitoring → post-rain outcome assessment → follow-up action**

### Product principles

1. **Action-oriented, not chart-heavy:** every key metric or alert should take the user to a useful filtered list or relevant record.
2. **Explainable decisions:** show why a priority is recommended and which evidence supports it.
3. **Human accountability:** AI or rules can recommend, flag, or summarise; authorised staff make operational decisions.
4. **Separate condition from workflow status:** a drain's observed condition, a work order's status, evidence review status, and post-rain outcome are different fields.
5. **Uncertainty is explicit:** missing or poor evidence must not be interpreted as proof of blockage or proof that a task failed.
6. **Traceability:** record important status changes, overrides, assignments, evidence decisions, and reasons.
7. **Honest demo:** clearly label synthetic data and simulated AI output.
8. **Progressive delivery:** prioritise a complete, functional end-to-end flow over many unfinished pages.

## 2. Scope and Non-Goals

### In scope for the prototype

- Municipal dashboard overview
- Complaint and incident management
- Drain registry and map/table view
- Separate inspection and cleaning priority queues
- Crew directory, assignment, and work-order tracking
- Completion evidence review
- Monitoring and post-rain outcome tracking
- Reports, filtering, CSV export, activity history
- Basic user roles and settings UI where feasible
- Seeded data and resettable demo scenarios
- Local persistence so demo interactions survive refresh

### Not required for the first demo

- Real municipal system integration
- Real citizen notifications or SMS delivery
- Live GPS tracking of crews
- A trained computer-vision model
- Automatic claims about flooding causality
- Production authentication, unless the project already has it
- Real citizen or municipal data

Do not add these as fake implementations. Use labelled placeholders when necessary.

## 3. Recommended Technology

Use the existing project stack if it is already configured. Otherwise, prefer:

- React + TypeScript + Vite
- Tailwind CSS
- shadcn/ui where available
- Lucide React icons
- React Router
- Recharts for simple charts
- Leaflet + OpenStreetMap for a map, with a fallback schematic if map tiles are unavailable
- LocalStorage for a standalone demo
- A clear data-access layer so LocalStorage can later be replaced with an API/database

Avoid requiring API keys or paid services for the prototype. Keep the project runnable throughout development.

## 4. Information Architecture and Navigation

Use a compact left sidebar. Main navigation should contain these sections:

1. **Overview**
2. **Complaints & Incidents**
3. **Drains & Map**
4. **Priority Queue**
5. **Work Orders**
6. **Evidence Review**
7. **Monitoring & Outcomes**
8. **Reports & Analytics**
9. **Administration**

Global header:

- Current corporation/ward scope selector (demo can use Ward 12)
- Global search for drain, complaint, location, incident, or work-order ID
- Notifications/inbox indicator
- Help/demo mode indicator
- User profile/role menu

Do not create a separate top-level page for every tiny action. Use tabs, filters, drawers, and modals where that keeps related work together.

## 5. UX and Visual Design Requirements

### Visual style

- Professional civic operations interface
- Deep navy for navigation and branding
- Teal as the primary action accent
- Neutral light workspace with subtle borders and limited shadows
- Red for urgent attention, amber for pending/uncertain, teal/blue for active states, green for accepted/verified states
- Consistent typography, spacing, icons, and status chips
- Desktop-first but usable on tablets and mobile screens
- Avoid excessive gradients, oversized cards, decorative animation, and visual clutter

### Usability requirements

- Every major page has a clear title, one-line purpose, and primary action
- Search and relevant filters appear at the top of list pages
- Tables have loading, empty, and error states
- Status labels and colors remain consistent throughout the app
- Actions that change or reject work require confirmation when appropriate
- Forms validate required fields and show field-level errors
- Important actions show a success/error toast and update visible state
- Clicking a KPI or alert opens a relevant filtered list
- Detail views preserve context and offer links to linked records
- Do not use color alone to communicate status
- Avoid dead buttons, placeholder navigation, and blank pages
- Make synthetic/demo records visually distinguishable from real records

## 6. Main Page Requirements

### 6.1 Overview

Purpose: show what needs attention right now.

Include KPI cards for:

- Registered drains
- Open incidents
- High-priority incidents requiring review
- Pending inspections
- Open cleaning work orders
- Overdue tasks
- Evidence awaiting review
- Persistent post-rain issues requiring follow-up

Also include:

- **Needs Attention** list: urgent reports, overdue tasks, evidence mismatches, repeated waterlogging, high-priority unassigned work
- Small ward map preview or location summary
- Recent activity timeline
- Simple charts only when they inform action (e.g. work-order status, incident categories)
- Quick actions: Create/Review Incident, Create Work Order, Record Observation

Metric counts must derive from current application data, not hardcoded values. Clicking a metric should open the matching filtered view.

### 6.2 Complaints & Incidents

Purpose: review incoming reports and group reports that refer to one real-world incident.

List/table fields:

- Report ID and linked incident ID
- Issue type
- Location / ward / drain ID if known
- Received time
- Urgency flag
- Evidence state
- Current status
- Assigned officer or next action

Required actions:

- Search and filter by ward, issue type, date, status, and urgency
- Open full report details
- View attached images and location details
- Link a report to an existing incident or create an incident
- Mark a possible duplicate without deleting the original report
- Add a triage note
- Recommend inspection, cleaning, monitoring, or further review
- Link an incident to an existing work order or create a work order
- Reopen an incident if new evidence shows the problem persists

Duplicate grouping should not create duplicate work orders. Complaint count is supporting context only; it must not be the sole priority factor. A credible, high-consequence single report can still deserve prompt review.

### 6.3 Drains & Map

Purpose: provide a reliable drain/asset register and spatial view.

Each drain record should support:

- Unique drain ID
- Display name / landmark
- Ward
- Coordinates or a clearly marked approximate/manual location
- Drain type and physical attributes, where known
- Current observed condition: clear, partial blockage, blocked, waterlogging observed, or unknown
- Evidence freshness and latest observation date
- Last inspection and cleaning dates
- Linked complaints/incidents
- Linked work orders and evidence decisions
- Recurring issue history
- Monitoring status and next check date

Views and actions:

- Map view and table view
- Search by ID/name/location
- Filter by ward, condition, priority, monitoring status, and overdue follow-up
- Click map markers to open a drain summary drawer
- Open full drain history

Do not invent true coordinates or infrastructure details. If the demo map uses approximate/synthetic points, label them as demo locations. If map tiles fail, show a usable schematic/list fallback.

### 6.4 Priority Queue

Purpose: organise work that needs a decision or allocation.

Provide distinct tabs/queues:

- Inspection queue
- Cleaning queue
- Monitoring/follow-up queue

Each row should show:

- Drain ID and location
- Recommended action
- Score and queue type
- Main contributing factors
- Evidence age/quality
- Consequence/context summary
- Incident and report count as supporting context
- Current assignment and time waiting
- Actions: open details, assign/create work order, defer with reason

Suggested prototype formulas, if no better validated model is available:

**Cleaning score:** `M = 100 × (0.40B + 0.35A + 0.25V)`

**Inspection score:** `I = 100 × (0.40U + 0.35A + 0.25V)`

Where:

- `B`: estimated visible blockage, 0–1
- `U`: evidence uncertainty/information gap, 0–1
- `A`: normalised catchment/area proxy, 0–1
- `V`: documented consequence, 0–1

These weights are provisional prototype assumptions, not validated operational risk models. Show score breakdown and a visible caveat. Never compare inspection and cleaning scores as if they were the same measure. Missing evidence increases uncertainty; it must not automatically imply a blocked drain.

Required behaviours:

- Sort/filter within a queue
- Recalculate when component values change
- Show reasons for recommendation
- Allow authorised manual override with required reason
- Record override and score-change history
- Defer tasks with a reason and optional review date
- Preserve emergency/safety escalation independent of normal score ordering

### 6.5 Work Orders

Purpose: manage field operations from assignment through completion submission.

Work-order fields:

- Work-order ID
- Linked drain and incident/report
- Task type: inspection, cleaning, reinspection, monitoring, or engineering investigation
- Priority/urgency and reason
- Assigned crew
- Created, assigned, due, started, and submitted timestamps where applicable
- Instructions and notes
- Work status
- Before/after evidence references
- Review decision and follow-up link

Recommended status lifecycle:

`Unassigned → Assigned → In Progress → Completion Submitted → Under Review → Accepted`

Alternative outcomes:

- `Rework Required`
- `Cancelled` (with reason and permission)
- `Deferred` (with reason and review date)

Required functions:

- Create work order from a complaint, incident, or priority item
- Assign/reassign crew and set target date/instructions
- Check basic crew role compatibility and warn about excessive active workload
- Start work and submit field findings
- Submit completion claim with notes and after-photo placeholder/upload
- Filter by status, crew, ward, due date, task type, and priority
- Highlight overdue tasks
- Show linked complaint, drain, evidence, and outcome history on a single detail page

Crew assignment in the prototype is a record update, not real dispatch or tracking.

### 6.6 Evidence Review

Purpose: review whether completion evidence supports the work claim.

Review panel should show:

- Work-order ID, drain ID, location, and task type
- Before/after image preview or clear placeholder
- Submitted notes
- Timestamp and available location metadata
- Evidence quality state
- Location consistency state
- Observed after-work condition
- Previous reviewer notes and history

Review flags:

- Missing evidence
- Unusable/unclear image
- Potential location mismatch
- Timestamp concern
- After-condition suggests work may remain incomplete
- Insufficient information to decide

Actions:

- Accept evidence
- Request rework
- Flag for further review / keep pending

Rules:

- Require a reason for rework or override
- Confirmation required before accepting/rejecting consequential evidence
- Record reviewer identity (demo role if authentication is not implemented), timestamp, decision, reason, and previous state
- Location mismatch is a review flag, not proof of fraud or misconduct
- Acceptance means the submitted evidence supports the stated completion at the observed location/time; it does not prove downstream capacity or overall flood prevention
- If accepted evidence shows the drain visually clear, move it to Monitoring where appropriate
- If evidence is inadequate, keep it pending or request clarification rather than silently accepting it

### 6.7 Monitoring & Outcomes

Keep this as one navigation section with tabs:

1. Current Monitoring
2. Post-Rain Observations
3. Recurring Issues

#### Current Monitoring

- Current/latest observed condition
- Last inspection/cleaning date
- Evidence freshness
- Next follow-up date and overdue checks
- Observation history
- Add observation action

#### Post-Rain Observations

Observation fields:

- Drain/location
- Rain event or observation date/time (if known)
- Observation source: citizen, field inspector, or other recorded source
- Waterlogging: observed / not observed / not checked
- Drain visible condition: clear / partial blockage / blocked / unknown
- Photo and notes
- Related incident and maintenance work order

#### Recurring Issues / Outcome Intelligence

- Repeated blockage at the same drain
- Waterlogging reported again after cleaning
- Previous accepted completion evidence and subsequent observations
- Frequency and dates of recurrences
- Suggested next action: reinspection, repeat cleaning, or engineering investigation
- Create follow-up work order

Important reasoning rules:

- Monitoring records observations; Outcome Intelligence compares them to work and incident history and suggests next steps.
- Waterlogging after cleaning does not automatically prove the cleaning crew failed.
- A clear-looking drain with renewed waterlogging may need investigation of downstream capacity, surface runoff, slope, connected drainage, or rainfall conditions.
- Do not assert causal explanations based on a single observation.
- “Not observed” is different from “confirmed absent”; “not checked” is different from both.
- Avoid calling an asset permanently healthy based on one clear image.

### 6.8 Reports & Analytics

Provide useful, filterable reports:

- Incoming complaints by time, ward, and issue type
- Open incidents and ageing
- Work-order status and overdue counts
- Assignment-to-start and report-to-action times (only when timestamps exist)
- Evidence accepted/rework/flagged counts
- Repeat blockage and post-rain waterlogging locations
- Outcomes after maintenance
- Priority ranking compared with independent inspection findings, if ground-truth data exists
- Audit/override report

Requirements:

- Filter by date range, ward, issue type, crew, and status where applicable
- Export current table to CSV
- Printable view or PDF export only if feasible
- Label synthetic values as synthetic
- Do not present demo data as real operational performance or claim the scoring model is validated
- Do not infer causal impact from simple before/after counts alone

### 6.9 Administration

Include only the administration features that are appropriate to the available stack:

- User/role list and role labels
- Ward list and configuration
- Crew directory and role/type
- Priority weights and reason-code configuration
- Task type and status configuration
- Notification preferences/placeholders
- Data reset/export controls for demo
- System/help/about information

If real authentication is not implemented, label role switching as demo-only and do not claim it provides security. Do not build a misleading fake login flow that looks production-secure.

## 7. Roles and Permissions

Design for these roles, even if prototype authentication is simulated:

- **Municipal Administrator:** manage wards, teams, users, and system configuration
- **Ward Officer:** review incidents, approve priorities, create/assign work orders, and override recommendations with reasons
- **Field Inspector:** record inspection findings, condition observations, and evidence
- **Cleaning Crew:** view assigned tasks and submit work updates/completion evidence
- **Evidence Reviewer:** review completion submissions, accept, request rework, or flag concerns
- **Analyst:** view and export reports

Enforce permissions in the actual backend when one exists. A frontend-only role selector is not access control.

## 8. Suggested Data Model

Create typed models and keep business logic out of presentation components. Exact field names may vary, but maintain the relationships.

### Drain

- `id`, `name`, `wardId`, `locationLabel`
- `latitude?`, `longitude?`, `locationAccuracy?`
- `drainType?`, `attributes?`
- `currentCondition`, `lastObservedAt?`, `evidenceFreshness`
- `lastInspectedAt?`, `lastCleanedAt?`
- `monitoringStatus`, `nextCheckAt?`
- `createdAt`, `updatedAt`

### CitizenReport

- `id`, `incidentId?`, `drainId?`
- `issueType`, `description`, `wardId`, `locationLabel`
- `latitude?`, `longitude?`, `photoRefs[]`
- `urgencyFlag`, `submittedAt`, `reporterRef?`
- `status`, `triageNotes?`

### Incident

- `id`, `primaryDrainId?`, `wardId`, `locationLabel`
- `reportIds[]`, `issueType`, `status`, `urgencyLevel`
- `priorityRecommendation?`, `assignedOfficer?`
- `createdAt`, `updatedAt`, `closedAt?`, `reopenedAt?`

### PriorityAssessment

- `id`, `drainId`, `queueType` (`inspection` or `cleaning`)
- `blockageScore?`, `uncertaintyScore?`, `catchmentProxy?`, `consequenceScore?`
- `score`, `reasonCodes[]`, `evidenceRefs[]`, `isProvisional`
- `createdAt`, `createdBy` (`system` or user reference)
- `overrideScore?`, `overrideReason?`, `overriddenBy?`, `overriddenAt?`

### Crew

- `id`, `name`, `crewType`, `availabilityStatus`
- `activeWorkOrderIds[]`, `maxActiveTasks?`, `contactRef?`

### WorkOrder

- `id`, `drainId`, `incidentId?`, `sourceReportIds[]`
- `taskType`, `priorityAssessmentId?`, `priorityLabel?`
- `assignedCrewId?`, `createdBy`, `dueAt?`, `startedAt?`, `submittedAt?`
- `status`, `instructions?`, `fieldNotes[]`
- `completionEvidenceId?`, `reviewDecisionId?`
- `createdAt`, `updatedAt`, `deferredReason?`, `cancelReason?`

### EvidenceItem

- `id`, `workOrderId?`, `drainId`, `evidenceType` (`before`, `after`, `inspection`, `post_rain`)
- `imageRef?`, `caption?`, `capturedAt?`, `uploadedAt`
- `latitude?`, `longitude?`, `locationVerificationStatus`
- `qualityStatus`, `conditionAssessment?`, `assessmentMode` (`manual`, `simulated`, `model`)
- `submittedBy`, `createdAt`

### EvidenceReview

- `id`, `workOrderId`, `evidenceIds[]`
- `decision` (`accepted`, `rework_required`, `flagged`, `pending`)
- `reasonCodes[]`, `reviewerNotes?`, `reviewerId`
- `reviewedAt`, `previousDecision?`

### Observation

- `id`, `drainId`, `incidentId?`, `workOrderId?`
- `sourceType`, `observedAt?`, `recordedAt`
- `visibleCondition`, `waterloggingStatus`
- `rainEventRef?`, `imageRefs[]`, `notes?`
- `followUpRecommended`, `createdBy`

### ActivityLog

- `id`, `entityType`, `entityId`, `action`
- `actorId?`, `actorRole?`, `timestamp`, `reason?`
- `beforeSummary?`, `afterSummary?`

### Persistence requirements

- Use stable IDs and explicit relationships; do not rely on array indexes as IDs.
- Store timestamps in ISO 8601 format.
- Validate values at form boundaries.
- Keep derived counts and charts derived from canonical data.
- For LocalStorage, version the storage schema and provide a safe reset/seed path.
- Keep a repository/service interface so LocalStorage can later be replaced by API calls without rewriting UI pages.

## 9. Seeded Demo Scenario

Use fictional records and label the environment as **Synthetic Demo Data**.

Suggested five drains:

- **DR-A — Hospital Access Road:** partial visible blockage; high documented consequence; cleaning recommended.
- **DR-B — Residential Drain:** severe visible blockage; cleaning recommended; seed one completion submission with a possible location mismatch.
- **DR-C — Central Underpass:** evidence uncertain; high consequence; inspection recommended; later record waterlogging after rain.
- **DR-D — Dead-End Lane:** visible blockage but lower documented consequence; cleaning queue/deferred depending on available crews.
- **DR-E — Park Lane:** recent usable image appears clear; monitoring status.

Suggested example scores using the provisional formulas:

- DR-A cleaning: `B=0.50`, `A=1.00`, `V=1.00` → `M=80.00`
- DR-B cleaning: `B=1.00`, `A=0.75`, `V=0.40` → `M=76.25`
- DR-C inspection: `U=1.00`, `A=0.60`, `V=0.80` → `I=81.00`
- DR-D cleaning: `B=1.00`, `A=0.46`, `V=0.30` → `M=63.60`
- DR-E: monitoring; no cleaning score unless newer evidence supports one

Seed an end-to-end demonstration:

1. Open overview and inspect high-priority list.
2. Open DR-C and show why it needs inspection due to uncertainty and consequence.
3. Open DR-B's evidence review and show a synthetic location mismatch.
4. Request rework or flag it for further review; add an audit entry.
5. Assign a crew to a cleaning/inspection work order and advance its status.
6. Submit a new synthetic observation that reports waterlogging at DR-C after rain.
7. Show Monitoring recording the observation and Outcome Intelligence recommending follow-up inspection/infrastructure investigation.
8. Create a follow-up work order and show it in the task queue.

Do not claim that the demo has contacted a real crew, analysed a real photo with AI, or recorded an actual municipal action.

## 10. Interaction and Business Rules

1. All major buttons must perform real state changes, navigation, or open a functional form/modal.
2. Saving a new report or work order updates the relevant dashboard counts and lists.
3. Search and filters must act on current application data.
4. A single incident can have multiple reports but should not automatically create duplicate work orders.
5. Accepting evidence updates the work-order review status and creates an activity log record.
6. Requesting rework returns the task to an actionable queue and records the reason.
7. New observations should link to a drain and, where possible, the prior incident/work order.
8. Repeated post-cleaning waterlogging should trigger a follow-up recommendation, not an automatic allegation of crew failure.
9. Manual priority overrides must record who changed the recommendation and why.
10. Score calculations should be pure, tested functions, separate from UI components.
11. Scores must update when input data changes; avoid stale duplicated values.
12. If data is missing, show “Unknown”, “Not recorded”, or “Needs verification”, not a misleading zero or inferred state.
13. Guard consequential actions with confirmation and clear feedback.
14. Reset/restore-demo-data actions must ask for confirmation.
15. Seed/reset operations should be deterministic so the demo returns to the same initial state.

## 11. Non-Functional Requirements

- No broken routes or blank pages
- No console errors in the main demo path
- Strong TypeScript types; avoid `any` unless unavoidable and documented
- Reusable components for tables, filters, status chips, detail drawers, empty states, and confirmation dialogs
- Accessible form labels, keyboard support, readable contrast and mobile layouts
- Graceful map failure fallback
- Safe handling of malformed or absent optional fields
- Reasonable performance on a typical laptop
- No API secrets committed to the repository
- Do not use real personal data in seeded content
- If using image assets, use safe demo assets or placeholders and avoid implying generated photos are evidence from real jobs

## 12. AI Coding Agent Instructions

Agents should follow these rules while implementing:

1. **Inspect the existing repository first.** Identify the framework, routes, existing components, installed dependencies, and current data handling before making major changes.
2. **Keep changes aligned with the current project.** Do not replace a working stack without a clear reason.
3. **Build in small, runnable increments.** After each major feature, run the available typecheck, lint, build, and tests.
4. **Start with shared design primitives.** Implement layout, sidebar, header, buttons, status chips, form controls, tables, detail drawers, notifications, and confirmation dialogs before duplicating them across pages.
5. **Keep business logic separate.** Place score calculations, duplicate grouping, status transitions, and metrics derivation in typed utility/service modules.
6. **Create typed mock data and services.** Do not hardcode separate values into each page. Use one data source and derived selectors.
7. **Complete workflows end to end.** A saved action must update data, visible metrics, activity history, and linked records as appropriate.
8. **No fake functionality.** If an action is a placeholder, label it clearly. Do not show fake success toasts for actions that did not occur.
9. **Avoid overbuilding.** Do not implement production authentication, complex AI, live tracking, or municipal integrations before the primary flows work.
10. **Avoid broad, unrelated refactors.** Keep the diff focused and preserve existing working features.
11. **Report honestly.** At the end, list implemented pages/flows, tests/build results, known limitations, and any remaining nonfunctional controls.
12. **Do not remove the demo reset.** The project must be easy to restore to the initial judge scenario.

## 13. Recommended Implementation Phases

### Phase 0 — Repository audit and plan

- Inspect repository and current app
- Confirm stack and run commands
- List current routes/components and broken interactions
- Propose a short implementation checklist

### Phase 1 — App shell and data layer

- Main sidebar/header and responsive layout
- Shared components and status styles
- Typed entities and deterministic synthetic seed data
- LocalStorage repository, schema versioning, reset/restore
- Activity log helper and derived KPI selectors

### Phase 2 — Overview and core records

- Overview metrics and actionable alerts
- Complaints/incidents list and detail drawer
- Drain table and map/fallback
- Search, sort, filters, empty states

### Phase 3 — Priority and work execution

- Inspection and cleaning queues
- Pure score calculation helpers and explanations
- Work-order creation and crew assignment
- Status progression, deadlines, workload warnings

### Phase 4 — Verification and outcomes

- Before/after evidence review
- Accept/rework/flag actions with audit log
- Monitoring observations
- Post-rain outcome records and recurring issue links
- Follow-up work-order creation

### Phase 5 — Reporting and polish

- Reports/charts and CSV export
- Administration/demo settings
- Responsive/accessibility pass
- Test full judge demo and restore scenario
- Fix console, typecheck, lint, and build errors

If the deadline is short, do not start Phase 5 until the core end-to-end flow works.

## 14. Acceptance Criteria

The prototype is ready for demonstration when all of the following are true:

- [ ] App opens to a populated Overview page with visibly labelled synthetic data.
- [ ] All nine navigation sections open a working page or a clearly scoped tab set.
- [ ] Global search finds relevant drain/report/work-order records.
- [ ] Complaint list supports filtering and opening a report detail.
- [ ] Multiple reports can link to one incident without duplicate work orders being created automatically.
- [ ] Drain records show condition, latest observation, and history.
- [ ] Inspection and cleaning priorities appear in separate queues with score explanations.
- [ ] Updating inputs recalculates derived scores correctly.
- [ ] Officer override/defer action requires and saves a reason.
- [ ] A work order can be created, assigned to a compatible crew, started, and submitted for review.
- [ ] Evidence reviewer can accept, request rework, or flag a submission.
- [ ] The review decision and reason appear in the activity history.
- [ ] A new post-rain observation can be recorded and linked to the appropriate drain and prior work.
- [ ] The app flags repeated waterlogging and allows a follow-up task to be created.
- [ ] Dashboard counts and charts update after mutations.
- [ ] Filters and CSV export work on current data.
- [ ] Refreshing the browser preserves saved demo changes.
- [ ] Reset/restore returns the data to the original seeded scenario.
- [ ] No main-path action is a dead button or fake confirmation.
- [ ] Typecheck/build (and available lint/tests) succeed.
- [ ] Known limitations are documented, particularly simulated AI and synthetic data.

## 15. Final Priority Rule

When time or implementation capacity is constrained, prioritise the following five flows in order:

1. **Complaint → Incident review**
2. **Incident/Drain → Explainable priority queue**
3. **Priority item → Crew-assigned work order**
4. **Work order → Evidence review and audit trail**
5. **Post-rain observation → Outcome assessment → Follow-up task**

A clean, working end-to-end system is more valuable than a large dashboard with static charts and nonfunctional controls.
