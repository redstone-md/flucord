# Coding standards

## Tests

Tautological tests considered harmful.

## Comments

Keep comments short. Delete any claim from comments that is derivable from the code.

## Scope

A change that leaves an acceptance criterion undone says why, and the reason names what was checked: the dependencies already in `pubspec.yaml`, the data the client receives, the code that solves a similar case. "Needs a new dependency" or "no data for it" without that check is a defect, not a reason.
