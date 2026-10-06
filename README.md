# Lib's - Disenchant Assist

[![Discord](https://img.shields.io/discord/265564257347829771.svg?logo=discord)](https://discord.gg/Qc9TRBv)

A smart disenchanting helper for Enchanters. Scans your bags, filters out gear you want to keep, and lets you disenchant the rest with one click.

![Disenchant Assist in action](https://cdn.spartanui.net/addons/LibsDisenchantAssist/useexample.gif)

## What Does It Do?

- Finds all disenchantable gear in your bags
- Filters out items you want to keep (upgrades, gear sets, high ilvl, and more)
- Disenchant the next item with one click, one key press, or one action bar button
- Auto-loots the materials for you
- Waits while you are in combat

## How It Works

1. Open the window with `/de` or the minimap button
2. Your bags are scanned and filtered automatically
3. Click "Disenchant next" to break down the next item, or click the DE button on a single item
4. Keep clicking (or pressing your key) until the list is empty

The game needs a separate click or key press for every item, so no addon can disenchant your whole bag from one click. You can keep pressing the same spot as fast as you like: a press while an item is still being disenchanted is simply ignored.

## Disenchant Without the Window

- **Key**: click "Set a key" in the window and press any key or turn the mouse wheel. You can also set it in the game's Key Bindings, under AddOns.
- **Action bar**: drag the disenchant icon (or the big button) onto an action bar. This makes a macro named "DE Next".
- **Your own macro**: add the line `/click LibsDENext`.

## Filters

Keep your important gear safe with built-in filters:

| Filter               | What It Does                                                    |
| -------------------- | --------------------------------------------------------------- |
| **Higher ilvl**      | Skips items stronger than what you have equipped                |
| **Gear Sets**        | Skips items saved in your Equipment Sets                        |
| **Warbound**         | Skips Warbound items (Retail only)                              |
| **Bind on Equip**    | Skips BoE items (so you can sell them instead)                  |
| **Pawn Upgrades**    | Skips items Pawn says are an upgrade (if you use Pawn)          |
| **Looted Today**     | Skips items you just picked up today                            |
| **Item Level Range** | Only disenchant items within a min/max ilvl range               |
| **Max Quality**      | Set the highest quality to disenchant (Uncommon, Rare, or Epic) |

All filters can be turned on or off in the settings panel.

![Settings Panel](https://media.forgecdn.net/attachments/1563/766/settings-png.png)

## Item List

![Main Window](https://media.forgecdn.net/attachments/1563/752/libsde-png.png)

- Each row shows the item icon, name, and item level
- Hover over any item to see its full tooltip
- **DE button**: Disenchant just that one item
- **X button**: Ignore the item (left-click = this session, right-click = permanent)

## Commands

| Command                | Action                            |
| ---------------------- | --------------------------------- |
| `/de` or `/disenchant` | Open the main window              |
| `/de toggle`           | Toggle the window                 |
| `/de scan`             | Rescan your bags                  |
| `/de macro`            | Put the "DE Next" macro on your cursor |
| `/de next`             | Show your key and the macro line  |
| `/de options`          | Open settings                     |

## Minimap Button

- **Left-click**: Toggle the main window
- **Right-click**: Open settings
- Can be shown or hidden in the options

## Good to Know

- Only works on characters that know Enchanting
- Works in Retail, WoW Forever, Classic Era, TBC Anniversary, Titan and Mists Classic, and picks the right way to disenchant for each
- Remembers items that can't be disenchanted so it won't try them again
- Works great alongside SpartanUI (options show up in the SUI menu)

## Support

- [Discord](https://discord.gg/Qc9TRBv)
