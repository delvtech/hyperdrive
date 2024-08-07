# DELV Solidity Style Guide

## Commenting

1. Use complete sentences and end them with the appropriate punctuation (typically a period).
2. Use correct spelling.
3. Use correct capitalization.
4. Comments should not go past the 80th column from the start of the line. An exception can be made for multi-line math comments in Ascii or Latex.
5. Add full Natspec to each contract, library, function, storage variable, struct, event, and error.
6. @notice tags indicate that something is part of the public interface and should be used for giving a synopsis of a contract, public and external functions, public state variables, events and errors.
7. @dev tags indicate something that developers will be interested in but isn't something that end users need to be concerned with. Each contract's Natspec should include a `@dev` section that explains the contract at a high-level and explains any gotchas that developers should be aware when integrating with or using the contracts.
6. Each contract must have a well-defined license.
7. Each contract's Natspec should contain the full legal disclaimer.
10. Integrations should include detailed comments explaining what is different or special about the implementation. This includes things like how interest accrues, why base or vault shares may not be a supported deposit or withdrawal asset, how the `convertToBase` or `convertToShares` functions work, etc.
11. Within function bodies, code should be broken up into logical chunks (hereafter called "comment blocks") that are clearly commented. These comments should logically explain what the block is accomplishing. Any comments interleaved within blocks should be `NOTE` or `TODO` comments.
    - For example, this follows the rule:
      ```
      // blah blah blah
      uint256 a = foo();
      a += b - c;
      // NOTE: We have to reduce a because…
      a = a.mulDown(0.5e18);
      ```
      Whereas this doesn’t:
      ```
      // blah blah blah
      uint256 a = foo();
      a += b - c;
      // We have to reduce a because…
      a = a.mulDown(0.5e18);
      ```
12. `FIXME` comments should always be removed before merging your PR.
13. A `NOTE` comment should be added above any line that uses fixed point math or another function that rounds up or down to explain why the code rounds in a particular direction.

## Imports

1. Relative paths are preferred because they improve lookups for LSP providers.
2. Imports must specify what they are importing.
3. All imports must be used.
4. Imports are sorted groups with absolute paths having the highest priority and relative paths having lower priority. Relative paths are grouped by the amount of leading `../`'s they have (more `../` have higher priority than less `../`).
5. Imports should be sorted alphabetically.

## Interfaces

1. Each immutable should have a corresponding getter.
2. Each state variable should have a corresponding getter or should be reachable through a generalized getter (like `loads`).
3. Each function that changes state should have an event that encodes the state changes that occurred within the function call. If possible, this event should be sufficient to fully recreate the state change that occurred from the previous state.

# Functions

1. Parameters should be prefaced with a leading underscore (`_`). To avoid shadowing internal or private immutable or storage values, prefix the parameter with a double underscore (`__`).

## Tests

1. Each test should have a comment above the function name giving a high-level description of what the test is doing.
2. Each test name that evaluates a failure case should contain "failure" in the function name.
