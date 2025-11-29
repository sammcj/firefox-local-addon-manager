# AutoConfig Template Files

These files are used to generate the Firefox AutoConfig configuration.

## Files

- **config-prefs.js** - Tells Firefox to load the AutoConfig system
- **autoconfig.js.template** - Template for the addon loader (copied to Firefox.app)
- **autoconfig.js** - Generated file (git-ignored, auto-created from template)

## How It Works

When you run `./firefox-addon-loader.sh add <path>`:

1. Addon path is added to `.addon-list.txt`
2. Script generates `autoconfig.js` from `autoconfig.js.template`
3. Both config files are copied into Firefox.app:
   - `config-prefs.js` → `Firefox.app/Contents/Resources/defaults/pref/`
   - `autoconfig.js` → `Firefox.app/Contents/Resources/`

When Firefox starts:

1. Reads `config-prefs.js` which tells it to load `autoconfig.js`
2. `autoconfig.js` waits for browser startup to complete
3. Loads each addon via `AddonManager.installTemporaryAddon()`

## Modifying the Template

If you need to modify how addons are loaded, edit `autoconfig.js.template`.

The placeholder `// ADDON_PATHS_PLACEHOLDER` is replaced with the addon paths from `.addon-list.txt`.
