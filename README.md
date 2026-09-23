# Clean Binds

Custom action-bar keybinding labels for World of Warcraft: Forever beta.
Targets client **1.60.1.69977**, Interface **16001**.

## Development status

The addon foundation is implemented: client compatibility checks, account-wide
saved-data initialization, a native bar inventory, and a diagnostic slash command.
It does **not yet** provide a settings page or change action-bar labels.

The intended UI is **Options -> AddOns -> Clean Binds**, with a page per action
bar and editable per-button labels. Labels will be shared across characters;
actual keybindings will not be changed by the addon.

## Installation

Place this directory at:

```text
C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\CleanBinds
```

`CleanBinds.toc` must be directly inside that folder. A Windows directory junction
to the development directory can be used instead of copying files.

Restart the client after first installation and enable **Clean Binds** in the
AddOns list. Use `/reload` after subsequent Lua changes.

## Foundation checkpoint

Run `/cleanbinds` or `/cleanbinds status` after logging in. It reports the client
version and the available native button counts. Unavailable special bars are
reported explicitly; their existence alone does not establish label support.

Reload and repeat the command. No settings window or label changes are expected
at this stage. Invalid saved data is preserved and reported rather than reset.

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
