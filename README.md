# DrainRank — Team Git Workflow

Repository: https://github.com/Sarthak-Chauhan-Git/DrainRank

This guide gives the Git commands for the four team-owned modules:

1. **Citizen App** — `apps/citizen-android/`
2. **Field App** — `apps/field-android/`
3. **Priority Queue** — `backend/priority-queue/`
4. **Monitoring System** — `backend/monitoring-system/`

The municipal corporation web dashboard and evidence page are maintained by the repository owner. Those areas are intentionally excluded from the contributor commands below.

## Team rules

- `main` is for stable releases. Do not work directly on it.
- `develop` is the integration branch. Feature branches start from `develop`; pull requests target `develop`.
- Every developer uses their own feature branch and works primarily in their assigned directory.
- Stage only your module's directory. Avoid `git add .`, which can include unrelated changes.
- Never push directly to `main` or `develop`, and do not use `git push --force`.
- Get the required review and passing checks before merging a pull request.
- Branches and directories reduce interference, but Git does not technically prevent a developer from editing another directory. Follow ownership boundaries and get the other module owner's agreement before changing shared files.

All commands below are for **Windows PowerShell**. Run repository commands from the local `DrainRank` root unless indicated otherwise.

---

## 0. First-time setup — every team member

Install Git, then clone the repository once:

```powershell
git --version
git clone https://github.com/Sarthak-Chauhan-Git/DrainRank.git
cd DrainRank
git remote -v
git fetch origin
git switch --track origin/develop
```

The last command creates your local `develop` branch tracking `origin/develop`. If you already have a local `develop` branch, use:

```powershell
git switch develop
git pull origin develop
```

If you already have a local repository, **do not clone it again**. Open PowerShell in that repository and follow the relevant module section.

---

## 1. Citizen App

**Directory:** `apps/citizen-android/`  
**Feature branch:** `feature/citizen-app`

### Create your feature branch (one time)

Run from the repository root:

```powershell
git switch develop
git pull origin develop
git switch -c feature/citizen-app
```

### Work in your module

```powershell
cd apps/citizen-android
```

Make changes inside this directory. When ready to commit, return to the repository root:

```powershell
cd ../..
git status
git add apps/citizen-android/
git commit -m "feat(citizen-app): implement citizen app changes"
git push -u origin feature/citizen-app
```

Create a pull request with base **`develop`** and compare **`feature/citizen-app`**:

https://github.com/Sarthak-Chauhan-Git/DrainRank/compare/develop...feature/citizen-app?expand=1

---

## 2. Field App

**Directory:** `apps/field-android/`  
**Feature branch:** `feature/field-app`

### Create your feature branch (one time)

Run from the repository root:

```powershell
git switch develop
git pull origin develop
git switch -c feature/field-app
```

### Work in your module

```powershell
cd apps/field-android
```

Make changes inside this directory. When ready to commit, return to the repository root:

```powershell
cd ../..
git status
git add apps/field-android/
git commit -m "feat(field-app): implement field app changes"
git push -u origin feature/field-app
```

Create a pull request with base **`develop`** and compare **`feature/field-app`**:

https://github.com/Sarthak-Chauhan-Git/DrainRank/compare/develop...feature/field-app?expand=1

---

## 3. Priority Queue

**Directory:** `backend/priority-queue/`  
**Feature branch:** `feature/priority-queue`

### Create your feature branch (one time)

Run from the repository root:

```powershell
git switch develop
git pull origin develop
git switch -c feature/priority-queue
```

### Create the module directory if it does not exist

```powershell
New-Item -ItemType Directory -Force -Path backend/priority-queue
New-Item -ItemType File -Force -Path backend/priority-queue/README.md
```

Put priority queue logic and its tests inside this directory. Document the module's purpose, inputs, outputs, and how to test it in its README.

### Commit and push

```powershell
git status
git add backend/priority-queue/
git commit -m "feat(priority-queue): add priority queue module"
git push -u origin feature/priority-queue
```

Create a pull request with base **`develop`** and compare **`feature/priority-queue`**:

https://github.com/Sarthak-Chauhan-Git/DrainRank/compare/develop...feature/priority-queue?expand=1

---

## 4. Monitoring System

**Directory:** `backend/monitoring-system/`  
**Feature branch:** `feature/monitoring-system`

### Create your feature branch (one time)

Run from the repository root:

```powershell
git switch develop
git pull origin develop
git switch -c feature/monitoring-system
```

### Create the module directory if it does not exist

```powershell
New-Item -ItemType Directory -Force -Path backend/monitoring-system
New-Item -ItemType File -Force -Path backend/monitoring-system/README.md
```

Keep monitoring logic, health checks, and tests in this directory. Coordinate shared API changes with the relevant owner before modifying files outside your module.

### Commit and push

```powershell
git status
git add backend/monitoring-system/
git commit -m "feat(monitoring): add monitoring system module"
git push -u origin feature/monitoring-system
```

Create a pull request with base **`develop`** and compare **`feature/monitoring-system`**:

https://github.com/Sarthak-Chauhan-Git/DrainRank/compare/develop...feature/monitoring-system?expand=1

---

## 5. Everyday workflow after your branch already exists

Replace `YOUR_BRANCH` with your branch name, such as `feature/citizen-app`.

```powershell
git switch YOUR_BRANCH
git status
git pull origin YOUR_BRANCH
```

Make your changes in your own module. Then stage only that module, commit, and push. Use the matching commands from your module section above. For example, the Citizen App developer uses:

```powershell
git add apps/citizen-android/
git commit -m "feat(citizen-app): describe your change"
git push
```

If Git says `nothing to commit`, check `git status` to see whether any files have changed.

---

## 6. Bring the latest `develop` changes into your feature branch

Do not merge another developer's feature branch directly into yours. Get integrated changes from `develop`. First commit or safely back up your own work.

```powershell
git switch develop
git pull origin develop
git switch YOUR_BRANCH
git merge develop
```

If there are merge conflicts, resolve them carefully and run your module's tests before committing. If you are unsure which change to keep, ask the relevant module owner instead of overwriting their work.

---

## 7. Creating a new module later

Agree on the directory name, module owner, and branch name with the team. Example for a future backend module called `drain-analytics`:

```powershell
git switch develop
git pull origin develop
git switch -c feature/drain-analytics
New-Item -ItemType Directory -Force -Path backend/drain-analytics
New-Item -ItemType File -Force -Path backend/drain-analytics/README.md
```

Implement the module, then commit and push only its directory:

```powershell
git add backend/drain-analytics/
git commit -m "feat(drain-analytics): scaffold new module"
git push -u origin feature/drain-analytics
```

Open a pull request into `develop`. If the repository has a `CODEOWNERS` file, ask the maintainer to add the new directory's owner in the same pull request.

---

## 8. Useful safety checks

```powershell
# Which branch am I on?
git branch --show-current

# Which files have changed?
git status

# Review changes before staging
git diff

# List local branches
git branch

# Refresh information about remote branches
git fetch origin

# View recent commits
git log --oneline -8
```

Do not commit passwords, API keys, Android signing keys, `.env` files, or machine-specific configuration.

## Quick reference

| Module | Directory | Branch | Pull request target |
|---|---|---|---|
| Citizen App | `apps/citizen-android/` | `feature/citizen-app` | `develop` |
| Field App | `apps/field-android/` | `feature/field-app` | `develop` |
| Priority Queue | `backend/priority-queue/` | `feature/priority-queue` | `develop` |
| Monitoring System | `backend/monitoring-system/` | `feature/monitoring-system` | `develop` |

The municipal corporation web dashboard and evidence page remain under the repository owner's responsibility. Contributors should not modify those areas unless a change has been explicitly coordinated.
