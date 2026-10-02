<h1>
  <img
    src="https://github.com/freddiehaddad/cleanbinds/raw/main/Media/Icon.png"
    alt="Clean Binds emblem"
    width="48"
    height="48"
    align="absmiddle"
  >
  Clean Binds
</h1>

**Know your keybinds at a glance.**

Long keybinding names can get cut off on your action bars, making binds like
**Mouse Wheel Up** and **Mouse Wheel Down** hard to tell apart. Clean Binds lets
you give each button a clear, short label such as **MWU** or **MWD** in **World
of Warcraft: Forever**. Your keybindings stay exactly the same.

Download on [CurseForge](https://www.curseforge.com/wow/addons/cleanbinds) |
[Wago](https://addons.wago.io/addons/cleanbinds) |
[GitHub releases](https://github.com/freddiehaddad/cleanbinds/releases)

## Features

- **Short labels you choose.** Customize each button individually, including
  mouse buttons, the mouse wheel, and Shift, Ctrl, or Alt combinations.
- **Labels for MMO mice.** Use names like `N1` or `N12` for side-button keybinds
  on a Razer Naga or similar mouse, even when those buttons are mapped to
  keyboard keys.
- **Blizzard's familiar action bars.** Change the text without replacing your
  bars or changing their layout.
- **Adjustable keybind font size.** Make labels easier to read without
  enlarging your action buttons. Keep Blizzard's font style and colors.
- **Optional macro-name hiding.** Keep macro names off your action buttons
  without renaming your macros.
- **Built into Options.** Browse buttons by action bar and preview your labels
  as you type.
- **Shared or character-specific settings.** Labels automatically follow WoW's
  keybinding setting, with no extra profile selector.

## Installation

On CurseForge, choose **Forever**. On Wago, choose **Classic Forever** as the
game version.

For a manual install, download the release ZIP from CurseForge, Wago, or GitHub
Releases. Place the extracted **CleanBinds** folder in your WoW Forever AddOns
folder. Within your World of Warcraft installation, the file layout should be:

```text
_classic_beta_\Interface\AddOns\CleanBinds\CleanBinds.toc
```

On GitHub, choose the **CleanBinds-VERSION-forever.zip** release asset, not the
source-code archive.

Restart WoW and enable **Clean Binds** in the AddOns list.

## Set up your labels

1. Type `/cleanbinds` in chat, or open **Esc -> Options -> AddOns -> Clean
   Binds**.
2. Choose an action bar.
3. Click a button's **Custom label** field, enter a label such as `MWD`, and
   press Enter. The label appears on the action button immediately.

Use the Options **Search** field to find **Clean Binds**, an option, or a bar
or button name such as **Action Bar 2 Button 3**. Choose **Open** on a button
result to jump to its label row.

Your current keybindings are shown for reference; they cannot be changed here.
Hover over a binding to see its full name and any additional keys assigned to
that button.

Press Tab or Shift+Tab to save and move between fields. Clicking elsewhere also
saves; Escape cancels the current edit. The preview warns if a label is too
wide, but you can still use it.

Change settings outside combat. Labels and macro-name visibility stay active in combat.
Changes are saved automatically when you reload the UI or log out.

## Hide macro names

Enable **Hide macro names** on the main Clean Binds settings page to hide them
on all supported action bars. Names in the macro window and tooltips are
unchanged. This works independently of **Enable custom labels**; uncheck it
to show names again. **Reset This Bar** leaves this preference unchanged.

## Keybinding font size

Use the **Keybinding font size** slider on the main Clean Binds page to choose
a size from **10 to 14**. The preview updates as you adjust it; the step buttons
allow precise changes. Returning to the default size or pressing **Default**
restores each button's native font size.

This applies to both native and custom keybind labels, even with **Enable custom
labels** unchecked. Macro names, cooldown text, and button sizes are unchanged.
**Reset This Bar** leaves the font-size setting alone.

## Account-wide and character-specific labels

Clean Binds follows **Character Specific Key Bindings** in WoW's Keybindings
options. The active setup is shown at the top of each Clean Binds page.

| Character Specific Key Bindings | Labels and settings |
| --- | --- |
| Unchecked | Shared with other characters using account-wide bindings. |
| Checked | Saved separately for this character. |

**This checkbox is set separately for each character.** Leave it unchecked on
every character that should share your labels. Create a shared label once, and
those characters use it too.

A new character-specific setup starts with WoW's default labels, not copies of
your shared labels. **Enable custom labels**, **Hide macro names**, and
**Keybinding font size** initially match the shared settings, then remember
that character's choices independently.

Switching back to account-wide bindings restores your shared labels. It does not
copy character-only labels into the shared setup. Each setup retains its labels
for when you return to it, provided the keybindings still match.

## Changing and resetting settings

Clear a **Custom label** field to restore WoW's default text for that button.

On an action-bar page, **Reset This Bar** clears only that bar's custom labels
after confirmation. Other bars, font size, and macro-name visibility are
unchanged.

To reset the entire active Clean Binds setup, select the main **Clean Binds**
page, click **Defaults**, and choose **These Settings**. This clears all custom
labels, enables custom labels, shows macro names, and restores native font sizing.

Both affect **only the active account-wide or character-specific setup**.
An account-wide reset leaves independent character settings untouched.
**Cancel** leaves settings unchanged.

**All Settings** also resets WoW's settings and keybindings and participating
addon settings. Choose **These Settings** to reset only Clean Binds.

Uncheck **Enable custom labels** to use WoW's default text without deleting your
labels. Each setup remembers its own on/off setting.

If you change the key shown on a button, Clean Binds clears that button's custom
label in the affected setup so it does not show a misleading key. This also
applies to key changes made while the addon was disabled. Changing only a
secondary binding keeps the label if the displayed key stays the same.

Labels belong to buttons, not to the spells or macros placed on them. You can
also prepare a label for an unbound button; it appears when you assign a key.

## Supported bars

Clean Binds supports Blizzard's **Action Bars 1-8**, **Pet Bar**, and **Stance
Bar** (listed as **Special Action Buttons** in WoW's Keybindings options).
Hidden or inactive bars can still be configured.

Vehicle and other temporary action bars that reuse the main bar's bindings use
its labels rather than having a separate setup. Vehicle support is experimental.

Action bars from other addons, extra-action buttons, totem bars, and flyout
buttons are not supported. Clean Binds is for **World of Warcraft: Forever**,
not other WoW versions.

## Support and license

[Report an issue](https://github.com/freddiehaddad/cleanbinds/issues). Include
your WoW version and what happened; `/cleanbinds status` shows your version,
active binding setup, and available action bars.

Clean Binds is distributed under the
[MIT License](https://github.com/freddiehaddad/cleanbinds/blob/main/LICENSE).
