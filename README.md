# Forever Quest Target

One action bar macro for the quest you focus in World of Warcraft: Forever.

1. Install the `ForeverQuestTarget` folder in `_forever_/Interface/AddOns/`.
2. Open `/macro` and drag **Quest Target** from the character-specific tab onto your bar. Leave one character macro slot free for the addon.
3. Focus a quest in Blizzard’s UI and press the macro.

Click the minimap icon or type `/fqt` to open options. Choose an enemy marker and an NPC marker independently, including **None**. Defaults are skull and green triangle. You can include mobs tagged by others, hide the minimap icon, or reset all settings.

[QuestieDB](https://www.curseforge.com/wow/addons/questiedb) adds quest item droppers and turn-in NPCs. Without it, straightforward English kill objectives can still work.

The addon refreshes the macro out of combat. The tagged-mob filter uses visible enemy nameplates and skips a name when every visible living mob with that name is tagged by someone else. Exact-name targeting can still select a tagged mob when a free mob shares its name. If the macro searches and finds no match, it clears your target.

## Packaging

Zip the `ForeverQuestTarget` folder so its TOC and Lua file are one directory below the archive root. On CurseForge select World of Warcraft: Forever 1.60.1 and add QuestieDB as an optional dependency.
