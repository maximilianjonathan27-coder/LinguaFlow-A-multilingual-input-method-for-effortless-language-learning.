# LinguaFlow

> **Type naturally. Learn effortlessly.**

## Local macOS MVP status

The current local build is a native InputMethodKit input method with:

- a read-only SQLite V2 lexicon containing 184,983 Chinese lexemes, 199,462
  structured senses, and 216,100 English glosses sourced from CC-CEDICT V2;
- librime-first continuous pinyin decoding, such as `nihao` and
  `woxiangqubeijing`, with LinguaFlow heuristics supplementing rather than
  replacing librime's initial candidate order;
- five candidates per page, number-key selection, paging, cursor editing, and Chinese punctuation;
- separate exposure and selection counters for future learning and ranking features;
- English candidate definitions imported from CC-CEDICT, with manually reviewed
  translations taking precedence for the seed records.
- offline English autocomplete backed by Peter Norvig's 333,333-word frequency
  list; existing bilingual entries retain priority so their Chinese glosses stay
  visible, while unmatched words remain selectable as English output.
- an offline Tatoeba example index containing 52,747 sentence pairs and 242,436
  term links, plus a small reviewed phrase layer used before general examples.
- hover vocabulary cards: resting on an English translation for 500 ms opens a
  structured learning card backed by the local macOS Dictionary, with a 250 ms
  grace period for moving between the candidate and card.
- local pronunciation: double-clicking an English translation speaks it with
  Apple's on-device speech synthesizer without committing the Chinese candidate.

## Hover vocabulary cards

Only the English translation line is a hover target; the Chinese candidate does
not open a card. Dictionary lookup uses Apple's public `DCSCopyTextDefinition`
API on a background queue and caches both hits and misses for the lifetime of the
input method. CC-CEDICT glosses are normalized into useful local dictionary
headwords by splitting alternatives and removing usage labels and infinitive or
article prefixes. Up to three matching definitions can be combined in one card.
The card parses the local dictionary's rich text into a clear headword header,
pronunciation and part of speech when available, a prominent Chinese meaning,
an English definition, numbered examples, and a related phrases / idioms module.
Its fixed section navigation scrolls directly to definitions, examples, or
phrases and highlights the active button. Dense phrase text is parsed into
separate expression rows with category, definition, and example information.
Terms absent from the user's installed dictionaries still retain a useful Chinese
meaning and a clear local-data status. Long content scrolls inside the card while
its header and source remain visible, and the top-right close button dismisses it.
Changing or hiding the candidate list cancels pending hover work and closes the
card.

## Candidate pronunciation

Double-click only the translation line to pronounce it. LinguaFlow uses
`AVSpeechSynthesizer` locally, stops the current utterance before starting a new
one, and selects a voice from each candidate's BCP-47 `targetLanguage` (specific
locale first, then its base language). Empty translations and unavailable voices
fail silently. A short utterance may continue when the candidate panel hides; it
is stopped when the input controller closes. The pronunciation controller also
exposes a local `onPronunciationPlayed` hook for future learning events, with no
remote analytics or network calls.

## Input surface and motion design

The candidate panel and vocabulary card share one translucent macOS glass
surface: ultra-thin material, restrained directional highlight, a fine luminous
edge, and a soft shadow. Translation hover feedback uses a fixed-size hit area
and a short ease-out transition so rows never jump. While speech is active, a
reserved speaker indicator appears beside the translation and disappears from
the synthesizer's real completion callback.

Only the temporary vocabulary card receives ambient motion: a slow 1–2 point
vertical drift plus a very small border/shadow breathing cycle. Entrance and
dismissal use short non-spring opacity, scale, and offset transitions. macOS
Reduce Motion disables continuous drift, scale, and positional animation while
preserving functional opacity feedback.

Build and install locally with:

```sh
./script/build_and_run.sh --install-ime
```

The install command also places a Finder- and Launchpad-visible
**LinguaFlow.app** in `/Applications`. Opening it launches the preferences
window. The input method service remains installed separately in the current
user's `~/Library/Input Methods` folder.

After installation, select **LinguaFlow** from the macOS input menu and test in
TextEdit. The locally imported rime-ice data is GPL-3.0; review the distribution
and licensing strategy before publishing a binary or committing the generated
database.

LinguaFlow is a multilingual input method designed to turn everyday typing into effortless language learning.

Instead of asking users to open a separate translator, LinguaFlow brings **real-time translations directly into the input candidate interface**. As you type, relevant translations appear alongside your input, allowing language exposure to happen naturally within the workflow.

LinguaFlow is not designed to replace traditional translation tools or compete primarily on AI text generation. Its core purpose is different:

> **Make language learning a by-product of everyday typing.**

---

## Why LinguaFlow?

Learning a language traditionally requires deliberate study:

```text
See an unfamiliar word
        ↓
Stop what you're doing
        ↓
Open a dictionary / translator
        ↓
Search the word
        ↓
Read the result
        ↓
Return to your original task
```

This process creates friction.

LinguaFlow takes a different approach:

```text
Type normally
     ↓
Translation appears in the candidate list
     ↓
Notice the translation
     ↓
Keep typing
     ↓
Repeated exposure
     ↓
Gradually build vocabulary
```

The user does not need to enter a "learning mode".

**The learning happens inside the workflow.**

---

# Core Concept

The defining feature of LinguaFlow is **real-time translation inside input candidates**.

For example, a user typing in Chinese might see:

```text
会议
meeting
conference
appointment
```

The translation is presented **at the moment the user is selecting an input candidate**, rather than after the text has already been entered.

This creates a fundamentally different interaction from a traditional translator.

### Traditional Translator

```text
Input
  ↓
Translate
  ↓
Read result
```

### LinguaFlow

```text
Type
  ↓
Candidate generation
  ↓
Translation appears alongside candidates
  ↓
Continue typing
```

The translation becomes part of the **input experience itself**.

---

# Product Philosophy

LinguaFlow is built around four principles.

### 01 — Invisible Learning

Language learning should not always feel like studying.

LinguaFlow aims to make vocabulary exposure a natural consequence of typing.

### 02 — Context Over Literal Translation

The best translation is not necessarily the most literal one.

LinguaFlow considers:

* Current input context
* User language level
* Preferred translation style
* Selected domain
* Learning goals
* Previous exposure

to determine which translation is most useful.

### 03 — Personalization

Different users need different language environments.

A student studying academic subjects should not necessarily receive the same vocabulary and expressions as someone learning casual conversational English.

### 04 — Progressive Learning

Most interactions should remain lightweight.

Users can simply notice a translation and continue typing.

When they become curious, they can progressively explore:

```text
Candidate
   ↓
Translation
   ↓
Hover
   ↓
Pronunciation
   ↓
Vocabulary Card
   ↓
Deeper Learning
```

---

# Core User Experience

The basic LinguaFlow experience can be represented as:

```text
                 USER TYPES
                     │
                     ▼
              INPUT PROCESSING
                     │
                     ▼
          CONTEXT-AWARE ANALYSIS
                     │
          ┌──────────┴──────────┐
          │                     │
          ▼                     ▼
   Input Candidates       Translation Engine
          │                     │
          └──────────┬──────────┘
                     ▼
            UNIFIED CANDIDATES
                     │
                     ▼
          ┌─────────────────────┐
          │  Candidate          │
          │                     │
          │  会议               │
          │  meeting            │
          │  conference         │
          └─────────────────────┘
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
       Continue    Hover      Click
       Typing      Pronounce  Explore
                     │          │
                     ▼          ▼
                 Audio     Vocabulary Card
                                │
                                ▼
                          Micro-Recall
                                │
                                ▼
                         Repeated Exposure
```

---

# 01 — Personalized Language Profile

Before using LinguaFlow, users create a **Language Learning Profile**.

The profile determines what kind of language environment LinguaFlow should create.

The onboarding process uses a progressive 9-step questionnaire.

```text
01 Languages
      ↓
02 Learning Goal
      ↓
03 Interests & Domains
      ↓
04 Language Level
      ↓
05 Translation Style
      ↓
06 Learning Intensity
      ↓
07 Learning Features
      ↓
08 Learning Preference
      ↓
09 Final Preference
      ↓
Profile Generated
```

---

## Language Selection

Users select:

* Input language
* Learning language

For example:

```text
🇨🇳 Chinese
      ↓
🇺🇸 English
```

The architecture should eventually support multiple language profiles:

```text
Chinese → English
Chinese → Japanese
English → Spanish
```

Users can switch between profiles depending on their needs.

---

# Native macOS Input Method MVP

The first working milestone is now a real macOS input source, not a fixed
translation window. It is listed beside Apple's input sources and receives
keystrokes only while the user has selected LinguaFlow from the input menu.
The MVP contains an extensible offline SQLite lexicon seeded with five pinyin
groups (`huiyi`, `anpai`, `yanqi`, `shenqing`, and `fangfa`). Its candidate
panel follows the active text caret and shows Chinese, English translation,
and Seen count. Seen records candidate exposure. Actual commits are stored
separately as selection counts and influence ranking without replacing system
frequency.

## Open and run

Open `LinguaFlowPrototype.xcodeproj` in Xcode. The `LinguaFlowPrototype` scheme
builds the `LinguaFlow Setup` app and embeds the signed `LinguaFlow.app`
input-method bundle. The `LinguaFlowInputMethod` scheme builds the input source
by itself; it is a background app and is not intended to show a window.

The project-local script is the recommended path because it selects the
installed Xcode toolchain without changing `xcode-select`:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --test
./script/build_and_run.sh --build-lexicon
./script/build_and_run.sh --build-ime
./script/build_and_run.sh --install-ime
./script/build_and_run.sh --verify-ime
./script/build_and_run.sh --verify
```

`--install-ime` installs to `~/Library/Input Methods/LinguaFlow.app`. Open the
Setup app, click “安装输入法”, then go to **System Settings → Keyboard → Text
Input → Edit** and add LinguaFlow. No administrator password or sensitive
privacy permission is required. Local development signing uses the first
available Apple Development identity; Developer ID signing, DMG packaging,
notarization, and a complete pinyin engine are later milestones.

The editable source of the built-in dictionary lives in `LexiconSource/`,
including the attributed Norvig English frequency list in `External/`.
`script/build_lexicon.swift` compiles those files into the read-only
`LinguaFlow.app/Contents/Resources/linguaflow.sqlite`; do not edit the database
binary by hand.

Learning counts are shared by the Setup app and the input method at:
`~/Library/Application Support/LinguaFlow/exposureCounts.v1.json`. The file
contains only stable candidate IDs and integer counts; no input history,
sentences, application names, or timestamps are stored.
Actual selection counts use the same privacy model in
`selectionCounts.v1.json`.

---

# 02 — Learning Goals

Users can select up to three learning goals.

Possible goals include:

* Everyday Communication
* Academic
* Professional
* Business
* Travel
* Personal Growth
* Other

These preferences help determine which expressions and vocabulary should be prioritized.

---

# 03 — Interests & Domains

Users select the domains they want to encounter more frequently.

Examples:

* General / Everyday
* Academic
* Business
* Technology
* Finance
* Science
* Arts & Culture
* Travel
* Media & Entertainment
* Law
* Medicine
* Social Sciences

Users can also enter custom interests.

For example:

```text
AI
fashion
economics
psychology
startups
```

This allows LinguaFlow to become increasingly relevant to the user's actual life and work.

---

# 04 — Language Level

Users select their current learning level:

```text
Beginner
Elementary
Intermediate
Upper-Intermediate
Advanced
Fluent
```

Language level can influence:

* Vocabulary difficulty
* Alternative expressions
* Example sentences
* Explanation depth
* Suggested synonyms
* Learning intensity

---

# 05 — Translation Style

Users can define how they want translations to sound.

Available styles:

```text
Casual
Neutral
Professional
Formal
Academic
```

For example, the same concept could be translated differently depending on the user's preference.

```text
Casual
push back

Neutral
postpone

Formal
defer
```

This transforms translation from a generic service into a **personalized language-learning environment**.

---

# 06 — Learning Intensity

Users can choose how visible the learning experience should be.

### Minimal

Keep the input experience clean.

```text
会议 → meeting
```

### Balanced

Provide useful learning signals without distraction.

```text
会议 → meeting · 12×
```

### Immersive

Actively surface:

* Alternative expressions
* Vocabulary information
* Learning signals
* Additional language exposure

The default should be **Balanced**.

---

# 07 — Optional Learning Features

Users can enable or disable individual learning tools.

### Micro-Recall

Shows how often a user has encountered a word.

```text
Seen 14 times
```

### Hover Pronunciation

Hover over a translation to hear pronunciation.

### Vocabulary Cards

Open a detailed learning card.

### Alternative Expressions

Show useful alternatives when appropriate.

### Collocations

Show common word combinations.

### Grammar Hints

Provide occasional explanations of useful grammatical patterns.

All of these features should remain optional so LinguaFlow does not become intrusive.

---

# 08 — Learning Priorities

Users can select what they most want to improve.

Possible priorities:

* Vocabulary
* Natural Expression
* Academic / Professional Language
* Pronunciation
* Grammar
* Confidence

These priorities can influence the information surfaced by the translation engine and vocabulary cards.

---

# 09 — Learning Style

Users can choose:

### Keep It Subtle

> I don't want to feel like I'm studying.

### Make It Noticeable

> I want regular language exposure while typing.

### Challenge Me

> I want LinguaFlow to actively introduce new vocabulary and expressions.

---

# Language Profile Summary

After onboarding, LinguaFlow generates a personalized profile.

Example:

```text
LANGUAGE
🇨🇳 Chinese → 🇺🇸 English

LEVEL
Intermediate

GOAL
Academic · Professional

DOMAIN
Technology · Business

STYLE
Neutral · Professional

INTENSITY
Balanced

PRIORITIES
Vocabulary · Natural Expression

ENABLED
✓ Micro-Recall
✓ Hover Pronunciation
✓ Vocabulary Cards
```

This profile becomes the foundation for personalized translation.

---

# Real-Time Candidate Translation

This is the **core interaction of LinguaFlow**.

Instead of requiring users to translate text after typing, translations appear directly inside the candidate interface.

Example:

```text
User input:

会议
```

Candidate interface:

```text
┌─────────────────────────────────┐
│  会议                            │
│  meeting                         │
│  conference                      │
│  appointment                     │
└─────────────────────────────────┘
```

The exact presentation can depend on:

* Context
* User's language pair
* Translation style
* Domain
* Language level
* Learning intensity
* Previous exposure

The system should prioritize the most useful translation rather than simply displaying every possible dictionary equivalent.

---

# Context-Aware Translation

Context awareness is a key component of LinguaFlow.

The same word can have different translations depending on context.

For example:

```text
bank
```

could refer to:

```text
financial institution
river bank
```

Similarly, the appropriate translation may change depending on the user's domain.

A technology user might receive terminology optimized for:

> Technology / Professional

while another user might receive:

> General / Casual

The translation system therefore considers:

```text
Current Input
      +
Surrounding Context
      +
User Profile
      +
Domain
      +
Style
      +
Language Level
      ↓
Personalized Translation
```

---

# Translation Style × Domain

LinguaFlow separates **Style** and **Domain**.

This is important because they represent different dimensions.

### Style

How the expression sounds.

```text
Casual
Neutral
Professional
Formal
Academic
```

### Domain

Where the expression is used.

```text
Technology
Business
Finance
Science
Law
Medicine
...
```

For example:

```text
Domain:
Technology

Style:
Professional
```

could produce a different translation from:

```text
Domain:
Everyday

Style:
Casual
```

This allows much more precise personalization.

---

# Micro-Recall

LinguaFlow does not require users to explicitly create flashcards.

Instead, it records lightweight exposure information.

For example:

```text
meeting
Seen 14 times
```

The purpose is simple:

> **Make repeated exposure visible.**

A user may encounter a word naturally dozens of times without realizing it.

Micro-Recall turns that repetition into a subtle learning signal.

Potential states include:

```text
New
Encountered
Familiar
Recognized
Used
Mastered
```

These should be treated as learning signals rather than definitive measurements of language proficiency.

---

# Vocabulary Cards

When users want to explore a translation further, they can open a Vocabulary Card.

The card is intentionally designed as a **micro-learning component**, rather than a traditional dictionary page.

---

## Card Layout

```text
┌──────────────────────────────────────────┐
│                                          │
│  postpone                         🔊     │
│  /pəˈspoʊn/   ·   verb                   │
│                                          │
│  延期 / 推迟                              │
│                                          │
│  ──────────────────────────────────────  │
│                                          │
│  CONTEXT                                 │
│  to delay something until a later time   │
│                                          │
│  ──────────────────────────────────────  │
│                                          │
│  EXAMPLE                                 │
│  We had to postpone the meeting.         │
│  我们不得不推迟会议。                      │
│                                          │
│  ──────────────────────────────────────  │
│                                          │
│  COLLOCATIONS                            │
│  postpone a meeting · postpone a        │
│  decision · postpone the event           │
│                                          │
│  ──────────────────────────────────────  │
│                                          │
│  SIMILAR                                 │
│  delay  ·  defer                         │
│                                          │
│  ──────────────────────────────────────  │
│                                          │
│  STYLE            DOMAIN                 │
│  Neutral          Business               │
│                                          │
│  ──────────────────────────────────────  │
│                                          │
│  ◉ Seen 14 times                         │
│                                          │
│                          More →          │
│                                          │
└──────────────────────────────────────────┘
```

---

# Vocabulary Card Information Architecture

```text
HEADER
Word + Pronunciation + Part of Speech + Audio
        ↓
TRANSLATION
Current contextual translation
        ↓
CONTEXT / DEFINITION
Meaning relevant to the current context
        ↓
EXAMPLE
Example sentence + translation
        ↓
COLLOCATIONS
Common word combinations
        ↓
SIMILAR WORDS
Synonyms / nuanced differences
        ↓
STYLE + DOMAIN
Language register / professional domain
        ↓
MICRO-RECALL
Seen ×
        ↓
MORE
Expanded information
```

---

# Progressive Information

Vocabulary Cards use three information layers.

### Layer 1 — Instant

Immediately available:

```text
postpone
/pəˈspoʊn/ 🔊
verb
```

### Layer 2 — Quick Learning

When the user opens the card:

```text
Meaning
Example
Collocations
Seen ×
```

### Layer 3 — Deep Learning

Available through **More / Explore More**:

```text
Synonyms
Register
Domain
Word family
Pronunciation details
Grammar
Etymology
Additional examples
```

This keeps the core interaction lightweight while allowing deeper exploration.

---

# Hover Pronunciation

When enabled, users can hover over a translated word.

Example:

```text
meeting  ← cursor
   ↓
🔊 /ˈmiːtɪŋ/
```

The goal is to connect:

```text
Visual recognition
        +
Sound
        +
Context
```

without requiring users to enter a separate pronunciation-learning environment.

---

# Personalization Architecture

The personalization system can be represented as:

```text
                    USER PROFILE
                         │
       ┌─────────────────┼─────────────────┐
       │                 │                 │
    Language           Style            Domain
       │                 │                 │
       └─────────────────┼─────────────────┘
                         │
                    Learning Level
                         │
                    Learning Goal
                         │
                         ▼
                TRANSLATION ENGINE
                         ▲
                         │
                  CURRENT CONTEXT
                         │
                         ▼
                PERSONALIZED OUTPUT
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
      Candidate        Hover          Card
          │           Audio            │
          │              │              │
          └──────────────┼──────────────┘
                         ▼
                  LEARNING HISTORY
                         │
                         ▼
                    MICRO-RECALL
```

---

# Core User Flow

The complete experience can be summarized as:

```text
ONBOARDING
    ↓
Create Language Profile
    ↓
Configure Goal / Domain / Style / Level
    ↓
────────────────────────────────
    ↓
EVERYDAY TYPING
    ↓
Type normally
    ↓
Real-time translations appear in candidates
    ↓
Natural exposure
    ↓
────────────────────────────────
    ↓
OPTIONAL INTERACTION
    │
    ├── Continue typing
    │
    ├── Hover → Pronunciation
    │
    └── Click → Vocabulary Card
                    ↓
              Explore meaning
                    ↓
              Examples / Usage
                    ↓
              Micro-Recall
                    ↓
              Repeated exposure
```

---

# What Makes LinguaFlow Different?

LinguaFlow sits at the intersection of:

```text
              INPUT
                │
                │
                ▼
         ┌──────────────┐
         │  LinguaFlow  │
         └──────────────┘
           │          │
           ▼          ▼
      TRANSLATION   LEARNING
           │          │
           └────┬─────┘
                ▼
        EVERYDAY WORKFLOW
```

Traditional products usually focus on one of these:

| Product Type             | Primary Function                             |
| ------------------------ | -------------------------------------------- |
| Traditional Input Method | Fast and accurate typing                     |
| Translator               | Translate existing text                      |
| Dictionary               | Explain individual words                     |
| AI Writing Tool          | Generate / improve text                      |
| Language Learning App    | Deliberate language study                    |
| **LinguaFlow**           | **Language exposure during everyday typing** |

The key difference is **where the translation happens**.

A translator waits for the user to ask.

LinguaFlow brings the translation **into the moment of input**.

---

# Product Scope

LinguaFlow is designed as a **multilingual input method**, rather than a Chinese-only input method.

The architecture should support multiple combinations of:

```text
Input Language
        ↕
Learning Language
```

Potential examples:

```text
Chinese → English
Chinese → Japanese
English → Chinese
English → Spanish
Japanese → English
Korean → English
...
```

The system should not fundamentally depend on a single source language or target language.

---

# Platform Strategy

LinguaFlow is intended to support desktop operating systems.

The initial implementation can focus on one platform while maintaining an architecture that can later support additional platforms.

Potential targets include:

* macOS
* Windows
* Other desktop environments in the future

The product concept itself is **platform-independent**.

---

# Product Architecture

At a high level, LinguaFlow can be separated into several layers:

```text
┌──────────────────────────────────────────┐
│              USER INTERFACE              │
│                                          │
│ Candidate UI · Settings · Cards · Audio  │
└────────────────────┬─────────────────────┘
                     │
┌────────────────────▼─────────────────────┐
│             INPUT ENGINE                 │
│                                          │
│ Keyboard Input · Candidate Generation    │
└────────────────────┬─────────────────────┘
                     │
┌────────────────────▼─────────────────────┐
│          CONTEXT & TRANSLATION           │
│                                          │
│ Context Analysis · Translation · Style   │
│ Domain Adaptation · Language Level       │
└────────────────────┬─────────────────────┘
                     │
┌────────────────────▼─────────────────────┐
│            LEARNING ENGINE               │
│                                          │
│ Vocabulary · Micro-Recall · History      │
│ Pronunciation · Learning Signals         │
└────────────────────┬─────────────────────┘
                     │
┌────────────────────▼─────────────────────┐
│             USER PROFILE                │
│                                          │
│ Languages · Goals · Domains · Style      │
│ Level · Intensity · Preferences          │
└──────────────────────────────────────────┘
```

---

# MVP

The first version should focus on the product's strongest differentiator rather than trying to build a complete language-learning platform.

### MVP Core

* Multilingual input
* Real-time translation inside candidate interface
* Configurable input / learning languages
* Basic context-aware translation
* Translation style selection
* Domain selection
* Basic Micro-Recall
* Vocabulary Card
* Hover pronunciation

### Secondary Features

* Alternative expressions
* Collocations
* Grammar hints
* Multiple language profiles
* Advanced learning history

### Future Possibilities

* Adaptive vocabulary difficulty
* Personalized review
* Spaced repetition
* Learning analytics
* Vocabulary goals
* Cross-device synchronization
* More advanced contextual models
* Additional platforms

---

# Privacy & Data

Because LinguaFlow operates at the input-method level, privacy is a fundamental product consideration.

The system may process highly sensitive user input depending on the application being used.

Therefore, privacy should be treated as a core architectural principle rather than an afterthought.

Potential principles include:

* Minimize stored input data
* Process locally whenever practical
* Avoid storing raw keystrokes unnecessarily
* Separate learning metadata from sensitive input
* Give users clear control over learning history
* Make cloud-based processing transparent
* Allow users to disable learning features

A production implementation should clearly define what data is processed locally, what is sent to external services, and what is stored.

---

# Development Philosophy

LinguaFlow should not attempt to become:

> "Another AI keyboard."

AI-powered prediction and generation can be useful supplementary features, but they are not the core product thesis.

The central question is:

> **How can everyday typing become a continuous source of language exposure?**

Every new feature should be evaluated against that principle.

If a feature makes the user more productive **and** creates meaningful language exposure, it strengthens LinguaFlow.

If it adds AI functionality without improving the learning experience, it should remain secondary.

---

# Roadmap

### Phase 1 — Foundation

* [ ] Define language architecture
* [ ] Build input engine prototype
* [ ] Implement candidate translation
* [ ] Create basic language profile
* [ ] Build candidate UI

### Phase 2 — Learning Layer

* [ ] Context-aware translation
* [ ] Translation style
* [ ] Domain personalization
* [ ] Micro-Recall
* [ ] Vocabulary Cards
* [ ] Hover pronunciation

### Phase 3 — Personalization

* [ ] Learning level adaptation
* [ ] Adaptive vocabulary
* [ ] Alternative expressions
* [ ] Collocations
* [ ] Grammar hints
* [ ] Multiple language profiles

### Phase 4 — Productization

* [ ] User-friendly installation
* [ ] Account system
* [ ] Cloud synchronization
* [ ] Subscription / commercialization infrastructure
* [ ] Cross-platform support
* [ ] Privacy controls

---

# Long-Term Vision

LinguaFlow aims to change the relationship between **productivity tools and language learning**.

Today, users generally have to choose:

```text
Work
     OR
Study
```

LinguaFlow proposes:

```text
Work
  +
Everyday Typing
  +
Natural Language Exposure
  =
Continuous Learning
```

The ultimate goal is not to make users spend more time studying.

It is to make them **learn more from the time they already spend typing**.

> **LinguaFlow — Type naturally. Learn effortlessly.**
> """
> from pathlib import Path
> p = Path("/mnt/data/README.md")
> p.write_text(content, encoding="utf-8")
> print(p)

---

# Prototype Development

`LinguaFlowPrototype` is the first native macOS SwiftUI visual prototype. It simulates candidate translation and Micro-Recall inside its own window; it is not yet a system input method.

## Requirements

- macOS 14 or later
- Xcode 26.6 installed at `/Applications/Xcode.app`
- No paid Apple Developer account is required for local development

## Open in Xcode

```bash
open LinguaFlowPrototype.xcodeproj
```

Choose the `LinguaFlowPrototype` scheme and `My Mac`, then press the Run button.

## Build and run

```bash
./script/build_and_run.sh
```

The script selects the full Xcode installation locally, so it does not require a global `xcode-select` change.

## Test

```bash
./script/build_and_run.sh --test
./script/build_and_run.sh --verify
```

Try these inputs in the prototype:

```text
huiyi · anpai · yanqi · shenqing · fangfa
```

Press Return to output the first candidate and increase its Seen count. You can also click any Chinese candidate to record that specific candidate.

All candidate data and Seen counts stay on the Mac. This prototype makes no network requests and requests no privacy-sensitive permissions.
