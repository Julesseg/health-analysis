# Domain Docs

This repository uses one domain context, with `GLOSSARY.md` at the root and architectural decisions in `docs/adr/`.

## Before exploring

Read `GLOSSARY.md` and the ADRs relevant to the work. If either is absent, proceed without requesting new documentation up front; use the domain-modeling skill when terminology or decisions are actually resolved.

## Vocabulary

Use glossary terms in specifications, issues, proposals, tests, and code. If a needed concept is missing, first check whether an existing term covers it. Use the domain-modeling skill for a real terminology gap.

Keep input and output roles distinct from causal claims, behavior windows distinct from the analysis period, and assumed defaults distinct from explicit observations. A day review is separate from autosaving individual daily-log entries. Use the glossary definitions as the authority.

## Architectural decisions

Read applicable ADRs before proposing or implementing a change. Explicitly identify a conflict with an accepted ADR and explain why it merits reconsideration rather than silently overriding it.
