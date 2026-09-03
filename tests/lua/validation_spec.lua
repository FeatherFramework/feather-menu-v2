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

Invalid(MenuValidation.Menu({ key = 'menu', dragable = true }, 'spec', true), 'invalid_input', 'unknown menu field')
Invalid(MenuValidation.Menu({ key = 'menu', theme = { background = 'url(https://example.com)' } }, 'spec', true), 'invalid_input', 'CSS asset injection')
Valid(MenuValidation.Menu({ key = 'menu', size = { width = '32rem', breakpoints = { ['720'] = '25rem' } }, theme = { background = 'rgba(22, 17, 14, .96)' } }, 'spec', true), 'bounded style tokens')
Invalid(MenuValidation.Element('imagebox', { key = 'image', image = 'https://example.com/image.png' }), 'invalid_input', 'remote image rejected')
Valid(MenuValidation.Element('imagebox', { key = 'image', image = 'https://cfx-nui-my-resource/images/icon.png' }), 'local Cfx image')
Valid(MenuValidation.Element('dropdown', { key = 'bool', value = false, options = { { value = false, label = 'No' }, { value = true, label = 'Yes' } } }), 'false option values')
Invalid(MenuValidation.Element('dropdown', { key = 'duplicates', value = 1, options = { 1, 1.0 } }), 'invalid_input', 'integer and float representations are the same choice')
Invalid(MenuValidation.Element('textarea', { key = 'bio', value = 'too long', maxLength = 3 }), 'invalid_input', 'text length enforced')
Invalid(MenuValidation.Element('textarea', { key = 'bio', rows = 0 }), 'invalid_input', 'textarea rows enforced')
local options = { key = 'choice', value = 'a', options = { 'a', 'b', 'c' } }
local replacement = MenuValidation.Copy(options)
MenuValidation.Merge(replacement, { options = { 'a' } })
Pass(#replacement.options == 1 and #options.options == 3, 'array replacement and defensive copy')
Invalid(MenuValidation.ElementAction({ type = 'toggle', data = { key = 'toggle', value = false, persist = false } }, { event = 'change', value = 'bad' }), 'invalid_input', 'non-persisted callback validation')
Invalid(MenuValidation.ElementAction({ type = 'dropdown', data = { key = 'choice', value = 'a', options = { 'a', { value = 'b', disabled = true } } } }, { event = 'change', value = 'b' }), 'invalid_input', 'disabled selection validation')
Invalid(MenuValidation.ElementAction({ type = 'pagearrows', data = { key = 'pages', current = 1, total = 2 } }, { event = 'previous', value = -1 }), 'invalid_input', 'page boundary validation')
Invalid(MenuValidation.OpenOptions({ keyboard = 'yes' }), 'invalid_input', 'focus flags are boolean')
Invalid(MenuValidation.Sound({ action = '', soundset = 'HUD' }, 'sound'), 'invalid_input', 'empty sound identifier')
-- The Cfx runtime supplies json.encode. This probe verifies the byte gate itself.
json = { encode = function() return string.rep('x', 65537) end }
Invalid(MenuValidation.Bytes({ key = 'oversized' }, 'payload'), 'invalid_input', 'encoded byte budget')
json = nil
print(('PASS validation suite %d assertions'):format(passed))
