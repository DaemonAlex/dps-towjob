-- Minimal test helper. Tests run under plain lua5.4 from the repo root.
local T = { passed = 0, failed = 0, failures = {} }

function T.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = name .. ': ' .. tostring(err)
    end
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or 'value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
    end
end

function T.truthy(value, msg)
    if not value then error((msg or 'value') .. ': expected truthy, got ' .. tostring(value), 2) end
end

function T.falsy(value, msg)
    if value then error((msg or 'value') .. ': expected falsy, got ' .. tostring(value), 2) end
end

function T.report()
    for i = 1, #T.failures do print('FAIL ' .. T.failures[i]) end
    print(('%d passed, %d failed'):format(T.passed, T.failed))
    return T.failed == 0
end

_G.T = T
return T
