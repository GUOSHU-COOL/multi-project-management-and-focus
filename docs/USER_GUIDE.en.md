# Multi-Project Management & Focus | User Guide

## 1. What it is for

This native macOS app is for people moving several research, work, or personal projects forward while keeping each day small and clear. It keeps long-term direction visible without turning life into a pressure-driven checklist.

## 2. Core workflow

1. Create a project with a name, description, and icon.
2. Build a task tree in the plan view. Tasks can be nested without a fixed depth limit.
3. Drag a planned task into Today. Long-term routines and spontaneous tasks join the same TodayTask list.
4. Reorder, edit, complete, or drag a task to the removal area. Removing it from Today does not delete the project plan.
5. Use the mind map to inspect structure, reparent tasks, place nodes manually, or add relationship lines.
6. Use the four-quadrant view to clarify priority and start a focus timer when needed.

## 3. AI and privacy

AI never edits the archive directly. It returns `AIProposal` / `TaskOperation` values; the app validates UUIDs, project ownership, tree cycles, and operation scope, then shows a preview. Changes happen only after confirmation. API keys are stored only in the macOS Keychain.

## 4. Data and backup

The workspace is stored at `~/Library/Application Support/CloudPlan/workspace.json` and written atomically after every change. Copy that file to back it up. Never commit a workspace containing personal records to a public repository.

## 5. Build and verification

```bash
swift test
./scripts/build-app.sh
```

Before release, check both 1240×780 and the minimum 760×560 window sizes. Every AI write operation should have an operation kind, validator, preview text, and tests.
