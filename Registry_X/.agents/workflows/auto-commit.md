---
description: auto-commit and push all changes to GitHub after completing work
---

After completing any feature, fix, or set of changes for the user, ALWAYS run the following steps automatically without being asked:

1. Check for uncommitted changes:
```
cd /Users/federico.joly/Desktop/Dev/Registry_X && git status --short
```

2. If there are modified/new files, stage them all:
```
git add -A
```

3. Commit with a descriptive message following conventional commits format (feat/fix/chore/refactor):
```
git commit -m "feat/fix: short summary

- bullet point describing each change"
```

4. Push to origin:
```
git push
```

Do this at the end of every conversation task — after the build passes and the feature is delivered. Never ask the user if they want to commit; just do it.
