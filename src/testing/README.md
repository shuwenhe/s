# testing support packages

this directory holds reusable test infrastructure for the s repository.

planned responsibilities:

- `golden/`: golden-file comparison helpers
- `harness/`: shared test runner and suite orchestration utilities
- `testdata/`: reusable repository-level test fixtures

package-specific tests can continue to live beside their implementations.
shared testing code should move here as it becomes reusable across the repo.

