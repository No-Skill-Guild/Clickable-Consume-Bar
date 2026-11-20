# ClickableConsumeBar

A clickable bar for the consumable buffs you want to keep up in World of Warcraft: Forever (interface 16001): elixirs, flasks, scrolls, food, sharpening stones, weightstones, oils, poisons, Firestones and Spellstones.

- An icon is in color while its buff is up.
- It glows when the buff is about to run out.
- It is desaturated, with its own glow, when the buff is missing or has expired.
- Left-click an icon to use the item from your bags.

## Upgrading from ClickBuffBar

This addon used to be called ClickBuffBar. The game stores settings under the addon's folder name, so they don't follow a rename by themselves. To keep them:

1. Put the new `ClickableConsumeBar` folder next to the old `ClickBuffBar` folder. Don't delete the old one yet.
2. Log in on each character that used it. A chat line confirms the import. (You'll see two bars for this one session.)
3. Log out and delete the old `ClickBuffBar` folder.

If you already deleted the old folder: with the game closed, go to `WTF\Account\<account>\<realm>\<character>\SavedVariables\` and rename `ClickBuffBar.lua` to `ClickableConsumeBar.lua`.

The command is now `/ccb`. The old `/cbb` still works.

## Install

Unzip so the folder ends up at:

    World of Warcraft\_forever_\Interface\AddOns\ClickableConsumeBar\

Restart the game or type `/reload`.

## Setting it up

Type `/ccb`, or click the flask icon on the minimap (left-click opens the menu, right-click locks or unlocks the bar, drag moves the button; it can be turned off on the Layout page). The menu is also under the game's addon button and Options > AddOns.

**Consumables.** The page lists what is on the bar and, below it, the usable consumables in your bags. Click Add next to the ones you want. You can also type an item ID or name, or drop an item from your bags onto the list.

Each consumable has:

- **Self / Weapon / View Only**: click to switch. Self buffs you, Weapon goes on a weapon (known weapon items are set for you), and View Only just shows how many you carry.
- **MH / OH** (weapon items): tick either or both. Each hand gets its own icon, and clicking it applies the item to that hand.
- **Auto / Stone / Oil / Poison** (weapon items): a weapon on Forever can carry a stone or oil and a poison at the same time, so the bar needs to know which one to look for. Known items are recognized. Others are learned the first time you apply them.
- **Buff to look for** (self items): leave it empty. Most items give a buff with the item's own spell. For items that don't, like food, the buff is learned the first time you use one. Type a buff name or spell ID to set it yourself. R forgets a learned buff.
- **Warn at**: seconds before expiry at which this item starts to glow. Empty uses the default.
- **< > X**: reorder or remove.

**View Only items.** For things you want to keep an eye on rather than keep up, like reagents. The icon always shows the bag count, is desaturated when you have none, and does nothing when clicked. Put a number in the "low" box and it glows like an expiring buff when you carry that many or fewer. Items with no use effect are added as View Only automatically, and reagents in your bags appear in the list to add.

**Profiles.** Each profile has its own list of consumables; glow, layout and show rules are shared. On the Profiles page you can create a profile (empty or as a copy of the one in use), switch with Use, pull another profile's list into the one in use with Copy From, and Delete. Copy From and Delete ask for a second click to confirm. Under "Switch Automatically", pick a profile for the open world, dungeons, raids, and battlegrounds and arenas, and the bar changes when you enter that kind of place. "Set Up Dungeon, Raid And PvP Profiles" creates all three as copies of the current profile and assigns them in one click. A profile you pick by hand stays until you move to a different kind of place. An item you already set up in one profile brings its settings along when you add it to another.

**Show When.** Always, or only while a buff is missing or about to expire. Then narrow it by combat, group, place, resting and mounted.

**Glow.** Separate glows for "expiring" and "missing": style (soft pulse, marching pixels, solid border, blinking border), color and opacity, speed and thickness, with a live preview. The default warning time is here too.

**Layout.** Lock, icon size, spacing, icons per row, direction, opacity, timer text, bag count and tooltips.

The menu is drawn in a flat dark style. If ElvUI is installed, the menu uses its accent color, panel colors and font.

The bar starts unlocked with a blue handle above it. Drag the handle to place the bar, then lock it on the Layout page.

**Minimap button and other addons.** The button follows the minimap's shape as minimap addons report it: round, square, and the partly rounded shapes, riding the curve on rounded corners and the straight edge on square ones. It re-seats itself when the minimap is resized or reshaped, its art scales if another addon resizes the button, and if a button-collecting addon moves it into its own bar, it leaves the placement to that addon.

## Commands

    /ccb                 open the menu
    /ccb add <item>      add by item ID, link or name
    /ccb profile <name>  switch profile (no name lists them)
    /ccb lock | unlock   lock or unlock the bar
    /ccb reset           move the bar back to the middle of the screen
    /ccb status          list what the bar is tracking
    /ccb debug           explain why the bar is or isn't showing
    /ccb buffs           show which buff each icon is tracking and what's on you

## Performance

The addon does no work unless something changed.

- **No per-frame code.** Nothing runs every frame, and there is no repeating timer. Glows are game animations that the client runs by itself.
- **One timer, set for the next change.** After each check the addon works out when an icon will next look different (a minute ticking over, the warning time, expiry) and sleeps until then. With a flask and food up that is about one wake-up a minute, and one a second only during a buff's final minute. With timer text turned off there are no wake-ups between events at all.
- **Reads only what changed.** A buff event re-reads your buffs once (not once per icon), a weapon event re-reads the weapons, a bag event re-counts items. A wake-up for a ticking timer asks the game nothing and only rewrites the text that changed.
- **Events only for what's on the bar.** Buff events are registered only while a self-buff item is on the bar, weapon events only while a weapon item is, and both are dropped otherwise. A bar with only View Only items listens to bag changes and nothing else.
- **Combat is quiet.** Buff events are ignored outright during combat, because the game hides buff data then. Each of your spell casts costs one table lookup.
- **Weapon icons** add one backup re-read every 15 seconds on top of the game's enchant events.
- **The menu** is built the first time you open it and costs nothing while closed.

## What the game allows in combat

WoW: Forever restricts addons in combat. This is how the bar deals with it.

- **Buffs are mostly hidden in combat.** A buff the game won't report keeps the state and timer it had when last seen, so the expiring glow and the expiry still happen on time. If you use a tracked consumable mid-fight the icon is marked as up from that moment. Everything is read again when combat ends. A buff removed early in combat (dispelled or cancelled) is not noticed until then. Tooltips say "Estimated" while this applies.
- **Weapon buffs can always be read**, so those icons are exact in combat too.
- **Clickable buttons can't be shown, hidden, moved or changed by an addon in combat.** Layout changes and newly added consumables apply when combat ends. Combat, group and mounted rules still switch instantly, because the game applies those itself. With "Only When Missing Or Expiring", the bar is hidden out of combat and invisible in combat until a buff needs you; while invisible in combat it still takes clicks where it sits.

## If the bar disappears in combat

With the default settings the bar stays visible in and out of combat. It is hidden or invisible in combat only when:

- Show When > Combat is set to "Only Out Of Combat".
- Show When > Show The Bar is set to "Only When Missing Or Expiring" and every buff is up.
- You added consumables, or logged in or reloaded, while already in combat. The icons appear when combat ends.

Type `/ccb debug` in combat to see which rule is in effect.

## If an icon's timer doesn't match the buff

The time left is always read from the buff itself, so longer buffs (for example food with the Gourmand Legacy perk) need no setup. A wrong timer means the icon is following the wrong buff.

- For 45 seconds after you use an item, the new buffs on you are weighed: the item's own spell first, then a buff called Well Fed, then whichever lasts longest. Buffs with no timer are ignored, and so are buffs the game says came from a group member or an NPC. The game doesn't name the caster of a buff from a player outside your group, so those can't be ruled out; a buff it confirms you cast is preferred over them. Food is recognized by its "Food" use effect and tracked by Well Fed without learning anything. Every use weighs them again, so a wrong choice corrects itself the next time you use the item.
- R on the item's row forgets what was learned. You can also type the buff's name or spell ID in the box.
- `/ccb buffs` (out of combat) lists what each icon is looking for, what it matched, and every long buff on you with its time left.
- The expiring glow starts at the warning time, 5 minutes by default (a third of the buff's length for shorter buffs). Change it on the Glow page or per item with "Warn At".

## Good to know

- Reapplying a weapon item over one that is still active brings up the game's own "replace enchant?" confirmation.
- An off-hand icon is dimmed, with no glow, while you have no weapon in that hand.
- Settings and profiles are saved per character.
- A profile switch during combat changes the bar when combat ends.
