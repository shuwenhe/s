# Testing Support Packages

This directory holds reusable test infrastructure for the S repository.

Planned responsibilities:

- `golden/`: golden-file comparison helpers
- `harness/`: shared test runner and suite orchestration utilities
- `testdata/`: reusable repository-level test fixtures

Package-specific tests can continue to live beside their implementations.
Shared testing code should move here as it becomes reusable across the repo.

