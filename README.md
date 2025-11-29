# Firefox Local Addon Manager

Automatically load local Firefox addons without manually installing via `about:debugging` each time.

Perfect for running personal/private addons daily that you don't want to publish.

## How It Works

Uses **Firefox AutoConfig** to automatically load addons as temporary extensions on startup:
- Calls `AddonManager.installTemporaryAddon()` on Firefox startup (same as about:debugging)
- **No signature checking required** - temporary addons are allowed
- Auto-reinstalls config after Firefox updates
- Addons load automatically every time Firefox starts

## Requirements

- Firefox Developer Edition, Nightly, or stable (all versions work)
- Bash shell
- macOS (Linux support could be added relatively easily)
- Local addon files (.xpi, .zip, or directories with manifest.json)

## Quick Start

```bash
# 1. Set up AutoConfig
./firefox-addon-loader.sh setup

# 2. Add your addons
./firefox-addon-loader.sh add ~/dev/my-addon
./firefox-addon-loader.sh add ~/downloads/another-addon.xpi

# 3. Start Firefox (addons auto-load)
./firefox-addon-loader.sh start
```

## Commands

- `setup` - Install AutoConfig into Firefox
- `add <path>` - Add addon to auto-load list
- `remove <path>` - Remove addon from list
- `list` - Show configured addons and installation status
- `status` - Show detailed status information
- `start` - Launch Firefox (auto-checks/fixes config)
- `help` - Show help message

## Examples

```bash
# Initial setup
./firefox-addon-loader.sh setup

# Add addons
./firefox-addon-loader.sh add ~/dev/my-firefox-addon
./firefox-addon-loader.sh add ~/projects/addon.xpi

# List configured addons
./firefox-addon-loader.sh list

# Start Firefox (auto-loads all configured addons)
./firefox-addon-loader.sh start

# Check installation status
./firefox-addon-loader.sh status

# Remove addon
./firefox-addon-loader.sh remove ~/dev/my-addon
```

## Firefox Updates

When Firefox updates, the AutoConfig files inside the app bundle get removed. The tool handles this automatically:

**Option 1: Use the launcher**
```bash
./firefox-addon-loader.sh start
```
The script checks if AutoConfig is installed and reinstalls it automatically before launching Firefox.

**Option 2: Manual reinstall**
```bash
./firefox-addon-loader.sh setup
```
This reinstalls the AutoConfig files without changing your addon list.

## How AutoConfig Works

The tool creates these files inside Firefox.app:
- `Firefox.app/Contents/Resources/defaults/pref/config-prefs.js` - Tells Firefox to load AutoConfig
- `Firefox.app/Contents/Resources/autoconfig.js` - Loads your addons on startup

When Firefox starts, AutoConfig runs and calls `AddonManager.installTemporaryAddon()` for each configured addon - exactly what you were doing manually via about:debugging.

## Development Workflow

```bash
# Add your addon once
./firefox-addon-loader.sh add ~/dev/my-addon

# Start Firefox
./firefox-addon-loader.sh start

# Edit your addon code...
# Reload addon in Firefox: about:debugging > Reload

# Your changes are immediately reflected (no need to re-add)
```

## Advantages Over Other Approaches

**vs. Installing into profile's extensions directory:**
- ✅ No signature checking required
- ✅ Works on all Firefox versions (not just Developer/Nightly)
- ✅ Addons are truly temporary (clean uninstall)

**vs. Manual about:debugging:**
- ✅ Fully automated
- ✅ Addons load on every Firefox start
- ✅ No clicking "Load Temporary Addon" repeatedly

**vs. Publishing to AMO:**
- ✅ Keep your addons private
- ✅ No review process
- ✅ Perfect for personal/experimental addons

## Notes

- Addons load as **temporary** (same as about:debugging)
- Must restart Firefox after adding/removing addons
- After Firefox updates, use `./firefox-addon-loader.sh start` to auto-fix
- Addon paths are stored in `.addon-list.txt` (one path per line)
- AutoConfig files are auto-generated from `autoconfig/autoconfig.js.template`

## Troubleshooting

**AutoConfig not working after Firefox update?**
```bash
./firefox-addon-loader.sh setup  # Reinstalls AutoConfig
```

**Addon not loading?**
- Check it's in the list: `./firefox-addon-loader.sh list`
- Verify path exists and contains valid manifest.json
- Check Firefox console for errors: Tools > Browser Console

**Want to see AutoConfig logs?**
- Open Firefox Browser Console: Tools > Browser Console
- Look for messages from "[AutoConfig Addon Loader]"

## Technical Details

The script stores templates in `autoconfig/`:
- `config-prefs.js` - Firefox preference file
- `autoconfig.js.template` - Template for addon loading code

When you add/remove addons:
1. Updates `.addon-list.txt`
2. Generates `autoconfig.js` from template with your addon paths
3. Copies files into Firefox.app

When Firefox starts:
1. Reads `config-prefs.js` and loads `autoconfig.js`
2. AutoConfig waits for `final-ui-startup` event
3. Loads each addon via `AddonManager.installTemporaryAddon()`

## Licence

MIT
