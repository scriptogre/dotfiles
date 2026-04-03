---
name: todoist
description: Manage Todoist via API. Use when organizing tasks, creating sections, moving tasks between projects, or batch operations. Requires Todoist API token.
---

# Todoist API

> Quick reference for programmatic Todoist access via REST and Sync APIs.

## IMPORTANT: API Version

**The REST v2 and Sync v9 APIs are DEPRECATED and return 410 Gone.**

Use the unified **API v1** instead:
- Base URL: `https://api.todoist.com/api/v1`
- Same endpoints, just different base URL
- Same Bearer token auth

## Authentication

Bearer token in Authorization header. Get token from Settings → Integrations → Developer.

```
Authorization: Bearer <API_TOKEN>
```

## REST API v1

Base URL: `https://api.todoist.com/api/v1`

### Projects
- GET /projects - list all
- GET /projects/{id} - get one
- POST /projects - create (name required)
- POST /projects/{id} - update
- DELETE /projects/{id} - delete

### Sections
- GET /sections?project_id={id} - list sections in project
- POST /sections - create (project_id, name required)
- POST /sections/{id} - update
- DELETE /sections/{id} - delete

### Tasks
- GET /tasks - list all (filter with ?project_id=X or ?section_id=X)
- GET /tasks/{id} - get one
- POST /tasks - create (content required, optional: project_id, section_id, parent_id, priority 1-4, due_string, description)
- POST /tasks/{id} - update (content, description, priority, due_string, labels)
- POST /tasks/{id}/close - complete task
- POST /tasks/{id}/reopen - uncomplete task
- DELETE /tasks/{id} - delete

### Labels
- GET /labels - list all
- POST /labels - create (name required)

### Comments
- GET /comments?task_id={id} - list comments on task
- POST /comments - create (task_id, content required)

## Sync API v1

Base URL: `https://api.todoist.com/api/v1/sync`

Use when REST API is insufficient (moving tasks, bulk operations, reordering).

### Moving Tasks

REST API cannot move tasks between sections/projects. Use Sync API:

```bash
curl -X POST "https://api.todoist.com/api/v1/sync" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "commands": [
      {
        "type": "item_move",
        "uuid": "unique-id-1",
        "args": {"id": "TASK_ID", "section_id": "SECTION_ID"}
      }
    ]
  }'
```

### Bulk Operations

Batch multiple commands in one request:

```json
{
  "commands": [
    {"type": "item_move", "uuid": "a1", "args": {"id": "123", "section_id": "456"}},
    {"type": "item_move", "uuid": "a2", "args": {"id": "124", "section_id": "456"}},
    {"type": "item_complete", "uuid": "b1", "args": {"id": "789"}}
  ]
}
```

Response contains sync_status with ok/error per uuid.

### Common Command Types
- item_add - create task
- item_update - update task
- item_move - move task to section/project
- item_complete - complete task
- item_uncomplete - uncomplete task
- item_delete - delete task
- section_add - create section
- section_update - update section
- section_delete - delete section

## Task Data Model

```json
{
  "id": "9913883968",
  "project_id": "2355268558",
  "section_id": "212462905",
  "parent_id": "9913883858",
  "content": "Task name",
  "description": "Details",
  "priority": 1,
  "due": {"date": "2024-01-15", "string": "tomorrow"},
  "labels": ["label1"]
}
```

Key fields:
- section_id: null = task is in project but not in any section
- parent_id: null = top-level task; set = subtask of that parent
- priority: 1 = no priority, 4 = urgent (red) — inverted scale

## Key Gotchas

1. **REST can't move tasks** - Use Sync API item_move for section/project changes
2. **parent_id creates subtasks** - Tasks with parent_id are nested under that task
3. **section_id: null** - Task is in project but not in any section
4. **priority is inverted** - 4 = urgent (red), 1 = no priority
5. **due_string is natural language** - "tomorrow", "every monday", "jan 15"
6. **Sync API needs UUIDs** - Each command needs unique uuid for status tracking

## Workflows

### List all tasks in a project with their structure

```bash
# Get project ID
curl -s "https://api.todoist.com/api/v1/projects" -H "Authorization: Bearer $TODOIST_API_TOKEN"

# Get all tasks in project
curl -s "https://api.todoist.com/api/v1/tasks?project_id=PROJECT_ID" -H "Authorization: Bearer $TODOIST_API_TOKEN"

# Get sections
curl -s "https://api.todoist.com/api/v1/sections?project_id=PROJECT_ID" -H "Authorization: Bearer $TODOIST_API_TOKEN"
```

Analyze the response:
- Tasks with `parent_id: null` and `section_id: null` are top-level unsectioned tasks
- Tasks with `parent_id` set are subtasks
- Group by section_id to see section membership

### Convert tasks-with-subtasks into sections

When you have tasks acting as "project headers" with subtasks underneath, and want to convert them to proper sections:

1. Identify parent tasks (tasks that have other tasks pointing to them via parent_id)
2. Create a section for each parent task
3. Move subtasks to the new section via Sync API
4. Delete the original parent task

```bash
# Step 1: Create section
curl -s -X POST "https://api.todoist.com/api/v1/sections" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"project_id": "PROJECT_ID", "name": "Section Name"}'

# Step 2: Move subtasks to section (Sync API - can batch multiple)
curl -s -X POST "https://api.todoist.com/api/v1/sync" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "commands": [
      {"type": "item_move", "uuid": "m1", "args": {"id": "SUBTASK_1_ID", "section_id": "NEW_SECTION_ID"}},
      {"type": "item_move", "uuid": "m2", "args": {"id": "SUBTASK_2_ID", "section_id": "NEW_SECTION_ID"}}
    ]
  }'

# Step 3: Delete original parent task
curl -s -X DELETE "https://api.todoist.com/api/v1/tasks/PARENT_TASK_ID" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN"
```

### Create a task with subtasks

```bash
# Create parent task
curl -s -X POST "https://api.todoist.com/api/v1/tasks" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "Parent task", "project_id": "PROJECT_ID"}'
# Note the returned id

# Create subtasks with parent_id
curl -s -X POST "https://api.todoist.com/api/v1/tasks" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "Subtask 1", "parent_id": "PARENT_ID"}'
```

### Batch complete multiple tasks

```bash
curl -s -X POST "https://api.todoist.com/api/v1/sync" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "commands": [
      {"type": "item_complete", "uuid": "c1", "args": {"id": "TASK_1"}},
      {"type": "item_complete", "uuid": "c2", "args": {"id": "TASK_2"}},
      {"type": "item_complete", "uuid": "c3", "args": {"id": "TASK_3"}}
    ]
  }'
```
