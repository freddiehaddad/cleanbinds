# Clean Binds

Custom action-bar keybinding labels for World of Warcraft: Forever beta.
Replace long names such as **Mouse Wheel Down** with **MWD** without changing
your keybindings.

## Features

The native UI is available at **Options -> AddOns -> Clean Binds**, with pages
for Action Bars 1-8, Pet Bar, and Stance Bar. It shows real bindings with editable
label previews, keyboard navigation, reset confirmation, and combat read-only
behavior.

**Labels and settings are saved account-wide across characters.** Edits update
the settings table, preview, and real action buttons. Actual keybindings are
never changed by the addon.

## Saved settings

Labels and the **Enable custom labels** setting are shared by all characters on
the same WoW account. Changes are saved automatically when you reload the UI or
log out.

## Installation

Place this directory at:

```text
C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\CleanBinds
```

`CleanBinds.toc` must be directly inside that folder.

Restart WoW and enable **Clean Binds** in the AddOns list.

## Usage

1. Run `/cleanbinds`, or open **Esc -> Options -> AddOns -> Clean Binds**.
2. Select the action bar containing the button you want to customize.
3. Click its **Custom label** cell, type a label such as `MWD`, and press Enter.

The action-button name and current binding are read-only. Hover the binding to
see its full text and any additional assigned keys. Only the custom label changes.

Tab/Shift-Tab accepts an edit and moves between label fields. Clicking elsewhere
also accepts; Escape cancels the current edit. Clear a field to restore the
native label. A preview shows the label at a shared magnification, preserving
native button and font proportions. Labels that are too wide receive a warning
but can still be saved.

Use **Reset This Bar** to clear one bar's overrides, or **Reset All Labels** on
the parent page to clear every override. Both affect all characters and require
confirmation. Turning off **Enable custom labels** restores native text without
discarding your labels; this setting is also shared across characters.

Use `/cleanbinds status` to see the client version and available action bars.

## Supported bars

CleanBinds supports Blizzard's **Action Bars 1-8**, **Pet Bar**, and **Stance Bar**
(called **Special Action Buttons** in WoW's keybinding settings). Hidden or
inactive bars remain configurable.

There is no separate Possess page. Possession actions that reuse the main action
buttons use their labels.

Vehicle/override displays use the first six main action-bar bindings. They have
no separate settings page and inherit those buttons' labels. Vehicle/override
support is experimental.

Third-party action bars, extra-action/totem/flyout buttons, appearance controls,
profiles, and other WoW clients are not supported.

## Label behavior

Labels belong to individual buttons, not spells or globally renamed keys. Empty
or whitespace-only labels restore the default. Long labels are allowed with a
fit warning; text is preserved as UTF-8 and displayed literally.

A committed change to a button's displayed binding clears its label for **all
characters**. Secondary-only changes keep the label when the displayed key is
unchanged. Canceled binding edits, loading binding sets, switching characters,
and changing input devices do not clear labels. An override prepared for an
unbound button becomes active on its first binding.

Custom labels preserve the game's fonts, colors, positioning, and visibility.
Clearing an override or disabling custom labels restores the latest native text.
Settings are read-only during combat, but existing custom labels remain active.
