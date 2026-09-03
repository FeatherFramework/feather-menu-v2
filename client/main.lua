local resourceName = GetCurrentResourceName()
local menus = {}
local activeMenuId = nil
local uiReady = false
local startedAt = GetGameTimer()

local limits = { menus = 64, pages = 64, elements = 512, patchOperations = 256 }

local function Owner()
    local owner = GetInvokingResource()
    if type(owner) ~= 'string' or owner == '' then return nil end
    return owner
end

local function Count(values)
    local count = 0
    for _ in pairs(values) do count = count + 1 end
    return count
end

local function Copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        if type(child) ~= 'function' then result[Copy(key, seen)] = Copy(child, seen) end
    end
    seen[value] = nil
    return result
end

local function Merge(target, changes)
    for key, value in pairs(changes) do
        if type(value) == 'table' and type(target[key]) == 'table' then
            Merge(target[key], value)
        else
            target[key] = Copy(value)
        end
    end
end

-- Cfx marshals callbacks crossing a resource boundary as callable function-reference
-- objects. They are tables in some runtime builds rather than plain Lua functions.
local function IsCallable(value)
    if type(value) == 'function' then return true end
    if type(value) ~= 'table' and type(value) ~= 'userdata' then return false end
    local metatable = getmetatable(value)
    return type(metatable) == 'table' and type(metatable.__call) == 'function'
end

local function Call(callback, payload)
    return pcall(function() callback(payload) end)
end

local function MenuFor(owner, menuId)
    local menu = menus[menuId]
    if not menu then return nil, MenuResults.Err('not_found', 'Menu was not found.') end
    if menu.owner ~= owner then return nil, MenuResults.Err('forbidden', 'Menu belongs to another resource.') end
    return menu, nil
end

local function PageFor(menu, pageId)
    local page = menu.pages[pageId]
    if not page then return nil, MenuResults.Err('not_found', 'Page was not found.') end
    return page, nil
end

local function PublicMenu(menu)
    local pages = {}
    for _, pageId in ipairs(menu.pageOrder) do
        local page = menu.pages[pageId]
        local elements = {}
        for _, elementId in ipairs(page.elementOrder) do elements[#elements + 1] = Copy(page.elements[elementId].public) end
        pages[#pages + 1] = { pageId = page.id, key = page.key, config = Copy(page.config), elements = elements }
    end
    local keys = {}
    for key in pairs(menu.keyCallbacks or {}) do keys[key] = true end
    return {
        menuId = menu.id, key = menu.key, revision = menu.revision, config = Copy(menu.config),
        pages = pages, activePageId = menu.activePageId, open = menu.open,
        navigation = Copy(menu.navigation), keys = keys,
    }
end

local function Send(action, payload)
    payload = payload or {}
    payload.action = action
    SendNUIMessage(payload)
end

local function Sync(menu)
    if uiReady then Send('menu:sync', { menu = PublicMenu(menu) }) end
end

local function Mutate(menu, operations)
    menu.revision = menu.revision + 1
    if uiReady then Send('menu:patch', { menuId = menu.id, revision = menu.revision, operations = operations }) end
end

local function EmitLifecycle(menu, event, details)
    if not menu.lifecycleCallback then return end
    local payload = Copy(details or {})
    payload.event = event
    payload.menuId = menu.id
    payload.pageId = payload.pageId or menu.activePageId
    local ok, problem = Call(menu.lifecycleCallback, payload)
    if not ok then print(('[%s] lifecycle callback failed owner=%s menu=%s error=%s'):format(resourceName, menu.owner, menu.id, tostring(problem))) end
end

local function Capabilities()
    return MenuResults.Ok({
        resource = resourceName, contract = 1,
        version = GetResourceMetadata(resourceName, 'version', 0) or '0.0.0',
        state = uiReady and 'ready' or 'starting',
        features = {
            menus = 1, pages = 1, elements = 1, focus = 1, dropdowns = 1,
            draggable = 1, resizable = 1, themes = 1, reactiveState = 1,
            tabs = 1, stepper = 1, ownerCleanup = 1, boundedValidation = 1,
        },
    })
end

local function Health()
    return MenuResults.Ok({ state = uiReady and 'ready' or 'starting', uiReady = uiReady, menuCount = Count(menus), activeMenuId = activeMenuId })
end

exports('GetCapabilities', Capabilities)
exports('GetHealth', Health)
exports('AwaitReady', function(timeoutMs)
    timeoutMs = tonumber(timeoutMs) or 0
    local deadline = GetGameTimer() + math.max(0, math.min(timeoutMs, 30000))
    repeat
        if uiReady then return Health() end
        if timeoutMs <= 0 then break end
        Wait(0)
    until GetGameTimer() >= deadline
    return MenuResults.Err(timeoutMs > 0 and 'timeout' or 'not_ready', 'Feather Menu UI is not ready.')
end)

print(('[%s] Contract 1 client exports registered; waiting for NUI readiness.'):format(resourceName))

exports('CreateMenu', function(spec)
    local owner = Owner()
    if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local invalid = MenuValidation.Menu(spec, 'spec', true)
    if invalid then return invalid end
    if Count(menus) >= limits.menus then return MenuResults.Err('limit_exceeded', 'Menu limit reached.') end
    local menuId = owner .. ':' .. spec.key
    if menus[menuId] then return MenuResults.Err('conflict', 'Menu key already exists for this resource.') end
    menus[menuId] = {
        id = menuId, key = spec.key, owner = owner, config = Copy(spec), pages = {}, pageOrder = {},
        revision = 0, open = false, activePageId = nil, navigation = nil, keyCallbacks = {}, lifecycleCallback = nil,
        focus = { keyboard = true, cursor = true },
    }
    return MenuResults.Ok({ menuId = menuId })
end)

exports('CreatePage', function(menuId, spec)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    local invalid = MenuValidation.Page(spec, 'spec', true); if invalid then return invalid end
    if Count(menu.pages) >= limits.pages then return MenuResults.Err('limit_exceeded', 'Page limit reached.') end
    local pageId = menuId .. '/' .. spec.key
    if menu.pages[pageId] then return MenuResults.Err('conflict', 'Page key already exists in this menu.') end
    menu.pages[pageId] = { id = pageId, key = spec.key, config = Copy(spec), elements = {}, elementOrder = {} }
    menu.pageOrder[#menu.pageOrder + 1] = pageId
    Mutate(menu, { { op = 'page:add', page = { pageId = pageId, key = spec.key, config = Copy(spec), elements = {} } } })
    return MenuResults.Ok({ pageId = pageId })
end)

exports('UpdatePage', function(menuId, pageId, changes)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    local page; page, failure = PageFor(menu, pageId); if failure then return failure end
    local invalid = MenuValidation.Page(changes, 'changes', false); if invalid then return invalid end
    Merge(page.config, changes); Mutate(menu, { { op = 'page:update', pageId = pageId, changes = Copy(changes) } })
    return MenuResults.Ok({ revision = menu.revision })
end)

exports('DestroyPage', function(menuId, pageId, fallbackPageId)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    local _, pageFailure = PageFor(menu, pageId); if pageFailure then return pageFailure end
    if menu.activePageId == pageId then
        if not fallbackPageId or fallbackPageId == pageId or not menu.pages[fallbackPageId] then
            return MenuResults.Err('conflict', 'Destroying the active page requires a valid fallbackPageId.')
        end
        menu.activePageId = fallbackPageId
    end
    menu.pages[pageId] = nil
    for index, id in ipairs(menu.pageOrder) do if id == pageId then table.remove(menu.pageOrder, index); break end end
    Mutate(menu, { { op = 'page:remove', pageId = pageId, fallbackPageId = fallbackPageId } })
    return MenuResults.Ok({ destroyed = true, revision = menu.revision })
end)

exports('AddElement', function(menuId, pageId, elementType, spec, callback)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    local page; page, failure = PageFor(menu, pageId); if failure then return failure end
    local invalid = MenuValidation.Element(elementType, spec, 'spec')
    if invalid then return invalid end
    if callback ~= nil and not IsCallable(callback) then return MenuResults.Err('invalid_input', 'callback must be callable.') end
    if Count(page.elements) >= limits.elements then return MenuResults.Err('limit_exceeded', 'Element limit reached.') end
    local elementId = pageId .. '/' .. spec.key
    if page.elements[elementId] then return MenuResults.Err('conflict', 'Element key already exists on this page.') end
    local public = { elementId = elementId, key = spec.key, type = elementType, data = Copy(spec) }
    page.elements[elementId] = { public = public, callback = callback }
    page.elementOrder[#page.elementOrder + 1] = elementId
    Mutate(menu, { { op = 'element:add', pageId = pageId, element = Copy(public) } })
    return MenuResults.Ok({ elementId = elementId })
end)

local function UpdateElement(owner, menuId, pageId, elementId, changes)
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    local page; page, failure = PageFor(menu, pageId); if failure then return failure end
    local element = page.elements[elementId]
    if not element then return MenuResults.Err('not_found', 'Element was not found.') end
    local invalid = MenuValidation.ElementChanges(element.public.type, element.public.data, changes, 'changes'); if invalid then return invalid end
    Merge(element.public.data, changes)
    Mutate(menu, { { op = 'element:update', pageId = pageId, elementId = elementId, changes = Copy(changes) } })
    return MenuResults.Ok({ revision = menu.revision })
end

exports('UpdateElement', function(menuId, pageId, elementId, changes)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    return UpdateElement(owner, menuId, pageId, elementId, changes)
end)

exports('SetElementValue', function(menuId, pageId, elementId, value)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    return UpdateElement(owner, menuId, pageId, elementId, { value = value })
end)

exports('FocusElement', function(menuId, pageId, elementId)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    local page; page, failure = PageFor(menu, pageId); if failure then return failure end
    if not page.elements[elementId] then return MenuResults.Err('not_found', 'Element was not found.') end
    if not menu.open or menu.activePageId ~= pageId then return MenuResults.Err('invalid_state', 'Element page is not active.') end
    Send('element:focus', { menuId = menuId, pageId = pageId, elementId = elementId })
    return MenuResults.Ok({ elementId = elementId })
end)

exports('RemoveElement', function(menuId, pageId, elementId)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    local page; page, failure = PageFor(menu, pageId); if failure then return failure end
    if not page.elements[elementId] then return MenuResults.Ok({ removed = false }, { idempotent = true }) end
    page.elements[elementId] = nil
    for index, id in ipairs(page.elementOrder) do if id == elementId then table.remove(page.elementOrder, index); break end end
    Mutate(menu, { { op = 'element:remove', pageId = pageId, elementId = elementId } })
    return MenuResults.Ok({ removed = true })
end)

exports('UpdateMenu', function(menuId, changes)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    local invalid = MenuValidation.Menu(changes, 'changes', false); if invalid then return invalid end
    Merge(menu.config, changes); Mutate(menu, { { op = 'menu:update', changes = Copy(changes) } })
    return MenuResults.Ok({ revision = menu.revision })
end)

exports('ApplyPatch', function(menuId, operations)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    if type(operations) ~= 'table' or #operations == 0 or #operations > limits.patchOperations then
        return MenuResults.Err('invalid_input', 'operations must be a non-empty bounded array.')
    end
    for index, operation in ipairs(operations) do
        if type(operation) ~= 'table' or operation.op ~= 'updateElement' or type(operation.changes) ~= 'table' then
            return MenuResults.Err('invalid_input', 'Contract 1 patches currently accept updateElement operations.', { index = index })
        end
        local page = menu.pages[operation.pageId]
        if not page or not page.elements[operation.elementId] then
            return MenuResults.Err('not_found', 'Patch references an unknown page or element.', { index = index })
        end
        local element = page.elements[operation.elementId]
        local invalid = MenuValidation.ElementChanges(element.public.type, element.public.data, operation.changes, 'operations.' .. index .. '.changes')
        if invalid then return invalid end
    end
    local publicOperations = {}
    for _, operation in ipairs(operations) do
        local element = menu.pages[operation.pageId].elements[operation.elementId]
        Merge(element.public.data, operation.changes)
        publicOperations[#publicOperations + 1] = {
            op = 'element:update', pageId = operation.pageId, elementId = operation.elementId,
            changes = Copy(operation.changes),
        }
    end
    Mutate(menu, publicOperations)
    return MenuResults.Ok({ revision = menu.revision, applied = #publicOperations })
end)

exports('ConfigureNavigation', function(menuId, spec, callback)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    local invalid = MenuValidation.Navigation(spec, 'spec'); if invalid then return invalid end
    if callback ~= nil and not IsCallable(callback) then return MenuResults.Err('invalid_input', 'callback must be callable.') end
    menu.navigation = Copy(spec); menu.navigationCallback = callback
    Mutate(menu, { { op = 'navigation:set', navigation = Copy(spec) } })
    return MenuResults.Ok({ revision = menu.revision })
end)

exports('RegisterKeyAction', function(menuId, key, callback)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    if type(key) ~= 'string' or key == '' or #key > 32 or not IsCallable(callback) then
        return MenuResults.Err('invalid_input', 'key and callback are required.')
    end
    menu.keyCallbacks[key] = callback
    Mutate(menu, { { op = 'key:set', key = key } })
    return MenuResults.Ok({ key = key })
end)

exports('RemoveKeyAction', function(menuId, key)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    menu.keyCallbacks[key] = nil
    Mutate(menu, { { op = 'key:remove', key = key } })
    return MenuResults.Ok({ key = key })
end)

exports('RegisterMenuLifecycle', function(menuId, callback)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    if callback ~= nil and not IsCallable(callback) then return MenuResults.Err('invalid_input', 'callback must be callable or nil.') end
    menu.lifecycleCallback = callback
    return MenuResults.Ok({ registered = callback ~= nil })
end)

exports('UpdateNavigation', function(menuId, changes)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    if not menu.navigation then return MenuResults.Err('invalid_state', 'Navigation is not configured.') end
    local candidate = Copy(menu.navigation); Merge(candidate, changes)
    local invalid = MenuValidation.Navigation(candidate, 'changes'); if invalid then return invalid end
    Merge(menu.navigation, changes); Mutate(menu, { { op = 'navigation:update', changes = Copy(changes) } })
    return MenuResults.Ok({ revision = menu.revision })
end)

exports('NavigateToPage', function(menuId, pageId)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    local _, pageFailure = PageFor(menu, pageId); if pageFailure then return pageFailure end
    local fromPageId = menu.activePageId
    menu.activePageId = pageId; Mutate(menu, { { op = 'page:activate', pageId = pageId } })
    EmitLifecycle(menu, 'pageChanged', { fromPageId = fromPageId, pageId = pageId })
    return MenuResults.Ok({ pageId = pageId, revision = menu.revision })
end)

exports('OpenMenu', function(menuId, options)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    if not uiReady then return MenuResults.Err('not_ready', 'Feather Menu UI is not ready.') end
    options = type(options) == 'table' and options or {}
    local pageId = options.pageId or menu.activePageId or menu.pageOrder[1]
    if not pageId or not menu.pages[pageId] then return MenuResults.Err('invalid_state', 'Menu has no valid startup page.') end
    if activeMenuId and activeMenuId ~= menuId then
        local active = menus[activeMenuId]
        if options.replace == false then return MenuResults.Err('focus_unavailable', 'Another menu is active.') end
        if active then
            active.open = false
            Send('menu:close', { menuId = active.id })
            EmitLifecycle(active, 'closed', { reason = 'replaced', replacedByMenuId = menuId })
        end
    end
    menu.activePageId = pageId; menu.open = true; activeMenuId = menuId; Sync(menu)
    Send('menu:open', { menuId = menuId, pageId = pageId })
    menu.focus = { keyboard = options.keyboard ~= false, cursor = options.cursor ~= false }
    SetNuiFocus(menu.focus.keyboard, menu.focus.cursor)
    if type(options.sound) == 'table' and type(options.sound.action) == 'string' and type(options.sound.soundset) == 'string' then
        PlaySoundFrontend(options.sound.action, options.sound.soundset, true, 0)
    end
    EmitLifecycle(menu, 'opened', { pageId = pageId })
    return MenuResults.Ok({ menuId = menuId, pageId = pageId })
end)

local function Close(menu, reason)
    local wasOpen = menu.open
    menu.open = false
    if activeMenuId == menu.id then activeMenuId = nil; SetNuiFocus(false, false) end
    if uiReady then Send('menu:close', { menuId = menu.id }) end
    if wasOpen then EmitLifecycle(menu, 'closed', { reason = reason or 'api' }) end
end

exports('CloseMenu', function(menuId, options)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    Close(menu, 'api')
    if type(options) == 'table' and type(options.sound) == 'table'
        and type(options.sound.action) == 'string' and type(options.sound.soundset) == 'string' then
        PlaySoundFrontend(options.sound.action, options.sound.soundset, true, 0)
    end
    return MenuResults.Ok({ menuId = menuId })
end)

exports('DestroyMenu', function(menuId)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    Close(menu); menus[menuId] = nil; Send('menu:destroy', { menuId = menuId })
    return MenuResults.Ok({ destroyed = true })
end)

exports('DestroyOwnedMenus', function()
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local removed = 0
    for menuId, menu in pairs(menus) do
        if menu.owner == owner then Close(menu); menus[menuId] = nil; Send('menu:destroy', { menuId = menuId }); removed = removed + 1 end
    end
    return MenuResults.Ok({ removed = removed })
end)

exports('GetMenuState', function(menuId)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    return MenuResults.Ok(PublicMenu(menu))
end)

exports('SyncMenu', function(menuId)
    local owner = Owner(); if not owner then return MenuResults.Err('unauthenticated', 'Calling resource is required.') end
    local menu, failure = MenuFor(owner, menuId); if failure then return failure end
    Sync(menu); return MenuResults.Ok({ revision = menu.revision })
end)

RegisterNUICallback('ready', function(_, cb)
    uiReady = true
    for _, menu in pairs(menus) do if menu.open then Sync(menu) end end
    cb({ ok = true })
end)

RegisterNUICallback('desync', function(data, cb)
    local menu = type(data) == 'table' and menus[data.menuId] or nil
    if menu then Sync(menu) end
    cb({ ok = menu ~= nil })
end)

RegisterNUICallback('close', function(data, cb)
    local menu = type(data) == 'table' and menus[data.menuId] or nil
    if menu and menu.open and menu.config.closable ~= false then Close(menu, 'user') end
    cb({ ok = true })
end)

RegisterNUICallback('elementAction', function(data, cb)
    local menu = type(data) == 'table' and menus[data.menuId] or nil
    local page = menu and menu.pages[data.pageId] or nil
    local element = page and page.elements[data.elementId] or nil
    if not menu or not menu.open or menu.activePageId ~= data.pageId or not element then cb({ ok = false }); return end
    if element.public.data.disabled == true then cb({ ok = false }); return end
    if data.value ~= nil and element.public.data.persist ~= false then
        local invalid = MenuValidation.ElementChanges(element.public.type, element.public.data, { value = data.value }, 'callback.value')
        if invalid then cb({ ok = false, code = invalid.code }); return end
        element.public.data.value = Copy(data.value)
        Mutate(menu, { {
            op = 'element:update', pageId = page.id, elementId = element.public.elementId,
            changes = { value = Copy(data.value) },
        } })
    end
    if element.callback then
        local ok, problem = Call(element.callback, {
            menuId = menu.id, pageId = page.id, elementId = element.public.elementId,
            action = data.event or 'activate', value = Copy(data.value), meta = Copy(data.meta),
        })
        if not ok then print(('[%s] callback failed owner=%s element=%s error=%s'):format(resourceName, menu.owner, element.public.elementId, tostring(problem))) end
    end
    cb({ ok = true })
end)

RegisterNUICallback('navigationIntent', function(data, cb)
    local menu = type(data) == 'table' and menus[data.menuId] or nil
    if menu and menu.open and menu.navigation and menu.navigation.type == 'tabs' and menu.navigation.controlled ~= true
        and type(data.toPageId) == 'string' and menu.pages[data.toPageId] then
        local fromPageId = menu.activePageId
        menu.activePageId = data.toPageId
        Mutate(menu, { { op = 'page:activate', pageId = data.toPageId } })
        EmitLifecycle(menu, 'pageChanged', { fromPageId = fromPageId, pageId = data.toPageId })
    end
    if menu and menu.open and menu.navigationCallback then
        local ok, problem = Call(menu.navigationCallback, Copy(data))
        if not ok then print(('[%s] navigation callback failed: %s'):format(resourceName, tostring(problem))) end
    end
    cb({ ok = menu ~= nil })
end)

RegisterNUICallback('keyAction', function(data, cb)
    local menu = type(data) == 'table' and menus[data.menuId] or nil
    local callback = menu and menu.open and menu.keyCallbacks[data.key] or nil
    if callback then
        local ok, problem = Call(callback, { menuId = menu.id, key = data.key })
        if not ok then print(('[%s] key callback failed: %s'):format(resourceName, tostring(problem))) end
    end
    cb({ ok = callback ~= nil })
end)

RegisterNUICallback('playSound', function(data, cb)
    if type(data) == 'table' and type(data.action) == 'string' and type(data.soundset) == 'string' then
        PlaySoundFrontend(data.action, data.soundset, true, 0)
    end
    cb({ ok = true })
end)

AddEventHandler('onClientResourceStop', function(stopped)
    if stopped == resourceName then SetNuiFocus(false, false); return end
    for menuId, menu in pairs(menus) do
        if menu.owner == stopped then
            if activeMenuId == menuId then SetNuiFocus(false, false); activeMenuId = nil end
            menus[menuId] = nil
            if uiReady then Send('menu:destroy', { menuId = menuId }) end
        end
    end
end)

CreateThread(function()
    Wait(5000)
    if not uiReady then print(('[%s] NUI did not report ready after %dms. Verify compiled ui/index.html and ui/assets are present.'):format(resourceName, GetGameTimer() - startedAt)) end
end)

CreateThread(function()
    local pausedMenuId = nil
    while true do
        Wait(0)
        if activeMenuId and IsPauseMenuActive() then
            local menu = menus[activeMenuId]
            if menu then
                pausedMenuId = menu.id
                menu.open = false
                activeMenuId = nil
                SetNuiFocus(false, false)
                Send('menu:close', { menuId = menu.id })
                EmitLifecycle(menu, 'suspended', { reason = 'pauseMenu' })
            end
        elseif pausedMenuId and not IsPauseMenuActive() then
            local menu = menus[pausedMenuId]
            pausedMenuId = nil
            if menu and not activeMenuId then
                menu.open = true
                activeMenuId = menu.id
                Sync(menu)
                Send('menu:open', { menuId = menu.id, pageId = menu.activePageId })
                SetNuiFocus(menu.focus.keyboard, menu.focus.cursor)
                EmitLifecycle(menu, 'resumed', { reason = 'pauseMenu' })
            end
        end
    end
end)
