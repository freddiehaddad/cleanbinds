# Clean Binds

Custom action-bar keybinding labels for World of Warcraft: Forever beta.
Targets client **1.60.1.69977**, Interface **16001**.

## Features

The native UI is available at **Options -> AddOns -> Clean Binds**, with pages
for Action Bars 1-8, Pet Bar, and Stance Bar. It shows real bindings with editable
label previews, keyboard navigation, reset confirmation, and combat read-only
behavior.

**Labels are session-only on this beta.** Edits update the settings table, preview,
and real action buttons. Actual keybindings are never changed by the addon.

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

## Usage

1. Run `/cleanbinds`, or open **Esc -> Options -> AddOns -> Clean Binds**.
2. Select the action bar containing the button you want to customize.
3. Click its **Custom label** cell, type a label such as `MWD`, and press Enter.

The action-button name and current binding are read-only. Hover the binding to
see its full text and any additional assigned keys. Only the custom label changes.

Tab/Shift-Tab accepts an edit and moves between label fields. Clicking elsewhere
also accepts; Escape cancels the current edit. Clear a field to restore the
native label. A preview shows the label at a shared magnification, preserving
native button and font proportions. Oversized labels warn but remain allowed.

Use **Reset This Bar** to clear one bar's overrides, or **Reset All Labels** on
the parent page to clear every override. Both require confirmation. Turning off
**Enable custom labels** restores native text without discarding your labels.

## Supported bars

Pet and Stance pages remain available when their bars are inactive. Stance Bar
contains Blizzard's **Special Action Buttons**, with their distinct
`SHAPESHIFTBUTTON1` through `SHAPESHIFTBUTTON10` bindings.

There is no separate Possess page. Possession actions that reuse the main action
buttons use their labels.

Vehicle/override displays use the first six main action-bar bindings. They have
no separate settings page and inherit those buttons' labels. This mapping has
source and automated coverage, but **vehicle entry has not been verified in game**.

Third-party action bars, extra-action/totem/flyout buttons, appearance controls,
profiles, and other WoW clients are outside the current scope.

## Label behavior

Labels belong to individual buttons, not spells or globally renamed keys. Empty
or whitespace-only labels restore the default. Long labels are allowed with a
fit warning; text is preserved as UTF-8 and displayed literally.

Within a session, a committed change to a button's displayed binding clears its
label. Secondary-only changes keep the label when the displayed key is unchanged.
Canceled binding edits, loading binding sets, and changing input devices do not
clear labels. An override prepared for an unbound button becomes active on its
first binding.

Custom text follows native hotkey refreshes without changing fonts, colors,
positions, alpha, or visibility. Unbound buttons retain native range indicators.
Clearing an override or disabling custom labels restores the latest native text.
Stance labels use the existing hotkey region even without a normal-bar refresh
method; their original native text is restored when the override is removed.

Changes are applied to the addon's data table immediately. WoW writes that data
on reload/logout, but the beta loader limitation prevents reliable restoration.
Labels edited after a pending rebind are associated with the new binding rather
than being cleared when that binding is saved.

All edit/reset controls are read-only during combat. Invalid saved entries are
reported and preserved, not silently deleted. A confirmed Reset All Labels also
removes invalid entries; resetting one bar leaves other bars alone.

Use `/cleanbinds status` for the client and native bar inventory. Unavailable
special bars are reported explicitly. No chat output is produced during normal
startup unless a compatibility or data error needs attention.

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
transactions, capability errors, bar mapping, live text restoration, range
indicators, and restricted-frame handling. Mocked SavedVariables tests verify
behavior when data is supplied; they do not establish that the beta loader works.

For in-game verification, keep checks within one session on this beta:

1. Confirm distinct `MWD`/`MWU` labels on real buttons without changing bindings.
2. Clear an override and toggle the addon setting off/on; verify native/custom
   text restoration.
3. Rebind a labeled spare button through WoW, save, and confirm its override
   clears to the new native text. Secondary-only or canceled changes retain it.
4. Exercise Pet/Stance buttons, paging/form changes, combat refreshes, editing
   lockout, and another UI scale. Restore changed bindings and UI scale afterward.
5. When available, check main-bar labels in vehicle/override states. Record an
   unavailable state as unverified, not passed.

Recheck reload, relog, restart, and cross-character persistence after Blizzard
fixes the loader; only then remove or revise the session-only notices.
