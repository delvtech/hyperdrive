# DELV Solidity Style Guide

## Commenting

1. Use complete sentences and end them with the appropriate puntuaction (typically a period).
2. Use correct spelling.
3. Use correct capitalization.
4. Comments should not go past the 80th column from the start of the line.
5. Add  full Natspec to each contract, library, function, storage variable, struct, event, and error.
6. Within function bodies, code should be broken up into logical chunks (hereafter called "comment blocks") that are clearly commented. These comments should logically explain what the block is accomplishing. Any comments interleaved within blocks should be `NOTE` or `TODO` comments.
7. `FIXME` comments should always be removed before merging your PR.
8. A `NOTE` comment should be added above any line that uses fixed point math or another function that rounds up or down to explain why the code rounds in a particular direction.
9. Integrations should include detailed comments explaining what is different or special about the implementation. This includes things like how interest accrues, why base or vault shares may not be a supported deposit or withdrawal asset, how the `convertToBase` or `convertToShares` functions work, etc.

## Imports

1. Relative paths are preferred because they improve lookups for LSP providers.
2. Imports must specify what they are importing.
3. All imports must be used.

## Interfaces

1. Each immutable should have a corresponding getter.
2. Each state variable should have a corresponding getter or should be reachable through a generalized getter (like `loads`).
3. Each function should have an event that encodes the state changes that occurred within the function call. If possible, this event should be sufficient to fully recreate the state change that occurred from the previous state.
