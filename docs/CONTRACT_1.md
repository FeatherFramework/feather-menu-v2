# Feather Menu v2 — Contract 1 alpha

This document describes the currently enforced public boundary. It is an alpha contract until the Master Plan Phase 0 freeze is approved.

## Common rules

- Every operation returns `{ ok = true, value = ... }` or `{ ok = false, code, message, details? }`.
- Menu ownership comes from `GetInvokingResource()`; callers cannot supply or borrow another resource's owner identity.
- Caller keys and generated handles contain 1–128 letters, numbers, `.`, `_`, `:`, `-`, or `/`.
- Definitions are copied. Mutating the caller's original Lua table does not mutate registered state.
- Payloads may contain tables, strings, finite numbers, booleans, and nil only.
- Payloads are limited to six nested table levels, 4,096 total fields, and 4,096 characters per string unless a field has a smaller limit.
- Cyclic tables, functions inside definitions, NaN, and positive/negative infinity are rejected.
- Cross-resource callbacks may be ordinary Lua functions or callable Cfx function-reference objects.

## Resource limits

| Scope | Contract 1 limit |
| --- | ---: |
| Registered menus | 64 |
| Pages per menu | 64 |
| Elements per page | 512 |
| Atomic patch operations | 256 |
| Choice options | 500 |
| Image-container children | 100 |

## Menu definition

`CreateMenu` requires `key`. Boolean flags include `draggable`, `resizable`, `closable`, `persistPosition`, and `persistSize`. Resizing is enabled only when `resizable = true`.

`position`, `size`, and `theme`, when present, must be tables. These token tables remain alpha and will receive exact field allowlists before the Contract 1 freeze.

## Common element fields

All elements require `key`. Common optional fields are:

- `slot`: `header`, `content`, or `footer`;
- `label`: at most 256 characters;
- `placeholder`: at most 256 characters;
- `disabled`, `persist`: booleans;
- `onLabel`, `offLabel`: at most 64 characters.

Header, subheader, input, and other short string values are limited to 512 characters. Textarea and text-display values are limited to 4,096 characters.

## Choice elements

`arrows`, `dropdown`, `radio`, and `colorpicker` require:

- a selected `value` that exactly matches an option value, including its Lua type;
- a sequential `options` array containing 1–500 entries;
- unique option values;
- option values limited to strings, finite numbers, or booleans;
- optional labels/text up to 256 characters and boolean disabled state.

Dropdowns display six rows by default. `maxVisibleOptions` accepts an integer from 3 through 10; additional options scroll inside the overlay.

## Numeric and spatial elements

- `number`, `slider`, and `progress` accept finite `value`, `min`, `max`, and positive `step`; value must be inside the declared range.
- `gridslider` requires `{ x, y }`, positive finite `maxx`/`maxy`, and coordinates inside those bounds. Pointer movement is local and one change is committed on release.
- `pagearrows` requires integer `current` and `total` with `1 <= current <= total`.
- `spacer.size` is `small`, `medium`, or `large`.

## Controlled behavior

Tabs navigate automatically unless configured as controlled. Steppers emit navigation intents and leave validation plus page changes to the consumer. Page arrows emit `previous` or `next`; the consumer updates `current` after accepting the intent.

Updates and NUI callback values are validated against the complete resulting element definition before state is mutated. `ApplyPatch` validates every operation before applying any operation.

## Still pending freeze

- Exact menu size, position, theme, sound, and asset URL allowlists;
- exact input draft/commit/clamp behavior;
- complete navigation update schemas;
- controller actions;
- callback metadata and acknowledgement semantics;
- performance and encoded-message byte budgets.
