---
description: Start working on a story from Azure Boards
---

I am about to start working on a new story from Azure Boards. Here is the story ID: $1

### Phase 1: Pre-computation
- Get the title of the story from Azure Boards using the story ID. The title will be used to create a new branch.
- Get the description of the story from Azure Boards using the story ID.

### Phase 2: Pre-flight Checks
1. Check if the git working directory is clean.
2. If it is not clean, ask if you want to stash your changes.
    - If yes, stash them.
    - If no, abort the process.

### Phase 3: Git Setup
1. Once the working directory is clean, fetch the latest changes from the develop branch and merge them into the current branch.
2. Create a new branch with the name in the format `<story_id>/<short-description>`, where `<short-description>` is a slugified version of the story title.
3. Switch to the new branch.

### Phase 4: Story Details
- Print the title and the description of the story. If the description is empty, say so.

To get the title, you can use this command:
`/opt/homebrew/bin/az boards work-item show --id $1 --fields "System.Title" --query "fields.\"System.Title\"" --expand none`

To get the description, you can use this command:
`/opt/homebrew/bin/az boards work-item show --id $1 --fields "System.Description" --query "fields.\"System.Description\"" --expand none`

### Phase 5: Environment Setup
1. Ask if you want to reset the local database.
    - If yes, run the `scripts/local-db-reset` script.
2. Run the `scripts/validate` script to make sure everything is set up correctly.

After that, let's start planning the work for this story.

Here are the tools you have available to you:
- bash: to run shell commands
- az: to interact with Azure DevOps
- git: to interact with git
