-- Minimal helpers for standalone Lua 5.4 tests (run from repo root, tests/ on package.path).
local M = { passed = 0, failed = 0 }

function M.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        M.passed = M.passed + 1
        print("PASS " .. name)
    else
        M.failed = M.failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

function M.eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

-- Numbers equal within eps (default 1e-9); a non-number actual fails.
function M.near(actual, expected, eps, what)
    eps = eps or 1e-9
    if type(actual) ~= "number" or math.abs(actual - expected) > eps then
        error(string.format("%s: expected %s +- %s, got %s", what or "value", tostring(expected), tostring(eps), tostring(actual)), 2)
    end
end

function M.str(list)
    return list and table.concat(list, " ") or "nil"
end

-- Prints the summary and exits with status 1 if any test failed.
function M.finish()
    print(string.format("%d passed, %d failed", M.passed, M.failed))
    os.exit(M.failed == 0 and 0 or 1)
end

return M
