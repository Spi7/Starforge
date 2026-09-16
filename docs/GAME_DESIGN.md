# Starforge — Game Design Document

> Version: 0.1
> Status: Early Prototype

## 1. Game Overview

Starforge is a single-player 2D pixel-art space exploration and
management game.

The player is the captain of a spaceship that serves as their home,
company, factory, warehouse, research center, and trading hub.

The player physically exists in the world and can walk around the ship,
visit planets, gather resources, farm, mine, fight enemies, interact with
crew, and manage their growing operation.

The spaceship begins small and gradually grows into a large mobile space
station.

The long-term goal is to explore and establish operations across all eight
planets of the Solar System.

---

## 2. Core Player Fantasy

The player should feel:

> "This is MY spaceship."

The ship is not just a menu.

The player should physically see it grow over time, walk through its rooms,
watch crew members work, interact with machines, store resources, operate
production facilities, and eventually automate parts of the company.

Progression should feel like:

Player does the work
→ Player + Crew
→ Crew + Machines
→ Large Automated Operation

---

## 3. Core Gameplay Loop

Explore
→ Gather Resources
→ Farm / Mine / Battle / Trade
→ Return to Ship
→ Process / Manufacture
→ Use / Sell / Trade
→ Earn Credits and Materials
→ Upgrade Ship and Equipment
→ Research
→ Unlock New Areas and Planets
→ Repeat

Farming, mining, combat, exploration, production, and trading should feed
into the same economy and progression loop rather than exist as separate
minigames.

---

## 4. Player and Perspective

- 2D pixel art
- Top-down / 3/4 perspective
- Player physically controls the captain
- WASD movement
- Interaction with objects, machines, NPCs, and environments
- Management UI for higher-level systems

Starforge contains combat, but it is not intended to become a
combat-focused action RPG.

Management, exploration, progression, and spaceship growth remain the
main focus.

---

## 5. Spaceship

The spaceship is the center of the game.

It functions as:

- Home
- Company headquarters
- Storage
- Factory
- Research facility
- Farming facility
- Crew workplace
- Trading hub
- Transportation

Possible rooms include:

- Bridge
- Storage
- Crew Quarters
- Engine Room
- Factory
- Refinery
- Research Lab
- Hydroponics
- Reactor
- Trading Hub

The ship should visibly expand and become more capable as the player
progresses.

### Ship Expansion and Customization

- The player cannot freely build or modify the structural boundaries of the spaceship.
- Walls, exterior borders, corridors, and permanent room layouts are predefined by ship progression.
- Upgrading the spaceship expands the playable interior by unlocking new rooms or previously inaccessible areas.
- New areas may be revealed through locked doors, corridors, or ship expansions as the ship level increases.
- Ship upgrades provide the structural space, but the player can customize unlocked areas with furniture, decorations, machines, storage, plants, and other placeable objects.
- Credits and resources can be used to purchase or obtain these interior objects.
- Some placeable objects are cosmetic, while others provide gameplay functions.
- The goal is to give the player ownership over the interior without turning Starforge into a free-form base-building game.

---

## 6. Resource Gathering

Important resources should come from active gameplay as well as trade and
automation.

### Farming

The player can grow crops and biological resources.

Farming may occur on planets or inside spaceship hydroponics.

Early farming is manual.

Later progression may allow crew and automation to manage routine farming.

### Mining

The player can extract minerals and other planetary resources.

Raw resources can be brought back to the ship and refined or manufactured
into more valuable materials.

### Combat

Hostile creatures, robots, or other threats may appear during exploration.

Combat can provide:

- Resources
- Rare materials
- Research samples
- Equipment
- Access to dangerous areas

Combat rewards should feed into production, research, trading, or
progression.

Exact farming, mining, and combat mechanics are not finalized.

---

## 7. Production and Economy

Resources can be:

Gathered
→ Stored
→ Processed
→ Manufactured
→ Used / Sold / Traded

Example:

Iron Ore
→ Steel
→ Machine Parts
→ Equipment

Different planets should create different economic opportunities.

The player should be encouraged to process resources and build
interplanetary trade networks rather than simply sell everything
immediately.

Recipes, prices, and balance values are not finalized.

---

## 8. Planets and Progression

The long-term game includes:

1. Mercury
2. Venus
3. Earth
4. Mars
5. Jupiter
6. Saturn
7. Uranus
8. Neptune

Each planet should eventually differ through some combination of:

- Resources
- Environment
- Farming
- Enemies
- Economy
- Hazards
- Technology requirements

Unlocking a planet should mean establishing meaningful access and
operations rather than simply visiting it once.

Earth and Mars are the current candidates for the early vertical slice.

---

## 9. Crew and Automation

Possible crew roles include:

- Engineer
- Scientist
- Merchant
- Pilot
- Farmer / Biologist
- Robot

Crew should physically appear and work aboard the ship when practical.

Progression should gradually allow repetitive tasks to move from:

Manual
→ Crew-assisted
→ Machine-assisted
→ Automated

Exact crew mechanics are not finalized.

---

## 10. Prototype Scope

Do NOT attempt to build the complete game immediately.

The first vertical slice should focus on proving the core foundation:

- Player movement
- Interaction
- Small spaceship interior
- Inventory
- Resources
- Storage
- Basic resource gathering
- Basic production
- Basic UI
- Save / Load foundation

- The first spaceship prototype represents the Level 1 starter ship: a small predefined interior with basic walls, floor, props, and room boundaries. Ship expansion and free furniture placement are not part of the initial prototype.

After the foundation works, systems such as farming, mining, trading,
combat, crew, research, and ship expansion can be introduced gradually.

---

## 11. Not Now

Do not implement these unless explicitly requested:

- Multiplayer
- PvP
- All eight planets
- Large story campaign
- Complex boss systems
- Procedural universe generation
- Massive crafting trees
- Large numbers of items or enemies

Combat and farming ARE planned features.

They simply do not need full implementations during the earliest
prototype.

---

## 12. Technical Direction

- Godot 4.7
- GDScript
- 2D pixel art
- Aseprite
- Git / GitHub
- VS Code
- Codex-assisted development

Systems should be modular and data-driven where useful.

Avoid unnecessary dependencies and over-engineering.

---

## 13. Design Principles

1. The spaceship is the heart of Starforge.
2. The player should physically participate in the world.
3. Exploration should produce meaningful discoveries and resources.
4. Farming, mining, combat, and trade should feed the same economy.
5. Production should turn resources into meaningful progression.
6. The ship should visibly grow with the player's success.
7. New planets should introduce new opportunities.
8. Crew and automation should reward progression.
9. Systems should connect rather than become isolated minigames.
10. Build simple versions first and expand them only when necessary.

When considering a new feature, ask:

> Does this make exploring, gathering resources, and growing my spaceship
> and company more interesting?