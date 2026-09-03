local root = arg[1] or '.'
dofile(root .. '/client/results.lua')
dofile(root .. '/client/validation.lua')

local passed = 0
local function Pass(condition, label)
    if not condition then error('FAIL ' .. label, 0) end
    passed = passed + 1
end
local function Valid(result, label) Pass(result == nil, label) end
local function Invalid(result, code, label)
    Pass(type(result) == 'table' and result.ok == false and result.code == code, label)
end

Valid(MenuValidation.Menu({ key = 'settings', draggable = true, resizable = false }, 'spec', true), 'valid menu')
Invalid(MenuValidation.Menu({ key = 'bad key' }, 'spec', true), 'invalid_input', 'unsafe menu key')
Invalid(MenuValidation.Menu({ key = 'menu', draggable = 'yes' }, 'spec', true), 'invalid_input', 'menu boolean')
Invalid(MenuValidation.Payload({ callback = function() end }, 'spec'), 'invalid_input', 'function payload')
Invalid(MenuValidation.Payload({ value = 0 / 0 }, 'spec'), 'invalid_input', 'NaN payload')
local cyclic = {}; cyclic.self = cyclic
Invalid(MenuValidation.Payload(cyclic, 'spec'), 'invalid_input', 'cyclic payload')

Valid(MenuValidation.Element('button', { key = 'save', label = 'Save' }), 'button')
Invalid(MenuValidation.Element('unknown', { key = 'bad' }), 'unsupported_element', 'unknown element')
Valid(MenuValidation.Element('toggle', { key = 'pvp', value = true }), 'toggle')
Invalid(MenuValidation.Element('toggle', { key = 'pvp', value = 'true' }), 'invalid_input', 'toggle value')
Valid(MenuValidation.Element('number', { key = 'age', value = 36, min = 18, max = 99, step = 1 }), 'number')
Invalid(MenuValidation.Element('number', { key = 'age', value = 100, min = 18, max = 99 }), 'invalid_input', 'numeric bounds')
Valid(MenuValidation.Element('dropdown', { key = 'town', value = 'valentine', options = {
    { value = 'valentine', label = 'Valentine' }, { value = 'blackwater', label = 'Blackwater' },
} }), 'dropdown')
Invalid(MenuValidation.Element('dropdown', { key = 'town', value = 'missing', options = {
    { value = 'valentine', label = 'Valentine' },
} }), 'invalid_input', 'selected option')
Invalid(MenuValidation.Element('dropdown', { key = 'town', value = 'one', maxVisibleOptions = 11, options = {
    { value = 'one', label = 'One' },
} }), 'invalid_input', 'dropdown row limit')
Valid(MenuValidation.Element('gridslider', { key = 'face', value = { x = 0.5, y = 0.5 }, maxx = 1, maxy = 1, step = 0.1 }), 'grid')
Invalid(MenuValidation.Element('gridslider', { key = 'face', value = { x = 2, y = 0.5 }, maxx = 1, maxy = 1 }), 'invalid_input', 'grid bounds')
Invalid(MenuValidation.Element('gridslider', { key = 'face', value = { x = 0.5, y = 0.5 }, step = 0 }), 'invalid_input', 'grid step')
Valid(MenuValidation.ElementChanges('toggle', { key = 'pvp', value = false }, { value = true }, 'changes'), 'valid merged update')
Invalid(MenuValidation.ElementChanges('toggle', { key = 'pvp', value = false }, { value = 'yes' }, 'changes'), 'invalid_input', 'invalid merged update')
Valid(MenuValidation.Navigation({ type = 'tabs', pages = {
    { pageId = 'menu/main', label = 'Main' }, { pageId = 'menu/language', label = 'Language' },
} }), 'tabs')
Invalid(MenuValidation.Navigation({ type = 'tabs', pages = {
    { pageId = 'menu/main' }, { pageId = 'menu/main' },
} }), 'invalid_input', 'duplicate navigation page')

print(('PASS validation suite %d assertions'):format(passed))
