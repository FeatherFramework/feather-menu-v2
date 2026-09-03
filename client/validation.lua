MenuValidation = {}

local allowedElementTypes = {
    header = true, subheader = true, line = true, bottomline = true,
    button = true, input = true, textarea = true, slider = true,
    arrows = true, toggle = true, checkbox = true, dropdown = true,
    gridslider = true, imagebox = true, imageboxcontainer = true,
    pagearrows = true, textdisplay = true, radio = true, number = true,
    progress = true, spacer = true, colorpicker = true,
}

local optionTypes = { arrows = true, dropdown = true, radio = true, colorpicker = true }
local stringValueTypes = { header = true, subheader = true, textdisplay = true, input = true, textarea = true }
local numericValueTypes = { slider = true, number = true, progress = true }
local booleanValueTypes = { toggle = true, checkbox = true }
local slots = { header = true, content = true, footer = true }
local spacerSizes = { small = true, medium = true, large = true }

local function Err(path, message, details)
    details = details or {}
    details.path = path
    return MenuResults.Err('invalid_input', path .. ' ' .. message, details)
end

local function Count(value)
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    return count
end

local function Copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do result[Copy(key, seen)] = Copy(child, seen) end
    seen[value] = nil
    return result
end

local function Merge(target, changes)
    for key, value in pairs(changes) do
        if type(value) == 'table' and type(target[key]) == 'table' then Merge(target[key], value)
        else target[key] = Copy(value) end
    end
end

function MenuValidation.Id(value, path)
    if type(value) ~= 'string' or value == '' or #value > 128 or not value:match('^[%w%._:%-/]+$') then
        return Err(path or 'key', 'must be 1-128 safe characters.')
    end
    return nil
end

function MenuValidation.ElementType(value)
    if type(value) ~= 'string' or not allowedElementTypes[value] then
        return MenuResults.Err('unsupported_element', 'Unsupported element type.', { elementType = value })
    end
    return nil
end

function MenuValidation.Table(value, path)
    if type(value) ~= 'table' then return Err(path or 'value', 'must be a table.') end
    return nil
end

function MenuValidation.Finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

function MenuValidation.Payload(value, path, limits)
    limits = limits or {}
    local maxDepth = limits.maxDepth or 6
    local maxEntries = limits.maxEntries or 4096
    local maxString = limits.maxString or 4096
    local entries, seen = 0, {}
    local function Visit(child, childPath, depth)
        local kind = type(child)
        if kind == 'string' then
            if #child > maxString then return Err(childPath, ('exceeds %d characters.'):format(maxString)) end
            return nil
        end
        if kind == 'number' then
            if not MenuValidation.Finite(child) then return Err(childPath, 'must be a finite number.') end
            return nil
        end
        if kind == 'nil' or kind == 'boolean' then return nil end
        if kind ~= 'table' then return Err(childPath, 'contains an unsupported value type.', { valueType = kind }) end
        if seen[child] then return Err(childPath, 'must not contain cycles.') end
        if depth > maxDepth then return Err(childPath, ('exceeds maximum depth %d.'):format(maxDepth)) end
        seen[child] = true
        for key, nested in pairs(child) do
            entries = entries + 1
            if entries > maxEntries then return Err(path, ('exceeds %d total fields.'):format(maxEntries)) end
            if type(key) ~= 'string' and type(key) ~= 'number' then return Err(childPath, 'contains an unsupported key type.') end
            if key == '__proto__' or key == 'prototype' or key == 'constructor' then return Err(childPath .. '.' .. key, 'is reserved.') end
            local problem = Visit(nested, childPath .. '.' .. tostring(key), depth + 1)
            if problem then return problem end
        end
        seen[child] = nil
        return nil
    end
    return Visit(value, path or 'value', 0)
end

local function OptionalString(spec, key, path, maxLength)
    local value = spec[key]
    if value == nil then return nil end
    if type(value) ~= 'string' or #value > maxLength then return Err(path .. '.' .. key, ('must be a string up to %d characters.'):format(maxLength)) end
end

local function OptionalBoolean(spec, key, path)
    if spec[key] ~= nil and type(spec[key]) ~= 'boolean' then return Err(path .. '.' .. key, 'must be boolean.') end
end

local function OptionalFinite(spec, key, path)
    if spec[key] ~= nil and not MenuValidation.Finite(spec[key]) then return Err(path .. '.' .. key, 'must be a finite number.') end
end

local function ValidateOptions(spec, path)
    if type(spec.options) ~= 'table' then return Err(path .. '.options', 'must be an array.') end
    if #spec.options == 0 or #spec.options > 500 or Count(spec.options) ~= #spec.options then
        return Err(path .. '.options', 'must contain 1-500 sequential entries.')
    end
    local values = {}
    for index, option in ipairs(spec.options) do
        local optionPath = path .. '.options.' .. index
        local value = option
        if type(option) == 'table' then
            value = option.value
            local problem = OptionalString(option, 'label', optionPath, 256)
                or OptionalString(option, 'text', optionPath, 256)
                or OptionalBoolean(option, 'disabled', optionPath)
            if problem then return problem end
        end
        local valueType = type(value)
        if valueType ~= 'string' and valueType ~= 'number' and valueType ~= 'boolean' then
            return Err(optionPath .. '.value', 'must be a string, finite number, or boolean.')
        end
        if valueType == 'number' and not MenuValidation.Finite(value) then return Err(optionPath .. '.value', 'must be finite.') end
        if valueType == 'string' and #value > 256 then return Err(optionPath .. '.value', 'exceeds 256 characters.') end
        local identity = valueType .. ':' .. tostring(value)
        if values[identity] then return Err(optionPath .. '.value', 'must be unique.') end
        values[identity] = true
    end
end

function MenuValidation.Menu(spec, path, requireKey)
    path = path or 'spec'
    local problem = MenuValidation.Table(spec, path) or MenuValidation.Payload(spec, path)
    if problem then return problem end
    if requireKey then problem = MenuValidation.Id(spec.key, path .. '.key'); if problem then return problem end end
    for _, key in ipairs({ 'draggable', 'resizable', 'closable', 'persistPosition', 'persistSize' }) do
        problem = OptionalBoolean(spec, key, path); if problem then return problem end
    end
    if spec.position ~= nil and type(spec.position) ~= 'table' then return Err(path .. '.position', 'must be a table.') end
    if spec.size ~= nil and type(spec.size) ~= 'table' then return Err(path .. '.size', 'must be a table.') end
    if spec.theme ~= nil and type(spec.theme) ~= 'table' then return Err(path .. '.theme', 'must be a table.') end
    return nil
end

function MenuValidation.Page(spec, path, requireKey)
    path = path or 'spec'
    local problem = MenuValidation.Table(spec, path) or MenuValidation.Payload(spec, path)
    if problem then return problem end
    if requireKey then return MenuValidation.Id(spec.key, path .. '.key') end
    return nil
end

function MenuValidation.Element(elementType, spec, path)
    path = path or 'spec'
    local problem = MenuValidation.ElementType(elementType) or MenuValidation.Table(spec, path)
        or MenuValidation.Payload(spec, path) or MenuValidation.Id(spec.key, path .. '.key')
    if problem then return problem end
    problem = OptionalString(spec, 'label', path, 256) or OptionalString(spec, 'placeholder', path, 256)
        or OptionalString(spec, 'onLabel', path, 64) or OptionalString(spec, 'offLabel', path, 64)
        or OptionalBoolean(spec, 'disabled', path) or OptionalBoolean(spec, 'persist', path)
    if problem then return problem end
    if spec.slot ~= nil and not slots[spec.slot] then return Err(path .. '.slot', 'must be header, content, or footer.') end

    if stringValueTypes[elementType] and spec.value ~= nil then
        local maximum = (elementType == 'textarea' or elementType == 'textdisplay') and 4096 or 512
        if type(spec.value) ~= 'string' or #spec.value > maximum then return Err(path .. '.value', ('must be a string up to %d characters.'):format(maximum)) end
    end
    if booleanValueTypes[elementType] and spec.value ~= nil and type(spec.value) ~= 'boolean' then return Err(path .. '.value', 'must be boolean.') end
    if numericValueTypes[elementType] then
        for _, key in ipairs({ 'value', 'min', 'max', 'step' }) do problem = OptionalFinite(spec, key, path); if problem then return problem end end
        local minimum, maximum = spec.min or 0, spec.max or 100
        if minimum > maximum then return Err(path .. '.min', 'must not exceed max.') end
        if spec.step ~= nil and spec.step <= 0 then return Err(path .. '.step', 'must be greater than zero.') end
        if spec.value ~= nil and (spec.value < minimum or spec.value > maximum) then return Err(path .. '.value', 'must be within min and max.') end
    end
    if optionTypes[elementType] then
        problem = ValidateOptions(spec, path); if problem then return problem end
        if spec.value == nil then return Err(path .. '.value', 'is required for this choice element.') end
        local selected = false
        for _, option in ipairs(spec.options) do
            local optionValue = type(option) == 'table' and option.value or option
            if type(optionValue) == type(spec.value) and optionValue == spec.value then selected = true; break end
        end
        if not selected then return Err(path .. '.value', 'must match one of the option values.') end
        if elementType == 'dropdown' and spec.maxVisibleOptions ~= nil then
            if not MenuValidation.Finite(spec.maxVisibleOptions) or spec.maxVisibleOptions % 1 ~= 0
                or spec.maxVisibleOptions < 3 or spec.maxVisibleOptions > 10 then
                return Err(path .. '.maxVisibleOptions', 'must be an integer from 3 through 10.')
            end
        end
    end
    if elementType == 'gridslider' then
        if type(spec.value) ~= 'table' then return Err(path .. '.value', 'must contain x and y.') end
        local maxx, maxy = spec.maxx or 1, spec.maxy or 1
        if not MenuValidation.Finite(maxx) or maxx <= 0 or not MenuValidation.Finite(maxy) or maxy <= 0 then return Err(path, 'grid bounds must be positive finite numbers.') end
        if not MenuValidation.Finite(spec.value.x) or not MenuValidation.Finite(spec.value.y)
            or spec.value.x < 0 or spec.value.x > maxx or spec.value.y < 0 or spec.value.y > maxy then
            return Err(path .. '.value', 'x and y must be finite and within grid bounds.')
        end
        for _, key in ipairs({ 'step', 'stepx', 'stepy' }) do
            if spec[key] ~= nil and (not MenuValidation.Finite(spec[key]) or spec[key] <= 0) then
                return Err(path .. '.' .. key, 'must be a positive finite number.')
            end
        end
    end
    if elementType == 'pagearrows' then
        if not MenuValidation.Finite(spec.current) or not MenuValidation.Finite(spec.total)
            or spec.current % 1 ~= 0 or spec.total % 1 ~= 0 or spec.total < 1 or spec.current < 1 or spec.current > spec.total then
            return Err(path, 'page arrows require integer current/total with 1 <= current <= total.')
        end
    end
    if elementType == 'imageboxcontainer' then
        if type(spec.items) ~= 'table' or #spec.items == 0 or #spec.items > 100 or Count(spec.items) ~= #spec.items then
            return Err(path .. '.items', 'must contain 1-100 sequential entries.')
        end
        for index, item in ipairs(spec.items) do
            if type(item) ~= 'table' then return Err(path .. '.items.' .. index, 'must be a table.') end
            problem = OptionalString(item, 'label', path .. '.items.' .. index, 256)
                or OptionalString(item, 'image', path .. '.items.' .. index, 2048)
                or OptionalString(item, 'img', path .. '.items.' .. index, 2048)
                or OptionalBoolean(item, 'disabled', path .. '.items.' .. index)
            if problem then return problem end
        end
    end
    if elementType == 'spacer' and spec.size ~= nil and not spacerSizes[spec.size] then return Err(path .. '.size', 'must be small, medium, or large.') end
    return nil
end

function MenuValidation.ElementChanges(elementType, current, changes, path)
    local problem = MenuValidation.Table(changes, path or 'changes') or MenuValidation.Payload(changes, path or 'changes')
    if problem then return problem end
    local candidate = Copy(current)
    Merge(candidate, changes)
    return MenuValidation.Element(elementType, candidate, path or 'changes')
end

function MenuValidation.Navigation(spec, path)
    path = path or 'spec'
    local problem = MenuValidation.Table(spec, path) or MenuValidation.Payload(spec, path)
    if problem then return problem end
    if spec.type ~= 'tabs' and spec.type ~= 'stepper' then return Err(path .. '.type', 'must be tabs or stepper.') end
    if type(spec.pages) ~= 'table' or #spec.pages == 0 or #spec.pages > 64 or Count(spec.pages) ~= #spec.pages then
        return Err(path .. '.pages', 'must contain 1-64 sequential entries.')
    end
    local ids = {}
    for index, page in ipairs(spec.pages) do
        if type(page) ~= 'table' then return Err(path .. '.pages.' .. index, 'must be a table.') end
        problem = MenuValidation.Id(page.pageId, path .. '.pages.' .. index .. '.pageId')
            or OptionalString(page, 'label', path .. '.pages.' .. index, 128)
            or OptionalBoolean(page, 'disabled', path .. '.pages.' .. index)
            or OptionalBoolean(page, 'hidden', path .. '.pages.' .. index)
        if problem then return problem end
        if ids[page.pageId] then return Err(path .. '.pages.' .. index .. '.pageId', 'must be unique.') end
        ids[page.pageId] = true
    end
    return nil
end
