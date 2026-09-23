# Clean Binds

Custom action-bar keybinding labels for World of Warcraft: Forever beta.
Targets client **1.60.1.69977**, Interface **16001**.

## Development status

The native UI is available at **Options -> AddOns -> Clean Binds**, with pages
for Action Bars 1-8, Pet Bar, and Stance Bar. It shows real bindings with editable label
previews, keyboard navigation, reset confirmation, and combat read-only behavior.

**Label edits are currently temporary and do not change action bars.** Persistent
labels and live action-bar rendering are subsequent implementation steps. Actual
keybindings are never changed by the addon.

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

These checks cover startup, saved-data preservation, capability errors, and bar
mapping. Native rendering and protected gameplay behavior require in-game review.
