# Visual CS Guide

Local-first SwiftUI prototype for a computer science flashcard learning app.

## Product Direction

- No backend server.
- No user accounts.
- No cloud database.
- Curriculum is bundled as local JSON in `VisualCSGuide/curriculum`.
- User progress and spaced-review scheduling are stored locally with `UserDefaults`.
- Optional AI review is represented by a settings toggle and checkpoint flow, but no API call is wired yet.

## Curriculum

Each bundled JSON card uses this schema:

- `id`
- `module`
- `topic`
- `difficulty`
- `title`
- `explanation`
- `analogy`
- `tiny_visual_key`
- `example`
- `why_it_matters`
- `checkpoint_question`
- `expected_answer`
- `common_mistake`

Current modules:

- Foundations
- Programming Basics
- Data Structures
- Algorithms
- Operating Systems
- Databases
- Networking
- Security
- Software Engineering
- AI ML

## Study Flow

1. Pick a module.
2. Swipe or use bottom buttons through cards.
3. Tap a card to flip between front and details.
4. Mark cards as `Got it` or `Review`.
5. Every 5 cards, complete an active-recall checkpoint.
6. If AI review is disabled, compare against a local model answer and self-grade.

## Verify

```sh
xcodebuild -project VisualCSGuide.xcodeproj -scheme VisualCSGuide -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
