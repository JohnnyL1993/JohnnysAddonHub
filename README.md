# Johnny's Warmane Addon Hub

A World of Warcraft 3.3.5a addon for the Warmane private server.

Always-on-screen launcher bar - shows a button for each of Johnny's standalone addons (Blacklist, Gear Advisor, Raid Browser, Raid Comp, Raid Roll) that's currently installed and enabled.

## Requirements

No other addons required. The bar shows a button for each of Johnny's addons you have installed (Raid Comp, Gear Advisor, Blacklist, Raid Browser, Raid Roll).

## Install

1. Go to [Releases](https://github.com/JohnnyL1993/JohnnysAddonHub/releases) and download **`JohnnysAddonHub-vX.Y.zip`** from the latest release.
   Don't use GitHub's green **Code → Download ZIP** button or the "Source code" zips. Those unpack as `JohnnysAddonHub-main` or `JohnnysAddonHub-2.0`, and WoW won't load an addon whose folder name doesn't match.
2. Extract it into `World of Warcraft\Interface\AddOns\`. You should end up with `Interface\AddOns\JohnnysAddonHub\JohnnysAddonHub.toc`.
3. Restart WoW, or log out to the character screen, and make sure the addon is enabled.

## Updating

Download the latest release zip, delete the old `JohnnysAddonHub` folder, and extract the new one in its place.

## Slash commands

| Command | What it does |
| --- | --- |
| `/hub` | Show or hide the launcher bar |

## Other Johnny's addons

- [Johnny's Raid Comp](https://github.com/JohnnyL1993/JohnnysRaidComp)
- [Johnny's Blacklist](https://github.com/JohnnyL1993/JohnnysBlackList)
- [Johnny's Currency Tracker](https://github.com/JohnnyL1993/JohnnysCurrencyBar)
- [Johnny's Gear Advisor](https://github.com/JohnnyL1993/JohnnysGearAdvisor)
- [Johnny's Messenger](https://github.com/JohnnyL1993/JohnnysMessenger)
- [Johnny's Raid Browser](https://github.com/JohnnyL1993/JohnnysRaidBrowser)
- [Johnny's Raid Roll](https://github.com/JohnnyL1993/JohnnysRaidRoll)

## Releasing (maintainer notes)

1. Bump `## Version:` in the `.toc`.
2. Commit, then `git tag vX.Y` and `git push && git push --tags`.
3. The **Release** GitHub Action builds the zip and attaches it to the release.
