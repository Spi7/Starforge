# Starforge - Development Guidelines

## Project

Starforge is a single-player 2D pixel-art space exploration and management game built with Godot.

Read `docs/GAME_DESIGN.md` before making game-design or architectural decisions.

## Technology

- Godot 4.7
- GDScript
- 2D
- VS Code
- Git / GitHub
- Aseprite

Do not introduce another engine, language, framework, or major dependency unless explicitly requested.

## Platform Direction

- PC is the primary development target.
- Keep gameplay systems input-device independent where practical.
- Use Godot Input Map actions instead of hard-coding keyboard or mouse inputs into gameplay logic.
- Avoid unnecessary assumptions about a fixed screen resolution or aspect ratio.
- Keep future mobile support possible, but do not implement mobile-specific controls, UI, or platform systems unless explicitly requested.

## Development Philosophy

Keep implementations simple, modular, and readable.

Do not over-engineer systems for hypothetical future requirements.

Build the smallest working version of a feature first, then expand it when needed.

DO not implement features simply because they appear in the game design document. Only implement the feature that is currently requested.

## Before Making Changes

Before implementing a feature:

1. Inspect the relevant existing files.
2. Understand the current project structure.
3. Reuse existing systems when appropriate.
4. Make the smallest reasonable change.
5. Avoid modifying unrelated files.

For large or architectural changes, explain the proposed approach before implementing it.

## Project Organization

Keep files organized by responsibility.

General structure:

- `assets/` — art, sprites, UI assets, audio, fonts
- `scenes/` — Godot scenes
- `scripts/` — GDScript
- `data/` — game data and definitions
- `docs/` — design and development documentation
- `tests/` — tests and test-related files

Create subfolders only when they are actually needed.

Do not place large numbers of unrelated files in the project root.

## Godot

Use:

- `snake_case` for files
- `snake_case` for variables
- `snake_case` for functions
- `PascalCase` for classes
- `PascalCase` for Godot node names

Prefer typed GDScript when practical.

Prefer configurable values over unexplained hard-coded values.

Use Godot scenes and resources appropriately rather than building
everything through code.

## Architecture

Prefer composition over large inheritance hierarchies.

Keep systems loosely coupled when practical.

Use signals when they provide a clear way for Godot systems to communicate.

Avoid global state unless the system genuinely needs to be globally
accessible.

Do not create unnecessary autoload singletons.

Game content such as resources, items, recipes, crops, enemies, and planets
should become data-driven when doing so provides a clear benefit.

Do not build generic frameworks before they are needed.

## Scenes

Do not create extremely large scenes containing unrelated responsibilities.

Reusable objects should eventually become reusable scenes where appropriate.

Be careful when editing `.tscn` files manually.

Do not restructure working scenes unless the requested feature requires it.

## Game Design Boundaries

Follow `docs/GAME_DESIGN.md`.

Do not independently redesign major gameplay systems.

Do not add major features that were not requested.

In particular, do not implement multiplayer or networking unless explicitly requested.

If a design decision is unclear and would significantly affect future
development, ask before committing to the decision.

## Code Quality

Code should be understandable by another developer reading it later.

Prefer:

- Clear names
- Small focused functions
- Simple control flow
- Useful comments only where needed

Avoid:

- Premature abstraction
- Duplicate systems
- Giant manager classes
- Unnecessary dependencies
- Clever code that is difficult to understand

## Testing

After implementing a feature:

1. Check for GDScript errors.
2. Check for broken scene or resource references.
3. Run the relevant scene or project when possible.
4. Verify the requested behavior.
5. Report anything that could not be tested.

Do not claim something was tested if it was not.

## Git

Do not commit, push, create branches, merge, rebase, or modify Git history unless explicitly requested.

Do not modify `.gitignore` unless necessary.

Never commit generated Godot cache files from `.godot/`.

## When Finishing a Task

Briefly report:

- What changed
- Important files changed
- How to test it
- Any important remaining issue

Do not produce unnecessary documentation or additional features unless requested.