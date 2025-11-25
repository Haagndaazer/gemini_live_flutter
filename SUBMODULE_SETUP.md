# Git Submodule Setup

This package is designed to be used as a Git submodule for easy sharing across multiple Flutter apps.

## Repository
```
https://github.com/Haagndaazer/gemini_live_flutter.git
```

## Setup Instructions

### First Time Setup (When Phase 1 Complete)

1. **Initialize Git repository in package directory:**
```bash
cd lib/packages/gemini_live
git init
git add .
git commit -m "Initial commit - Gemini Live Flutter package"
```

2. **Add remote and push:**
```bash
git remote add origin https://github.com/Haagndaazer/gemini_live_flutter.git
git branch -M main
git push -u origin main
```

3. **Convert to submodule in this app:**
```bash
cd ../../..  # Back to app root
rm -rf lib/packages/gemini_live/.git  # Remove local git
git rm -r --cached lib/packages/gemini_live
git submodule add https://github.com/Haagndaazer/gemini_live_flutter.git lib/packages/gemini_live
git commit -m "Convert gemini_live to submodule"
```

### Adding to Other Apps

In your other Flutter app:
```bash
git submodule add https://github.com/Haagndaazer/gemini_live_flutter.git lib/packages/gemini_live
git submodule init
git submodule update
```

### Updating Package Across Apps

**When you make changes to the package:**
```bash
# In this app (SimpleEMDR)
cd lib/packages/gemini_live
git add .
git commit -m "Update: description of changes"
git push origin main
cd ../../..
git add lib/packages/gemini_live
git commit -m "Update gemini_live submodule"
```

**To pull updates in other app:**
```bash
# In your other app
cd lib/packages/gemini_live
git pull origin main
cd ../../..
git add lib/packages/gemini_live
git commit -m "Update gemini_live to latest version"
```

## Benefits

✅ **Single source of truth** - One codebase for both apps
✅ **Version control** - Track package versions independently
✅ **Easy updates** - Pull changes across all apps
✅ **Clean separation** - Package development isolated from app

## Import Path

Once set up, import from:
```dart
import 'package:simple_emdr/packages/gemini_live/gemini_live.dart';
```

Or in your other app:
```dart
import 'package:your_app/packages/gemini_live/gemini_live.dart';
```

## Status

- ⏸️ **Pending**: Complete Phase 1 implementation first
- ⏸️ **Then**: Set up as separate Git repository
- ⏸️ **Finally**: Convert to submodule in both apps
