# Feature Requirement: Palindrome Checker

## Title

Palindrome Checker

## Repo

ks-testing/agent-e2e-bun-template

## Description

Add a palindrome checker to the bun web server. The user submits a string via
an HTML form; the server responds with whether the string is a palindrome.

## Problem

The bun server template has an HTML form with no backend logic. We need a
palindrome solver to validate that the agent pipeline can implement a feature
end-to-end: from product requirement to specification, implementation, tested
release, and product verification.

## Acceptance Criteria

- The palindrome checker MUST be implemented as a backend service
- The backend response MUST return JSON with `input` (string) and
  `is_palindrome` (boolean) fields
- The HTML form in `packages/web/` MUST submit a string and display whether
  it is a palindrome
- The engineering agent MUST write Playwright end-to-end tests in
  `packages/e2e/` that exercise the palindrome happy path
- Playwright tests MUST capture screenshots at key steps following the naming
  convention `{test-name}.{step-index}.{step-name}.png`
- Screenshots MUST be committed via git LFS

## Priority

high

## Process

Please follow the standard product process:

1. Create a press release issue on the Forgejo repo describing the Palindrome
   Checker feature
2. Create a milestone titled "Palindrome Checker v1" and associate the press
   release issue with it
3. Assign the engineering agent to the press release issue (or create a linked
   engineering-intake issue assigned to the engineering agent) to begin
   implementation
