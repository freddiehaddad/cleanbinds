# Clean Binds

Custom action-bar keybinding labels for World of Warcraft: Forever beta.
Targets client **1.60.1.69977**, Interface **16001**.

## Development status

The native UI is available at **Options -> AddOns -> Clean Binds**, with pages
for Action Bars 1-8, Pet Bar, and Stance Bar. It shows real bindings with editable label
previews, keyboard navigation, reset confirmation, and combat read-only behavior.

**Labels are session-only on this beta, and live action-bar rendering is not
implemented yet.** Edits update the settings table and preview. Actual keybindings
are never changed by the addon.

## Beta persistence limitation

In build 69977, the client wrote CleanBinds' SavedVariables correctly but did not
load them before addon initialization. Labels can therefore disappear after
`/reload`, relogging, or restarting WoW. The UI warns about this limitation.

This matches the [SavedVariables loader issue reported for the Forever beta](https://eu.forums.blizzard.com/en/wow/t/forever-beta-160169913-savedvariables-fail-to-load-on-client-startupreload-%E2%80%94-all-addon-settings-reset-on-restart/629888).
Standard account-wide SavedVariables support is retained, but persistence and
cross-character sharing are deferred until the client loader is working and
verified. No external workaround, custom file loader, or background tool is used.

## Installation

Place this directory at:

```text
C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\CleanBinds
```

`CleanBinds.toc` must be directly inside that folder. A Windows directory junction
to the development directory can be used instead of copying files.

Restart the client after first installation and enable **Clean Binds** in the
AddOns list. Use `/reload` after subsequent Lua changes.

## UI checkpoint

Run `/cleanbinds` to open the native settings category, then select an action bar.
Click a custom-label cell to edit it. Enter, Tab, or clicking elsewhere accepts;
Escape cancels. Clear a field to restore its default preview. Labels that are too
wide receive a warning but can still be used.

Pet and Stance pages remain available when their bars are inactive. Stance Bar
contains Blizzard's **Special Action Buttons**, with their distinct
`SHAPESHIFTBUTTON1` through `SHAPESHIFTBUTTON10` bindings.

There is no separate Possess page. Possession actions that reuse the main action
buttons use their labels.

Vehicle/override displays use the first six main action-bar bindings. They have
no separate settings page and will inherit those buttons' labels.

## Label behavior

Labels belong to individual buttons, not spells or globally renamed keys. Empty
or whitespace-only labels restore the default. Long labels are allowed with a
fit warning; text is preserved as UTF-8 and displayed literally.

Within a session, a committed change to a button's displayed binding clears its
label. Secondary-only changes keep the label when the displayed key is unchanged.
Canceled binding edits, loading binding sets, and changing input devices do not
clear labels. An override prepared for an unbound button becomes active on its
first binding.

Changes are applied to the addon's data table immediately. WoW writes that data
on reload/logout, but the beta loader limitation prevents reliable restoration.
Labels edited after a pending rebind are associated with the new binding rather
than being cleared when that binding is saved.

All edit/reset controls are read-only during combat. Invalid saved entries are
reported and preserved, not silently deleted. A confirmed Reset All Labels also
removes invalid entries; resetting one bar leaves other bars alone.

Use `/cleanbinds status` for the client and native bar inventory. Unavailable
special bars are reported explicitly; their existence alone does not establish
label support. Invalid saved data is preserved and reported rather than reset.

## Development checks

Run from the project root with Lua 5.1 or a compatible interpreter:

```powershell
lua tests\run.lua
```

If Neovim is already installed, its LuaJIT interpreter can run the same checks:

```powershell
nvim --clean --headless -l tests\run.lua
```

These checks cover startup, saved-data preservation, label validation, binding
transactions, capability errors, and bar mapping. Native rendering and protected
gameplay behavior require in-game review.
