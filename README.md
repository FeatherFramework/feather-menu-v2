# Feather Menu v2

Feather Menu v2 is a focused, reactive menu-building resource for RedM. It owns menus, pages, elements, focus, input, presentation, and cleanup. It does not include notifications, version checking, persistence, or gameplay behavior, and it does not require `feather-core`.

> Existing scripts that require `feather-menu` need Feather Menu Legacy. Do not replace or rename that resource. `feather-menu` and `feather-menu-v2` may run together.

## Installation

Download the prepared `feather-menu-v2` release archive, extract it without renaming the folder, and add:

```cfg
ensure feather-menu-v2
```

Server operators do not need Node.js. Node and pnpm are used only by contributors to build the included NUI assets.

## Contract 1 example

```lua
local menu = exports['feather-menu-v2']:CreateMenu({
    key = 'example',
    draggable = true,
    resizable = true, -- Explicitly opt in; false/omitted disables the resize grip.
    persistSize = true, -- Default when enabled; set false to discard the size when the menu closes.
    size = { width = '32rem', minWidth = '20rem', maxHeight = '80vh' },
    theme = { preset = 'redemption' },
})

if not menu.ok then return print(menu.code, menu.message) end

local page = exports['feather-menu-v2']:CreatePage(menu.value.menuId, { key = 'main' })
local pageId = page.value.pageId

exports['feather-menu-v2']:AddElement(menu.value.menuId, pageId, 'header', {
    key = 'title', value = 'Example Menu', slot = 'header'
})

exports['feather-menu-v2']:AddElement(menu.value.menuId, pageId, 'button', {
    key = 'action', label = 'Continue'
}, function(event)
    print(event.action, event.elementId)
end)

exports['feather-menu-v2']:RegisterMenuLifecycle(menu.value.menuId, function(event)
    print(event.event, event.pageId, event.reason)
end)

exports['feather-menu-v2']:OpenMenu(menu.value.menuId, { pageId = pageId })
```

All public operations return `{ ok = true, value = ... }` or `{ ok = false, code, message, details? }`. Public IDs are owned by the calling resource and cleaned up when it stops.

The currently enforced alpha schemas and bounds are documented in [`docs/CONTRACT_1.md`](docs/CONTRACT_1.md).

## Contributor build

Node 22 is pinned in `.node-version`.

```text
cd web
corepack enable
pnpm install --frozen-lockfile
pnpm check
```

The Vite project lives in `/web` and builds directly into the runtime-only
`/ui` directory referenced by `fxmanifest.lua`. GitHub releases copy `/ui`
unchanged. Frontend source, Vue files, tests, package manifests, lockfiles, and
build configuration remain under `/web` and are excluded from the archive, so
CFX cannot mistake an installed release for a frontend project that needs an
automatic build.

## Live Cfx test resource

[`feather-menu-v2-test`](../feather-menu-v2-test/README.md) is a sibling standalone consumer resource, not an internal UI fixture. It runs Contract 1 assertions and provides an all-elements tabbed menu plus a character-creation-style stepper.

Start it after `feather-menu-v2`, then run `/MenuV2Test` or `/MenuV2Stepper`.
