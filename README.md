<img align="right" src="Media/Icon.svg" alt="Clean Binds emblem" width="96" height="96">

# Clean Binds

Custom action-bar keybinding labels for World of Warcraft: Forever beta.
Replace long names such as **Mouse Wheel Down** with **MWD** without changing
your keybindings.

## Features

The native UI is available at **Options -> AddOns -> Clean Binds**, with pages
for Action Bars 1-8, Pet Bar, and Stance Bar. It shows real bindings with editable
label previews, keyboard navigation, reset confirmation, and combat read-only
behavior.

**Labels automatically follow WoW's account-wide or character-specific
keybindings.** Edits update the preview and real action buttons. CleanBinds
never changes your keybindings or selects a binding mode for you.

## Saved settings

CleanBinds follows **Character Specific Key Bindings** in WoW's Keybindings
options. The current scope is shown at the top of each CleanBinds page.

| WoW binding mode | CleanBinds labels and enable setting |
| --- | --- |
| Account-wide | Shared by characters using account-wide bindings. |
| Character-specific | Independent settings for the current character. |

The first time a character uses its own setup, it starts with native labels,
not copies of the shared overrides. **Enable custom labels** initially matches
the account setting, then remembers that character's choice independently.

Switching modes recalls each setup's labels and enable state. For example, a
button can have `MWD` in the shared setup and `Q` in a character's setup.
Changes are saved automatically when you reload the UI or log out.

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
the parent page to clear every override **in the displayed scope**. Both require
confirmation and leave the other setup untouched. An account-wide reset affects
the shared labels, not independent character labels.

Turning off **Enable custom labels** restores native text without discarding
labels in that setup. If the binding scope changes while you are editing or
confirming a reset, the unfinished operation is canceled to protect both setups.

Use `/cleanbinds status` to see the client version, active scope, and available
action bars.

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
manually managed profiles, and other WoW clients are not supported.

## Label behavior

Labels belong to individual buttons, not spells or globally renamed keys. Empty
or whitespace-only labels restore the default. Long labels are allowed with a
fit warning; text is preserved as UTF-8 and displayed literally.

A saved change to a button's displayed binding clears its label **only in that
binding setup**. A stale label is also removed when its key changed while the
setup or addon was inactive. For example, `MWD` is cleared if its button is now
bound to F.

Secondary-only changes keep the label when the displayed key is unchanged.
Simply switching scopes or characters does not erase labels for unchanged
bindings. Canceled binding edits and input-device changes also preserve them.
An override prepared for an unbound button becomes active on its first binding.

Custom labels preserve the game's fonts, colors, positioning, and visibility.
Clearing an override or disabling custom labels restores the latest native text.
Settings are read-only during combat, but existing custom labels remain active.
