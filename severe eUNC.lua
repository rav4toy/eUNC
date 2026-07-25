-- ==========================================================
-- External Luau VM Capability Lab v4.4
--
-- Outcomes are kept distinct:
--   PASS    = the capability exists and the tested behavior worked
--   FAIL    = it exists, but its behavior or return contract was wrong
--   MISSING = no canonical name or accepted alias was found
--   SKIP    = a live fixture or an intentionally disabled test is needed
--
-- ==========================================================

local PASS = "[PASS]"
local FAIL = "[FAIL]"
local MISSING = "[MISSING]"
local SKIP = "[SKIP]"
local INFO = "[INFO]"
local SEP  = "----------------------------------------"
local SEVERE_EXTENSION_SIGNATURE_COUNT = 182
local SUITE_VERSION = "v4.5"
local FAILURE_INDEX_YIELD_INTERVAL = 20
local NATIVE_WARN = warn
local LOADSTRING_CONFIG_OVERRIDE, LOADSTRING_VALUES_OVERRIDE = ...

local function emit_warn(message)
    if type(NATIVE_WARN) == "function" then
        NATIVE_WARN(message)
    else
        print(message)
    end
end

print(INFO .. " External Luau VM Capability Lab: " .. SUITE_VERSION)

-- ============================================================
--                    TEST CONFIGURATION
-- ============================================================
--
--
local EXTERNAL_TEST_CONFIG = {
    run_notifications = true,
    run_clipboard_write = true,
    run_window_block_toggle = true,
    run_input_simulation = true,
    run_user_input_service_write = true,
    run_live_instance_mutation = true,
    run_live_basepart_mutation = true,
    run_model_data_mutation = true,
    run_local_data_override = true,
    run_destructive_clear_functions = true,
    run_http_get = true,
    run_http_post = true,
    run_hwid_read = true,
    run_websocket = false,
    run_immediate_drawing_calls = true,
    run_drawing_clear = true,
    run_memory_reads = true,
    run_memory_writes = true,
    run_signal_wait = true,
    run_instance_clear_tags = true,
    run_instance_destroy = true,
    run_memory_changed = true
}

local EXTERNAL_TEST_VALUES = {
    http_get_url = "https://example.com/",
    http_post_url = nil,
    http_post_body = "{\"severe_vm_test\":true}",
    http_post_content_type = "application/json",
    http_post_accept = "application/json",
    -- Supported values: "2arg", "3arg", or "4arg". Only one request is made.
    http_post_signature = "4arg",
    websocket_url = "ws://127.0.0.1:8765",
    memory_read_address = nil,
    memory_write_address = nil,
    memory_string_address = nil,
    memory_vector_address = nil,
    memory_changed_address = nil,
    memory_changed_type = "u8",

    memory_buffer_size = 16,
    input_test_key = 0x87
}

local EXTERNAL_TEST_CONFIG_KEYS = {}
for key in pairs(EXTERNAL_TEST_CONFIG) do
    EXTERNAL_TEST_CONFIG_KEYS[key] = true
end


local EXTERNAL_TEST_VALUE_KEYS = {
    http_get_url = true,
    http_post_url = true,
    http_post_body = true,
    http_post_content_type = true,
    http_post_accept = true,
    http_post_signature = true,
    websocket_url = true,
    memory_read_address = true,
    memory_write_address = true,
    memory_string_address = true,
    memory_vector_address = true,
    memory_changed_address = true,
    memory_changed_type = true,
    memory_buffer_size = true,
    input_test_key = true
}

local function apply_loadstring_overrides(
    target,
    allowed_keys,
    overrides,
    boolean_values_only,
    label
)
    if overrides == nil then
        return 0
    end

    if type(overrides) ~= "table" then
        emit_warn(
            "[CONFIG] Ignored "
                .. label
                .. " override: expected table, got "
                .. type(overrides)
        )
        return 0
    end

    local applied = 0
    for key, value in pairs(overrides) do
        if allowed_keys[key] ~= true then
            emit_warn(
                "[CONFIG] Ignored unknown "
                    .. label
                    .. " key: "
                    .. tostring(key)
            )
        elseif boolean_values_only
            and type(value) ~= "boolean"
        then
            emit_warn(
                "[CONFIG] Ignored "
                    .. label
                    .. "."
                    .. tostring(key)
                    .. ": expected boolean, got "
                    .. type(value)
            )
        else
            target[key] = value
            applied = applied + 1
        end
    end

    return applied
end

local loadstring_config_count =
    apply_loadstring_overrides(
        EXTERNAL_TEST_CONFIG,
        EXTERNAL_TEST_CONFIG_KEYS,
        LOADSTRING_CONFIG_OVERRIDE,
        true,
        "config"
    )
local loadstring_value_count =
    apply_loadstring_overrides(
        EXTERNAL_TEST_VALUES,
        EXTERNAL_TEST_VALUE_KEYS,
        LOADSTRING_VALUES_OVERRIDE,
        false,
        "values"
    )

if loadstring_config_count > 0
    or loadstring_value_count > 0
then
    print(
        INFO
        .. " Loadstring overrides applied: config="
        .. tostring(loadstring_config_count)
        .. ", values="
        .. tostring(loadstring_value_count)
    )
end


local pass_count = 0
local fail_count = 0
local missing_count = 0
local skip_count = 0
local failure_records = {}
local result_records = {}
local result_kind_stats = {}
local category_stats = {}
local current_result_kind = "extension"
local current_category = "Bootstrap"

local function new_stats()
    return {
        passed = 0,
        failed = 0,
        missing = 0,
        skipped = 0,
        counted = 0
    }
end

local function get_stats(bucket, key)
    if bucket[key] == nil then
        bucket[key] = new_stats()
    end

    return bucket[key]
end

local function update_stats(stats, status)
    if status == "PASS" then
        stats.passed = stats.passed + 1
        stats.counted = stats.counted + 1
    elseif status == "FAIL" then
        stats.failed = stats.failed + 1
        stats.counted = stats.counted + 1
    elseif status == "MISSING" then
        stats.missing = stats.missing + 1
        stats.counted = stats.counted + 1
    elseif status == "SKIP" then
        stats.skipped = stats.skipped + 1
    end
end

local function value_to_string(value)
    local ok, result = pcall(tostring, value)
    if ok then
        return result
    end
    return "<unprintable>"
end

local function contains_plain(value, needle)
    if type(value) ~= "string" then
        value = value_to_string(value)
    end

    return string.find(value, needle, 1, true) ~= nil
end

local function diagnose_failure(label, extra)
    local detail = value_to_string(extra)

    if label == "load is a function" then
        return "The global load function is absent in this build. "
            .. "luau.load is available and is the working bytecode loader."
    end

    if contains_plain(detail, "attempt to index vector with") then
        return "Vector construction and arithmetic work, but this runtime's "
            .. "native vector value does not expose the requested documented "
            .. "property or method."
    end

    if contains_plain(detail, "number expected, got vector") then
        return "The numeric overload works, but the documented Vector3 "
            .. "constructor overload is not implemented by this build."
    end

    if contains_plain(detail, "expected Vector3, got vector") then
        return "There is a native type-bridge mismatch: Vector3.new returns "
            .. "a Luau 'vector', while this API entry expects a different "
            .. "native type named 'Vector3'."
    end

    if contains_plain(detail, "not a valid member") then
        return "The supplied documentation lists this member, but the live "
            .. "mirrored object does not expose it in this build."
    end

    if contains_plain(detail, "Invalid Image field")
        or contains_plain(detail, "invalid Image field")
    then
        return "The Image documentation lists this property, but the native "
            .. "Drawing Image implementation rejects it."
    end

    if contains_plain(detail, "invalid content type") then
        return "HttpPost requires an additional content-type argument in this "
            .. "runtime, even though the supplied signature only shows URL "
            .. "and data."
    end

    if contains_plain(detail, "bad allocation") then
        return "A native allocation failed below Luau. This is an "
            .. "implementation bug rather than a normal script error."
    end

    if contains_plain(detail, "no Connect/connect method") then
        return "The signal may be namecall-only. The suite now tries direct "
            .. ":Connect and :connect calls before property lookup."
    end

    if contains_plain(label, "HasTag observes added tag") then
        return "AddTag returned without throwing, but the mirrored Instance "
            .. "did not persist the tag. The method appears to be a no-op "
            .. "on every tested live target."
    end

    if contains_plain(label, "GetAttribute observes assigned value") then
        return "SetAttribute returned without throwing, but GetAttribute "
            .. "still returned nil. Attribute writes appear unsupported or "
            .. "non-persistent on the mirrored live instances."
    end

    if contains_plain(label, "secretbox") then
        return "The test now uses exact raw nonce/key byte lengths rather "
            .. "than crypt.random output. A remaining failure is likely in "
            .. "the secretbox implementation itself."
    end

    if contains_plain(label, "hkdf") then
        return "The runtime requires a fourth numeric output-length argument, "
            .. "although the supplied documentation lists only three."
    end

    if contains_plain(detail, "callback returned false without detail") then
        return "The call completed without throwing, but its returned value "
            .. "did not satisfy the documented behavior."
    end

    if contains_plain(label, "Camera.CameraSubject") then
        return "CameraSubject is documented, but this Camera mirror does not "
            .. "currently expose it."
    end

    if contains_plain(label, "typeof(Color3)") then
        return "Color3 operations work, but typeof reports the backing table "
            .. "instead of the documented custom type name."
    end

    if contains_plain(label, "Point3D") then
        return "Point3D construction was tried with multiple available "
            .. "position sources. None matched the native expected type."
    end

    return nil
end

local function record_result(
    label,
    status,
    detail,
    result_kind,
    quiet,
    diagnosis
)
    local kind = result_kind or current_result_kind
    local category = current_category
    local printable_detail = detail

    if printable_detail == nil then
        if status == "FAIL" then
            printable_detail = "behavior check failed"
        elseif status == "MISSING" then
            printable_detail = "no canonical function or alias was found"
        elseif status == "SKIP" then
            printable_detail = "test was not executed"
        end
    end

    printable_detail = value_to_string(printable_detail)

    if status == "PASS" then
        pass_count = pass_count + 1
    elseif status == "FAIL" then
        fail_count = fail_count + 1
    elseif status == "MISSING" then
        missing_count = missing_count + 1
    elseif status == "SKIP" then
        skip_count = skip_count + 1
    else
        error("unknown result status: " .. value_to_string(status), 0)
    end

    update_stats(get_stats(result_kind_stats, kind), status)
    update_stats(get_stats(category_stats, category), status)

    result_records[#result_records + 1] = {
        label = label,
        status = status,
        detail = printable_detail,
        diagnosis = diagnosis,
        kind = kind,
        category = category
    }

    if status == "FAIL" or status == "MISSING" then
        failure_records[#failure_records + 1] = {
            label = label,
            status = status,
            detail = printable_detail,
            diagnosis = diagnosis,
            kind = kind,
            category = category
        }
    end

    if not quiet then
        if status == "PASS" then
            local pass_suffix = ""
            if kind == "compatibility"
                and printable_detail ~= "nil"
            then
                pass_suffix = " | " .. printable_detail
            end

            print(PASS .. " " .. label .. pass_suffix)
        elseif status == "FAIL" then
            emit_warn(FAIL .. " " .. label .. " | " .. printable_detail)
        elseif status == "MISSING" then
            emit_warn(MISSING .. " " .. label .. " | " .. printable_detail)
        else
            print(SKIP .. " " .. label .. " | " .. printable_detail)
        end

        if diagnosis ~= nil
            and (status == "FAIL" or status == "MISSING")
        then
            emit_warn("[WHY] " .. diagnosis)
        end
    end

    return status == "PASS"
end

local function check(label, condition, extra)
    if condition then
        return record_result(label, "PASS")
    end

    local detail = extra
    if detail == nil then
        detail = "condition evaluated to false"
    end

    return record_result(
        label,
        "FAIL",
        detail,
        nil,
        false,
        diagnose_failure(label, detail)
    )
end

local function test(label, callback)
    local ok, result, extra = pcall(callback)

    if not ok then
        check(label, false, result)
        return nil
    end

    if result ~= true and extra == nil then
        extra = "callback returned " .. value_to_string(result)
            .. " without detail"
    end

    check(label, result == true, extra)
    return result
end

local function section(name, result_kind, category)
    if result_kind ~= nil then
        current_result_kind = result_kind
    end

    if category ~= nil then
        current_category = category
    else
        current_category =
            string.gsub(name, "^%d+%.%s*", "")
    end

    print("")
    print(SEP)
    print("  " .. name)
    print(SEP)
end

local function info(label, value)
    print(INFO .. " " .. label .. ": " .. value_to_string(value))
end

local function first_present(object, ...)
    if object == nil then
        return nil
    end

    local names = {...}
    for i = 1, #names do
        local ok, value = pcall(function()
            return object[names[i]]
        end)

        if ok and value ~= nil then
            return value
        end
    end

    return nil
end

local CAPABILITY_SKIP = {}
local CAPABILITY_MISSING = {}

local function resolve_function_candidates(candidates)
    local first_nonfunction_path = nil
    local first_nonfunction_type = nil

    for i = 1, #candidates do
        local candidate = candidates[i]
        local path = candidate[1]
        local value = candidate[2]

        if type(value) == "function" then
            return value, path, nil, nil
        end

        if value ~= nil and first_nonfunction_path == nil then
            first_nonfunction_path = path
            first_nonfunction_type = type(value)
        end
    end

    return nil, nil, first_nonfunction_path, first_nonfunction_type
end

local function dependency_function(candidates)
    local value, path = resolve_function_candidates(candidates)
    return value, path
end

local function capability_test(category, label, candidates, callback)
    current_result_kind = "compatibility"
    current_category = category

    local fn, resolved_path, bad_path, bad_type =
        resolve_function_candidates(candidates)

    if fn == nil then
        if bad_path ~= nil then
            return record_result(
                label,
                "FAIL",
                bad_path
                    .. " exists but is "
                    .. value_to_string(bad_type),
                "compatibility"
            )
        end

        local names = {}
        for i = 1, #candidates do
            names[#names + 1] = candidates[i][1]
        end

        return record_result(
            label,
            "MISSING",
            "checked: " .. table.concat(names, ", "),
            "compatibility"
        )
    end

    local ok, result, detail = pcall(callback, fn, resolved_path)
    if not ok then
        return record_result(
            label,
            "FAIL",
            "resolved via "
                .. resolved_path
                .. " | "
                .. value_to_string(result),
            "compatibility"
        )
    end

    if result == CAPABILITY_SKIP then
        return record_result(
            label,
            "SKIP",
            detail or ("resolved via " .. resolved_path),
            "compatibility"
        )
    end

    if result == CAPABILITY_MISSING then
        return record_result(
            label,
            "MISSING",
            detail or "a required companion capability is missing",
            "compatibility"
        )
    end

    if result ~= true then
        return record_result(
            label,
            "FAIL",
            "resolved via "
                .. resolved_path
                .. " | "
                .. value_to_string(
                    detail or "behavior assertion returned false"
                ),
            "compatibility"
        )
    end

    return record_result(
        label,
        "PASS",
        "resolved via " .. resolved_path,
        "compatibility"
    )
end

local function raw_capability_test(category, label, callback)
    current_result_kind = "compatibility"
    current_category = category

    local ok, result, detail = pcall(callback)
    if not ok then
        return record_result(
            label,
            "FAIL",
            result,
            "compatibility"
        )
    end

    if result == CAPABILITY_SKIP then
        return record_result(
            label,
            "SKIP",
            detail,
            "compatibility"
        )
    end

    if result == CAPABILITY_MISSING then
        return record_result(
            label,
            "MISSING",
            detail,
            "compatibility"
        )
    end

    return record_result(
        label,
        result == true and "PASS" or "FAIL",
        detail,
        "compatibility"
    )
end

local function connect_signal(signal, callback)
    if signal == nil then
        return false, nil, "signal is nil"
    end

    local errors = {}

    local upper_ok, upper_connection = pcall(function()
        return signal:Connect(callback)
    end)

    if upper_ok then
        return true, upper_connection, "direct :Connect namecall"
    end

    errors[#errors + 1] = ":Connect => "
        .. value_to_string(upper_connection)

    local lower_ok, lower_connection = pcall(function()
        return signal:connect(callback)
    end)

    if lower_ok then
        return true, lower_connection, "direct :connect namecall"
    end

    errors[#errors + 1] = ":connect => "
        .. value_to_string(lower_connection)

    local connect = first_present(signal, "Connect", "connect")
    if type(connect) == "function" then
        local property_ok, property_connection =
            pcall(connect, signal, callback)

        if property_ok then
            return true, property_connection, "indexed function call"
        end

        errors[#errors + 1] = "indexed call => "
            .. value_to_string(property_connection)
    else
        errors[#errors + 1] =
            "Connect/connect property lookup returned "
            .. type(connect)
    end

    return false, nil, table.concat(errors, " || ")
end

local function disconnect_connection(connection)
    if connection == nil then
        return false, "Connect succeeded but returned no connection handle"
    end

    local upper_ok, upper_error = pcall(function()
        connection:Disconnect()
    end)

    if upper_ok then
        return true, "direct :Disconnect namecall"
    end

    local lower_ok, lower_error = pcall(function()
        connection:disconnect()
    end)

    if lower_ok then
        return true, "direct :disconnect namecall"
    end

    local disconnect = first_present(
        connection,
        "Disconnect",
        "disconnect"
    )

    if type(disconnect) == "function" then
        local property_ok, property_error =
            pcall(disconnect, connection)

        if property_ok then
            return true, "indexed function call"
        end

        return false,
            ":Disconnect => "
            .. value_to_string(upper_error)
            .. " || :disconnect => "
            .. value_to_string(lower_error)
            .. " || indexed call => "
            .. value_to_string(property_error)
    end

    return false,
        ":Disconnect => "
        .. value_to_string(upper_error)
        .. " || :disconnect => "
        .. value_to_string(lower_error)
        .. " || no indexed method"
end

local function fire_signal(signal, ...)
    local arguments = {...}

    local upper_ok, upper_error = pcall(function()
        signal:Fire(table.unpack(arguments))
    end)

    if upper_ok then
        return true, "direct :Fire namecall"
    end

    local lower_ok, lower_error = pcall(function()
        signal:fire(table.unpack(arguments))
    end)

    if lower_ok then
        return true, "direct :fire namecall"
    end

    return false,
        ":Fire => "
        .. value_to_string(upper_error)
        .. " || :fire => "
        .. value_to_string(lower_error)
end

-- ============================================================
-- 1. CORE GLOBALS
-- ============================================================
section("1. Core Globals")

check("print is a function", type(print) == "function")
check("warn is a function", type(warn) == "function")
check(
    "a bytecode loader is available",
    type(load) == "function"
        or (
            type(luau) == "table"
            and type(luau.load) == "function"
        ),
    "global load type="
        .. type(load)
        .. "; luau.load type="
        .. (
            type(luau) == "table"
                and type(luau.load)
                or "nil"
        )
)

info("global load compatibility alias", type(load))
check("pcall is a function", type(pcall) == "function")
check("type is a function", type(type) == "function")
check("tostring is a function", type(tostring) == "function")

check("luau library exists", type(luau) == "table")
check(
    "luau.compile is a function",
    type(luau) == "table" and type(luau.compile) == "function"
)
check(
    "luau.load is a function",
    type(luau) == "table" and type(luau.load) == "function"
)

-- These are reported here and tested behaviorally in the compatibility
-- lab later in the suite.
info("loadstring global", type(loadstring))
info("getgenv global", type(getgenv))
info("Instance.new", type(first_present(Instance, "new", "New")))
info("ui global", type(ui))
info("fragment_ui global", type(fragment_ui))
info("input namespace", type(input))

if type(getgenv) == "function" then
    local ok, genv = pcall(getgenv)
    info(
        "getgenv() compatibility probe",
        ok and ("returned " .. type(genv))
            or ("error: " .. value_to_string(genv))
    )
end

-- ============================================================
-- 2. SANDBOX / FILESYSTEM GLOBALS
-- ============================================================
section("2. Sandbox and Filesystem")

-- Sandboxing choices are not correctness rules for an external VM.
-- Presence or absence is inventoried without penalizing a VM merely
-- for exposing more of the standard Lua runtime.
info("io library", type(io))
info("package library", type(package))
info("require global", type(require))

info("os library", type(os))
if type(os) == "table" then
    if type(os.clock) == "function" then
        test("os.clock returns a number", function()
            local value = os.clock()
            return type(value) == "number", value
        end)
    end

    if type(os.time) == "function" then
        test("os.time returns a number", function()
            local value = os.time()
            return type(value) == "number", value
        end)
    end

    if type(os.date) == "function" then
        test("os.date returns a string", function()
            local value = os.date()
            return type(value) == "string", value
        end)
    end
end

info("debug library", type(debug))
if type(debug) == "table" then
    info("debug.traceback", type(debug.traceback))
    info("debug.info", type(debug.info))
    info("debug.getinfo", type(debug.getinfo))

    if type(debug.traceback) == "function" then
        test("debug.traceback returns a string", function()
            local value = debug.traceback("severe-test")
            return type(value) == "string"
                and #value > 0,
                value
        end)
    end
end

-- Filesystem globals supplied by this runtime profile.
check("dofile is a function", type(dofile) == "function")
check("loadfile is a function", type(loadfile) == "function")
check("writefile is a function", type(writefile) == "function")
check("readfile is a function", type(readfile) == "function")
check("isfile is a function", type(isfile) == "function")
check("isfolder is a function", type(isfolder) == "function")
check("listfiles is a function", type(listfiles) == "function")
check("makefolder is a function", type(makefolder) == "function")
check("delfolder is a function", type(delfolder) == "function")

local filesystem_ready =
    type(dofile) == "function"
    and type(loadfile) == "function"
    and type(writefile) == "function"
    and type(readfile) == "function"
    and type(isfile) == "function"
    and type(isfolder) == "function"
    and type(listfiles) == "function"
    and type(makefolder) == "function"
    and type(delfolder) == "function"

if filesystem_ready then
    local suffix = tostring(math.random(100000, 999999))
    local temp_folder = "__severe_vm_test_" .. suffix
    local temp_file = temp_folder .. "/module.luau"
    local temp_source = "return 123, 'filesystem-ok'"

    local folder_created = false

    test("temporary folder does not already exist", function()
        return isfolder(temp_folder) == false
    end)

    local make_ok, make_err = pcall(makefolder, temp_folder)
    check("makefolder creates temporary folder", make_ok, make_err)
    folder_created = make_ok

    if folder_created then
        test("isfolder detects temporary folder", function()
            return isfolder(temp_folder) == true
        end)

        local write_ok, write_err = pcall(writefile, temp_file, temp_source)
        check("writefile creates temporary file", write_ok, write_err)

        if write_ok then
            test("isfile detects temporary file", function()
                return isfile(temp_file) == true
            end)

            test("readfile returns exact contents", function()
                local contents = readfile(temp_file)
                return contents == temp_source, contents
            end)

            test("listfiles returns a table", function()
                local files = listfiles(temp_folder)
                return type(files) == "table", files
            end)

            test("listfiles includes at least one item", function()
                local files = listfiles(temp_folder)
                return type(files) == "table" and #files >= 1, #files
            end)

            test("loadfile returns an executable function", function()
                local fn = loadfile(temp_file)
                return type(fn) == "function", type(fn)
            end)

            test("loadfile function returns expected values", function()
                local fn = loadfile(temp_file)
                local number_value, string_value = fn()
                return number_value == 123 and string_value == "filesystem-ok",
                    value_to_string(number_value) .. ", " .. value_to_string(string_value)
            end)

            test("dofile executes and preserves module returns", function()
                local first, second, third = dofile(temp_file)

                local standard_shape =
                    first == 123
                    and second == "filesystem-ok"

                local severe_shape =
                    type(first) == "string"
                    and second == 123
                    and third == "filesystem-ok"

                return standard_shape or severe_shape,
                    "returned: "
                    .. value_to_string(first)
                    .. ", "
                    .. value_to_string(second)
                    .. ", "
                    .. value_to_string(third)
                    .. " | this build may prepend the executed path"
            end)

            test("writefile overwrites existing contents", function()
                writefile(temp_file, "return 456")
                local contents = readfile(temp_file)
                writefile(temp_file, temp_source)
                return contents == "return 456", contents
            end)

            test("readfile rejects a missing file", function()
                local ok, err = pcall(
                    readfile,
                    temp_folder .. "/definitely_missing.luau"
                )

                return ok == false,
                    ok and "missing read unexpectedly succeeded" or err
            end)
        end

        local delete_ok, delete_err = pcall(delfolder, temp_folder)
        check("delfolder removes temporary folder", delete_ok, delete_err)

        if delete_ok then
            test("temporary folder is gone after cleanup", function()
                return isfolder(temp_folder) == false
            end)
        else
            emit_warn(
                FAIL
                .. " Cleanup failed; manually remove workspace/"
                .. temp_folder
            )
        end
    end
else
    info("Filesystem execution tests", "skipped because required functions are missing")
end

-- ============================================================
-- 3. LUAU COMPILATION AND LOADING
-- ============================================================
section("3. Luau Compilation and Loading")

local function compile_source(source)
    return luau.compile(source, {
        optimizationLevel = 1,
        coverageLevel = 0,
        debugLevel = 1
    })
end

if type(luau) == "table" and type(luau.compile) == "function" then
    local compile_ok, bytecode_or_error = pcall(
        compile_source,
        "return 1 + 1"
    )

    check(
        "luau.compile compiles valid source",
        compile_ok and type(bytecode_or_error) == "string",
        bytecode_or_error
    )

    if compile_ok and type(bytecode_or_error) == "string" then
        if type(load) == "function" then
            local load_ok, fn_or_error = pcall(load, bytecode_or_error)

            check(
                "load accepts compiled bytecode",
                load_ok and type(fn_or_error) == "function",
                fn_or_error
            )

            if load_ok and type(fn_or_error) == "function" then
                local run_ok, result = pcall(fn_or_error)

                check("loaded function executes", run_ok, result)
                check(
                    "loaded function returns 2",
                    run_ok and result == 2,
                    result
                )
            end
        end

        if type(luau.load) == "function" then
            local luau_load_ok, luau_fn_or_error = pcall(
                luau.load,
                bytecode_or_error,
                {
                    debugName = "SevereVMTest",
                    injectGlobals = true,
                    codegenEnabled = false
                }
            )

            check(
                "luau.load accepts compiled bytecode",
                luau_load_ok and type(luau_fn_or_error) == "function",
                luau_fn_or_error
            )

            if luau_load_ok and type(luau_fn_or_error) == "function" then
                local run_ok, result = pcall(luau_fn_or_error)
                check(
                    "luau.load function returns 2",
                    run_ok and result == 2,
                    result
                )
            end
        end
    end

    local string_ok, string_bytecode = pcall(
        compile_source,
        "return 'hello severe'"
    )

    check(
        "string-returning source compiles",
        string_ok and type(string_bytecode) == "string",
        string_bytecode
    )

    if string_ok and type(string_bytecode) == "string" and type(load) == "function" then
        local load_ok, fn = pcall(load, string_bytecode)
        check(
            "string-returning bytecode loads",
            load_ok and type(fn) == "function",
            fn
        )

        if load_ok and type(fn) == "function" then
            local run_ok, result = pcall(fn)
            check(
                "string-returning function executes correctly",
                run_ok and result == "hello severe",
                result
            )
        end
    end

    info(
        "invalid-source compiler test",
        "skipped because Severe prints the expected syntax error in red "
            .. "even when pcall catches it"
    )
else
    info("Compilation tests", "skipped because luau.compile is missing")
end

-- ============================================================
-- 4. MISCELLANEOUS RUNTIME EXTENSION API
-- ============================================================
section("4. Miscellaneous API")

local misc_functions = {
    {"isrbxactive", isrbxactive},
    {"send_notification", send_notification},
    {"setclipboard", setclipboard},
    {"block_roblox_window", block_roblox_window},
    {"pointer_to_userdata", pointer_to_userdata},
    {"get_overlay_fps", get_overlay_fps},
    {"is_forcefield_check_active", is_forcefield_check_active},
    {"is_local_health_check_active", is_local_health_check_active},
    {"is_team_check_active", is_team_check_active},
    {"add_model_data", add_model_data},
    {"edit_model_data", edit_model_data},
    {"remove_model_data", remove_model_data},
    {"clear_model_data", clear_model_data},
    {"override_local_data", override_local_data},
    {"clear_local_data", clear_local_data}
}

for i = 1, #misc_functions do
    local entry = misc_functions[i]
    check(entry[1] .. " is a function", type(entry[2]) == "function")
end

local menu_function = ismenuopened or is_menu_opened
check(
    "ismenuopened/is_menu_opened is available",
    type(menu_function) == "function"
)

if type(isrbxactive) == "function" then
    test("isrbxactive returns boolean", function()
        return type(isrbxactive()) == "boolean"
    end)
end

if type(get_overlay_fps) == "function" then
    test("get_overlay_fps returns number", function()
        local fps = get_overlay_fps()
        return type(fps) == "number", fps
    end)
end

if type(is_forcefield_check_active) == "function" then
    test("forcefield-check state returns boolean", function()
        return type(is_forcefield_check_active()) == "boolean"
    end)
end

if type(is_local_health_check_active) == "function" then
    test("health-check state returns boolean", function()
        return type(is_local_health_check_active()) == "boolean"
    end)
end

if type(is_team_check_active) == "function" then
    test("team-check state returns boolean", function()
        return type(is_team_check_active()) == "boolean"
    end)
end

if type(menu_function) == "function" then
    test("menu-open state returns boolean", function()
        return type(menu_function()) == "boolean"
    end)
end

-- ============================================================
-- 5. DATA MODEL AND SERVICES
-- ============================================================
section("5. Data Model and Services")

check("game global exists", game ~= nil)
check("workspace global exists", workspace ~= nil)

if game ~= nil then
    test("game.ClassName is DataModel", function()
        return game.ClassName == "DataModel", game.ClassName
    end)
end

if workspace ~= nil then
    test("workspace.ClassName is Workspace", function()
        return workspace.ClassName == "Workspace", workspace.ClassName
    end)
end

local players_service = nil
local workspace_service = nil
local run_service = nil
local user_input_service = nil
local lighting_service = nil

if game ~= nil then
    local ok_players, players_or_error = pcall(function()
        return game:GetService("Players")
    end)
    players_service = ok_players and players_or_error or nil
    check("game:GetService('Players') works", players_service ~= nil, players_or_error)

    local ok_workspace, workspace_or_error = pcall(function()
        return game:GetService("Workspace")
    end)
    workspace_service = ok_workspace and workspace_or_error or nil
    check("game:GetService('Workspace') works", workspace_service ~= nil, workspace_or_error)

    local ok_run, run_or_error = pcall(function()
        return game:GetService("RunService")
    end)
    run_service = ok_run and run_or_error or nil
    check("game:GetService('RunService') works", run_service ~= nil, run_or_error)

    local ok_uis, uis_or_error = pcall(function()
        return game:GetService("UserInputService")
    end)
    user_input_service = ok_uis and uis_or_error or nil
    check(
        "game:GetService('UserInputService') works",
        user_input_service ~= nil,
        uis_or_error
    )

    local ok_lighting, lighting_or_error = pcall(function()
        return game:GetService("Lighting")
    end)
    lighting_service = ok_lighting and lighting_or_error or nil
    check("game:GetService('Lighting') works", lighting_service ~= nil, lighting_or_error)
end

if workspace_service ~= nil and workspace ~= nil then
    check(
        "Workspace service matches workspace global",
        workspace_service == workspace
    )
end

-- ============================================================
-- 6. INSTANCE READ API
-- ============================================================
section("6. Instance Read API")

if workspace ~= nil then
    test("workspace:GetChildren returns table", function()
        local children = workspace:GetChildren()
        return type(children) == "table", type(children)
    end)

    test("workspace:GetDescendants returns table", function()
        local descendants = workspace:GetDescendants()
        return type(descendants) == "table", type(descendants)
    end)

    test("workspace:GetAttributes returns table", function()
        local attributes = workspace:GetAttributes()
        return type(attributes) == "table", type(attributes)
    end)

    test("missing workspace attribute returns nil", function()
        return workspace:GetAttribute("__SEVERE_VM_TEST_MISSING__") == nil
    end)

    local children_ok, children = pcall(function()
        return workspace:GetChildren()
    end)

    if children_ok and type(children) == "table" then
        info("Workspace child count", #children)

        local first_child = children[1]
        if first_child ~= nil then
            test("child has a string Name", function()
                return type(first_child.Name) == "string", first_child.Name
            end)

            test("child has a string ClassName", function()
                return type(first_child.ClassName) == "string", first_child.ClassName
            end)

            test("child.Parent is workspace", function()
                return first_child.Parent == workspace, first_child.Parent
            end)

            test("FindFirstChild finds the first child by name", function()
                return workspace:FindFirstChild(first_child.Name) == first_child
            end)

            test("child:IsDescendantOf(workspace)", function()
                return first_child:IsDescendantOf(workspace) == true
            end)

            test("workspace:IsAncestorOf(child)", function()
                return workspace:IsAncestorOf(first_child) == true
            end)

            local missing_name =
                "__SEVERE_VM_TEST_CHILD_THAT_SHOULD_NOT_EXIST__"

            test("FindFirstChild returns nil for missing child", function()
                return workspace:FindFirstChild(missing_name) == nil
            end)
        else
            info("Workspace relationship tests", "skipped because workspace has no children")
        end
    end
end

-- ============================================================
-- 7. PLAYERS AND CAMERA
-- ============================================================
section("7. Players and Camera")

if players_service ~= nil then
    test("Players:GetChildren returns table", function()
        local players = players_service:GetChildren()
        return type(players) == "table", type(players)
    end)

    local players_ok, players = pcall(function()
        return players_service:GetChildren()
    end)

    if players_ok and type(players) == "table" then
        info("Player count", #players)

        for i = 1, math.min(#players, 5) do
            local player = players[i]
            local name = player and player.Name or "?"
            local display_name = player and player.DisplayName or "?"
            local user_id = player and player.UserId or "?"

            print(
                INFO
                .. " ["
                .. tostring(i)
                .. "] "
                .. value_to_string(name)
                .. " | display="
                .. value_to_string(display_name)
                .. " | userId="
                .. value_to_string(user_id)
            )
        end
    end

    local local_player_ok, local_player = pcall(function()
        return players_service.LocalPlayer
    end)

    if local_player_ok and local_player ~= nil then
        check("Players.LocalPlayer exists", true)

        test("LocalPlayer.Name is string", function()
            return type(local_player.Name) == "string", local_player.Name
        end)

        test("LocalPlayer.DisplayName is string", function()
            return type(local_player.DisplayName) == "string",
                local_player.DisplayName
        end)

        test("LocalPlayer.UserId is number", function()
            return type(local_player.UserId) == "number", local_player.UserId
        end)

        local character = local_player.Character
        if character ~= nil then
            test("LocalPlayer.Character is a Model", function()
                return character.ClassName == "Model", character.ClassName
            end)
        else
            info("LocalPlayer.Character", "nil; character tests skipped")
        end
    else
        info("Players.LocalPlayer", "nil; local-player tests skipped")
    end
end

if workspace ~= nil then
    local camera_ok, camera = pcall(function()
        return workspace.CurrentCamera
    end)

    if camera_ok and camera ~= nil then
        check("workspace.CurrentCamera exists", true)

        test("Camera.ViewportSize has X and Y", function()
            local size = camera.ViewportSize
            return size ~= nil
                and type(size.X) == "number"
                and type(size.Y) == "number"
        end)

        test("Camera.FieldOfView is number", function()
            return type(camera.FieldOfView) == "number", camera.FieldOfView
        end)

        test("Camera.Position is Vector3-like", function()
            local position = camera.Position
            return position ~= nil
                and type(position.X) == "number"
                and type(position.Y) == "number"
                and type(position.Z) == "number"
        end)

        if Vector3 and type(Vector3.new) == "function" then
            test("Camera:WorldToScreenPoint returns point and boolean", function()
                local point, on_screen =
                    camera:WorldToScreenPoint(Vector3.new(0, 0, 0))

                return point ~= nil
                    and type(point.X) == "number"
                    and type(point.Y) == "number"
                    and type(point.Z) == "number"
                    and type(on_screen) == "boolean"
            end)
        end
    else
        info("workspace.CurrentCamera", "nil; camera tests skipped")
    end
end

-- ============================================================
-- 8. RUNSERVICE SIGNALS
-- ============================================================
section("8. RunService Signals")

if run_service ~= nil then
    local event_names = {
        "Render",
        "PreLocal",
        "PostLocal",
        "PreModel",
        "PostModel",
        "PreData",
        "PostData"
    }

    local active_connections = {}

    for i = 1, #event_names do
        local event_name = event_names[i]
        local signal = first_present(run_service, event_name)

        check(
            event_name .. " signal exists",
            signal ~= nil,
            "RunService." .. event_name .. " returned nil"
        )

        if signal ~= nil then
            local fired_count = 0
            local connected, connection, connect_mode =
                connect_signal(signal, function()
                    fired_count = fired_count + 1
                end)

            check(
                event_name .. " signal can connect",
                connected,
                connect_mode
            )

            if connected then
                active_connections[#active_connections + 1] = {
                    name = event_name,
                    connection = connection,
                    mode = connect_mode,
                    counter = function()
                        return fired_count
                    end
                }
            end
        end
    end

    if #active_connections > 0
        and type(task) == "table"
        and type(task.wait) == "function"
    then
        task.wait(0.08)
    end

    for i = 1, #active_connections do
        local entry = active_connections[i]
        local count = entry.counter()

        check(
            entry.name .. " signal fires",
            count > 0,
            "connected through "
                .. value_to_string(entry.mode)
                .. " but callback count="
                .. value_to_string(count)
        )

        if entry.connection ~= nil then
            local disconnected, disconnect_detail =
                disconnect_connection(entry.connection)

            check(
                entry.name .. " connection can disconnect",
                disconnected,
                disconnect_detail
            )
        else
            info(
                entry.name .. " disconnect",
                "Connect succeeded but returned no handle"
            )
        end
    end
else
    info("RunService signal tests", "skipped because RunService is missing")
end

-- ============================================================
-- 9. STATIC DRAWING API
-- ============================================================
section("9. Static Drawing API")

check("Drawing library exists", type(Drawing) == "table")
check(
    "Drawing.new is a function",
    type(Drawing) == "table" and type(Drawing.new) == "function"
)
check(
    "Drawing.clear is a function",
    type(Drawing) == "table" and type(Drawing.clear) == "function"
)

local drawing_ready =
    type(Drawing) == "table"
    and type(Drawing.new) == "function"
    and Vector2 ~= nil
    and type(Vector2.new) == "function"
    and Color3 ~= nil
    and type(Color3.new) == "function"

local function remove_drawing(object)
    if object == nil then
        return false, "drawing is nil"
    end

    local remove = first_present(object, "Remove", "remove")
    if type(remove) ~= "function" then
        return false, "drawing has no Remove/remove method"
    end

    local ok, err = pcall(remove, object)
    return ok, err
end

if drawing_ready then
    local square_ok, square = pcall(Drawing.new, "Square")
    check("Drawing.new('Square') succeeds", square_ok and square ~= nil, square)

    if square_ok and square ~= nil then
        local props_ok, props_err = pcall(function()
            square.Size = Vector2.new(80, 40)
            square.Position = Vector2.new(50, 50)
            square.Color = Color3.new(0.2, 0.8, 0.2)
            square.Opacity = 1
            square.Filled = true
            square.Visible = false
            square.ZIndex = 5
            square.Thickness = 2
            square.Rounding = 4
        end)

        check("Square documented properties can be set", props_ok, props_err)

        local removed, remove_err = remove_drawing(square)
        check("Square:Remove works", removed, remove_err)
    end

    local text_ok, text = pcall(Drawing.new, "Text")
    check("Drawing.new('Text') succeeds", text_ok and text ~= nil, text)

    if text_ok and text ~= nil then
        local props_ok, props_err = pcall(function()
            text.Text = "Severe VM Test"
            text.Position = Vector2.new(50, 100)
            text.Color = Color3.new(1, 1, 0.2)
            text.Opacity = 1
            text.Size = 16
            text.Center = false
            text.Outline = true
            text.Visible = false
            text.ZIndex = 5
        end)

        check("Text documented properties can be set", props_ok, props_err)

        local removed, remove_err = remove_drawing(text)
        check("Text:Remove works", removed, remove_err)
    end

    local polyline_ok, polyline = pcall(Drawing.new, "Polyline")
    check(
        "Drawing.new('Polyline') succeeds",
        polyline_ok and polyline ~= nil,
        polyline
    )

    if polyline_ok and polyline ~= nil then
        local props_ok, props_err = pcall(function()
            polyline.Points = {
                Vector2.new(50, 150),
                Vector2.new(150, 150),
                Vector2.new(250, 175)
            }
            polyline.Color = Color3.new(0.2, 0.5, 1)
            polyline.Opacity = 1
            polyline.Thickness = 2
            polyline.Filled = false
            polyline.Visible = false
            polyline.ZIndex = 5
        end)

        check("Polyline documented properties can be set", props_ok, props_err)

        local removed, remove_err = remove_drawing(polyline)
        check("Polyline:Remove works", removed, remove_err)
    end

    local triangle_ok, triangle = pcall(Drawing.new, "Triangle")
    check(
        "Drawing.new('Triangle') succeeds",
        triangle_ok and triangle ~= nil,
        triangle
    )

    if triangle_ok and triangle ~= nil then
        local props_ok, props_err = pcall(function()
            triangle.PointA = Vector2.new(50, 200)
            triangle.PointB = Vector2.new(100, 250)
            triangle.PointC = Vector2.new(150, 200)
            triangle.Color = Color3.new(1, 0.4, 0.2)
            triangle.Opacity = 1
            triangle.Transparency = 0
            triangle.Thickness = 2
            triangle.Filled = true
            triangle.Visible = false
            triangle.ZIndex = 5
        end)

        check("Triangle documented properties can be set", props_ok, props_err)

        local removed, remove_err = remove_drawing(triangle)
        check("Triangle:Remove works", removed, remove_err)
    end

    local unsupported_ok, unsupported_result =
        pcall(Drawing.new, "__DefinitelyUnsupportedDrawingClass__")

    check(
        "unsupported Drawing class is rejected",
        unsupported_ok == false or unsupported_result == nil,
        unsupported_result
    )
else
    info(
        "Drawing object tests",
        "skipped because Drawing, Vector2, or Color3 is missing"
    )
end

-- ============================================================
-- 10. TASK SCHEDULER
-- ============================================================
section("10. Task Scheduler")

check("task library exists", type(task) == "table")
check("task.spawn is a function", type(task) == "table" and type(task.spawn) == "function")
check("task.defer is a function", type(task) == "table" and type(task.defer) == "function")
check("task.delay is a function", type(task) == "table" and type(task.delay) == "function")
check("task.cancel is a function", type(task) == "table" and type(task.cancel) == "function")
check("task.wait is a function", type(task) == "table" and type(task.wait) == "function")

if type(task) == "table"
    and type(task.spawn) == "function"
    and type(task.defer) == "function"
    and type(task.delay) == "function"
    and type(task.cancel) == "function"
    and type(task.wait) == "function"
then
    local spawn_fired = false
    local spawn_argument_a = nil
    local spawn_argument_b = nil
    local spawn_ok, spawn_thread = pcall(
        task.spawn,
        function(a, b)
            spawn_fired = true
            spawn_argument_a = a
            spawn_argument_b = b
        end,
        123,
        "spawn-ok"
    )

    check(
        "task.spawn returns a thread",
        spawn_ok and type(spawn_thread) == "thread",
        spawn_thread
    )
    check(
        "task.spawn forwards function arguments",
        spawn_fired
            and spawn_argument_a == 123
            and spawn_argument_b == "spawn-ok",
        "received "
            .. value_to_string(spawn_argument_a)
            .. ", "
            .. value_to_string(spawn_argument_b)
    )

    local spawned_coroutine_argument = nil
    local raw_spawn_thread = coroutine.create(function(value)
        spawned_coroutine_argument = value
    end)
    local spawn_thread_ok, returned_spawn_thread =
        pcall(task.spawn, raw_spawn_thread, "thread-ok")

    check(
        "task.spawn accepts a coroutine thread",
        spawn_thread_ok
            and type(returned_spawn_thread) == "thread"
            and spawned_coroutine_argument == "thread-ok",
        returned_spawn_thread
    )

    local defer_fired = false
    local defer_argument = nil
    local defer_ok, defer_thread = pcall(
        task.defer,
        function(value)
            defer_fired = true
            defer_argument = value
        end,
        "defer-ok"
    )

    check(
        "task.defer returns a thread",
        defer_ok and type(defer_thread) == "thread",
        defer_thread
    )
    check(
        "task.defer waits until the current thread yields",
        defer_fired == false,
        "callback fired before a yield="
            .. value_to_string(defer_fired)
    )

    local deferred_coroutine_argument = nil
    local raw_defer_thread = coroutine.create(function(value)
        deferred_coroutine_argument = value
    end)
    local defer_thread_ok, returned_defer_thread =
        pcall(task.defer, raw_defer_thread, "thread-ok")

    check(
        "task.defer accepts a coroutine thread",
        defer_thread_ok and type(returned_defer_thread) == "thread",
        returned_defer_thread
    )

    local delay_fired = false
    local delay_argument_a = nil
    local delay_argument_b = nil
    local delay_ok, delay_thread = pcall(
        task.delay,
        0,
        function(a, b)
            delay_fired = true
            delay_argument_a = a
            delay_argument_b = b
        end,
        456,
        "delay-ok"
    )

    check(
        "task.delay returns a thread",
        delay_ok and type(delay_thread) == "thread",
        delay_thread
    )

    local delayed_coroutine_argument = nil
    local raw_delay_thread = coroutine.create(function(value)
        delayed_coroutine_argument = value
    end)
    local delay_thread_ok, returned_delay_thread =
        pcall(task.delay, 0, raw_delay_thread, "thread-ok")

    check(
        "task.delay accepts a coroutine thread",
        delay_thread_ok and type(returned_delay_thread) == "thread",
        returned_delay_thread
    )

    local wait_ok, elapsed = pcall(task.wait, 0)
    check(
        "task.wait(0) returns number",
        wait_ok and type(elapsed) == "number",
        elapsed
    )

    local default_wait_ok, default_elapsed = pcall(task.wait)
    check(
        "task.wait() default-duration form returns number",
        default_wait_ok and type(default_elapsed) == "number",
        default_elapsed
    )

    check("task.spawn callback fired", spawn_fired == true)

    if spawn_ok and type(spawn_thread) == "thread" then
        local cancel_completed_ok, cancel_completed_error =
            pcall(task.cancel, spawn_thread)

        check(
            "task.cancel ignores an already completed thread",
            cancel_completed_ok,
            cancel_completed_error
        )
    end

    check(
        "task.defer callback fired after yielding",
        defer_fired == true and defer_argument == "defer-ok",
        defer_argument
    )
    check(
        "task.defer coroutine resumed after yielding",
        deferred_coroutine_argument == "thread-ok",
        deferred_coroutine_argument
    )
    check(
        "task.delay callback fired after yielding",
        delay_fired
            and delay_argument_a == 456
            and delay_argument_b == "delay-ok",
        "received "
            .. value_to_string(delay_argument_a)
            .. ", "
            .. value_to_string(delay_argument_b)
    )
    check(
        "task.delay coroutine resumed after yielding",
        delayed_coroutine_argument == "thread-ok",
        delayed_coroutine_argument
    )

    local delayed_cancel_fired = false
    local cancel_ok, cancel_thread = pcall(task.delay, 60, function()
        delayed_cancel_fired = true
    end)

    if cancel_ok and type(cancel_thread) == "thread" then
        local did_cancel, cancel_error = pcall(task.cancel, cancel_thread)
        check("task.cancel accepts delayed thread", did_cancel, cancel_error)

        local cancel_again_ok, cancel_again_error =
            pcall(task.cancel, cancel_thread)
        check(
            "task.cancel ignores an already cancelled thread",
            cancel_again_ok,
            cancel_again_error
        )

        task.wait(0)
        check(
            "task.cancel keeps delayed callback cancelled",
            delayed_cancel_fired == false,
            "callback fired=" .. value_to_string(delayed_cancel_fired)
        )
    else
        check("create delayed thread for task.cancel test", false, cancel_thread)
    end

    local deferred_cancel_fired = false
    local deferred_cancel_ok, deferred_cancel_thread =
        pcall(task.defer, function()
            deferred_cancel_fired = true
        end)

    if deferred_cancel_ok
        and type(deferred_cancel_thread) == "thread"
    then
        local did_cancel, cancel_error =
            pcall(task.cancel, deferred_cancel_thread)

        check(
            "task.cancel accepts deferred thread",
            did_cancel,
            cancel_error
        )
        task.wait(0)
        check(
            "task.cancel prevents deferred callback",
            deferred_cancel_fired == false,
            "callback fired=" .. value_to_string(deferred_cancel_fired)
        )
    else
        check(
            "create deferred thread for task.cancel test",
            false,
            deferred_cancel_thread
        )
    end

    local spawned_cancel_resumed = false
    local spawned_cancel_ok, spawned_cancel_thread =
        pcall(task.spawn, function()
            task.wait(60)
            spawned_cancel_resumed = true
        end)

    if spawned_cancel_ok
        and type(spawned_cancel_thread) == "thread"
    then
        local did_cancel, cancel_error =
            pcall(task.cancel, spawned_cancel_thread)

        check(
            "task.cancel accepts spawned thread",
            did_cancel,
            cancel_error
        )
        task.wait(0)
        check(
            "task.cancel prevents spawned thread resumption",
            spawned_cancel_resumed == false,
            "thread resumed="
                .. value_to_string(spawned_cancel_resumed)
        )
    else
        check(
            "create spawned thread for task.cancel test",
            false,
            spawned_cancel_thread
        )
    end
end


-- ============================================================
-- 11. PASSIVE INPUT API
-- ============================================================
section("11. Passive Input API")

local input_functions = {
    {"keypress", keypress},
    {"keyrelease", keyrelease},
    {"getpressedkey", getpressedkey},
    {"getpressedkeys", getpressedkeys},
    {"isleftclicked", isleftclicked},
    {"isrightclicked", isrightclicked},
    {"isleftpressed", isleftpressed},
    {"isrightpressed", isrightpressed},
    {"getmouseposition", getmouseposition},
    {"mousemoverel", mousemoverel},
    {"mousemoveabs", mousemoveabs},
    {"mousescroll", mousescroll},
    {"mouse1click", mouse1click},
    {"mouse1press", mouse1press},
    {"mouse1release", mouse1release},
    {"mouse2click", mouse2click},
    {"mouse2press", mouse2press},
    {"mouse2release", mouse2release}
}

for i = 1, #input_functions do
    local entry = input_functions[i]
    check(entry[1] .. " is a function", type(entry[2]) == "function")
end

-- Only passive getters are called. No input is generated.
if type(getpressedkey) == "function" then
    test("getpressedkey returns string", function()
        local key = getpressedkey()
        return type(key) == "string", key
    end)
end

if type(getpressedkeys) == "function" then
    test("getpressedkeys returns table", function()
        local keys = getpressedkeys()
        return type(keys) == "table", type(keys)
    end)
end

local passive_boolean_functions = {
    {"isleftclicked returns boolean", isleftclicked},
    {"isrightclicked returns boolean", isrightclicked},
    {"isleftpressed returns boolean", isleftpressed},
    {"isrightpressed returns boolean", isrightpressed}
}

for i = 1, #passive_boolean_functions do
    local entry = passive_boolean_functions[i]
    if type(entry[2]) == "function" then
        test(entry[1], function()
            return type(entry[2]()) == "boolean"
        end)
    end
end

if type(getmouseposition) == "function" then
    test("getmouseposition returns Vector2-like value", function()
        local position = getmouseposition()
        return position ~= nil
            and type(position.X) == "number"
            and type(position.Y) == "number"
    end)
end

if user_input_service ~= nil then
    test("UserInputService:GetMouseLocation returns Vector2-like value", function()
        local position = user_input_service:GetMouseLocation()
        return position ~= nil
            and type(position.X) == "number"
            and type(position.Y) == "number"
    end)

    test("UserInputService.MouseDeltaSensitivity is number", function()
        return type(user_input_service.MouseDeltaSensitivity) == "number",
            user_input_service.MouseDeltaSensitivity
    end)

    test("UserInputService.MouseIconEnabled is boolean", function()
        return type(user_input_service.MouseIconEnabled) == "boolean",
            user_input_service.MouseIconEnabled
    end)
end

-- ============================================================
-- 12. VECTOR2 AND VECTOR3
-- ============================================================
section("12. Vector2 and Vector3 Basic Operations")

check(
    "Vector2.new is a function",
    Vector2 ~= nil and type(Vector2.new) == "function"
)
check(
    "Vector3.new is a function",
    Vector3 ~= nil and type(Vector3.new) == "function"
)

if Vector2 ~= nil and type(Vector2.new) == "function" then
    local vector2_ok, v2 = pcall(Vector2.new, 3, 4)
    check("Vector2.new succeeds", vector2_ok and v2 ~= nil, v2)

    if vector2_ok and v2 ~= nil then
        test("Vector2.X is correct", function()
            return v2.X == 3, v2.X
        end)

        test("Vector2.Y is correct", function()
            return v2.Y == 4, v2.Y
        end)

        test("Vector2 addition works", function()
            local result = v2 + Vector2.new(1, 2)
            return result.X == 4 and result.Y == 6
        end)

        test("Vector2 scalar multiplication works", function()
            local result = v2 * 2
            return result.X == 6 and result.Y == 8
        end)
    end
end

if Vector3 ~= nil and type(Vector3.new) == "function" then
    local vector3_ok, v3 = pcall(Vector3.new, 1, 2, 3)
    check("Vector3.new succeeds", vector3_ok and v3 ~= nil, v3)

    if vector3_ok and v3 ~= nil then
        test("Vector3.X is correct", function()
            return v3.X == 1, v3.X
        end)

        test("Vector3.Y is correct", function()
            return v3.Y == 2, v3.Y
        end)

        test("Vector3.Z is correct", function()
            return v3.Z == 3, v3.Z
        end)

        test("Vector3 addition works", function()
            local result = v3 + Vector3.new(1, 1, 1)
            return result.X == 2
                and result.Y == 3
                and result.Z == 4
        end)

        test("Vector3 scalar multiplication works", function()
            local result = v3 * 2
            return result.X == 2
                and result.Y == 4
                and result.Z == 6
        end)
    end
end

-- ============================================================
-- 13. COLOR3
-- ============================================================
section("13. Color3")

check("Color3.new is a function", Color3 ~= nil and type(Color3.new) == "function")
check("Color3.fromRGB is a function", Color3 ~= nil and type(Color3.fromRGB) == "function")
check("Color3.fromHSV is a function", Color3 ~= nil and type(Color3.fromHSV) == "function")
check("Color3.fromHex is a function", Color3 ~= nil and type(Color3.fromHex) == "function")

if Color3 ~= nil and type(Color3.new) == "function" then
    local color_ok, color = pcall(Color3.new, 0.5, 0.25, 0.75)
    check("Color3.new succeeds", color_ok and color ~= nil, color)

    if color_ok and color ~= nil then
        test("Color3.R is correct", function()
            return color.R == 0.5, color.R
        end)

        test("Color3.G is correct", function()
            return color.G == 0.25, color.G
        end)

        test("Color3.B is correct", function()
            return color.B == 0.75, color.B
        end)

        test("Color3:Lerp works", function()
            local result = color:Lerp(Color3.new(1, 1, 1), 0.5)
            return math.abs(result.R - 0.75) < 0.0001
                and math.abs(result.G - 0.625) < 0.0001
                and math.abs(result.B - 0.875) < 0.0001
        end)

        test("Color3:ToHSV returns three numbers", function()
            local h, s, v = color:ToHSV()
            return type(h) == "number"
                and type(s) == "number"
                and type(v) == "number"
        end)
    end
end

if Color3 ~= nil and type(Color3.fromRGB) == "function" then
    test("Color3.fromRGB converts 255,128,0", function()
        local color = Color3.fromRGB(255, 128, 0)
        return math.abs(color.R - 1) < 0.0001
            and math.abs(color.G - (128 / 255)) < 0.001
            and math.abs(color.B) < 0.0001
    end)
end

if Color3 ~= nil and type(Color3.fromHex) == "function" then
    test("Color3.fromHex parses #FF0000", function()
        local color = Color3.fromHex("#FF0000")
        return color.R == 1 and color.G == 0 and color.B == 0
    end)
end

-- ============================================================
-- 14. CFRAME
-- ============================================================
section("14. CFrame")

check("CFrame.new is a function", CFrame ~= nil and type(CFrame.new) == "function")
check("CFrame.Angles is a function", CFrame ~= nil and type(CFrame.Angles) == "function")
check("CFrame.lookAt is a function", CFrame ~= nil and type(CFrame.lookAt) == "function")
check(
    "CFrame.fromAxisAngle is a function",
    CFrame ~= nil and type(CFrame.fromAxisAngle) == "function"
)
check(
    "CFrame.fromOrientation is a function",
    CFrame ~= nil and type(CFrame.fromOrientation) == "function"
)

if CFrame ~= nil
    and type(CFrame.new) == "function"
    and Vector3 ~= nil
    and type(Vector3.new) == "function"
then
    local cframe_ok, cf = pcall(CFrame.new, 10, 20, 30)
    check("CFrame.new succeeds", cframe_ok and cf ~= nil, cf)

    if cframe_ok and cf ~= nil then
        test("CFrame.X is correct", function()
            return cf.X == 10, cf.X
        end)

        test("CFrame.Y is correct", function()
            return cf.Y == 20, cf.Y
        end)

        test("CFrame.Z is correct", function()
            return cf.Z == 30, cf.Z
        end)

        test("CFrame.Position is correct", function()
            return cf.Position.X == 10
                and cf.Position.Y == 20
                and cf.Position.Z == 30
        end)

        test("CFrame:Inverse works", function()
            local identity = cf * cf:Inverse()
            return math.abs(identity.X) < 0.0001
                and math.abs(identity.Y) < 0.0001
                and math.abs(identity.Z) < 0.0001
        end)

        test("CFrame:PointToWorldSpace works", function()
            local point = cf:PointToWorldSpace(Vector3.new(1, 2, 3))
            return point.X == 11 and point.Y == 22 and point.Z == 33,
                value_to_string(point)
        end)

        test("CFrame multiplication works", function()
            local result = cf * CFrame.new(1, 2, 3)
            return result.X == 11 and result.Y == 22 and result.Z == 33
        end)

        test("CFrame:GetComponents returns position first", function()
            local x, y, z = cf:GetComponents()
            return x == 10 and y == 20 and z == 30
        end)
    end
end

-- UDim/UDim2 are used by documented drawing examples but do not
-- have complete standalone class documentation in the supplied file.
info("UDim global", type(UDim))
info("UDim2 global", type(UDim2))

if UDim ~= nil and type(UDim.new) == "function" then
    local ok, value = pcall(UDim.new, 0.5, 10)
    if ok then
        info("UDim.new result", value)
    else
        info("UDim.new error", value)
    end
end

if UDim2 ~= nil then
    info("UDim2.new", type(UDim2.new))
    info("UDim2.fromScale", type(UDim2.fromScale))
end

-- ============================================================
-- 15. CRYPTOGRAPHY
-- ============================================================
section("15. Cryptography")

check("crypt library exists", type(crypt) == "table")

if type(crypt) == "table" then
    check(
        "crypt.hash.sha256 is a function",
        type(crypt.hash) == "table"
            and type(crypt.hash.sha256) == "function"
    )
    check(
        "crypt.base64.encode is a function",
        type(crypt.base64) == "table"
            and type(crypt.base64.encode) == "function"
    )
    check(
        "crypt.base64.decode is a function",
        type(crypt.base64) == "table"
            and type(crypt.base64.decode) == "function"
    )
    check(
        "crypt.json.encode is a function",
        type(crypt.json) == "table"
            and type(crypt.json.encode) == "function"
    )
    check(
        "crypt.json.decode is a function",
        type(crypt.json) == "table"
            and type(crypt.json.decode) == "function"
    )
    check(
        "crypt.hexadecimal.encode is a function",
        type(crypt.hexadecimal) == "table"
            and type(crypt.hexadecimal.encode) == "function"
    )
    check(
        "crypt.hexadecimal.decode is a function",
        type(crypt.hexadecimal) == "table"
            and type(crypt.hexadecimal.decode) == "function"
    )

    if type(crypt.hash) == "table"
        and type(crypt.hash.sha256) == "function"
    then
        test("crypt.hash.sha256 returns non-empty string", function()
            local digest = crypt.hash.sha256("abc")
            return type(digest) == "string" and #digest > 0, digest
        end)
    end

    if type(crypt.base64) == "table"
        and type(crypt.base64.encode) == "function"
        and type(crypt.base64.decode) == "function"
    then
        test("crypt.base64 round trip works", function()
            local original = "Severe VM test"
            local encoded = crypt.base64.encode(original)
            local decoded = crypt.base64.decode(encoded)
            return decoded == original, decoded
        end)
    end

    if type(crypt.hexadecimal) == "table"
        and type(crypt.hexadecimal.encode) == "function"
        and type(crypt.hexadecimal.decode) == "function"
    then
        test("crypt.hexadecimal round trip works", function()
            local original = "Severe"
            local encoded = crypt.hexadecimal.encode(original)
            local decoded = crypt.hexadecimal.decode(encoded)
            return decoded == original, decoded
        end)
    end

    if type(crypt.json) == "table"
        and type(crypt.json.encode) == "function"
        and type(crypt.json.decode) == "function"
    then
        test("crypt.json round trip works", function()
            local encoded = crypt.json.encode({
                name = "Severe",
                value = 42,
                enabled = true
            })
            local decoded = crypt.json.decode(encoded)

            return type(decoded) == "table"
                and decoded.name == "Severe"
                and decoded.value == 42
                and decoded.enabled == true
        end)
    end
end

-- ============================================================
-- 16. SAFE CAPABILITY PROBES
-- ============================================================
section("16. Safe Capability Probes")

-- These APIs are only checked for availability. They are not invoked
-- because doing so would require memory access, network access, input
-- generation, or modification of live game state.

info("memory library", type(memory))
if type(memory) == "table" then
    info("memory.readu8", type(memory.readu8))
    info("memory.writeu8", type(memory.writeu8))
    info("memory.readstring", type(memory.readstring))
    info("memory.writestring", type(memory.writestring))
    info("memory.base", memory.base)
end

info("WebsocketClient", type(WebsocketClient))
if WebsocketClient ~= nil then
    info(
        "WebsocketClient.new",
        type(first_present(WebsocketClient, "new", "New"))
    )
end

info("Signal", type(Signal))
if Signal ~= nil then
    info("Signal.new", type(first_present(Signal, "new", "New")))
end

info("DrawingImmediate", type(DrawingImmediate))
info("PointInstance", type(PointInstance))
info("Point3D", type(Point3D))
info("Cluster", type(Cluster))


-- ============================================================
-- 17. EXTENDED LUAU / STANDARD RUNTIME
-- ============================================================
section("17. Extended Luau and Standard Runtime")

local standard_libraries = {
    {"math", math},
    {"string", string},
    {"table", table},
    {"coroutine", coroutine},
    {"utf8", utf8},
    {"bit32", bit32},
    {"buffer", buffer}
}

for i = 1, #standard_libraries do
    local entry = standard_libraries[i]
    info(entry[1] .. " library", type(entry[2]))
end

local standard_functions = {
    {"assert", assert},
    {"error", error},
    {"ipairs", ipairs},
    {"pairs", pairs},
    {"next", next},
    {"select", select},
    {"tonumber", tonumber},
    {"typeof", typeof},
    {"xpcall", xpcall},
    {"rawequal", rawequal},
    {"rawget", rawget},
    {"rawset", rawset},
    {"setmetatable", setmetatable},
    {"getmetatable", getmetatable}
}

for i = 1, #standard_functions do
    local entry = standard_functions[i]
    info(entry[1] .. " global", type(entry[2]))
end

if type(buffer) == "table" then
    local create = first_present(buffer, "create")
    local writeu8 = first_present(buffer, "writeu8")
    local readu8 = first_present(buffer, "readu8")
    local len = first_present(buffer, "len")

    if type(create) == "function"
        and type(writeu8) == "function"
        and type(readu8) == "function"
        and type(len) == "function"
    then
        test("buffer create/read/write/len round trip", function()
            local value = create(4)
            writeu8(value, 0, 123)
            return len(value) == 4 and readu8(value, 0) == 123
        end)
    end
end

-- ============================================================
-- 18. SIGNAL CLASS COMPLETE BEHAVIOR
-- ============================================================
section("18. Signal Class Complete Behavior")

check("Signal table/class exists", Signal ~= nil)
check(
    "Signal.new exists",
    Signal ~= nil and type(first_present(Signal, "new", "New")) == "function"
)

if Signal ~= nil then
    local signal_new = first_present(Signal, "new", "New")

    if type(signal_new) == "function" then
        local new_ok, custom_signal = pcall(signal_new)

        check(
            "Signal.new creates a signal",
            new_ok and custom_signal ~= nil,
            custom_signal
        )

        if new_ok and custom_signal ~= nil then
            info(
                "Signal indexed Connect lookup",
                type(first_present(custom_signal, "Connect", "connect"))
            )
            info(
                "Signal indexed Fire lookup",
                type(first_present(custom_signal, "Fire", "fire"))
            )

            local received_a = nil
            local received_b = nil

            local connected, connection, connect_detail =
                connect_signal(
                    custom_signal,
                    function(a, b)
                        received_a = a
                        received_b = b
                    end
                )

            check(
                "Signal connection can be created",
                connected,
                connect_detail
            )

            if connected then
                local fired, fire_detail =
                    fire_signal(
                        custom_signal,
                        123,
                        "signal-ok"
                    )

                check("Signal can fire", fired, fire_detail)

                check(
                    "Signal callback receives arguments",
                    received_a == 123
                        and received_b == "signal-ok",
                    "received "
                        .. value_to_string(received_a)
                        .. ", "
                        .. value_to_string(received_b)
                )

                if connection ~= nil then
                    local disconnected, disconnect_detail =
                        disconnect_connection(connection)

                    check(
                        "Signal connection can disconnect",
                        disconnected,
                        disconnect_detail
                    )

                    received_a = nil
                    fire_signal(
                        custom_signal,
                        999,
                        "after-disconnect"
                    )

                    check(
                        "Disconnected Signal callback stays disconnected",
                        received_a == nil,
                        "callback received "
                            .. value_to_string(received_a)
                    )
                else
                    info(
                        "Signal disconnect test",
                        "skipped because Connect returned no handle"
                    )
                end
            end

            local once_count = 0
            local once_upper_ok, once_upper_result =
                pcall(function()
                    return custom_signal:Once(function()
                        once_count = once_count + 1
                    end)
                end)

            local once_ok = once_upper_ok
            local once_result = once_upper_result

            if not once_ok then
                local once_lower_ok, once_lower_result =
                    pcall(function()
                        return custom_signal:once(function()
                            once_count = once_count + 1
                        end)
                    end)

                once_ok = once_lower_ok
                once_result = once_lower_result
            end

            check(
                "Signal once/Once connection can be created",
                once_ok,
                once_result
            )

            if once_ok then
                fire_signal(custom_signal)
                fire_signal(custom_signal)

                check(
                    "Signal once callback fires exactly once",
                    once_count == 1,
                    "callback count="
                        .. value_to_string(once_count)
                )
            end

            info(
                "Signal indexed Wait lookup",
                type(first_present(custom_signal, "Wait", "wait"))
            )

            if EXTERNAL_TEST_CONFIG.run_signal_wait
                and type(task) == "table"
                and type(task.delay) == "function"
                and type(task.spawn) == "function"
                and type(task.wait) == "function"
            then
                local wait_signal_ok, wait_signal =
                    pcall(signal_new)

                check(
                    "Signal.new creates wait-test signal",
                    wait_signal_ok and wait_signal ~= nil,
                    wait_signal
                )

                if wait_signal_ok and wait_signal ~= nil then
                    local wait_finished = false
                    local wait_ok = false
                    local wait_first = nil
                    local wait_second = nil

                    local worker_ok, worker_error =
                        pcall(task.spawn, function()
                            wait_ok, wait_first, wait_second =
                                pcall(function()
                                    local upper_ok,
                                        upper_first,
                                        upper_second =
                                        pcall(function()
                                            return wait_signal:Wait()
                                        end)

                                    if upper_ok then
                                        return upper_first, upper_second
                                    end

                                    return wait_signal:wait()
                                end)

                            wait_finished = true
                        end)

                    check(
                        "Signal.wait worker is scheduled",
                        worker_ok,
                        worker_error
                    )

                    local delay_ok, delay_error =
                        pcall(task.delay, 0.01, function()
                            fire_signal(
                                wait_signal,
                                321,
                                "signal-wait-ok"
                            )
                        end)

                    check(
                        "Signal.wait delayed fire is scheduled",
                        delay_ok,
                        delay_error
                    )

                    if worker_ok and delay_ok then
                        for i = 1, 100 do
                            if wait_finished then
                                break
                            end

                            task.wait(0.01)
                        end

                        check(
                            "Signal wait/Wait resumes with arguments",
                            wait_finished
                                and wait_ok
                                and wait_first == 321
                                and wait_second == "signal-wait-ok",
                            "finished="
                                .. value_to_string(wait_finished)
                                .. " returned "
                                .. value_to_string(wait_first)
                                .. ", "
                                .. value_to_string(wait_second)
                        )

                        -- Release a still-waiting worker without making the
                        -- main suite block on a broken Wait implementation.
                        if not wait_finished then
                            pcall(fire_signal, wait_signal)
                        end
                    end
                end
            else
                info(
                    "Signal wait active test",
                    "scheduler functions required for bounded wait test "
                        .. "are unavailable"
                )
            end
        end
    end
end

-- ============================================================
-- 19. VECTOR2 / VECTOR3 COMPLETE OPERATIONS
-- ============================================================
section("19. Vector2 and Vector3 Complete Operations")

if Vector2 ~= nil and type(Vector2.new) == "function" then
    local vector_ok, v = pcall(Vector2.new, 6, 8)
    check(
        "Vector2 extended-test fixture can be created",
        vector_ok and v ~= nil,
        v
    )

    if vector_ok and v ~= nil then

    test("Vector2 zero constructor works", function()
        local zero = Vector2.new()
        return zero.X == 0 and zero.Y == 0
    end)

    test("Vector2 Magnitude property works", function()
        return math.abs(v.Magnitude - 10) < 0.0001, v.Magnitude
    end)

    test("Vector2 Unit property works", function()
        return math.abs(v.Unit.X - 0.6) < 0.0001
            and math.abs(v.Unit.Y - 0.8) < 0.0001
    end)

    test("Vector2 Dot method works", function()
        return v:Dot(Vector2.new(2, 3)) == 36
    end)

    test("Vector2 Cross method works", function()
        return v:Cross(Vector2.new(2, 3)) == 2
    end)

    test("Vector2 Lerp method works", function()
        local result = v:Lerp(Vector2.new(10, 12), 0.5)
        return result.X == 8 and result.Y == 10
    end)

    test("Vector2 subtraction works", function()
        local result = v - Vector2.new(1, 2)
        return result.X == 5 and result.Y == 6
    end)

    test("Vector2 component multiplication works", function()
        local result = v * Vector2.new(2, 3)
        return result.X == 12 and result.Y == 24
    end)

    test("Vector2 scalar division works", function()
        local result = v / 2
        return result.X == 3 and result.Y == 4
    end)

    test("Vector2 component division works", function()
        local result = v / Vector2.new(2, 4)
        return result.X == 3 and result.Y == 2
    end)

    test("Vector2 unary negation works", function()
        local result = -v
        return result.X == -6 and result.Y == -8
    end)

    test("Vector2 equality works", function()
        return Vector2.new(6, 8) == v
            and Vector2.new(6, 7) ~= v
    end)

    test("Vector2 tostring works", function()
        local result = tostring(v)
        return type(result) == "string" and #result > 0, result
    end)
    end
end

if Vector3 ~= nil and type(Vector3.new) == "function" then
    local vector_ok, v = pcall(Vector3.new, 2, 3, 6)
    check(
        "Vector3 extended-test fixture can be created",
        vector_ok and v ~= nil,
        v
    )

    if vector_ok and v ~= nil then

    test("Vector3 zero constructor works", function()
        local zero = Vector3.new()
        return zero.X == 0 and zero.Y == 0 and zero.Z == 0
    end)

    test("Vector3 Magnitude property works", function()
        return math.abs(v.Magnitude - 7) < 0.0001, v.Magnitude
    end)

    test("Vector3 Unit property works", function()
        return math.abs(v.Unit.Magnitude - 1) < 0.0001
    end)

    test("Vector3 Dot method works", function()
        return v:Dot(Vector3.new(1, 2, 3)) == 26
    end)

    test("Vector3 Cross method works", function()
        local result = v:Cross(Vector3.new(1, 0, 0))
        return result.X == 0 and result.Y == 6 and result.Z == -3
    end)

    test("Vector3 Lerp method works", function()
        local result = v:Lerp(Vector3.new(4, 5, 8), 0.5)
        return result.X == 3 and result.Y == 4 and result.Z == 7
    end)

    test("Vector3 subtraction works", function()
        local result = v - Vector3.new(1, 1, 1)
        return result.X == 1 and result.Y == 2 and result.Z == 5
    end)

    test("Vector3 component multiplication works", function()
        local result = v * Vector3.new(2, 3, 4)
        return result.X == 4 and result.Y == 9 and result.Z == 24
    end)

    test("Vector3 scalar division works", function()
        local result = v / 2
        return result.X == 1 and result.Y == 1.5 and result.Z == 3
    end)

    test("Vector3 component division works", function()
        local result = v / Vector3.new(2, 3, 2)
        return result.X == 1 and result.Y == 1 and result.Z == 3
    end)

    test("Vector3 unary negation works", function()
        local result = -v
        return result.X == -2 and result.Y == -3 and result.Z == -6
    end)

    test("Vector3 equality works", function()
        return Vector3.new(2, 3, 6) == v
            and Vector3.new(2, 3, 5) ~= v
    end)

    test("Vector3 tostring works", function()
        local result = tostring(v)
        return type(result) == "string" and #result > 0, result
    end)
    end
end

-- ============================================================
-- 20. COLOR3 COMPLETE OPERATIONS
-- ============================================================
section("20. Color3 Complete Operations")

if Color3 ~= nil then
    if type(Color3.fromHSV) == "function" then
        test("Color3.fromHSV creates red", function()
            local value = Color3.fromHSV(0, 1, 1)
            return math.abs(value.R - 1) < 0.0001
                and math.abs(value.G) < 0.0001
                and math.abs(value.B) < 0.0001
        end)
    end

    if type(Color3.fromHex) == "function" then
        test("Color3.fromHex accepts value without hash", function()
            local value = Color3.fromHex("00FF00")
            return value.R == 0 and value.G == 1 and value.B == 0
        end)
    end

    if type(Color3.new) == "function" then
        local a_ok, a = pcall(Color3.new, 1, 0.5, 0)
        local b_ok, b = pcall(Color3.new, 1, 0.5, 0)

        check(
            "Color3 extended-test fixtures can be created",
            a_ok and b_ok and a ~= nil and b ~= nil,
            "a=" .. value_to_string(a)
                .. ", b=" .. value_to_string(b)
        )

        if a_ok and b_ok and a ~= nil and b ~= nil then

        test("Color3 equality works", function()
            return a == b and a ~= Color3.new(0, 0, 0)
        end)

        test("Color3 tostring works", function()
            local result = tostring(a)
            return type(result) == "string" and #result > 0, result
        end)

        if type(typeof) == "function" then
            test("typeof(Color3) returns Color3", function()
                return typeof(a) == "Color3", typeof(a)
            end)
        end
        end
    end
end

-- ============================================================
-- 21. CFRAME COMPLETE OPERATIONS
-- ============================================================
section("21. CFrame Complete Operations")

if CFrame ~= nil
    and Vector3 ~= nil
    and type(CFrame.new) == "function"
    and type(Vector3.new) == "function"
then
    test("CFrame identity constructor works", function()
        local cf = CFrame.new()
        return cf.X == 0 and cf.Y == 0 and cf.Z == 0
    end)

    test("CFrame Vector3 constructor works", function()
        local cf = CFrame.new(Vector3.new(1, 2, 3))
        return cf.X == 1 and cf.Y == 2 and cf.Z == 3
    end)

    test("CFrame position/lookAt constructor works", function()
        local cf = CFrame.new(
            Vector3.new(0, 0, 0),
            Vector3.new(0, 0, -10)
        )
        return cf ~= nil
    end)

    test("CFrame quaternion constructor works", function()
        local cf = CFrame.new(
            1,
            2,
            3,
            0,
            0,
            0,
            1
        )

        return cf ~= nil
            and cf.X == 1
            and cf.Y == 2
            and cf.Z == 3
    end)

    test("CFrame rotation-matrix constructor works", function()
        local cf = CFrame.new(
            1,
            2,
            3,
            1,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            1
        )

        return cf ~= nil
            and cf.X == 1
            and cf.Y == 2
            and cf.Z == 3
    end)

    if type(CFrame.fromEulerAnglesXYZ) == "function" then
        test("CFrame.fromEulerAnglesXYZ numbers works", function()
            return CFrame.fromEulerAnglesXYZ(0.1, 0.2, 0.3) ~= nil
        end)

        test("CFrame.fromEulerAnglesXYZ Vector3 works", function()
            return CFrame.fromEulerAnglesXYZ(
                Vector3.new(0.1, 0.2, 0.3)
            ) ~= nil
        end)
    end

    if type(CFrame.fromEulerAnglesYXZ) == "function" then
        test("CFrame.fromEulerAnglesYXZ numbers works", function()
            return CFrame.fromEulerAnglesYXZ(0.1, 0.2, 0.3) ~= nil
        end)

        test("CFrame.fromEulerAnglesYXZ Vector3 works", function()
            return CFrame.fromEulerAnglesYXZ(
                Vector3.new(0.1, 0.2, 0.3)
            ) ~= nil
        end)
    end

    if type(CFrame.fromOrientation) == "function" then
        test("CFrame.fromOrientation works", function()
            return CFrame.fromOrientation(0.1, 0.2, 0.3) ~= nil
        end)
    end

    if type(CFrame.fromAxisAngle) == "function" then
        test("CFrame.fromAxisAngle works", function()
            return CFrame.fromAxisAngle(
                Vector3.new(0, 1, 0),
                math.pi / 4
            ) ~= nil
        end)
    end

    if type(CFrame.fromMatrix) == "function" then
        test("CFrame.fromMatrix works", function()
            return CFrame.fromMatrix(
                Vector3.new(1, 2, 3),
                Vector3.new(1, 0, 0),
                Vector3.new(0, 1, 0),
                Vector3.new(0, 0, 1)
            ) ~= nil
        end)
    end

    if type(CFrame.lookAt) == "function" then
        test("CFrame.lookAt works", function()
            return CFrame.lookAt(
                Vector3.new(0, 0, 0),
                Vector3.new(0, 0, -1),
                Vector3.new(0, 1, 0)
            ) ~= nil
        end)
    end

    if type(CFrame.Angles) == "function" then
        test("CFrame.Angles works", function()
            return CFrame.Angles(0.1, 0.2, 0.3) ~= nil
        end)
    end

    local cframe_ok, cf = pcall(CFrame.new, 10, 20, 30)
    check(
        "CFrame extended-test fixture can be created",
        cframe_ok and cf ~= nil,
        cf
    )

    if cframe_ok and cf ~= nil then

    test("CFrame RightVector works", function()
        return cf.RightVector ~= nil
    end)

    test("CFrame UpVector works", function()
        return cf.UpVector ~= nil
    end)

    test("CFrame LookVector works", function()
        return cf.LookVector ~= nil
    end)

    test("CFrame Lerp works", function()
        local result = cf:Lerp(CFrame.new(20, 30, 40), 0.5)
        return result.X == 15 and result.Y == 25 and result.Z == 35
    end)

    test("CFrame ToWorldSpace works", function()
        local result = cf:ToWorldSpace(CFrame.new(1, 2, 3))
        return result.X == 11 and result.Y == 22 and result.Z == 33
    end)

    test("CFrame ToObjectSpace works", function()
        local result = cf:ToObjectSpace(CFrame.new(11, 22, 33))
        return math.abs(result.X - 1) < 0.0001
            and math.abs(result.Y - 2) < 0.0001
            and math.abs(result.Z - 3) < 0.0001
    end)

    test("CFrame PointToObjectSpace works", function()
        local result = cf:PointToObjectSpace(Vector3.new(11, 22, 33))
        return result.X == 1 and result.Y == 2 and result.Z == 3
    end)

    test("CFrame VectorToWorldSpace works", function()
        local result = cf:VectorToWorldSpace(Vector3.new(1, 2, 3))
        return result ~= nil
    end)

    test("CFrame VectorToObjectSpace works", function()
        local result = cf:VectorToObjectSpace(Vector3.new(1, 2, 3))
        return result ~= nil
    end)

    test("CFrame ToOrientation returns numbers", function()
        local x, y, z = cf:ToOrientation()
        return type(x) == "number"
            and type(y) == "number"
            and type(z) == "number"
    end)

    test("CFrame ToEulerAnglesXYZ returns numbers", function()
        local x, y, z = cf:ToEulerAnglesXYZ()
        return type(x) == "number"
            and type(y) == "number"
            and type(z) == "number"
    end)

    test("CFrame ToEulerAnglesYXZ returns numbers", function()
        local x, y, z = cf:ToEulerAnglesYXZ()
        return type(x) == "number"
            and type(y) == "number"
            and type(z) == "number"
    end)

    test("CFrame ToAxisAngle returns axis and angle", function()
        local axis, angle = cf:ToAxisAngle()
        return axis ~= nil and type(angle) == "number"
    end)

    test("CFrame addition with Vector3 works", function()
        local result = cf + Vector3.new(1, 2, 3)
        return result.X == 11 and result.Y == 22 and result.Z == 33
    end)

    test("CFrame subtraction with Vector3 works", function()
        local result = cf - Vector3.new(1, 2, 3)
        return result.X == 9 and result.Y == 18 and result.Z == 27
    end)

    test("CFrame multiplication transforms Vector3", function()
        local result = cf * Vector3.new(1, 2, 3)
        return result.X == 11 and result.Y == 22 and result.Z == 33
    end)

    test("CFrame tostring works", function()
        local result = tostring(cf)
        return type(result) == "string" and #result > 0, result
    end)
    end
end

-- ============================================================
-- 22. UDIM / UDIM2 COMPATIBILITY
-- ============================================================
section("22. UDim and UDim2 Compatibility")

if UDim ~= nil and type(UDim.new) == "function" then
    test("UDim.new succeeds", function()
        return UDim.new(0.5, 10) ~= nil
    end)

    local ud_ok, ud = pcall(UDim.new, 0.5, 10)
    if ud_ok and ud ~= nil then
        test("UDim Scale/scale property works", function()
            local scale = first_present(ud, "Scale", "scale")
            return scale == 0.5, scale
        end)

        test("UDim Offset/offset property works", function()
            local offset = first_present(ud, "Offset", "offset")
            return offset == 10, offset
        end)
    end
end

if UDim2 ~= nil then
    if type(UDim2.new) == "function" then
        test("UDim2.new succeeds", function()
            return UDim2.new(1, 2, 3, 4) ~= nil
        end)
    end

    if type(UDim2.fromScale) == "function" then
        test("UDim2.fromScale succeeds", function()
            return UDim2.fromScale(0.5, 0.25) ~= nil
        end)
    end

    if type(UDim2.fromOffset) == "function" then
        test("UDim2.fromOffset succeeds", function()
            return UDim2.fromOffset(100, 50) ~= nil
        end)
    end
end

-- ============================================================
-- 23. ALL STATIC DRAWING CLASSES
-- ============================================================
section("23. All Static Drawing Classes")

local function set_and_read_property(object, property, value)
    local set_ok, set_error = pcall(function()
        object[property] = value
    end)

    if not set_ok then
        return false, set_error
    end

    local read_ok, result = pcall(function()
        return object[property]
    end)

    if not read_ok then
        return false, result
    end

    return true, result
end

local function create_static_drawing(class_name)
    if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
        return nil, "Drawing.new is missing"
    end

    local ok, object = pcall(Drawing.new, class_name)
    if not ok then
        return nil, object
    end

    return object
end

if type(Drawing) == "table" and type(Drawing.new) == "function" then
    local circle, circle_error = create_static_drawing("Circle")
    check("Drawing Circle can be created", circle ~= nil, circle_error)

    if circle ~= nil then
        test("Circle documented properties work", function()
            local values = {
                Visible = false,
                Color = Color3.new(1, 0, 0),
                ZIndex = 10,
                Opacity = 0.75,
                Thickness = 2,
                NumSides = 24,
                Radius = 30,
                Filled = false,
                Position = Vector2.new(100, 100)
            }

            for property, value in pairs(values) do
                local ok, err = set_and_read_property(circle, property, value)
                if not ok then
                    return false, property .. ": " .. value_to_string(err)
                end
            end

            return true
        end)

        local removed, remove_error = remove_drawing(circle)
        check("Circle Remove works", removed, remove_error)
    end

    local image, image_error = create_static_drawing("Image")
    check("Drawing Image can be created", image ~= nil, image_error)

    if image ~= nil then
        local image_properties = {
            {"Visible", false},
            {"Color", Color3.new(1, 1, 1)},
            {"ZIndex", 10},
            {"Opacity", 1},
            {"Url", ""},
            {"Data", ""},
            {"Gif", false},
            {"Position", Vector2.new(10, 10)},
            {"Size", Vector2.new(32, 32)},
            {"Rounding", 0}
        }

        for i = 1, #image_properties do
            local entry = image_properties[i]

            test("Image." .. entry[1] .. " documented property works", function()
                local ok, value_or_error =
                    set_and_read_property(
                        image,
                        entry[1],
                        entry[2]
                    )

                return ok,
                    entry[1]
                    .. ": "
                    .. value_to_string(value_or_error)
            end)
        end

        test("Image.Delay documented property works", function()
            local ok, value_or_error =
                set_and_read_property(image, "Delay", 0)

            return ok,
                "documentation lists Image.Delay; runtime result="
                .. value_to_string(value_or_error)
        end)

        test("Image.ImageSize can be read", function()
            local value = image.ImageSize
            return value ~= nil, value
        end)

        local removed, remove_error = remove_drawing(image)
        check("Image Remove works", removed, remove_error)
    end

    local line, line_error = create_static_drawing("Line")
    info(
        "Drawing Line creation",
        line ~= nil and "supported" or ("unsupported: " .. value_to_string(line_error))
    )

    if line ~= nil then
        test("Line common properties work", function()
            line.Visible = false
            line.Color = Color3.new(1, 1, 1)
            line.ZIndex = 10
            line.Opacity = 1
            line.Thickness = 2
            line.From = Vector2.new(10, 10)
            line.To = Vector2.new(100, 100)
            return true
        end)

        local removed, remove_error = remove_drawing(line)
        check("Line Remove works", removed, remove_error)
    end

    local text_object, text_error = create_static_drawing("Text")
    if text_object ~= nil then
        test("Text extended properties work", function()
            text_object.Visible = false
            text_object.Color = Color3.new(1, 1, 1)
            text_object.ZIndex = 10
            text_object.Opacity = 1
            text_object.Text = "Severe exhaustive test"
            text_object.Size = 16
            text_object.Center = false
            text_object.Outline = true
            text_object.OutlineColor = Vector3.new(0, 0, 0)
            text_object.Position = Vector2.new(50, 50)
            text_object.Font = 0

            local unused = text_object.TextBounds
            return true
        end)

        local removed, remove_error = remove_drawing(text_object)
        check("Extended Text Remove works", removed, remove_error)
    else
        check("Drawing Text can be created", false, text_error)
    end

    if EXTERNAL_TEST_CONFIG.run_drawing_clear
        and type(Drawing.clear) == "function"
    then
        local clear_ok, clear_error = pcall(Drawing.clear)
        check("Drawing.clear executes", clear_ok, clear_error)
    else
        info(
            "Drawing.clear active test",
            "disabled because it removes drawings belonging to every script"
        )
    end
end

-- ============================================================
-- 24. DYNAMIC DRAWING
-- ============================================================
section("24. Dynamic Drawing")

check(
    "Point3D.new exists",
    Point3D ~= nil and type(first_present(Point3D, "new", "New")) == "function"
)
check(
    "PointInstance.new exists",
    PointInstance ~= nil
        and type(first_present(PointInstance, "new", "New")) == "function"
)
check(
    "Drawing.attach exists",
    type(Drawing) == "table" and type(Drawing.attach) == "function"
)

local point3d_object = nil

if Point3D ~= nil
    and type(first_present(Point3D, "new", "New")) == "function"
then
    local new_point3d = first_present(Point3D, "new", "New")
    local candidates = {}

    if Vector3 ~= nil and type(Vector3.new) == "function" then
        local vector_ok, vector_value =
            pcall(Vector3.new, 0, 10, 0)

        if vector_ok then
            candidates[#candidates + 1] = {
                name = "Vector3.new(0, 10, 0)",
                value = vector_value
            }
        end
    end

    if CFrame ~= nil and type(CFrame.new) == "function" then
        local cframe_ok, cframe_value = pcall(function()
            return CFrame.new(0, 10, 0).Position
        end)

        if cframe_ok then
            candidates[#candidates + 1] = {
                name = "CFrame.Position",
                value = cframe_value
            }
        end
    end

    if workspace ~= nil then
        local camera_position_ok, camera_position = pcall(function()
            local camera = workspace.CurrentCamera
            return camera and camera.Position or nil
        end)

        if camera_position_ok and camera_position ~= nil then
            candidates[#candidates + 1] = {
                name = "Camera.Position",
                value = camera_position
            }
        end
    end

    local point_errors = {}

    for i = 1, #candidates do
        local entry = candidates[i]
        local point_ok, point_or_error =
            pcall(new_point3d, entry.value)

        if point_ok and point_or_error ~= nil then
            point3d_object = point_or_error
            info(
                "Point3D accepted source",
                entry.name
                    .. " | type="
                    .. type(entry.value)
                    .. " | typeof="
                    .. (type(typeof) == "function"
                        and value_to_string(typeof(entry.value))
                        or "unavailable")
            )
            break
        end

        point_errors[#point_errors + 1] =
            entry.name
            .. " (type="
            .. type(entry.value)
            .. ") => "
            .. value_to_string(point_or_error)
    end

    check(
        "Point3D.new creates a point",
        point3d_object ~= nil,
        #point_errors > 0
            and table.concat(point_errors, " || ")
            or "no position candidates were available"
    )

    if point3d_object ~= nil then
        test("Point3D.Position works", function()
            local position = point3d_object.Position
            return position ~= nil
                and type(position.X) == "number"
                and type(position.Y) == "number"
                and type(position.Z) == "number",
                position
        end)

        test("Point3D.Active is boolean", function()
            return type(point3d_object.Active) == "boolean",
                point3d_object.Active
        end)
    end
end

local dynamic_cluster = nil
local dynamic_drawing = nil

if point3d_object ~= nil
    and type(Drawing) == "table"
    and type(Drawing.new) == "function"
    and type(Drawing.attach) == "function"
    and UDim2 ~= nil
    and type(UDim2.fromScale) == "function"
then
    local drawing_ok, drawing_or_error = pcall(Drawing.new, "Square")
    dynamic_drawing = drawing_ok and drawing_or_error or nil

    if dynamic_drawing ~= nil then
        pcall(function()
            dynamic_drawing.Visible = false
            dynamic_drawing.Filled = true
            dynamic_drawing.Color = Color3.new(1, 1, 0)
        end)

        local attach_ok, cluster_or_error = pcall(
            Drawing.attach,
            {
                [dynamic_drawing] = {
                    Link = point3d_object,
                    Size = UDim2.fromScale(1, 1),
                    AnchorPoint = Vector2.new(0.5, 0.5)
                }
            }
        )

        dynamic_cluster = attach_ok and cluster_or_error or nil

        check(
            "Drawing.attach returns a Cluster",
            dynamic_cluster ~= nil,
            cluster_or_error
        )

        if dynamic_cluster ~= nil then
            local pause = first_present(dynamic_cluster, "Pause", "pause")
            local resume = first_present(dynamic_cluster, "Resume", "resume")
            local destroy = first_present(dynamic_cluster, "Destroy", "destroy")

            check("Cluster Pause exists", type(pause) == "function")
            check("Cluster Resume exists", type(resume) == "function")
            check("Cluster Destroy exists", type(destroy) == "function")

            if type(pause) == "function" then
                local ok, err = pcall(pause, dynamic_cluster)
                check("Cluster Pause executes", ok, err)
            end

            if type(resume) == "function" then
                local ok, err = pcall(resume, dynamic_cluster)
                check("Cluster Resume executes", ok, err)
            end

            if type(destroy) == "function" then
                local ok, err = pcall(destroy, dynamic_cluster)
                check("Cluster Destroy executes", ok, err)
                dynamic_cluster = nil
                dynamic_drawing = nil
            end
        end
    end
end

if dynamic_drawing ~= nil then
    remove_drawing(dynamic_drawing)
end

if point3d_object ~= nil then
    local destroy = first_present(point3d_object, "Destroy", "destroy")
    if type(destroy) == "function" then
        local ok, err = pcall(destroy, point3d_object)
        check("Point3D Destroy executes", ok, err)
    end
end

local function find_first_basepart()
    if workspace == nil then
        return nil
    end

    local ok, descendants = pcall(function()
        return workspace:GetDescendants()
    end)

    if not ok or type(descendants) ~= "table" then
        return nil
    end

    local known_classes = {
        Part = true,
        MeshPart = true,
        UnionOperation = true,
        SpawnLocation = true,
        CornerWedgePart = true,
        TrussPart = true,
        WedgePart = true
    }

    for i = 1, #descendants do
        local object = descendants[i]
        local class_name = nil

        pcall(function()
            class_name = object.ClassName
        end)

        if known_classes[class_name] then
            return object
        end
    end

    return nil
end

local first_basepart = find_first_basepart()

if first_basepart ~= nil
    and PointInstance ~= nil
    and type(first_present(PointInstance, "new", "New")) == "function"
then
    local new_point_instance = first_present(PointInstance, "new", "New")
    local point_ok, point_or_error = pcall(
        new_point_instance,
        first_basepart
    )

    check(
        "PointInstance.new tracks a BasePart",
        point_ok and point_or_error ~= nil,
        point_or_error
    )

    if point_ok and point_or_error ~= nil then
        local tracked = point_or_error

        test("PointInstance.CFrame works", function()
            return tracked.CFrame ~= nil
        end)

        test("PointInstance.Size works", function()
            return tracked.Size ~= nil
        end)

        test("PointInstance.Active is boolean", function()
            return type(tracked.Active) == "boolean", tracked.Active
        end)

        local destroy = first_present(tracked, "Destroy", "destroy")
        if type(destroy) == "function" then
            local ok, err = pcall(destroy, tracked)
            check("PointInstance Destroy executes", ok, err)
        end
    end
else
    info("PointInstance active test", "skipped because no BasePart or constructor was found")
end

-- ============================================================
-- 25. IMMEDIATE DRAWING COMPLETE API
-- ============================================================
section("25. Immediate Drawing Complete API")

local immediate_function_names = {
    "Line",
    "Circle",
    "FilledCircle",
    "Triangle",
    "FilledTriangle",
    "Rectangle",
    "FilledRectangle",
    "Quad",
    "FilledQuad",
    "Polyline",
    "Text",
    "OutlinedText",
    "Image",
    "GetTextBounds"
}

check("DrawingImmediate exists", type(DrawingImmediate) == "table")

if type(DrawingImmediate) == "table" then
    for i = 1, #immediate_function_names do
        local function_name = immediate_function_names[i]
        local function_value = first_present(DrawingImmediate, function_name)
        check(
            "DrawingImmediate." .. function_name .. " exists",
            type(function_value) == "function"
        )
    end

    if type(DrawingImmediate.GetTextBounds) == "function" then
        test("DrawingImmediate.GetTextBounds returns Vector2-like value", function()
            local bounds = DrawingImmediate.GetTextBounds(
                "Tamzen",
                16,
                "Severe"
            )

            return bounds ~= nil
                and type(bounds.X) == "number"
                and type(bounds.Y) == "number"
        end)
    end

    if EXTERNAL_TEST_CONFIG.run_immediate_drawing_calls
        and Vector2 ~= nil
        and Color3 ~= nil
    then
        local fixtures_ok, a, b, c, d, white =
            pcall(function()
                return Vector2.new(10, 10),
                    Vector2.new(30, 10),
                    Vector2.new(20, 30),
                    Vector2.new(40, 30),
                    Color3.new(1, 1, 1)
            end)

        check(
            "DrawingImmediate fixtures can be created",
            fixtures_ok
                and a ~= nil
                and b ~= nil
                and c ~= nil
                and d ~= nil
                and white ~= nil,
            a
        )

        if fixtures_ok
            and a ~= nil
            and b ~= nil
            and c ~= nil
            and d ~= nil
            and white ~= nil
        then

        local immediate_calls = {
            {
                "Line",
                function()
                    DrawingImmediate.Line(a, b, white, 1, 1, 1)
                end
            },
            {
                "Circle",
                function()
                    DrawingImmediate.Circle(a, 10, white, 1, 1)
                end
            },
            {
                "FilledCircle",
                function()
                    DrawingImmediate.FilledCircle(a, 10, white, 1)
                end
            },
            {
                "Triangle",
                function()
                    DrawingImmediate.Triangle(a, b, c, white, 1, 1)
                end
            },
            {
                "FilledTriangle",
                function()
                    DrawingImmediate.FilledTriangle(a, b, c, white, 1)
                end
            },
            {
                "Rectangle",
                function()
                    DrawingImmediate.Rectangle(a, b, white, 1, 1)
                end
            },
            {
                "FilledRectangle",
                function()
                    DrawingImmediate.FilledRectangle(a, b, white, 1)
                end
            },
            {
                "Quad",
                function()
                    DrawingImmediate.Quad(a, b, c, d, white, 1, 1)
                end
            },
            {
                "FilledQuad",
                function()
                    DrawingImmediate.FilledQuad(a, b, c, d, white, 1)
                end
            },
            {
                "Polyline",
                function()
                    DrawingImmediate.Polyline(
                        {a, b, c, d},
                        white,
                        1,
                        1
                    )
                end
            },
            {
                "Text",
                function()
                    DrawingImmediate.Text(
                        a,
                        16,
                        white,
                        1,
                        "Severe",
                        false,
                        "Tamzen"
                    )
                end
            },
            {
                "OutlinedText",
                function()
                    DrawingImmediate.OutlinedText(
                        a,
                        16,
                        white,
                        1,
                        "Severe",
                        false,
                        "Tamzen"
                    )
                end
            }
        }

        for i = 1, #immediate_calls do
            local entry = immediate_calls[i]
            local ok, err = pcall(entry[2])
            check(
                "DrawingImmediate." .. entry[1] .. " executes",
                ok,
                err
            )
        end
        end
    else
        info(
            "Immediate drawing execution tests",
            "disabled; functions are still checked for availability"
        )
    end
end

-- ============================================================
-- 26. DATA MODEL / CAMERA / WORLD MIRROR
-- ============================================================
section("26. Data Model, Camera, and World Mirror")

if game ~= nil then
    test("game.PlaceId is number", function()
        return type(game.PlaceId) == "number", game.PlaceId
    end)

    test("game.GameId is number", function()
        return type(game.GameId) == "number", game.GameId
    end)

    test("game.JobId is string", function()
        return type(game.JobId) == "string", game.JobId
    end)

    test("game:GetPing returns number", function()
        local ping = game:GetPing()
        return type(ping) == "number", ping
    end)

    if EXTERNAL_TEST_CONFIG.run_hwid_read then
        test("game:GetHwid returns non-empty string", function()
            local hwid = game:GetHwid()
            return type(hwid) == "string" and #hwid > 0
        end)
    else
        info(
            "game:GetHwid active test",
            "disabled to avoid reading device identity"
        )
    end

    if EXTERNAL_TEST_CONFIG.run_http_get then
        test("game:HttpGet returns a string", function()
            local response = game:HttpGet(
                EXTERNAL_TEST_VALUES.http_get_url
            )
            return type(response) == "string" and #response > 0
        end)
    end

    if EXTERNAL_TEST_CONFIG.run_http_post then
        local post_url = EXTERNAL_TEST_VALUES.http_post_url
        local post_signature = EXTERNAL_TEST_VALUES.http_post_signature

        if type(post_url) ~= "string" or post_url == "" then
            record_result(
                "game:HttpPost live behavior",
                "SKIP",
                "run_http_post=true, but http_post_url was not explicitly "
                    .. "set to a known-good fixture",
                "compatibility"
            )
        elseif post_signature ~= "2arg"
            and post_signature ~= "3arg"
            and post_signature ~= "4arg"
        then
            record_result(
                "game:HttpPost live behavior",
                "SKIP",
                "invalid http_post_signature="
                    .. value_to_string(post_signature)
                    .. "; expected 2arg, 3arg, or 4arg",
                "compatibility"
            )
        else
            test(
                "game:HttpPost "
                    .. post_signature
                    .. " returns a string",
                function()
                    local response

                    if post_signature == "2arg" then
                        response = game:HttpPost(
                            post_url,
                            EXTERNAL_TEST_VALUES.http_post_body
                        )
                    elseif post_signature == "3arg" then
                        response = game:HttpPost(
                            post_url,
                            EXTERNAL_TEST_VALUES.http_post_body,
                            EXTERNAL_TEST_VALUES.http_post_content_type
                        )
                    else
                        response = game:HttpPost(
                            post_url,
                            EXTERNAL_TEST_VALUES.http_post_body,
                            EXTERNAL_TEST_VALUES.http_post_content_type,
                            EXTERNAL_TEST_VALUES.http_post_accept
                        )
                    end

                    return type(response) == "string",
                        "returned " .. type(response)
                end
            )
        end
    else
        record_result(
            "game:HttpPost live behavior",
            "SKIP",
            "disabled by default because no script-level timeout can stop "
                .. "a blocked Severe native HttpPost call; enable only with "
                .. "an explicitly configured known-good fixture",
            "compatibility"
        )
    end
end

local extended_camera = nil
if workspace ~= nil then
    pcall(function()
        extended_camera = workspace.CurrentCamera
    end)
end

if extended_camera ~= nil then
    local camera = extended_camera

    local camera_properties = {
        {"ViewportSize", "userdata"},
        {"FieldOfView", "number"},
        {"Position", "userdata"},
        {"CFrame", "userdata"},
        {"Velocity", "userdata"},
        {"RightVector", "userdata"},
        {"UpVector", "userdata"},
        {"LookVector", "userdata"}
    }

    for i = 1, #camera_properties do
        local entry = camera_properties[i]
        test("Camera." .. entry[1] .. " can be read", function()
            local value = camera[entry[1]]
            return value ~= nil, value
        end)
    end

    test("Camera.CameraSubject documented property can be read", function()
        local subject = camera.CameraSubject
        return true, subject
    end)

    if EXTERNAL_TEST_CONFIG.run_live_instance_mutation then
        test("Camera documented writable properties accept old values", function()
            local old_position = camera.Position
            local old_cframe = camera.CFrame
            local old_velocity = camera.Velocity
            local old_right = camera.RightVector
            local old_up = camera.UpVector
            local old_look = camera.LookVector
            local old_subject = camera.CameraSubject

            camera.Position = old_position
            camera.CFrame = old_cframe
            camera.Velocity = old_velocity
            camera.RightVector = old_right
            camera.UpVector = old_up
            camera.LookVector = old_look
            camera.CameraSubject = old_subject

            return true
        end)
    else
        info(
            "Camera mutation tests",
            "disabled; documented writable properties are only read"
        )
    end

    if first_basepart ~= nil then
        test("Camera WorldToScreenPoint works on BasePart", function()
            local screen, visible =
                camera:WorldToScreenPoint(first_basepart.Position)

            return screen ~= nil
                and type(screen.X) == "number"
                and type(screen.Y) == "number"
                and type(screen.Z) == "number"
                and type(visible) == "boolean"
        end)
    end
else
    info(
        "Extended Camera property tests",
        "skipped because workspace.CurrentCamera is unavailable"
    )
end

if first_basepart ~= nil then
    local basepart_properties = {
        "CanCollide",
        "Transparency",
        "Size",
        "Position",
        "CFrame",
        "Velocity",
        "RightVector",
        "UpVector",
        "LookVector",
        "IsNetworkSleeping",
        "Description"
    }

    local basepart_name_ok, basepart_name = pcall(function()
        return first_basepart.Name
    end)
    info(
        "BasePart test target",
        basepart_name_ok and basepart_name or "<name unavailable>"
    )

    for i = 1, #basepart_properties do
        local property = basepart_properties[i]
        test("BasePart." .. property .. " can be read", function()
            local unused = first_basepart[property]
            return true
        end)
    end

    if EXTERNAL_TEST_CONFIG.run_live_basepart_mutation then
        test("BasePart writable properties can be restored", function()
            local old_can_collide = first_basepart.CanCollide
            local old_transparency = first_basepart.Transparency
            local old_size = first_basepart.Size
            local old_position = first_basepart.Position
            local old_cframe = first_basepart.CFrame
            local old_velocity = first_basepart.Velocity
            local old_description = first_basepart.Description

            first_basepart.CanCollide = old_can_collide
            first_basepart.Transparency = old_transparency
            first_basepart.Size = old_size
            first_basepart.Position = old_position
            first_basepart.CFrame = old_cframe
            first_basepart.Velocity = old_velocity
            first_basepart.Description = old_description

            return true
        end)
    else
        info(
            "BasePart mutation tests",
            "disabled; writable properties are only read"
        )
    end
else
    info("BasePart tests", "skipped because no BasePart was found")
end

local function find_first_class(class_name)
    if workspace == nil then
        return nil
    end

    local ok, descendants = pcall(function()
        return workspace:GetDescendants()
    end)

    if not ok or type(descendants) ~= "table" then
        return nil
    end

    for i = 1, #descendants do
        local object = descendants[i]
        local object_class = nil

        pcall(function()
            object_class = object.ClassName
        end)

        if object_class == class_name then
            return object
        end
    end

    return nil
end

local first_mesh_object =
    find_first_class("MeshPart")
    or find_first_class("SpecialMesh")

if first_mesh_object ~= nil then
    info(
        "Mesh property test target",
        first_mesh_object.ClassName
            .. " "
            .. first_mesh_object.Name
    )

    test("Mesh TextureId can be read on supported class", function()
        local value = first_mesh_object.TextureId
        return type(value) == "string", value
    end)

    test("Mesh MeshId can be read on supported class", function()
        local value = first_mesh_object.MeshId
        return type(value) == "string", value
    end)

    if EXTERNAL_TEST_CONFIG.run_live_instance_mutation then
        test("Mesh TextureId and MeshId accept old values", function()
            local old_texture = first_mesh_object.TextureId
            local old_mesh = first_mesh_object.MeshId

            first_mesh_object.TextureId = old_texture
            first_mesh_object.MeshId = old_mesh

            return true
        end)
    else
        info(
            "Mesh mutation tests",
            "disabled; TextureId and MeshId are only read"
        )
    end
else
    info(
        "Mesh TextureId/MeshId tests",
        "skipped because no MeshPart or SpecialMesh was found"
    )
end

local first_humanoid = find_first_class("Humanoid")
if first_humanoid ~= nil then
    test("Humanoid.Health can be read", function()
        return type(first_humanoid.Health) == "number",
            first_humanoid.Health
    end)

    test("Humanoid.MaxHealth can be read", function()
        return type(first_humanoid.MaxHealth) == "number",
            first_humanoid.MaxHealth
    end)

    if EXTERNAL_TEST_CONFIG.run_live_instance_mutation then
        test("Humanoid Health and MaxHealth accept old values", function()
            local old_health = first_humanoid.Health
            local old_max_health = first_humanoid.MaxHealth

            first_humanoid.Health = old_health
            first_humanoid.MaxHealth = old_max_health

            return true
        end)
    else
        info(
            "Humanoid mutation tests",
            "disabled; Health and MaxHealth are only read"
        )
    end
else
    info("Humanoid tests", "skipped because no Humanoid was found")
end

local first_billboard = find_first_class("BillboardGui")
if first_billboard ~= nil then
    test("BillboardGui.Adornee can be read", function()
        local unused = first_billboard.Adornee
        return true
    end)
else
    info("BillboardGui test", "skipped because none was found")
end

local value_classes = {
    "BoolValue",
    "BrickColorValue",
    "CFrameValue",
    "Color3Value",
    "IntValue",
    "NumberValue",
    "ObjectValue",
    "StringValue",
    "Vector3Value"
}

local valuebase_found = nil

for i = 1, #value_classes do
    valuebase_found = find_first_class(value_classes[i])
    if valuebase_found ~= nil then
        break
    end
end

if valuebase_found ~= nil then
    test("ValueBase.Value can be read", function()
        local unused = valuebase_found.Value
        return true
    end)

    if EXTERNAL_TEST_CONFIG.run_live_instance_mutation then
        test("ValueBase.Value accepts its old value", function()
            local old_value = valuebase_found.Value
            valuebase_found.Value = old_value
            return true
        end)
    else
        info(
            "ValueBase mutation test",
            "disabled; Value is only read"
        )
    end
else
    info("ValueBase test", "skipped because no ValueBase was found")
end

-- ============================================================
-- 27. INSTANCE API COMPLETE COVERAGE
-- ============================================================
section("27. Instance API Complete Coverage")

local instance_target = first_basepart

if instance_target == nil and workspace ~= nil then
    local ok, children = pcall(function()
        return workspace:GetChildren()
    end)

    if ok and type(children) == "table" then
        instance_target = children[1]
    end
end

if instance_target ~= nil then
    local instance_name_ok, instance_name = pcall(function()
        return instance_target.Name
    end)
    info(
        "Instance API target",
        instance_name_ok and instance_name or "<name unavailable>"
    )

    info(
        "Instance method exposure",
        "methods are tested through direct namecalls because indexed "
            .. "method lookup returns nil on this native mirror"
    )

    test("Instance Name can be read", function()
        return type(instance_target.Name) == "string",
            instance_target.Name
    end)

    test("Instance ClassName can be read", function()
        return type(instance_target.ClassName) == "string",
            instance_target.ClassName
    end)

    test("Instance Parent can be read", function()
        local unused = instance_target.Parent
        return true
    end)

    test("Instance Data can be read", function()
        local unused = instance_target.Data
        return true
    end)

    test("Instance:GetTags returns table", function()
        local tags = instance_target:GetTags()
        return type(tags) == "table", type(tags)
    end)

    test("Instance:HasTag returns boolean", function()
        return type(instance_target:HasTag(
            "__SEVERE_VM_TEST_TAG_THAT_SHOULD_NOT_EXIST__"
        )) == "boolean"
    end)

    test("Instance:GetAttributes returns table", function()
        return type(instance_target:GetAttributes()) == "table"
    end)

    test("Instance:GetAttribute missing returns nil", function()
        return instance_target:GetAttribute(
            "__SEVERE_VM_TEST_ATTRIBUTE_THAT_SHOULD_NOT_EXIST__"
        ) == nil
    end)

    test("Instance:FindFirstChildOfClass can execute", function()
        local unused = instance_target:FindFirstChildOfClass("Folder")
        return true
    end)

    test("Instance:FindFirstDescendant can execute", function()
        local unused = instance_target:FindFirstDescendant(
            "__SEVERE_VM_TEST_MISSING_DESCENDANT__"
        )
        return true
    end)

    test("Instance:FindFirstAncestor can execute", function()
        local unused = instance_target:FindFirstAncestor("Workspace")
        return true
    end)

    test("Instance:FindFirstAncestorOfClass can execute", function()
        local unused = instance_target:FindFirstAncestorOfClass("Workspace")
        return true
    end)

    test("Instance:GetChildren returns table", function()
        return type(instance_target:GetChildren()) == "table"
    end)

    test("Instance:GetDescendants returns table", function()
        return type(instance_target:GetDescendants()) == "table"
    end)

    test("Instance:WaitForChild timeout path returns safely", function()
        local result = instance_target:WaitForChild(
            "__SEVERE_VM_TEST_MISSING_CHILD__",
            0
        )

        return result == nil
    end)

    if workspace ~= nil then
        test("Instance:IsDescendantOf works", function()
            return type(instance_target:IsDescendantOf(workspace)) == "boolean"
        end)

        test("Instance:IsAncestorOf works", function()
            return type(workspace:IsAncestorOf(instance_target)) == "boolean"
        end)
    end

    if EXTERNAL_TEST_CONFIG.run_live_instance_mutation then
        local test_tag = "__SEVERE_VM_TEST_TAG__"
        local test_attribute = "__SEVERE_VM_TEST_ATTRIBUTE__"

        local mutation_targets = {}
        local seen_targets = {}

        local function add_mutation_target(name, object)
            if object == nil or seen_targets[object] then
                return
            end

            seen_targets[object] = true
            mutation_targets[#mutation_targets + 1] = {
                name = name,
                object = object
            }
        end

        add_mutation_target("selected instance", instance_target)
        add_mutation_target("workspace", workspace)
        add_mutation_target("first BasePart", first_basepart)

        if players_service ~= nil then
            local local_player = nil
            pcall(function()
                local_player = players_service.LocalPlayer
            end)

            add_mutation_target("LocalPlayer", local_player)

            if local_player ~= nil then
                local character = nil
                pcall(function()
                    character = local_player.Character
                end)
                add_mutation_target("LocalPlayer.Character", character)
            end
        end

        local tag_success_target = nil
        local tag_attempts = {}

        for i = 1, #mutation_targets do
            local entry = mutation_targets[i]
            local object = entry.object

            local add_ok, add_error = pcall(function()
                object:AddTag(test_tag)
            end)

            local read_ok, has_tag = pcall(function()
                return object:HasTag(test_tag)
            end)

            pcall(function()
                object:RemoveTag(test_tag)
            end)

            tag_attempts[#tag_attempts + 1] =
                entry.name
                .. ": AddTag ok="
                .. value_to_string(add_ok)
                .. ", HasTag ok="
                .. value_to_string(read_ok)
                .. ", value="
                .. value_to_string(has_tag)
                .. (
                    add_ok
                        and ""
                        or ", error=" .. value_to_string(add_error)
                )

            if add_ok and read_ok and has_tag == true then
                tag_success_target = entry
                break
            end
        end

        check(
            "Instance:HasTag observes added tag on at least one live target",
            tag_success_target ~= nil,
            table.concat(tag_attempts, " || ")
        )

        if tag_success_target ~= nil then
            info(
                "Writable tag target",
                tag_success_target.name
            )
        end

        local attribute_success_target = nil
        local attribute_attempts = {}

        for i = 1, #mutation_targets do
            local entry = mutation_targets[i]
            local object = entry.object
            local old_value = nil

            pcall(function()
                old_value = object:GetAttribute(test_attribute)
            end)

            local set_ok, set_error = pcall(function()
                object:SetAttribute(test_attribute, 12345)
            end)

            local get_ok, actual_value = pcall(function()
                return object:GetAttribute(test_attribute)
            end)

            pcall(function()
                object:SetAttribute(test_attribute, old_value)
            end)

            attribute_attempts[#attribute_attempts + 1] =
                entry.name
                .. ": SetAttribute ok="
                .. value_to_string(set_ok)
                .. ", GetAttribute ok="
                .. value_to_string(get_ok)
                .. ", value="
                .. value_to_string(actual_value)
                .. (
                    set_ok
                        and ""
                        or ", error=" .. value_to_string(set_error)
                )

            if set_ok and get_ok and actual_value == 12345 then
                attribute_success_target = entry
                break
            end
        end

        check(
            "Instance:GetAttribute observes assigned value on at least one live target",
            attribute_success_target ~= nil,
            table.concat(attribute_attempts, " || ")
        )

        if attribute_success_target ~= nil then
            info(
                "Writable attribute target",
                attribute_success_target.name
            )
        end
    else
        info(
            "Instance mutation tests",
            "disabled; AddTag, RemoveTag, ClearTags, and SetAttribute are not called"
        )
    end
else
    info("Instance API tests", "skipped because no target was found")
end

if instance_target ~= nil
    and EXTERNAL_TEST_CONFIG.run_instance_clear_tags
then
    test("Instance:ClearTags clears and restores a test target", function()
        local original_tags = instance_target:GetTags()
        local test_tag_a = "__SEVERE_VM_CLEAR_TAG_A__"
        local test_tag_b = "__SEVERE_VM_CLEAR_TAG_B__"

        local operation_ok, operation_result =
            pcall(function()
                instance_target:AddTag(test_tag_a)
                instance_target:AddTag(test_tag_b)
                instance_target:ClearTags()

                return instance_target:HasTag(test_tag_a) == false
                    and instance_target:HasTag(test_tag_b) == false
                    and #instance_target:GetTags() == 0
            end)

        -- Restore the complete original tag set even when the active
        -- test itself failed after ClearTags.
        local restore_ok, restore_error = pcall(function()
            instance_target:ClearTags()

            for i = 1, #original_tags do
                instance_target:AddTag(original_tags[i])
            end
        end)

        if not restore_ok then
            return false,
                "tag restoration failed: "
                .. value_to_string(restore_error)
        end

        if not operation_ok then
            return false, operation_result
        end

        return operation_result == true
    end)
else
    info(
        "Instance:ClearTags active test",
        "disabled because it temporarily removes every tag from a live target"
    )
end

if EXTERNAL_TEST_CONFIG.run_instance_destroy then
    local instance_new =
        Instance ~= nil
        and first_present(Instance, "new", "New")
        or nil

    if type(instance_new) == "function" then
        local create_ok, disposable_instance =
            pcall(instance_new, "Folder")

        check(
            "Instance.new creates disposable Destroy target",
            create_ok and disposable_instance ~= nil,
            disposable_instance
        )

        if create_ok and disposable_instance ~= nil then
            local destroy_ok, destroy_error = pcall(function()
                disposable_instance:Destroy()
            end)

            check(
                "Instance:Destroy removes disposable target",
                destroy_ok,
                destroy_error
            )
        end
    else
        info(
            "Instance:Destroy active test",
            "Instance.new is unavailable, so no safe disposable target exists"
        )
    end
else
    info(
        "Instance:Destroy active test",
        "disabled; the suite never destroys a live mirrored game object"
    )
end

if players_service ~= nil then
    local local_player = nil
    pcall(function()
        local_player = players_service.LocalPlayer
    end)

    if local_player ~= nil then
        test("Player.DisplayName can be read", function()
            return type(local_player.DisplayName) == "string",
                local_player.DisplayName
        end)

        test("Player.UserId can be read", function()
            return type(local_player.UserId) == "number",
                local_player.UserId
        end)

        test("Player.Character can be read", function()
            local unused = local_player.Character
            return true
        end)

        test("Player.Team can be read", function()
            local unused = local_player.Team
            return true
        end)

        if local_player.Character ~= nil then
            test("Model.PrimaryPart can be read", function()
                local unused = local_player.Character.PrimaryPart
                return true
            end)
        end
    end
end

-- ============================================================
-- 28. USER INPUT SERVICE COMPLETE COVERAGE
-- ============================================================
section("28. UserInputService Complete Coverage")

if user_input_service ~= nil then
    info(
        "UserInputService.SetMouseLocation indexed lookup",
        type(first_present(user_input_service, "SetMouseLocation"))
            .. " (direct namecall is tested below)"
    )

    test("UserInputService.MouseBehavior can be read", function()
        local unused = user_input_service.MouseBehavior
        return true
    end)

    if EXTERNAL_TEST_CONFIG.run_user_input_service_write then
        test("UserInputService:SetMouseLocation can restore position", function()
            local current = user_input_service:GetMouseLocation()
            user_input_service:SetMouseLocation(current.X, current.Y)
            return true
        end)

        test("MouseDeltaSensitivity can be assigned its old value", function()
            local old = user_input_service.MouseDeltaSensitivity
            user_input_service.MouseDeltaSensitivity = old
            return true
        end)

        test("MouseIconEnabled can be assigned its old value", function()
            local old = user_input_service.MouseIconEnabled
            user_input_service.MouseIconEnabled = old
            return true
        end)

        test("MouseBehavior can be assigned its old value", function()
            local old = user_input_service.MouseBehavior
            user_input_service.MouseBehavior = old
            return true
        end)
    else
        info(
            "UserInputService write tests",
            "disabled; properties and cursor location are not changed"
        )
    end
end

-- ============================================================
-- 29. COMPLETE CRYPTOGRAPHY API
-- ============================================================
section("29. Complete Cryptography API")

local function nested_function(root, first, second)
    if type(root) ~= "table" then
        return nil
    end

    local branch = root[first]
    if type(branch) ~= "table" then
        return nil
    end

    return branch[second]
end

local crypto_function_paths = {
    {
        "crypt.random",
        type(crypt) == "table" and crypt.random or nil
    },
    {
        "crypt.random_deterministic",
        type(crypt) == "table" and crypt.random_deterministic or nil
    },
    {"crypt.hash.sha256", crypt and nested_function(crypt, "hash", "sha256")},
    {"crypt.hash.sha512", crypt and nested_function(crypt, "hash", "sha512")},
    {"crypt.hash.blake2b", crypt and nested_function(crypt, "hash", "blake2b")},
    {
        "crypt.pwhash",
        type(crypt) == "table" and crypt.pwhash or nil
    },
    {
        "crypt.pwhash_str",
        type(crypt) == "table" and crypt.pwhash_str or nil
    },
    {
        "crypt.pwhash_str_verify",
        type(crypt) == "table" and crypt.pwhash_str_verify or nil
    },
    {"crypt.secretbox.seal", crypt and nested_function(crypt, "secretbox", "seal")},
    {"crypt.secretbox.open", crypt and nested_function(crypt, "secretbox", "open")},
    {"crypt.aead.encrypt", crypt and nested_function(crypt, "aead", "encrypt")},
    {"crypt.aead.decrypt", crypt and nested_function(crypt, "aead", "decrypt")},
    {"crypt.box.keypair", crypt and nested_function(crypt, "box", "keypair")},
    {"crypt.box.encrypt", crypt and nested_function(crypt, "box", "encrypt")},
    {"crypt.box.decrypt", crypt and nested_function(crypt, "box", "decrypt")},
    {"crypt.box.seal", crypt and nested_function(crypt, "box", "seal")},
    {"crypt.box.open", crypt and nested_function(crypt, "box", "open")},
    {"crypt.box.beforenm", crypt and nested_function(crypt, "box", "beforenm")},
    {"crypt.sign.keypair", crypt and nested_function(crypt, "sign", "keypair")},
    {"crypt.sign.sign", crypt and nested_function(crypt, "sign", "sign")},
    {"crypt.sign.open", crypt and nested_function(crypt, "sign", "open")},
    {"crypt.sign.detached", crypt and nested_function(crypt, "sign", "detached")},
    {
        "crypt.sign.verify_detached",
        crypt and nested_function(crypt, "sign", "verify_detached")
    },
    {"crypt.base64.encode", crypt and nested_function(crypt, "base64", "encode")},
    {"crypt.base64.decode", crypt and nested_function(crypt, "base64", "decode")},
    {"crypt.hmac.sha256", crypt and nested_function(crypt, "hmac", "sha256")},
    {"crypt.hmac.sha512", crypt and nested_function(crypt, "hmac", "sha512")},
    {"crypt.hkdf.sha256", crypt and nested_function(crypt, "hkdf", "sha256")},
    {"crypt.json.encode", crypt and nested_function(crypt, "json", "encode")},
    {"crypt.json.decode", crypt and nested_function(crypt, "json", "decode")},
    {
        "crypt.hexadecimal.encode",
        crypt and nested_function(crypt, "hexadecimal", "encode")
    },
    {
        "crypt.hexadecimal.decode",
        crypt and nested_function(crypt, "hexadecimal", "decode")
    }
}

for i = 1, #crypto_function_paths do
    local entry = crypto_function_paths[i]
    check(entry[1] .. " exists", type(entry[2]) == "function")
end

local function crypto_random(size)
    if type(crypt) ~= "table" or type(crypt.random) ~= "function" then
        error("crypt.random is missing")
    end

    local number_ok, number_value = pcall(crypt.random, size)
    if number_ok then
        return number_value
    end

    return crypt.random(tostring(size))
end

if type(crypt) == "table" then
    if type(crypt.random) == "function" then
        test("crypt.random returns requested-size-like data", function()
            local value = crypto_random(16)
            return type(value) == "string" and #value > 0, #value
        end)
    end

    if type(crypt.random_deterministic) == "function" then
        test("crypt.random_deterministic is deterministic", function()
            local seed = string.rep("S", 32)

            local first_ok, first = pcall(
                crypt.random_deterministic,
                16,
                seed
            )

            if not first_ok then
                first = crypt.random_deterministic("16", seed)
            end

            local second_ok, second = pcall(
                crypt.random_deterministic,
                16,
                seed
            )

            if not second_ok then
                second = crypt.random_deterministic("16", seed)
            end

            return type(first) == "string"
                and first == second
                and #first > 0
        end)
    end

    local hash_algorithms = {
        {"sha256", crypt.hash and crypt.hash.sha256},
        {"sha512", crypt.hash and crypt.hash.sha512},
        {"blake2b", crypt.hash and crypt.hash.blake2b}
    }

    for i = 1, #hash_algorithms do
        local entry = hash_algorithms[i]

        if type(entry[2]) == "function" then
            test("crypt.hash." .. entry[1] .. " is deterministic", function()
                local a = entry[2]("Severe")
                local b = entry[2]("Severe")
                return type(a) == "string"
                    and #a > 0
                    and a == b
            end)
        end
    end

    if type(crypt.pwhash) == "function" then
        test("crypt.pwhash returns string", function()
            local result = crypt.pwhash("severe-test-password")
            return type(result) == "string" and #result > 0
        end)
    end

    if type(crypt.pwhash_str) == "function"
        and type(crypt.pwhash_str_verify) == "function"
    then
        test("crypt password hash verifies correct password", function()
            local hash = crypt.pwhash_str("severe-test-password")
            return crypt.pwhash_str_verify(
                hash,
                "severe-test-password"
            ) == true
        end)

        test("crypt password hash rejects wrong password", function()
            local hash = crypt.pwhash_str("severe-test-password")
            return crypt.pwhash_str_verify(
                hash,
                "wrong-password"
            ) == false
        end)
    end

    if type(crypt.secretbox) == "table"
        and type(crypt.secretbox.seal) == "function"
        and type(crypt.secretbox.open) == "function"
    then
        test("crypt.secretbox round trip works", function()
            local message = "secretbox-message"
            local candidates = {
                {nonce = 24, key = 32},
                {nonce = 12, key = 32}
            }
            local errors = {}

            for i = 1, #candidates do
                local candidate = candidates[i]
                local nonce = string.rep("N", candidate.nonce)
                local key = string.rep("K", candidate.key)

                local seal_ok, cipher_or_error = pcall(
                    crypt.secretbox.seal,
                    message,
                    nonce,
                    key
                )

                if seal_ok then
                    local open_ok, plain_or_error = pcall(
                        crypt.secretbox.open,
                        cipher_or_error,
                        nonce,
                        key
                    )

                    if open_ok and plain_or_error == message then
                        info(
                            "crypt.secretbox accepted sizes",
                            "nonce="
                                .. tostring(candidate.nonce)
                                .. " key="
                                .. tostring(candidate.key)
                        )
                        return true
                    end

                    errors[#errors + 1] =
                        "nonce="
                        .. tostring(candidate.nonce)
                        .. " key="
                        .. tostring(candidate.key)
                        .. " open="
                        .. value_to_string(plain_or_error)
                else
                    errors[#errors + 1] =
                        "nonce="
                        .. tostring(candidate.nonce)
                        .. " key="
                        .. tostring(candidate.key)
                        .. " seal="
                        .. value_to_string(cipher_or_error)
                end
            end

            return false, table.concat(errors, " || ")
        end)
    end

    if type(crypt.aead) == "table"
        and type(crypt.aead.encrypt) == "function"
        and type(crypt.aead.decrypt) == "function"
        and type(crypt.random) == "function"
    then
        test("crypt.aead round trip works", function()
            local message = "aead-message"
            local aad = "aead-context"
            local nonce = crypto_random(24)
            local key = crypto_random(32)
            local cipher =
                crypt.aead.encrypt(message, aad, nonce, key)
            local plain =
                crypt.aead.decrypt(cipher, aad, nonce, key)
            return plain == message
        end)
    end

    if type(crypt.box) == "table"
        and type(crypt.box.keypair) == "function"
    then
        local alice_public = nil
        local alice_secret = nil
        local bob_public = nil
        local bob_secret = nil

        local keypair_ok, keypair_error = pcall(function()
            alice_public, alice_secret = crypt.box.keypair()
            bob_public, bob_secret = crypt.box.keypair()
        end)

        check(
            "crypt.box.keypair creates two keypairs",
            keypair_ok
                and type(alice_public) == "string"
                and type(alice_secret) == "string"
                and type(bob_public) == "string"
                and type(bob_secret) == "string",
            keypair_error
        )

        if keypair_ok then
            if type(crypt.box.encrypt) == "function"
                and type(crypt.box.decrypt) == "function"
            then
                test("crypt.box authenticated round trip works", function()
                    local nonce = crypto_random(24)
                    local message = "box-message"
                    local cipher = crypt.box.encrypt(
                        message,
                        nonce,
                        bob_public,
                        alice_secret
                    )
                    local plain = crypt.box.decrypt(
                        cipher,
                        nonce,
                        alice_public,
                        bob_secret
                    )
                    return plain == message
                end)
            end

            if type(crypt.box.seal) == "function"
                and type(crypt.box.open) == "function"
            then
                test("crypt.box sealed round trip works", function()
                    local message = "sealed-message"
                    local cipher =
                        crypt.box.seal(message, bob_public)
                    local plain = crypt.box.open(
                        cipher,
                        bob_public,
                        bob_secret
                    )
                    return plain == message
                end)
            end

            if type(crypt.box.beforenm) == "function" then
                test("crypt.box.beforenm derives matching secrets", function()
                    local alice_shared =
                        crypt.box.beforenm(bob_public, alice_secret)
                    local bob_shared =
                        crypt.box.beforenm(alice_public, bob_secret)

                    return type(alice_shared) == "string"
                        and alice_shared == bob_shared
                end)
            end
        end
    end

    if type(crypt.sign) == "table"
        and type(crypt.sign.keypair) == "function"
    then
        local public_key = nil
        local secret_key = nil

        local keypair_ok, keypair_error = pcall(function()
            public_key, secret_key = crypt.sign.keypair()
        end)

        check(
            "crypt.sign.keypair creates keys",
            keypair_ok
                and type(public_key) == "string"
                and type(secret_key) == "string",
            keypair_error
        )

        if keypair_ok then
            if type(crypt.sign.sign) == "function"
                and type(crypt.sign.open) == "function"
            then
                test("crypt.sign attached signature round trip works", function()
                    local message = "signed-message"
                    local signed =
                        crypt.sign.sign(message, secret_key)
                    local opened =
                        crypt.sign.open(signed, public_key)
                    return opened == message
                end)
            end

            if type(crypt.sign.detached) == "function"
                and type(crypt.sign.verify_detached) == "function"
            then
                test("crypt.sign detached signature verifies", function()
                    local message = "detached-message"
                    local signature =
                        crypt.sign.detached(message, secret_key)
                    return crypt.sign.verify_detached(
                        signature,
                        message,
                        public_key
                    ) == true
                end)

                test("crypt.sign detached rejects changed message", function()
                    local message = "detached-message"
                    local signature =
                        crypt.sign.detached(message, secret_key)
                    return crypt.sign.verify_detached(
                        signature,
                        "changed-message",
                        public_key
                    ) == false
                end)
            end
        end
    end

    if type(crypt.hmac) == "table" then
        local hmac_algorithms = {
            {"sha256", crypt.hmac.sha256},
            {"sha512", crypt.hmac.sha512}
        }

        for i = 1, #hmac_algorithms do
            local entry = hmac_algorithms[i]
            if type(entry[2]) == "function" then
                test("crypt.hmac." .. entry[1] .. " is deterministic", function()
                    local a = entry[2]("data", "key")
                    local b = entry[2]("data", "key")
                    local c = entry[2]("different", "key")
                    return type(a) == "string"
                        and #a > 0
                        and a == b
                        and a ~= c
                end)
            end
        end
    end

    if type(crypt.hkdf) == "table"
        and type(crypt.hkdf.sha256) == "function"
    then
        test("crypt.hkdf.sha256 is deterministic", function()
            local three_ok, three_result = pcall(
                crypt.hkdf.sha256,
                "key",
                "salt",
                "info"
            )

            if three_ok
                and type(three_result) == "string"
                and #three_result > 0
            then
                local second =
                    crypt.hkdf.sha256("key", "salt", "info")

                info(
                    "crypt.hkdf.sha256 accepted signature",
                    "3 arguments as documented"
                )

                return three_result == second
            end

            local four_ok, four_result = pcall(
                crypt.hkdf.sha256,
                "key",
                "salt",
                "info",
                32
            )

            if not four_ok then
                return false,
                    "3-argument result="
                    .. value_to_string(three_result)
                    .. " || 4-argument result="
                    .. value_to_string(four_result)
            end

            local second_four =
                crypt.hkdf.sha256(
                    "key",
                    "salt",
                    "info",
                    32
                )

            info(
                "crypt.hkdf.sha256 accepted signature",
                "4 arguments with output length=32"
            )

            return type(four_result) == "string"
                and #four_result > 0
                and four_result == second_four,
                "length=" .. value_to_string(#four_result)
        end)
    end
end

-- ============================================================
-- 30. MEMORY API COMPLETE INVENTORY
-- ============================================================
section("30. Memory API Complete Inventory")

check("memory library exists", type(memory) == "table")

if type(memory) == "table" then
    local numeric_memory_types = {
        "i8",
        "u8",
        "i16",
        "u16",
        "i32",
        "u32",
        "i64",
        "u64",
        "f32",
        "f64"
    }

    for i = 1, #numeric_memory_types do
        local suffix = numeric_memory_types[i]
        check(
            "memory.read" .. suffix .. " exists",
            type(rawget(memory, "read" .. suffix)) == "function"
        )
        check(
            "memory.write" .. suffix .. " exists",
            type(rawget(memory, "write" .. suffix)) == "function"
        )
    end

    local other_memory_functions = {
        "readbits",
        "writebits",
        "readstring",
        "writestring",
        "readvector",
        "writevector",
        "readbuffer",
        "writebuffer",
        "rtti",
        "changed"
    }

    for i = 1, #other_memory_functions do
        local name = other_memory_functions[i]
        check(
            "memory." .. name .. " exists",
            type(memory[name]) == "function"
        )
    end

    test("memory.base is a positive number", function()
        return type(memory.base) == "number"
            and memory.base > 0,
            memory.base
    end)

    local read_address =
        EXTERNAL_TEST_VALUES.memory_read_address

    if EXTERNAL_TEST_CONFIG.run_memory_reads
        and type(read_address) == "number"
    then
        for i = 1, #numeric_memory_types do
            local suffix = numeric_memory_types[i]
            local read_function = rawget(memory, "read" .. suffix)

            if type(read_function) == "function" then
                test("memory.read" .. suffix .. " reads configured address", function()
                    local value = read_function(read_address)
                    return type(value) == "number", value
                end)
            end
        end

        if type(memory.readbits) == "function" then
            test("memory.readbits reads configured address", function()
                local value = memory.readbits(read_address, 0, 8)
                return type(value) == "number", value
            end)
        end

        if type(memory.readbuffer) == "function" then
            test("memory.readbuffer reads configured address", function()
                local value = memory.readbuffer(
                    read_address,
                    EXTERNAL_TEST_VALUES.memory_buffer_size
                )
                return value ~= nil
            end)
        end

        if type(memory.rtti) == "function" then
            test("memory.rtti accepts configured address", function()
                local value = memory.rtti(read_address)
                return value == nil or type(value) == "string", value
            end)
        end

        if type(pointer_to_userdata) == "function" then
            test("pointer_to_userdata accepts configured address", function()
                local value = pointer_to_userdata(read_address)
                return value ~= nil
            end)
        end
    else
        info(
            "Memory read execution tests",
            "disabled or memory_read_address is not configured"
        )
    end

    local write_address =
        EXTERNAL_TEST_VALUES.memory_write_address

    if EXTERNAL_TEST_CONFIG.run_memory_writes
        and type(write_address) == "number"
    then
        for i = 1, #numeric_memory_types do
            local suffix = numeric_memory_types[i]
            local read_function = rawget(memory, "read" .. suffix)
            local write_function = rawget(memory, "write" .. suffix)

            if type(read_function) == "function"
                and type(write_function) == "function"
            then
                test("memory.write" .. suffix .. " writes same value safely", function()
                    local old_value = read_function(write_address)
                    write_function(write_address, old_value)
                    local new_value = read_function(write_address)
                    return new_value == old_value
                end)
            end
        end

        if type(memory.readbits) == "function"
            and type(memory.writebits) == "function"
        then
            test("memory.writebits writes same bits safely", function()
                local old_value =
                    memory.readbits(write_address, 0, 8)
                memory.writebits(
                    write_address,
                    0,
                    8,
                    old_value
                )
                local new_value =
                    memory.readbits(write_address, 0, 8)
                return new_value == old_value
            end)
        end

        if type(memory.readbuffer) == "function"
            and type(memory.writebuffer) == "function"
        then
            test("memory.writebuffer writes same buffer safely", function()
                local old_buffer = memory.readbuffer(
                    write_address,
                    EXTERNAL_TEST_VALUES.memory_buffer_size
                )
                memory.writebuffer(write_address, old_buffer)
                return true
            end)
        end
    else
        info(
            "Memory write execution tests",
            "disabled or memory_write_address is not configured"
        )
    end

    local string_address =
        EXTERNAL_TEST_VALUES.memory_string_address

    if EXTERNAL_TEST_CONFIG.run_memory_reads
        and type(string_address) == "number"
        and type(memory.readstring) == "function"
    then
        test("memory.readstring reads configured string address", function()
            local value = memory.readstring(string_address)
            return type(value) == "string", value
        end)
    else
        info(
            "memory.readstring active test",
            "disabled or memory_string_address is not configured"
        )
    end

    if EXTERNAL_TEST_CONFIG.run_memory_writes
        and type(string_address) == "number"
        and type(memory.readstring) == "function"
        and type(memory.writestring) == "function"
    then
        test("memory.writestring writes same string safely", function()
            local old_value = memory.readstring(string_address)
            memory.writestring(string_address, old_value)
            return memory.readstring(string_address) == old_value
        end)
    else
        info(
            "memory.writestring active test",
            "disabled or memory_string_address is not configured"
        )
    end

    local vector_address =
        EXTERNAL_TEST_VALUES.memory_vector_address

    if EXTERNAL_TEST_CONFIG.run_memory_reads
        and type(vector_address) == "number"
        and type(memory.readvector) == "function"
    then
        test("memory.readvector reads configured vector address", function()
            local value = memory.readvector(vector_address)
            return value ~= nil, value
        end)
    else
        info(
            "memory.readvector active test",
            "disabled or memory_vector_address is not configured"
        )
    end

    if EXTERNAL_TEST_CONFIG.run_memory_writes
        and type(vector_address) == "number"
        and type(memory.readvector) == "function"
        and type(memory.writevector) == "function"
    then
        test("memory.writevector writes same vector safely", function()
            local old_value = memory.readvector(vector_address)
            memory.writevector(vector_address, old_value)
            local new_value = memory.readvector(vector_address)
            return value_to_string(new_value)
                == value_to_string(old_value)
        end)
    else
        info(
            "memory.writevector active test",
            "disabled or memory_vector_address is not configured"
        )
    end

    local changed_address =
        EXTERNAL_TEST_VALUES.memory_changed_address
    local changed_type =
        EXTERNAL_TEST_VALUES.memory_changed_type
    local changed_read =
        type(changed_type) == "string"
        and rawget(memory, "read" .. changed_type)
        or nil
    local changed_write =
        type(changed_type) == "string"
        and rawget(memory, "write" .. changed_type)
        or nil

    if EXTERNAL_TEST_CONFIG.run_memory_changed
        and type(changed_address) == "number"
        and type(memory.changed) == "function"
        and type(changed_read) == "function"
        and type(changed_write) == "function"
        and type(task) == "table"
        and type(task.wait) == "function"
    then
        test("memory.changed observes configured scratch address", function()
            local old_value = changed_read(changed_address)
            local replacement =
                changed_type == "u8"
                and ((old_value + 1) % 256)
                or (old_value + 1)

            local callback_count = 0
            local callback_new = nil
            local callback_old = nil

            local watch_ok, watcher_or_error = pcall(
                memory.changed,
                changed_address,
                changed_type,
                function(_, new_value, previous_value)
                    callback_count = callback_count + 1
                    callback_new = new_value
                    callback_old = previous_value
                end,
                1
            )

            if not watch_ok then
                return false, watcher_or_error
            end

            local write_ok, write_error = pcall(
                changed_write,
                changed_address,
                replacement
            )

            if type(task.wait) == "function" then
                task.wait(0.05)
            end

            -- Always attempt restoration before judging the callback.
            local restore_ok, restore_error = pcall(
                changed_write,
                changed_address,
                old_value
            )

            if not restore_ok then
                return false,
                    "restore failed: "
                    .. value_to_string(restore_error)
            end

            if not write_ok then
                return false, write_error
            end

            return callback_count > 0
                and callback_new == replacement
                and callback_old == old_value,
                "watcher="
                .. value_to_string(watcher_or_error)
                .. ", count="
                .. value_to_string(callback_count)
                .. ", old="
                .. value_to_string(callback_old)
                .. ", new="
                .. value_to_string(callback_new)
        end)
    else
        info(
            "memory.changed active test",
            "disabled or memory_changed_address/type is not configured"
        )
    end
end

-- ============================================================
-- 31. EXTERNAL OVERLAY / SYSTEM INTERACTION
-- ============================================================
section("31. External Overlay and System Interaction")

if EXTERNAL_TEST_CONFIG.run_notifications
    and type(send_notification) == "function"
then
    local notification_ok = false
    local accepted_signature = nil
    local notification_errors = {}

    local one_argument_ok, one_argument_error = pcall(
        send_notification,
        "Severe VM exhaustive test notification"
    )

    if one_argument_ok then
        notification_ok = true
        accepted_signature = "send_notification(content)"
    else
        notification_errors[#notification_errors + 1] =
            "one argument => "
            .. value_to_string(one_argument_error)
    end

    if not notification_ok then
        local notification_types = {
            "info",
            "Info",
            "INFO",
            "success",
            "Success",
            "warning",
            "Warning",
            "error",
            "Error",
            "default",
            "Default",
            "notification",
            "Notification",
            "message",
            "Message"
        }

        for i = 1, #notification_types do
            local notification_type = notification_types[i]
            local typed_ok, typed_error = pcall(
                send_notification,
                "Severe VM exhaustive test notification",
                notification_type
            )

            if typed_ok then
                notification_ok = true
                accepted_signature = notification_type
                break
            end

            notification_errors[#notification_errors + 1] =
                "type="
                .. notification_type
                .. " => "
                .. value_to_string(typed_error)
        end
    end

    check(
        "send_notification executes with a supported signature",
        notification_ok,
        table.concat(notification_errors, " || ")
    )

    if notification_ok then
        info(
            "send_notification accepted type",
            accepted_signature
        )
    end
else
    info("send_notification active test", "disabled or function missing")
end

if EXTERNAL_TEST_CONFIG.run_clipboard_write
    and type(setclipboard) == "function"
then
    local ok, err = pcall(
        setclipboard,
        "Severe VM exhaustive clipboard test"
    )
    check("setclipboard executes", ok, err)
else
    info("setclipboard active test", "disabled")
end

if EXTERNAL_TEST_CONFIG.run_window_block_toggle
    and type(block_roblox_window) == "function"
then
    local block_ok, block_error = pcall(block_roblox_window, true)
    local unblock_ok, unblock_error = pcall(block_roblox_window, false)

    check("block_roblox_window(true) executes", block_ok, block_error)
    check("block_roblox_window(false) executes", unblock_ok, unblock_error)
else
    info("block_roblox_window active test", "disabled")
end

if type(getmouseposition) == "function"
    and user_input_service ~= nil
then
    test("WinAPI and game mouse positions are both readable", function()
        local win_position = getmouseposition()
        local game_position =
            user_input_service:GetMouseLocation()

        return win_position ~= nil
            and game_position ~= nil
            and type(win_position.X) == "number"
            and type(win_position.Y) == "number"
            and type(game_position.X) == "number"
            and type(game_position.Y) == "number"
    end)
end

if EXTERNAL_TEST_CONFIG.run_input_simulation then
    local key = EXTERNAL_TEST_VALUES.input_test_key

    if type(keypress) == "function"
        and type(keyrelease) == "function"
    then
        local press_ok, press_error = pcall(keypress, key)
        local release_ok, release_error = pcall(keyrelease, key)

        check("keypress executes", press_ok, press_error)
        check("keyrelease executes", release_ok, release_error)
    end

    if type(mousemoverel) == "function" then
        local ok, err = pcall(mousemoverel, 0, 0)
        check("mousemoverel(0, 0) executes", ok, err)
    end

    if type(mousescroll) == "function" then
        local ok, err = pcall(mousescroll, 0)
        check("mousescroll(0) executes", ok, err)
    end

    if type(getmouseposition) == "function"
        and type(mousemoveabs) == "function"
    then
        local current = getmouseposition()
        local ok, err = pcall(
            mousemoveabs,
            current.X,
            current.Y
        )
        check("mousemoveabs restores current position", ok, err)
    end

    local click_functions = {
        {"mouse1click", mouse1click},
        {"mouse1press", mouse1press},
        {"mouse1release", mouse1release},
        {"mouse2click", mouse2click},
        {"mouse2press", mouse2press},
        {"mouse2release", mouse2release}
    }

    for i = 1, #click_functions do
        local entry = click_functions[i]

        if type(entry[2]) == "function" then
            local ok, err = pcall(entry[2])
            check(entry[1] .. " executes", ok, err)
        end
    end
else
    info(
        "Input simulation execution tests",
        "disabled; all input functions are still inventoried"
    )
end

-- ============================================================
-- 32. WEBSOCKET CLIENT
-- ============================================================
section("32. WebsocketClient")

if EXTERNAL_TEST_CONFIG.run_websocket then
    check(
        "WebsocketClient.new exists",
        WebsocketClient ~= nil
            and type(first_present(WebsocketClient, "new", "New"))
                == "function"
    )
end

if EXTERNAL_TEST_CONFIG.run_websocket then
    if WebsocketClient == nil
        or type(first_present(WebsocketClient, "new", "New"))
            ~= "function"
    then
        info(
            "WebSocket active test",
            "enabled, but WebsocketClient.new is unavailable"
        )
    else
        info(
            "WebSocket prerequisite",
            "local_websocket_echo_server.py must already be listening on "
                .. EXTERNAL_TEST_VALUES.websocket_url
        )

        local websocket_new =
            first_present(WebsocketClient, "new", "New")

        local connect_ok, websocket_or_error =
            pcall(
                websocket_new,
                EXTERNAL_TEST_VALUES.websocket_url
            )

        check(
            "WebsocketClient connects to local echo server",
            connect_ok and websocket_or_error ~= nil,
            websocket_or_error
        )

        if connect_ok and websocket_or_error ~= nil then
            local websocket = websocket_or_error
            local received_events = {}
            local registration_mode = nil
            local registration_ok = false

            test("WebsocketClient.Url is readable", function()
                return type(websocket.Url) == "string",
                    websocket.Url
            end)

            test("WebsocketClient.Url matches constructor URL", function()
                return websocket.Url
                        == EXTERNAL_TEST_VALUES.websocket_url,
                    "expected="
                        .. EXTERNAL_TEST_VALUES.websocket_url
                        .. " received="
                        .. value_to_string(websocket.Url)
            end)

            test("WebsocketClient.Url is read-only", function()
                local original_url = websocket.Url
                local write_ok, write_error = pcall(function()
                    websocket.Url = original_url
                        .. "#__severe_write_probe__"
                end)
                local after_url = websocket.Url

                return write_ok == false or after_url == original_url,
                    "write_ok="
                        .. value_to_string(write_ok)
                        .. " after="
                        .. value_to_string(after_url)
                        .. " error="
                        .. value_to_string(write_error)
            end)

            -- Keep this callback deliberately minimal. Console, UI,
            -- yielding, and other Severe API calls inside the callback
            -- previously caused concurrent VM/console corruption.
            local function on_data_received(payload, is_binary)
                received_events[#received_events + 1] = {
                    payload = payload,
                    is_binary = is_binary
                }
            end

            local data_received_ok, data_received = pcall(function()
                return websocket.DataReceived
            end)

            check(
                "WebsocketClient.DataReceived exists",
                data_received_ok and data_received ~= nil,
                data_received
            )

            if data_received_ok and data_received ~= nil then
                -- The GitBook documents DataReceived as a Signal. Some
                -- tested Severe builds expose a callback-registration
                -- namecall instead. Prefer the documented Signal form,
                -- then retain the known runtime compatibility form.
                local connected, connection, connect_detail =
                    connect_signal(data_received, on_data_received)

                if connected then
                    registration_mode =
                        "documented Signal | " .. connect_detail
                    registration_ok = true
                elseif type(data_received) == "function" then
                    local register_ok, register_error = pcall(function()
                        websocket:DataReceived(on_data_received)
                    end)

                    if not register_ok then
                        register_ok, register_error = pcall(function()
                            websocket.DataReceived(
                                websocket,
                                on_data_received
                            )
                        end)
                    end

                    if register_ok then
                        registration_mode =
                            "runtime callback-registration namecall"
                        registration_ok = true
                    else
                        registration_mode = register_error
                    end
                else
                    registration_mode = connect_detail
                end
            end

            check(
                "WebsocketClient DataReceived callback registers",
                registration_ok,
                registration_mode
            )

            info(
                "WebSocket DataReceived registration mode",
                registration_mode
            )

            local function wait_for_event_count(target_count)
                if type(task) ~= "table"
                    or type(task.wait) ~= "function"
                then
                    return #received_events >= target_count
                end

                for i = 1, 30 do
                    if #received_events >= target_count then
                        return true
                    end

                    task.wait(0.1)
                end

                return #received_events >= target_count
            end

            local function send_frame(payload, is_binary, omit_flag)
                local upper_ok, upper_error

                if omit_flag then
                    upper_ok, upper_error = pcall(function()
                        websocket:Send(payload)
                    end)
                else
                    upper_ok, upper_error = pcall(function()
                        websocket:Send(payload, is_binary)
                    end)
                end

                if upper_ok then
                    return true, "Send"
                end

                local lower_ok, lower_error
                if omit_flag then
                    lower_ok, lower_error = pcall(function()
                        websocket:send(payload)
                    end)
                else
                    lower_ok, lower_error = pcall(function()
                        websocket:send(payload, is_binary)
                    end)
                end

                if lower_ok then
                    return true, "send compatibility alias"
                end

                return false,
                    "Send => "
                        .. value_to_string(upper_error)
                        .. " || send => "
                        .. value_to_string(lower_error)
            end

            local function exercise_echo(
                label,
                payload,
                is_binary,
                omit_flag
            )
                local before_count = #received_events
                local send_ok, send_detail =
                    send_frame(payload, is_binary, omit_flag)

                check(label .. " Send executes", send_ok, send_detail)

                if not send_ok then
                    return nil
                end

                local fired = wait_for_event_count(before_count + 1)
                check(
                    label .. " callback fires",
                    fired,
                    "before="
                        .. value_to_string(before_count)
                        .. " after="
                        .. value_to_string(#received_events)
                )

                local event = received_events[before_count + 1]
                if event == nil then
                    return nil
                end

                if type(task) == "table"
                    and type(task.wait) == "function"
                then
                    task.wait(0.05)
                end

                check(
                    label .. " callback fires exactly once",
                    #received_events == before_count + 1,
                    "before="
                        .. value_to_string(before_count)
                        .. " after="
                        .. value_to_string(#received_events)
                )

                check(
                    label .. " payload matches",
                    event.payload == payload,
                    "expected="
                        .. value_to_string(payload)
                        .. " received="
                        .. value_to_string(event.payload)
                )

                return event
            end

            if registration_ok then
                if type(task) == "table"
                    and type(task.wait) == "function"
                then
                    task.wait(0.05)
                end

                check(
                    "DataReceived does not fire before a message",
                    #received_events == 0,
                    "callback count="
                        .. value_to_string(#received_events)
                )

                local default_text =
                    "Severe WebSocket default text test"
                local default_event = exercise_echo(
                    "Default text frame",
                    default_text,
                    false,
                    true
                )

                if default_event ~= nil then
                    check(
                        "Default text frame isBinary is false",
                        default_event.is_binary == false,
                        "received="
                            .. value_to_string(
                                default_event.is_binary
                            )
                            .. " | the GitBook documents a boolean"
                    )
                end

                local explicit_text =
                    "Severe WebSocket explicit text test"
                local explicit_event = exercise_echo(
                    "Explicit text frame",
                    explicit_text,
                    false,
                    false
                )

                if explicit_event ~= nil then
                    check(
                        "Explicit text frame isBinary is false",
                        explicit_event.is_binary == false,
                        "received="
                            .. value_to_string(
                                explicit_event.is_binary
                            )
                            .. " | the GitBook documents a boolean"
                    )
                end

                local utf8_text =
                    "Severe UTF-8: check ✓ | Привет | 你好"
                local utf8_event = exercise_echo(
                    "UTF-8 text frame",
                    utf8_text,
                    false,
                    true
                )

                if utf8_event ~= nil then
                    check(
                        "UTF-8 text frame isBinary is false",
                        utf8_event.is_binary == false,
                        "received="
                            .. value_to_string(utf8_event.is_binary)
                    )
                end

                local empty_event = exercise_echo(
                    "Empty text frame",
                    "",
                    false,
                    true
                )

                if empty_event ~= nil then
                    check(
                        "Empty text frame isBinary is false",
                        empty_event.is_binary == false,
                        "received="
                            .. value_to_string(empty_event.is_binary)
                    )
                end

                local binary_payload = string.char(
                    0,
                    1,
                    2,
                    3,
                    127,
                    128,
                    254,
                    255
                )
                local binary_event = exercise_echo(
                    "Binary frame",
                    binary_payload,
                    true,
                    false
                )

                if binary_event ~= nil then
                    check(
                        "Binary frame isBinary is true",
                        binary_event.is_binary == true,
                        "received="
                            .. value_to_string(binary_event.is_binary)
                    )
                end

                check(
                    "WebSocket callback order is preserved",
                    #received_events >= 5
                        and received_events[1].payload == default_text
                        and received_events[2].payload == explicit_text
                        and received_events[3].payload == utf8_text
                        and received_events[4].payload == ""
                        and received_events[5].payload
                            == binary_payload,
                    "received count="
                        .. value_to_string(#received_events)
                )

                info(
                    "WebSocket callback total",
                    #received_events
                )
            end

            local disconnect_ok, disconnect_error =
                pcall(function()
                    websocket:Disconnect()
                end)

            if not disconnect_ok then
                disconnect_ok, disconnect_error =
                    pcall(function()
                        websocket:disconnect()
                    end)
            end

            check(
                "WebsocketClient Disconnect executes",
                disconnect_ok,
                disconnect_error
            )

            if disconnect_ok then
                local before_post_disconnect = #received_events
                local post_disconnect_send_ok,
                    post_disconnect_send_error =
                    pcall(function()
                        websocket:Send(
                            "__severe_post_disconnect_probe__"
                        )
                    end)

                if type(task) == "table"
                    and type(task.wait) == "function"
                then
                    task.wait(0.2)
                end

                check(
                    "No data is received after Disconnect",
                    #received_events == before_post_disconnect,
                    "send_ok="
                        .. value_to_string(post_disconnect_send_ok)
                        .. " callback count before="
                        .. value_to_string(before_post_disconnect)
                        .. " after="
                        .. value_to_string(#received_events)
                        .. " error="
                        .. value_to_string(
                            post_disconnect_send_error
                        )
                )
            end
        end
    end
else
    record_result(
        "WebsocketClient live behavior",
        "SKIP",
        "disabled by EXTERNAL_TEST_CONFIG.run_websocket",
        nil,
        false
    )
end

-- ============================================================
-- 33. MODEL DATA / TARGETING BRIDGE
-- ============================================================
section("33. Model Data and Targeting Bridge")

if EXTERNAL_TEST_CONFIG.run_model_data_mutation then
    local local_player = nil

    if players_service ~= nil then
        pcall(function()
            local_player = players_service.LocalPlayer
        end)
    end

    -- Do not use Character:FindFirstChild here. Some Severe builds
    -- throw a native "bad allocation" error for that call on mirrored
    -- character objects, and the native failure can terminate the
    -- complete script instead of being contained by pcall.
    local function safe_get_children(object)
        if object == nil then
            return {}
        end

        local get_children = first_present(object, "GetChildren")
        if type(get_children) ~= "function" then
            return {}
        end

        local ok, children = pcall(get_children, object)
        if not ok or type(children) ~= "table" then
            return {}
        end

        return children
    end

    local function safe_child_by_name(object, expected_name)
        local children = safe_get_children(object)

        for i = 1, #children do
            local child = children[i]
            local child_name = nil

            pcall(function()
                child_name = child.Name
            end)

            if child_name == expected_name then
                return child
            end
        end

        return nil
    end

    local function safe_child_by_class(object, expected_class)
        local children = safe_get_children(object)

        for i = 1, #children do
            local child = children[i]
            local child_class = nil

            pcall(function()
                child_class = child.ClassName
            end)

            if child_class == expected_class then
                return child
            end
        end

        return nil
    end

    local character = nil

    if local_player ~= nil then
        pcall(function()
            character = local_player.Character
        end)
    end

    local head = safe_child_by_name(character, "Head")
    local root = safe_child_by_name(character, "HumanoidRootPart")
    local humanoid = safe_child_by_class(character, "Humanoid")

    if root == nil and character ~= nil then
        pcall(function()
            root = character.PrimaryPart
        end)
    end

    if local_player ~= nil
        and character ~= nil
        and head ~= nil
        and type(add_model_data) == "function"
        and type(edit_model_data) == "function"
        and type(remove_model_data) == "function"
    then
        local key =
            "__severe_vm_test_model_"
            .. tostring(math.random(100000, 999999))

        local model_data = {
            Username = local_player.Name,
            Displayname = local_player.DisplayName,
            Userid = local_player.UserId,
            Character = character,
            PrimaryPart = root,
            Head = head,
            LeftLeg = nil,
            LeftArm = nil,
            RightLeg = nil,
            RightArm = nil,
            Torso = root,
            ToolName = "",
            TeamName = "",
            BodyHeightScale = 1,
            RigType = 0,
            Whitelisted = false,
            Archenemies = false,
            Aimbot_Part = head,
            Aimbot_TP_Part = head,
            Triggerbot_Part = head,
            Health = humanoid and humanoid.Health or 100,
            MaxHealth = humanoid and humanoid.MaxHealth or 100,
            body_parts_data = {},
            full_body_data = {}
        }

        local add_ok, add_result = pcall(
            add_model_data,
            model_data,
            key
        )

        check(
            "add_model_data accepts local-player test data",
            add_ok and add_result == true,
            add_result
        )

        if add_ok and add_result == true then
            local edit_ok, edit_result = pcall(
                edit_model_data,
                {
                    Health = model_data.Health,
                    MaxHealth = model_data.MaxHealth,
                    Aimbot_Part = head
                },
                key
            )

            check(
                "edit_model_data updates test data",
                edit_ok and edit_result == true,
                edit_result
            )

            local remove_ok, remove_result = pcall(
                remove_model_data,
                key
            )

            check(
                "remove_model_data removes test data",
                remove_ok and remove_result == true,
                remove_result
            )
        end
    else
        info(
            "Model data active test",
            "skipped because local-player data or required functions are missing"
        )
    end

    if EXTERNAL_TEST_CONFIG.run_local_data_override
        and local_player ~= nil
        and type(override_local_data) == "function"
    then
        local left_foot =
            safe_child_by_name(character, "LeftFoot")
            or safe_child_by_name(character, "Left Leg")
            or root
            or head

        local lower_torso =
            safe_child_by_name(character, "LowerTorso")
            or safe_child_by_name(character, "Torso")
            or root
            or head

        local tool =
            safe_child_by_class(character, "Tool")
            or root
            or head

        local team = nil
        pcall(function()
            team = local_player.Team
        end)

        if team == nil then
            team = local_player
        end

        local local_data = {
            LocalPlayer = local_player,
            Displayname = local_player.DisplayName,
            Username = local_player.Name,
            Userid = local_player.UserId,
            Character = character,
            Team = team,
            RootPart = root or head,
            LeftFoot = left_foot,
            Head = head,
            LowerTorso = lower_torso,
            Tool = tool,
            Humanoid = humanoid or character,
            Health = humanoid and humanoid.Health or 100,
            MaxHealth = humanoid and humanoid.MaxHealth or 100,
            RigType = 0
        }

        local override_ok, override_result = pcall(
            override_local_data,
            local_data
        )

        check(
            "override_local_data accepts local-player test data",
            override_ok and override_result == true,
            override_result
        )

        if EXTERNAL_TEST_CONFIG.run_destructive_clear_functions
            and type(clear_local_data) == "function"
        then
            local clear_ok, clear_result =
                pcall(clear_local_data)

            check(
                "clear_local_data executes",
                clear_ok and clear_result == true,
                clear_result
            )
        end
    else
        info(
            "override_local_data active test",
            "disabled because Severe exposes no getter that could preserve "
                .. "and restore pre-existing local overlay data"
        )
    end

    if EXTERNAL_TEST_CONFIG.run_destructive_clear_functions
        and type(clear_model_data) == "function"
    then
        local clear_ok, clear_result =
            pcall(clear_model_data)

        check(
            "clear_model_data executes",
            clear_ok and clear_result == true,
            clear_result
        )
    end
else
    info(
        "Model/local data mutation tests",
        "disabled; functions are still checked for availability"
    )
end

-- ============================================================
-- 34. DIRECT DRAWING CONSTRUCTORS
-- ============================================================
section("34. Direct Drawing Constructors")

local direct_drawing_classes = {
    {"Circle", Circle},
    {"Image", Image},
    {"Polyline", Polyline},
    {"Square", Square},
    {"Text", Text},
    {"Triangle", Triangle}
}

for i = 1, #direct_drawing_classes do
    local entry = direct_drawing_classes[i]
    local class_name = entry[1]
    local class_table = entry[2]

    info(class_name .. " global", type(class_table))

    if type(class_table) == "table"
        and type(first_present(class_table, "new", "New"))
            == "function"
    then
        local constructor =
            first_present(class_table, "new", "New")
        local create_ok, object_or_error =
            pcall(constructor)

        check(
            class_name .. ".new creates a drawing",
            create_ok and object_or_error ~= nil,
            object_or_error
        )

        if create_ok and object_or_error ~= nil then
            local removed, remove_detail =
                remove_drawing(object_or_error)

            check(
                class_name .. ".new object can be removed",
                removed,
                remove_detail
            )
        end
    end
end

-- ============================================================
-- 35. ARGUMENT VALIDATION AND ERROR PATHS
-- ============================================================
section("35. Argument Validation and Error Paths")

if Vector2 ~= nil and type(Vector2.new) == "function" then
    test("Vector2.new rejects string component", function()
        local ok, result = pcall(Vector2.new, "x", 0)
        return ok == false,
            ok and value_to_string(result) or result
    end)
end

if Vector3 ~= nil and type(Vector3.new) == "function" then
    test("Vector3.new rejects string component", function()
        local ok, result = pcall(Vector3.new, "x", 0, 0)
        return ok == false,
            ok and value_to_string(result) or result
    end)
end

if Color3 ~= nil and type(Color3.fromHex) == "function" then
    test("Color3.fromHex handles invalid hex safely", function()
        local ok, result = pcall(
            Color3.fromHex,
            "this-is-not-hex"
        )

        if not ok then
            info(
                "Color3.fromHex invalid-input behavior",
                "throws: " .. value_to_string(result)
            )
            return true
        end

        local color_like =
            result ~= nil
            and type(result.R) == "number"
            and type(result.G) == "number"
            and type(result.B) == "number"

        info(
            "Color3.fromHex invalid-input behavior",
            "returns fallback: " .. value_to_string(result)
        )

        return color_like, result
    end)
end

if type(Drawing) == "table"
    and type(Drawing.new) == "function"
then
    test("Drawing.new rejects unsupported class", function()
        local ok, result = pcall(
            Drawing.new,
            "__UnsupportedDrawingClass__"
        )

        return ok == false or result == nil,
            "ok="
                .. value_to_string(ok)
                .. " result="
                .. value_to_string(result)
    end)
end

if PointInstance ~= nil
    and type(first_present(PointInstance, "new", "New"))
        == "function"
    and workspace ~= nil
then
    test("PointInstance.new handles a non-BasePart safely", function()
        local constructor =
            first_present(PointInstance, "new", "New")
        local ok, result = pcall(constructor, workspace)

        if not ok or result == nil then
            info(
                "PointInstance invalid-input behavior",
                "rejected non-BasePart"
            )
            return true
        end

        local active = nil
        local active_ok = pcall(function()
            active = result.Active
        end)

        local cframe_ok = pcall(function()
            local unused = result.CFrame
        end)

        local destroy =
            first_present(result, "Destroy", "destroy")

        if type(destroy) == "function" then
            pcall(destroy, result)
        end

        info(
            "PointInstance invalid-input behavior",
            "returned tracker; Active="
                .. value_to_string(active)
                .. " CFrame readable="
                .. value_to_string(cframe_ok)
        )

        return active_ok and (active == false or cframe_ok == false),
            "invalid tracker was unexpectedly active/readable"
    end)
end

if filesystem_ready then
    test("readfile cannot read outside workspace sandbox", function()
        local outside_candidates = {
            "../Windows/System32/drivers/etc/hosts",
            "../../Windows/System32/drivers/etc/hosts",
            "C:/Windows/System32/drivers/etc/hosts"
        }

        local unexpected_successes = {}

        for i = 1, #outside_candidates do
            local path = outside_candidates[i]
            local ok, result = pcall(readfile, path)

            if ok then
                unexpected_successes[#unexpected_successes + 1] =
                    path
                    .. " returned "
                    .. value_to_string(result)
            end
        end

        return #unexpected_successes == 0,
            #unexpected_successes == 0
                and "all outside paths rejected"
                or table.concat(
                    unexpected_successes,
                    " || "
                )
    end)
end

if type(task) == "table"
    and type(task.delay) == "function"
    and type(task.cancel) == "function"
    and type(task.wait) == "function"
then
    test("task.cancel prevents delayed callback", function()
        local fired = false
        local delayed = task.delay(0.1, function()
            fired = true
        end)

        task.cancel(delayed)
        task.wait(0.15)

        return fired == false,
            "callback fired="
                .. value_to_string(fired)
    end)
end

-- ============================================================
-- 36. RUNTIME TYPE BRIDGE REPORT
-- ============================================================
section("36. Runtime Type Bridge Report")

local type_samples = {}

local function add_type_sample(label, callback)
    local ok, value = pcall(callback)

    if ok and value ~= nil then
        type_samples[#type_samples + 1] = {
            label,
            value
        }
    else
        info(
            label .. " type sample",
            ok and "returned nil" or value
        )
    end
end

if Vector2 ~= nil and type(Vector2.new) == "function" then
    add_type_sample("Vector2.new", function()
        return Vector2.new(1, 2)
    end)
end

if Vector3 ~= nil and type(Vector3.new) == "function" then
    add_type_sample("Vector3.new", function()
        return Vector3.new(1, 2, 3)
    end)
end

if Color3 ~= nil and type(Color3.new) == "function" then
    add_type_sample("Color3.new", function()
        return Color3.new(1, 0, 0)
    end)
end

if CFrame ~= nil and type(CFrame.new) == "function" then
    add_type_sample("CFrame.new", function()
        return CFrame.new(1, 2, 3)
    end)
end

if workspace ~= nil then
    add_type_sample("Camera.Position", function()
        local camera = workspace.CurrentCamera
        return camera and camera.Position or nil
    end)
end

if first_basepart ~= nil then
    add_type_sample("BasePart.Position", function()
        return first_basepart.Position
    end)
end

for i = 1, #type_samples do
    local entry = type_samples[i]
    local native_type =
        type(typeof) == "function"
            and value_to_string(typeof(entry[2]))
            or "typeof unavailable"

    info(
        entry[1],
        "type="
            .. type(entry[2])
            .. " | typeof="
            .. native_type
            .. " | tostring="
            .. value_to_string(entry[2])
    )
end

-- ============================================================
-- 37. BEHAVIOR-FIRST EXTERNAL VM COMPATIBILITY LAB
-- ============================================================
section(
    "37. Behavior-First External VM Compatibility Lab",
    "compatibility",
    "Environment"
)

-- Behavioral capabilities use one canonical score entry. Accepted
-- aliases are resolved in order and are shown in the result metadata.
-- The raw catalog in section 38 still scores every individual path.
do
    local function step_once()
        if type(task) == "table"
            and type(task.wait) == "function"
        then
            task.wait()
        end
    end

    local function list_contains_identity(values, target)
        if type(values) ~= "table" then
            return false
        end

        for _, value in pairs(values) do
            if value == target then
                return true
            end
        end

        return false
    end

    local function is_instance(value)
        if type(typeof) == "function" then
            local ok, native_type = pcall(typeof, value)
            if ok and native_type == "Instance" then
                return true
            end
        end

        local ok, class_name = pcall(function()
            return value.ClassName
        end)

        return ok and type(class_name) == "string"
    end

    local function destroy_instance(value)
        if value == nil then
            return
        end

        pcall(function()
            value:Destroy()
        end)
    end

    local function disconnect_connection(value)
        if value == nil then
            return
        end

        pcall(function()
            value:Disconnect()
        end)

        pcall(function()
            value:disconnect()
        end)
    end

    local function remove_drawing(value)
        if value == nil then
            return
        end

        pcall(function()
            value:Remove()
        end)

        pcall(function()
            value:Destroy()
        end)
    end

    local crypt_base64 =
        type(crypt) == "table"
            and first_present(crypt, "base64")
            or nil
    local generic_base64 =
        type(base64) == "table"
            and base64
            or nil
    local http_namespace =
        type(http) == "table"
            and http
            or nil

    capability_test(
        "Environment",
        "getgenv returns one stable environment table",
        {
            {"getgenv", getgenv}
        },
        function(fn)
            local first = fn()
            local second = fn()
            return type(first) == "table"
                and first == second,
                "first="
                    .. type(first)
                    .. ", second="
                    .. type(second)
        end
    )

    capability_test(
        "Environment",
        "getinstances returns real Instance objects",
        {
            {"getinstances", getinstances},
            {"get_instances", get_instances}
        },
        function(fn)
            local values = fn()
            if type(values) ~= "table" then
                return false, "returned " .. type(values)
            end

            local instance_count = 0
            for _, value in pairs(values) do
                if is_instance(value) then
                    instance_count = instance_count + 1
                end
            end

            return instance_count > 0,
                "instances="
                    .. value_to_string(instance_count)
                    .. "/"
                    .. value_to_string(#values)
        end
    )

    capability_test(
        "Environment",
        "getnilinstances finds a private unparented Instance",
        {
            {"getnilinstances", getnilinstances},
            {"get_nil_instances", get_nil_instances}
        },
        function(fn)
            local instance_new =
                first_present(Instance, "new", "New")
            if type(instance_new) ~= "function" then
                return CAPABILITY_SKIP,
                    "Instance.new is required for a private fixture"
            end

            local fixture = instance_new("Folder")
            fixture.Name =
                "__VMCapabilityNilInstance_"
                .. value_to_string(math.random(100000, 999999))
            fixture.Parent = nil
            step_once()

            local values = fn()
            local found = list_contains_identity(values, fixture)
            destroy_instance(fixture)

            return type(values) == "table" and found,
                "returned="
                    .. type(values)
                    .. ", found fixture="
                    .. value_to_string(found)
        end
    )

    capability_test(
        "Environment",
        "gethui returns an Instance container",
        {
            {"gethui", gethui},
            {"get_hidden_gui", get_hidden_gui},
            {"gethiddengui", gethiddengui}
        },
        function(fn)
            local value = fn()
            return is_instance(value),
                "returned " .. type(value)
        end
    )

    capability_test(
        "Closures",
        "loadstring compiles and executes fresh source",
        {
            {"loadstring", loadstring},
            {"load", load}
        },
        function(fn)
            local compiled, compile_error =
                fn(
                    "local a = 9300; return a + 41, "
                    .. "'vm-capability-load'"
                )

            if type(compiled) ~= "function" then
                return false,
                    "compiler returned "
                    .. type(compiled)
                    .. ": "
                    .. value_to_string(compile_error)
            end

            local number_value, string_value = compiled()
            return number_value == 9341
                and string_value == "vm-capability-load",
                "returned "
                    .. value_to_string(number_value)
                    .. ", "
                    .. value_to_string(string_value)
        end
    )

    capability_test(
        "Closures",
        "newcclosure preserves arguments and multiple returns",
        {
            {"newcclosure", newcclosure},
            {"new_c_closure", new_c_closure}
        },
        function(fn)
            local wrapped = fn(function(a, b, c)
                return a + 1, b, c
            end)

            if type(wrapped) ~= "function" then
                return false, "returned " .. type(wrapped)
            end

            local a, b, c = wrapped(40, nil, "marker")
            if a ~= 41 or b ~= nil or c ~= "marker" then
                return false,
                    "argument/return mismatch: "
                    .. value_to_string(a)
                    .. ", "
                    .. value_to_string(b)
                    .. ", "
                    .. value_to_string(c)
            end

            local is_c =
                dependency_function({
                    {"iscclosure", iscclosure},
                    {"is_c_closure", is_c_closure}
                })

            if type(is_c) == "function" and is_c(wrapped) ~= true then
                return false,
                    "iscclosure did not recognize the wrapper"
            end

            return true
        end
    )

    capability_test(
        "Closures",
        "clonefunction creates an independent working clone",
        {
            {"clonefunction", clonefunction},
            {"clonefunc", clonefunc},
            {"clone_function", clone_function}
        },
        function(fn)
            local upvalue = 73
            local function original(value)
                return upvalue + value
            end

            local clone = fn(original)
            return type(clone) == "function"
                and clone ~= original
                and clone(4) == 77,
                "clone type="
                    .. type(clone)
                    .. ", same reference="
                    .. value_to_string(clone == original)
        end
    )

    capability_test(
        "Closures",
        "islclosure recognizes a Lua closure",
        {
            {"islclosure", islclosure},
            {"is_l_closure", is_l_closure}
        },
        function(fn)
            local function lua_closure()
                return 1
            end

            return fn(lua_closure) == true,
                "local closure was not recognized"
        end
    )

    capability_test(
        "Closures",
        "iscclosure distinguishes a native closure",
        {
            {"iscclosure", iscclosure},
            {"is_c_closure", is_c_closure}
        },
        function(fn)
            local function lua_closure()
                return 1
            end

            local native_result = fn(print)
            local lua_result = fn(lua_closure)
            return native_result == true
                and lua_result == false,
                "print="
                    .. value_to_string(native_result)
                    .. ", Lua closure="
                    .. value_to_string(lua_result)
        end
    )

    capability_test(
        "Closures",
        "isexecutorclosure recognizes external-VM-created code",
        {
            {"isexecutorclosure", isexecutorclosure},
            {"checkclosure", checkclosure},
            {"isourclosure", isourclosure}
        },
        function(fn)
            local function external_vm_closure()
                return "external-vm"
            end

            return fn(external_vm_closure) == true,
                "external-VM-created closure was not recognized"
        end
    )

    capability_test(
        "Closures",
        "getfunctionhash is stable and input-sensitive",
        {
            {"getfunctionhash", getfunctionhash},
            {"get_function_hash", get_function_hash},
            {"debug.getfunctionhash", first_present(debug, "getfunctionhash")}
        },
        function(fn)
            local function first_probe()
                return "VM_HASH_ALPHA"
            end

            local function second_probe()
                return "VM_HASH_BETA"
            end

            local first_hash = fn(first_probe)
            local second_first_hash = fn(first_probe)
            local second_hash = fn(second_probe)

            return type(first_hash) == "string"
                and #first_hash > 0
                and first_hash == second_first_hash
                and first_hash ~= second_hash,
                "hash types="
                    .. type(first_hash)
                    .. "/"
                    .. type(second_hash)
                    .. ", stable="
                    .. value_to_string(
                        first_hash == second_first_hash
                    )
                    .. ", distinct="
                    .. value_to_string(first_hash ~= second_hash)
        end
    )

    capability_test(
        "Metatable",
        "getrawmetatable returns the exact private metatable",
        {
            {"getrawmetatable", getrawmetatable},
            {"debug.getmetatable", first_present(debug, "getmetatable")}
        },
        function(fn)
            local metatable = {
                __index = function()
                    return "raw-metatable"
                end
            }
            local target = setmetatable({}, metatable)
            return fn(target) == metatable,
                "metatable identity mismatch"
        end
    )

    capability_test(
        "Metatable",
        "setrawmetatable changes a private table's metatable",
        {
            {"setrawmetatable", setrawmetatable},
            {"debug.setmetatable", first_present(debug, "setmetatable")}
        },
        function(fn)
            local target = {}
            local metatable = {
                __index = {
                    marker = "setrawmetatable"
                }
            }

            fn(target, metatable)
            return getmetatable(target) == metatable
                and target.marker == "setrawmetatable",
                "new metatable was not observed"
        end
    )

    capability_test(
        "Metatable",
        "setreadonly and isreadonly perform a reversible transition",
        {
            {"setreadonly", setreadonly},
            {"make_readonly", make_readonly}
        },
        function(fn)
            local is_readonly =
                dependency_function({
                    {"isreadonly", isreadonly},
                    {"is_readonly", is_readonly}
                })

            if type(is_readonly) ~= "function" then
                return CAPABILITY_SKIP,
                    "isreadonly is required for verification"
            end

            local target = {}
            fn(target, true)
            local locked = is_readonly(target) == true
            local write_ok = pcall(function()
                target.value = 1
            end)
            fn(target, false)
            local unlocked = is_readonly(target) == false
            local second_write_ok = pcall(function()
                target.value = 2
            end)

            return locked
                and not write_ok
                and unlocked
                and second_write_ok,
                "locked="
                    .. value_to_string(locked)
                    .. ", write while locked="
                    .. value_to_string(write_ok)
                    .. ", unlocked="
                    .. value_to_string(unlocked)
        end
    )

    capability_test(
        "Metatable",
        "isreadonly distinguishes writable and readonly tables",
        {
            {"isreadonly", isreadonly},
            {"is_readonly", is_readonly}
        },
        function(fn)
            local set_readonly =
                dependency_function({
                    {"setreadonly", setreadonly},
                    {"make_readonly", make_readonly}
                })

            if type(set_readonly) ~= "function" then
                return CAPABILITY_SKIP,
                    "setreadonly is required for verification"
            end

            local target = {}
            local before = fn(target)
            set_readonly(target, true)
            local during = fn(target)
            set_readonly(target, false)
            local after = fn(target)

            return before == false
                and during == true
                and after == false,
                "states="
                    .. value_to_string(before)
                    .. "/"
                    .. value_to_string(during)
                    .. "/"
                    .. value_to_string(after)
        end
    )

    capability_test(
        "Debug",
        "debug.getupvalue returns an exact sentinel",
        {
            {"debug.getupvalue", first_present(debug, "getupvalue")},
            {"getupvalue", getupvalue}
        },
        function(fn)
            local sentinel = {}
            local function capture()
                return sentinel
            end

            local first, second = fn(capture, 1)
            local value = second ~= nil and second or first

            return value == sentinel,
                "sentinel identity matched="
                    .. value_to_string(value == sentinel)
        end
    )

    capability_test(
        "Debug",
        "debug.getupvalues returns the real captured values",
        {
            {"debug.getupvalues", first_present(debug, "getupvalues")},
            {"getupvalues", getupvalues}
        },
        function(fn)
            local first_sentinel = {}
            local second_sentinel = "VM_UPVALUE_SECOND_5521"
            local function capture()
                return first_sentinel, second_sentinel
            end

            local values = fn(capture)
            if type(values) ~= "table" then
                return false, "returned " .. type(values)
            end

            local found_first = false
            local found_second = false
            for _, value in pairs(values) do
                if value == first_sentinel then
                    found_first = true
                elseif value == second_sentinel then
                    found_second = true
                end
            end

            return found_first and found_second,
                "first="
                    .. value_to_string(found_first)
                    .. ", second="
                    .. value_to_string(found_second)
        end
    )

    capability_test(
        "Debug",
        "debug.setupvalue mutates a real closure upvalue",
        {
            {"debug.setupvalue", first_present(debug, "setupvalue")},
            {"setupvalue", setupvalue}
        },
        function(fn)
            local value = "before"
            local function capture()
                return value
            end

            fn(capture, 1, "after")
            return capture() == "after",
                "closure returned " .. value_to_string(capture())
        end
    )

    capability_test(
        "Debug",
        "debug.getconstants exposes unique function constants",
        {
            {"debug.getconstants", first_present(debug, "getconstants")},
            {"getconstants", getconstants}
        },
        function(fn)
            local function constant_probe()
                return "VM_UNIQUE_CONSTANT_74291", 74291
            end

            local constants = fn(constant_probe)
            if type(constants) ~= "table" then
                return false, "returned " .. type(constants)
            end

            local found_string = false
            local found_number = false
            for _, value in pairs(constants) do
                if value == "VM_UNIQUE_CONSTANT_74291" then
                    found_string = true
                elseif value == 74291 then
                    found_number = true
                end
            end

            return found_string or found_number,
                "unique string="
                    .. value_to_string(found_string)
                    .. ", unique number="
                    .. value_to_string(found_number)
        end
    )

    capability_test(
        "Debug",
        "debug.getconstant agrees with debug.getconstants",
        {
            {"debug.getconstant", first_present(debug, "getconstant")},
            {"getconstant", getconstant}
        },
        function(fn)
            local get_constants =
                dependency_function({
                    {
                        "debug.getconstants",
                        first_present(debug, "getconstants")
                    },
                    {"getconstants", getconstants}
                })

            if type(get_constants) ~= "function" then
                return CAPABILITY_SKIP,
                    "debug.getconstants is required for index discovery"
            end

            local function constant_probe()
                return "VM_GETCONSTANT_38117"
            end

            local constants = get_constants(constant_probe)
            local index = nil
            for i, value in pairs(constants) do
                if value == "VM_GETCONSTANT_38117"
                    and type(i) == "number"
                then
                    index = i
                    break
                end
            end

            if index == nil then
                return false,
                    "companion getconstants omitted the sentinel"
            end

            return fn(constant_probe, index)
                == "VM_GETCONSTANT_38117",
                "index=" .. value_to_string(index)
        end
    )

    capability_test(
        "Debug",
        "debug.setconstant changes live function behavior",
        {
            {"debug.setconstant", first_present(debug, "setconstant")},
            {"setconstant", setconstant}
        },
        function(fn)
            local get_constants =
                dependency_function({
                    {
                        "debug.getconstants",
                        first_present(debug, "getconstants")
                    },
                    {"getconstants", getconstants}
                })

            if type(get_constants) ~= "function" then
                return CAPABILITY_SKIP,
                    "debug.getconstants is required for index discovery"
            end

            local function constant_probe()
                return "VM_SETCONSTANT_BEFORE_9182"
            end

            local constants = get_constants(constant_probe)
            local index = nil
            for i, value in pairs(constants) do
                if value == "VM_SETCONSTANT_BEFORE_9182"
                    and type(i) == "number"
                then
                    index = i
                    break
                end
            end

            if index == nil then
                return false, "could not locate the sentinel constant"
            end

            fn(
                constant_probe,
                index,
                "VM_SETCONSTANT_AFTER_9182"
            )
            local changed =
                constant_probe()
                    == "VM_SETCONSTANT_AFTER_9182"

            pcall(
                fn,
                constant_probe,
                index,
                "VM_SETCONSTANT_BEFORE_9182"
            )

            return changed,
                "execution reflected mutation="
                    .. value_to_string(changed)
        end
    )

    capability_test(
        "Debug",
        "debug.getprotos returns real callable prototypes",
        {
            {"debug.getprotos", first_present(debug, "getprotos")},
            {"getprotos", getprotos}
        },
        function(fn)
            local function outer()
                local function first_inner()
                    return "VM_PROTO_ONE"
                end
                local function second_inner()
                    return "VM_PROTO_TWO"
                end
                return first_inner, second_inner
            end

            local protos = fn(outer)
            if type(protos) ~= "table" then
                return false, "returned " .. type(protos)
            end

            local callable_count = 0
            for _, proto in pairs(protos) do
                if type(proto) == "function" then
                    callable_count = callable_count + 1
                end
            end

            return callable_count >= 2,
                "callable prototypes="
                    .. value_to_string(callable_count)
        end
    )

    capability_test(
        "Debug",
        "debug.getproto returns a callable nested prototype",
        {
            {"debug.getproto", first_present(debug, "getproto")},
            {"getproto", getproto}
        },
        function(fn)
            local function outer()
                local function inner()
                    return "VM_SINGLE_PROTO_441"
                end
                return inner
            end

            local proto = fn(outer, 1)
            if type(proto) == "table" and #proto == 1 then
                proto = proto[1]
            end

            return type(proto) == "function"
                and proto() == "VM_SINGLE_PROTO_441",
                "returned " .. type(proto)
        end
    )

    capability_test(
        "Debug",
        "debug.getinfo distinguishes Lua and native functions",
        {
            {"debug.getinfo", first_present(debug, "getinfo")},
            {"debug.info", first_present(debug, "info")}
        },
        function(fn, path)
            local function two_arguments(a, b)
                return a, b
            end

            if path == "debug.info" then
                local source = fn(two_arguments, "s")
                return type(source) == "string"
                    and #source > 0,
                    "debug.info source=" .. value_to_string(source)
            end

            local lua_info = fn(two_arguments)
            local native_info = fn(print)
            if type(lua_info) ~= "table"
                or type(native_info) ~= "table"
            then
                return false,
                    "returned "
                    .. type(lua_info)
                    .. "/"
                    .. type(native_info)
            end

            if lua_info.what ~= nil
                and native_info.what ~= nil
                and lua_info.what == native_info.what
            then
                return false,
                    "Lua/native 'what' fields are identical"
            end

            if lua_info.numparams ~= nil
                and lua_info.numparams ~= 2
            then
                return false,
                    "numparams="
                    .. value_to_string(lua_info.numparams)
            end

            return true
        end
    )

    local fs_suffix =
        value_to_string(math.random(100000, 999999))
    local fs_folder =
        "__vm_capability_lab_" .. fs_suffix
    local fs_file = fs_folder .. "/roundtrip.luau"
    local fs_append_file = fs_folder .. "/append.txt"

    local write_file =
        dependency_function({
            {"writefile", writefile},
            {"write_file", write_file}
        })
    local read_file =
        dependency_function({
            {"readfile", readfile},
            {"read_file", read_file}
        })
    local make_folder =
        dependency_function({
            {"makefolder", makefolder},
            {"createfolder", createfolder},
            {"mkdir", mkdir},
            {"makedir", makedir}
        })
    local delete_file =
        dependency_function({
            {"delfile", delfile},
            {"deletefile", deletefile},
            {"removefile", removefile}
        })
    local delete_folder =
        dependency_function({
            {"delfolder", delfolder},
            {"deletefolder", deletefolder},
            {"removefolder", removefolder},
            {"rmdir", rmdir}
        })
    local is_file =
        dependency_function({
            {"isfile", isfile},
            {"is_file", is_file}
        })
    local is_folder =
        dependency_function({
            {"isfolder", isfolder},
            {"is_folder", is_folder}
        })

    if type(make_folder) == "function" then
        pcall(make_folder, fs_folder)
    end

    capability_test(
        "Filesystem",
        "writefile persists exact bytes",
        {
            {"writefile", writefile},
            {"write_file", write_file}
        },
        function(fn)
            if type(read_file) ~= "function" then
                return CAPABILITY_SKIP,
                    "readfile is required to verify persistence"
            end

            if type(make_folder) == "function" then
                pcall(make_folder, fs_folder)
            end

            local payload = "return 'VM_WRITEFILE_" .. fs_suffix .. "'"
            fn(fs_file, payload)
            local observed = read_file(fs_file)
            return observed == payload,
                "read-back bytes="
                    .. value_to_string(
                        type(observed) == "string"
                            and #observed
                            or type(observed)
                    )
        end
    )

    capability_test(
        "Filesystem",
        "readfile returns exact persisted bytes",
        {
            {"readfile", readfile},
            {"read_file", read_file}
        },
        function(fn)
            if type(write_file) ~= "function" then
                return CAPABILITY_SKIP,
                    "writefile is required to create a fixture"
            end

            if type(make_folder) == "function" then
                pcall(make_folder, fs_folder)
            end

            local payload = "VM_READFILE_" .. fs_suffix
            write_file(fs_file, payload)
            return fn(fs_file) == payload,
                "read-back data mismatch"
        end
    )

    capability_test(
        "Filesystem",
        "appendfile appends instead of overwriting",
        {
            {"appendfile", appendfile},
            {"append_file", append_file}
        },
        function(fn)
            if type(write_file) ~= "function"
                or type(read_file) ~= "function"
            then
                return CAPABILITY_SKIP,
                    "writefile and readfile are required"
            end

            if type(make_folder) == "function" then
                pcall(make_folder, fs_folder)
            end

            write_file(fs_append_file, "alpha")
            fn(fs_append_file, "-beta")
            local observed = read_file(fs_append_file)
            return observed == "alpha-beta",
                "read-back=" .. value_to_string(observed)
        end
    )

    capability_test(
        "Filesystem",
        "isfile distinguishes files from missing paths",
        {
            {"isfile", isfile},
            {"is_file", is_file}
        },
        function(fn)
            if type(write_file) ~= "function" then
                return CAPABILITY_SKIP,
                    "writefile is required to create a fixture"
            end

            if type(make_folder) == "function" then
                pcall(make_folder, fs_folder)
            end

            write_file(fs_file, "isfile")
            return fn(fs_file) == true
                and fn(fs_folder .. "/missing.txt") == false,
                "existing/missing distinction failed"
        end
    )

    capability_test(
        "Filesystem",
        "makefolder creates a discoverable folder",
        {
            {"makefolder", makefolder},
            {"createfolder", createfolder},
            {"mkdir", mkdir},
            {"makedir", makedir}
        },
        function(fn)
            if type(is_folder) ~= "function" then
                return CAPABILITY_SKIP,
                    "isfolder is required for verification"
            end

            pcall(delete_folder or function() end, fs_folder)
            fn(fs_folder)
            return is_folder(fs_folder) == true,
                "isfolder did not observe the created folder"
        end
    )

    capability_test(
        "Filesystem",
        "isfolder distinguishes folders from missing paths",
        {
            {"isfolder", isfolder},
            {"is_folder", is_folder}
        },
        function(fn)
            if type(make_folder) ~= "function" then
                return CAPABILITY_SKIP,
                    "makefolder is required to create a fixture"
            end

            pcall(make_folder, fs_folder)
            return fn(fs_folder) == true
                and fn(fs_folder .. "_missing") == false,
                "existing/missing distinction failed"
        end
    )

    capability_test(
        "Filesystem",
        "listfiles returns the created file",
        {
            {"listfiles", listfiles},
            {"listdir", listdir},
            {"list_files", list_files}
        },
        function(fn)
            if type(make_folder) ~= "function"
                or type(write_file) ~= "function"
            then
                return CAPABILITY_SKIP,
                    "makefolder and writefile are required"
            end

            pcall(make_folder, fs_folder)
            write_file(fs_file, "listfiles")
            local values = fn(fs_folder)
            if type(values) ~= "table" then
                return false, "returned " .. type(values)
            end

            local found = false
            for _, path in pairs(values) do
                if type(path) == "string"
                    and (
                        path == fs_file
                        or contains_plain(path, "roundtrip.luau")
                    )
                then
                    found = true
                    break
                end
            end

            return found,
                "entries=" .. value_to_string(#values)
        end
    )

    capability_test(
        "Filesystem",
        "loadfile executes source from the filesystem",
        {
            {"loadfile", loadfile},
            {"load_file", load_file}
        },
        function(fn)
            if type(write_file) ~= "function" then
                return CAPABILITY_SKIP,
                    "writefile is required to create a fixture"
            end

            pcall(make_folder or function() end, fs_folder)
            write_file(
                fs_file,
                "return 7712, 'VM_LOADFILE_OK'"
            )
            local compiled, load_error = fn(fs_file)

            if type(compiled) ~= "function" then
                return false,
                    "returned "
                    .. type(compiled)
                    .. ": "
                    .. value_to_string(load_error)
            end

            local number_value, string_value = compiled()
            return number_value == 7712
                and string_value == "VM_LOADFILE_OK",
                "returned "
                    .. value_to_string(number_value)
                    .. ", "
                    .. value_to_string(string_value)
        end
    )

    capability_test(
        "Filesystem",
        "delfile removes an existing file",
        {
            {"delfile", delfile},
            {"deletefile", deletefile},
            {"removefile", removefile}
        },
        function(fn)
            if type(write_file) ~= "function"
                or type(is_file) ~= "function"
            then
                return CAPABILITY_SKIP,
                    "writefile and isfile are required"
            end

            pcall(make_folder or function() end, fs_folder)
            write_file(fs_file, "delete-me")
            fn(fs_file)
            return is_file(fs_file) == false,
                "isfile still reports the fixture"
        end
    )

    capability_test(
        "Filesystem",
        "delfolder removes an existing folder",
        {
            {"delfolder", delfolder},
            {"deletefolder", deletefolder},
            {"removefolder", removefolder},
            {"rmdir", rmdir}
        },
        function(fn)
            if type(make_folder) ~= "function"
                or type(is_folder) ~= "function"
            then
                return CAPABILITY_SKIP,
                    "makefolder and isfolder are required"
            end

            pcall(delete_file or function() end, fs_file)
            pcall(delete_file or function() end, fs_append_file)
            pcall(fn, fs_folder)
            make_folder(fs_folder)
            fn(fs_folder)
            return is_folder(fs_folder) == false,
                "isfolder still reports the fixture"
        end
    )

    capability_test(
        "Filesystem",
        "getcustomasset returns an engine asset URI for a real file",
        {
            {"getcustomasset", getcustomasset},
            {"get_custom_asset", get_custom_asset}
        },
        function(fn)
            if type(write_file) ~= "function" then
                return CAPABILITY_SKIP,
                    "writefile is required to create an asset fixture"
            end

            pcall(make_folder or function() end, fs_folder)
            local asset_path = fs_folder .. "/asset.txt"
            write_file(asset_path, "VM_CUSTOM_ASSET_" .. fs_suffix)
            local uri = fn(asset_path)
            pcall(delete_file or function() end, asset_path)

            return type(uri) == "string"
                and #uri > 0
                and (
                    contains_plain(uri, "rbxasset")
                    or contains_plain(uri, "asset")
                ),
                "returned " .. value_to_string(uri)
        end
    )

    capability_test(
        "Encoding",
        "base64 encode returns the canonical vector",
        {
            {
                "crypt.base64.encode",
                first_present(crypt_base64, "encode")
            },
            {"base64encode", base64encode},
            {"base64_encode", base64_encode},
            {"base64.encode", first_present(generic_base64, "encode")}
        },
        function(fn)
            local result = fn("Hello, VM!")
            return result == "SGVsbG8sIFZNIQ==",
                "returned " .. value_to_string(result)
        end
    )

    capability_test(
        "Encoding",
        "base64 decode reverses the canonical vector",
        {
            {
                "crypt.base64.decode",
                first_present(crypt_base64, "decode")
            },
            {"base64decode", base64decode},
            {"base64_decode", base64_decode},
            {"base64.decode", first_present(generic_base64, "decode")}
        },
        function(fn)
            local result = fn("SGVsbG8sIFZNIQ==")
            return result == "Hello, VM!",
                "returned " .. value_to_string(result)
        end
    )

    capability_test(
        "Encoding",
        "lz4 compression round-trips binary-safe data",
        {
            {"lz4compress", lz4compress},
            {"lz4_compress", lz4_compress},
            {"lz4.compress", first_present(lz4, "compress")}
        },
        function(fn)
            local decompress =
                dependency_function({
                    {"lz4decompress", lz4decompress},
                    {"lz4_decompress", lz4_decompress},
                    {"lz4.decompress", first_present(lz4, "decompress")}
                })

            if type(decompress) ~= "function" then
                return CAPABILITY_SKIP,
                    "lz4decompress is required for verification"
            end

            local source =
                "VM-LZ4\0"
                .. string.rep("roundtrip-", 32)
            local compressed = fn(source)
            if type(compressed) ~= "string" then
                return false,
                    "compress returned " .. type(compressed)
            end

            local ok, restored =
                pcall(decompress, compressed, #source)
            if not ok or restored ~= source then
                ok, restored = pcall(decompress, compressed)
            end

            return ok and restored == source,
                "compressed="
                    .. value_to_string(#compressed)
                    .. " bytes, restored="
                    .. value_to_string(
                        type(restored) == "string"
                            and #restored
                            or type(restored)
                    )
        end
    )

    capability_test(
        "Encoding",
        "lz4 decompression restores the original bytes",
        {
            {"lz4decompress", lz4decompress},
            {"lz4_decompress", lz4_decompress},
            {"lz4.decompress", first_present(lz4, "decompress")}
        },
        function(fn)
            local compress =
                dependency_function({
                    {"lz4compress", lz4compress},
                    {"lz4_compress", lz4_compress},
                    {"lz4.compress", first_present(lz4, "compress")}
                })

            if type(compress) ~= "function" then
                return CAPABILITY_SKIP,
                    "lz4compress is required for verification"
            end

            local source = string.rep("VM-LZ4-DECODE-", 24)
            local compressed = compress(source)
            local ok, restored = pcall(fn, compressed, #source)
            if not ok or restored ~= source then
                ok, restored = pcall(fn, compressed)
            end

            return ok and restored == source,
                "restored exact bytes="
                    .. value_to_string(restored == source)
        end
    )

    capability_test(
        "Cryptography",
        "crypt.hash is deterministic and input-sensitive",
        {
            {
                "crypt.hash.sha256",
                first_present(
                    first_present(crypt, "hash"),
                    "sha256"
                )
            },
            {"crypt.sha256", first_present(crypt, "sha256")},
            {"crypt.hash", first_present(crypt, "hash")},
            {"crypto.hash", first_present(crypto, "hash")}
        },
        function(fn)
            local function hash(value)
                local ok, result = pcall(fn, value)
                if ok and type(result) == "string" then
                    return result
                end

                ok, result = pcall(fn, value, "sha256")
                if ok and type(result) == "string" then
                    return result
                end

                ok, result = pcall(fn, "sha256", value)
                if ok and type(result) == "string" then
                    return result
                end

                error(result, 0)
            end

            local first = hash("VM-HASH-ALPHA")
            local second = hash("VM-HASH-ALPHA")
            local different = hash("VM-HASH-BETA")

            return #first > 0
                and first == second
                and first ~= different,
                "length="
                    .. value_to_string(#first)
                    .. ", stable="
                    .. value_to_string(first == second)
                    .. ", distinct="
                    .. value_to_string(first ~= different)
        end
    )

    capability_test(
        "Network",
        "request performs a real HTTP GET",
        {
            {"request", request},
            {"http_request", http_request},
            {"http.request", first_present(http_namespace, "request")}
        },
        function(fn)
            if not EXTERNAL_TEST_CONFIG.run_http_get then
                return CAPABILITY_SKIP,
                    "HTTP execution is disabled"
            end

            local response = fn({
                Url = EXTERNAL_TEST_VALUES.http_get_url,
                URL = EXTERNAL_TEST_VALUES.http_get_url,
                Method = "GET"
            })

            if type(response) ~= "table" then
                return false, "returned " .. type(response)
            end

            local status =
                response.StatusCode
                or response.Status
                or response.status_code
                or response.status
            local body =
                response.Body
                or response.body

            return type(status) == "number"
                and status >= 200
                and status < 400
                and type(body) == "string"
                and #body > 0,
                "status="
                    .. value_to_string(status)
                    .. ", body="
                    .. value_to_string(
                        type(body) == "string"
                            and #body
                            or type(body)
                    )
        end
    )

    capability_test(
        "Instances",
        "cloneref preserves engine identity",
        {
            {"cloneref", cloneref},
            {"clone_ref", clone_ref}
        },
        function(fn)
            if game == nil then
                return CAPABILITY_SKIP,
                    "game is required as an Instance fixture"
            end

            local clone = fn(game)
            if clone == nil then
                return false, "returned nil"
            end

            local compare =
                dependency_function({
                    {"compareinstances", compareinstances},
                    {"compare_instances", compare_instances}
                })

            if type(compare) == "function" then
                return compare(game, clone) == true,
                    "compareinstances did not preserve identity"
            end

            return clone == game,
                "no compareinstances; direct identity="
                    .. value_to_string(clone == game)
        end
    )

    capability_test(
        "Instances",
        "compareinstances distinguishes equal engine identities",
        {
            {"compareinstances", compareinstances},
            {"compare_instances", compare_instances}
        },
        function(fn)
            if game == nil then
                return CAPABILITY_SKIP,
                    "game is required as an Instance fixture"
            end

            local positive = fn(game, game)
            local negative = nil
            if workspace ~= nil and workspace ~= game then
                negative = fn(game, workspace)
            end

            return positive == true
                and (negative == nil or negative == false),
                "same="
                    .. value_to_string(positive)
                    .. ", different="
                    .. value_to_string(negative)
        end
    )

    capability_test(
        "Instances",
        "getcallbackvalue retrieves an exact write-only callback",
        {
            {"getcallbackvalue", getcallbackvalue},
            {"get_callback_value", get_callback_value}
        },
        function(fn)
            local instance_new =
                first_present(Instance, "new", "New")
            if type(instance_new) ~= "function" then
                return CAPABILITY_SKIP,
                    "Instance.new is required for a BindableFunction"
            end

            local bindable = instance_new("BindableFunction")
            local function callback(value)
                return "VM_CALLBACK:" .. value
            end
            bindable.OnInvoke = callback

            local retrieved = fn(bindable, "OnInvoke")
            local valid =
                type(retrieved) == "function"
                and retrieved == callback
                and retrieved("ok") == "VM_CALLBACK:ok"

            destroy_instance(bindable)
            return valid,
                "returned "
                    .. type(retrieved)
                    .. ", identity="
                    .. value_to_string(retrieved == callback)
        end
    )

    capability_test(
        "Instances",
        "fireclickdetector triggers a private detector signal",
        {
            {"fireclickdetector", fireclickdetector},
            {"fire_click_detector", fire_click_detector}
        },
        function(fn)
            local instance_new =
                first_present(Instance, "new", "New")
            if type(instance_new) ~= "function"
                or workspace == nil
            then
                return CAPABILITY_SKIP,
                    "Instance.new and workspace are required"
            end

            local part = instance_new("Part")
            local detector = instance_new("ClickDetector")
            detector.Parent = part
            part.Parent = workspace

            local fired = false
            local connection =
                detector.MouseClick:Connect(function()
                    fired = true
                end)

            fn(detector)
            step_once()

            disconnect_connection(connection)
            destroy_instance(part)
            return fired,
                "MouseClick observed=" .. value_to_string(fired)
        end
    )

    capability_test(
        "Instances",
        "fireproximityprompt triggers a private prompt signal",
        {
            {"fireproximityprompt", fireproximityprompt},
            {"fire_proximity_prompt", fire_proximity_prompt}
        },
        function(fn)
            local instance_new =
                first_present(Instance, "new", "New")
            if type(instance_new) ~= "function"
                or workspace == nil
            then
                return CAPABILITY_SKIP,
                    "Instance.new and workspace are required"
            end

            local part = instance_new("Part")
            local prompt = instance_new("ProximityPrompt")
            prompt.HoldDuration = 0
            prompt.Parent = part
            part.Parent = workspace

            local fired = false
            local connection =
                prompt.Triggered:Connect(function()
                    fired = true
                end)

            fn(prompt)
            step_once()

            disconnect_connection(connection)
            destroy_instance(part)
            return fired,
                    "Triggered observed=" .. value_to_string(fired)
        end
    )

    capability_test(
        "Instances",
        "firetouchinterest triggers a private touch signal",
        {
            {"firetouchinterest", firetouchinterest},
            {"fire_touch_interest", fire_touch_interest}
        },
        function(fn)
            local instance_new =
                first_present(Instance, "new", "New")
            if type(instance_new) ~= "function"
                or workspace == nil
            then
                return CAPABILITY_SKIP,
                    "Instance.new and workspace are required"
            end

            local first_part = instance_new("Part")
            local second_part = instance_new("Part")
            first_part.Anchored = true
            second_part.Anchored = true
            pcall(function()
                first_part.Position =
                    Vector3.new(0, 100000, 0)
                second_part.Position =
                    Vector3.new(0, 100100, 0)
            end)
            first_part.Parent = workspace
            second_part.Parent = workspace

            local fired = false
            local connection =
                first_part.Touched:Connect(function(other)
                    if other == second_part then
                        fired = true
                    end
                end)

            fn(first_part, second_part, 0)
            step_once()
            fn(first_part, second_part, 1)
            step_once()

            disconnect_connection(connection)
            destroy_instance(first_part)
            destroy_instance(second_part)
            return fired,
                "Touched observed=" .. value_to_string(fired)
        end
    )

    capability_test(
        "Signals",
        "getconnections exposes a private signal connection",
        {
            {"getconnections", getconnections},
            {"get_connections", get_connections}
        },
        function(fn)
            local instance_new =
                first_present(Instance, "new", "New")
            if type(instance_new) ~= "function" then
                return CAPABILITY_SKIP,
                    "Instance.new is required for a BindableEvent"
            end

            local bindable = instance_new("BindableEvent")
            local connection = bindable.Event:Connect(function()
            end)
            local values = fn(bindable.Event)
            local found =
                type(values) == "table"
                and #values > 0

            disconnect_connection(connection)
            destroy_instance(bindable)

            return found,
                "returned="
                    .. type(values)
                    .. ", count="
                    .. value_to_string(
                        type(values) == "table"
                            and #values
                            or 0
                    )
        end
    )

    capability_test(
        "Signals",
        "firesignal delivers exact arguments to a private signal",
        {
            {"firesignal", firesignal},
            {"fire_signal", fire_signal}
        },
        function(fn)
            local instance_new =
                first_present(Instance, "new", "New")
            if type(instance_new) ~= "function" then
                return CAPABILITY_SKIP,
                    "Instance.new is required for a BindableEvent"
            end

            local bindable = instance_new("BindableEvent")
            local observed_a = nil
            local observed_b = nil
            local connection = bindable.Event:Connect(function(a, b)
                observed_a = a
                observed_b = b
            end)

            fn(bindable.Event, "VM_SIGNAL", 8192)
            step_once()

            disconnect_connection(connection)
            destroy_instance(bindable)

            return observed_a == "VM_SIGNAL"
                and observed_b == 8192,
                "observed="
                    .. value_to_string(observed_a)
                    .. ", "
                    .. value_to_string(observed_b)
        end
    )

    capability_test(
        "Scripts",
        "getloadedmodules returns only ModuleScript Instances",
        {
            {"getloadedmodules", getloadedmodules},
            {"get_loaded_modules", get_loaded_modules}
        },
        function(fn)
            local values = fn()
            if type(values) ~= "table" then
                return false, "returned " .. type(values)
            end

            for _, value in pairs(values) do
                if not is_instance(value) then
                    return false,
                        "non-Instance entry: " .. type(value)
                end

                local ok, is_module = pcall(function()
                    return value:IsA("ModuleScript")
                end)
                if ok and not is_module then
                    return false,
                        "entry is not a ModuleScript"
                end
            end

            return true,
                "module count=" .. value_to_string(#values)
        end
    )

    capability_test(
        "Scripts",
        "getscripts returns Lua source containers",
        {
            {"getscripts", getscripts},
            {"getrunningscripts", getrunningscripts},
            {"get_scripts", get_scripts}
        },
        function(fn)
            local values = fn()
            if type(values) ~= "table" then
                return false, "returned " .. type(values)
            end

            local valid_count = 0
            for _, value in pairs(values) do
                if is_instance(value) then
                    local ok, is_source = pcall(function()
                        return value:IsA("LuaSourceContainer")
                    end)

                    if not ok or is_source then
                        valid_count = valid_count + 1
                    end
                end
            end

            return valid_count > 0 or #values == 0,
                "valid source containers="
                    .. value_to_string(valid_count)
                    .. "/"
                    .. value_to_string(#values)
        end
    )

    capability_test(
        "Scripts",
        "getrunningscripts returns currently running source containers",
        {
            {"getrunningscripts", getrunningscripts},
            {"get_running_scripts", get_running_scripts},
            {"getscripts", getscripts}
        },
        function(fn)
            local values = fn()
            if type(values) ~= "table" then
                return false, "returned " .. type(values)
            end

            for _, value in pairs(values) do
                if not is_instance(value) then
                    return false,
                        "non-Instance entry: " .. type(value)
                end
            end

            return true,
                "running script count="
                    .. value_to_string(#values)
        end
    )

    capability_test(
        "Scripts",
        "getscriptbytecode returns nonempty bytecode",
        {
            {"getscriptbytecode", getscriptbytecode},
            {"dumpstring", dumpstring},
            {"get_script_bytecode", get_script_bytecode}
        },
        function(fn)
            local get_scripts =
                dependency_function({
                    {"getscripts", getscripts},
                    {"getrunningscripts", getrunningscripts}
                })

            if type(get_scripts) ~= "function" then
                return CAPABILITY_SKIP,
                    "getscripts is required to find a fixture"
            end

            local scripts = get_scripts()
            local target = scripts[1]
            if target == nil then
                return CAPABILITY_SKIP,
                    "no live script fixture was returned"
            end

            local bytecode = fn(target)
            return type(bytecode) == "string"
                and #bytecode > 0,
                "returned "
                    .. type(bytecode)
                    .. ", bytes="
                    .. value_to_string(
                        type(bytecode) == "string"
                            and #bytecode
                            or 0
                    )
        end
    )

    capability_test(
        "Scripts",
        "getscripthash returns stable nonempty script hashes",
        {
            {"getscripthash", getscripthash},
            {"get_script_hash", get_script_hash}
        },
        function(fn)
            local get_scripts =
                dependency_function({
                    {"getscripts", getscripts},
                    {"getrunningscripts", getrunningscripts}
                })

            if type(get_scripts) ~= "function" then
                return CAPABILITY_SKIP,
                    "getscripts is required to find a fixture"
            end

            local scripts = get_scripts()
            local target = scripts[1]
            if target == nil then
                return CAPABILITY_SKIP,
                    "no live script fixture was returned"
            end

            local first = fn(target)
            local second = fn(target)
            return type(first) == "string"
                and #first > 0
                and first == second,
                "type="
                    .. type(first)
                    .. ", length="
                    .. value_to_string(
                        type(first) == "string"
                            and #first
                            or 0
                    )
                    .. ", stable="
                    .. value_to_string(first == second)
        end
    )

    capability_test(
        "Miscellaneous",
        "identifyexecutor returns a usable identity",
        {
            {"identifyexecutor", identifyexecutor},
            {"getexecutorname", getexecutorname},
            {"getexecutor", getexecutor}
        },
        function(fn)
            local name, version = fn()
            return type(name) == "string"
                and #name > 0
                and (
                    version == nil
                    or type(version) == "string"
                    or type(version) == "number"
                ),
                "name="
                    .. value_to_string(name)
                    .. ", version="
                    .. value_to_string(version)
        end
    )

    capability_test(
        "Reflection",
        "isscriptable distinguishes valid and missing properties",
        {
            {"isscriptable", isscriptable},
            {"is_scriptable", is_scriptable}
        },
        function(fn)
            local instance_new =
                first_present(Instance, "new", "New")
            if type(instance_new) ~= "function" then
                return CAPABILITY_SKIP,
                    "Instance.new is required for a private fixture"
            end

            local part = instance_new("Part")
            local valid = fn(part, "Name")
            local missing =
                fn(part, "__VM_PROPERTY_DOES_NOT_EXIST__")
            destroy_instance(part)

            return valid == true and missing == nil,
                "Name="
                    .. value_to_string(valid)
                    .. ", missing="
                    .. value_to_string(missing)
        end
    )

    capability_test(
        "Reflection",
        "setscriptable performs a reversible private-property toggle",
        {
            {"setscriptable", setscriptable},
            {"set_scriptable", set_scriptable}
        },
        function(fn)
            local is_scriptable_fn =
                dependency_function({
                    {"isscriptable", isscriptable},
                    {"is_scriptable", is_scriptable}
                })
            local instance_new =
                first_present(Instance, "new", "New")

            if type(is_scriptable_fn) ~= "function"
                or type(instance_new) ~= "function"
            then
                return CAPABILITY_SKIP,
                    "isscriptable and Instance.new are required"
            end

            local part = instance_new("Part")
            local property = "BottomParamA"
            local original = is_scriptable_fn(part, property)
            if type(original) ~= "boolean" then
                destroy_instance(part)
                return CAPABILITY_SKIP,
                    property
                    .. " is not exposed by this engine build"
            end

            local target = not original
            fn(part, property, target)
            local changed =
                is_scriptable_fn(part, property)
            pcall(fn, part, property, original)
            local restored =
                is_scriptable_fn(part, property)
            destroy_instance(part)

            return changed == target
                and restored == original,
                "original="
                    .. value_to_string(original)
                    .. ", changed="
                    .. value_to_string(changed)
                    .. ", restored="
                    .. value_to_string(restored)
        end
    )

    capability_test(
        "Reflection",
        "gethiddenproperty returns a stable private property value",
        {
            {"gethiddenproperty", gethiddenproperty},
            {"get_hidden_property", get_hidden_property}
        },
        function(fn)
            local instance_new =
                first_present(Instance, "new", "New")
            if type(instance_new) ~= "function" then
                return CAPABILITY_SKIP,
                    "Instance.new is required for a private fixture"
            end

            local part = instance_new("Part")
            local first = fn(part, "BottomParamA")
            local second = fn(part, "BottomParamA")
            destroy_instance(part)

            return first ~= nil and first == second,
                "first="
                    .. value_to_string(first)
                    .. ", second="
                    .. value_to_string(second)
        end
    )

    capability_test(
        "Reflection",
        "sethiddenproperty changes and restores a private value",
        {
            {"sethiddenproperty", sethiddenproperty},
            {"set_hidden_property", set_hidden_property}
        },
        function(fn)
            local getter =
                dependency_function({
                    {"gethiddenproperty", gethiddenproperty},
                    {"get_hidden_property", get_hidden_property}
                })
            local instance_new =
                first_present(Instance, "new", "New")

            if type(getter) ~= "function"
                or type(instance_new) ~= "function"
            then
                return CAPABILITY_SKIP,
                    "gethiddenproperty and Instance.new are required"
            end

            local part = instance_new("Part")
            local property = "BottomParamA"
            local original = getter(part, property)
            local replacement = nil

            if type(original) == "number" then
                replacement = original + 1
            elseif type(original) == "boolean" then
                replacement = not original
            elseif type(original) == "string" then
                replacement = original .. "_VM_TEST"
            end

            if replacement == nil then
                destroy_instance(part)
                return CAPABILITY_SKIP,
                    "unsupported fixture value type: "
                    .. type(original)
            end

            fn(part, property, replacement)
            local changed = getter(part, property)
            pcall(fn, part, property, original)
            local restored = getter(part, property)
            destroy_instance(part)

            return changed == replacement
                and restored == original,
                "changed="
                    .. value_to_string(changed)
                    .. ", restored="
                    .. value_to_string(restored)
        end
    )

    local drawing_new =
        first_present(Drawing, "new", "New")

    capability_test(
        "Drawing",
        "Drawing.new creates a writable removable object",
        {
            {"Drawing.new", drawing_new},
            {"Drawing.New", first_present(Drawing, "New")}
        },
        function(fn)
            local object = fn("Line")
            if object == nil then
                return false, "returned nil"
            end

            local write_ok, write_error = pcall(function()
                object.Visible = false
                object.Thickness = 2
            end)
            local read_ok, thickness = pcall(function()
                return object.Thickness
            end)
            remove_drawing(object)

            return write_ok
                and read_ok
                and thickness == 2,
                "write="
                    .. value_to_string(write_ok)
                    .. ", thickness="
                    .. value_to_string(thickness)
                    .. ", error="
                    .. value_to_string(write_error)
        end
    )

    capability_test(
        "Drawing",
        "isrenderobj recognizes a live Drawing object",
        {
            {"isrenderobj", isrenderobj},
            {"is_render_obj", is_render_obj}
        },
        function(fn)
            if type(drawing_new) ~= "function" then
                return CAPABILITY_SKIP,
                    "Drawing.new is required for verification"
            end

            local object = drawing_new("Line")
            local result = fn(object)
            remove_drawing(object)
            return result == true,
                "returned " .. value_to_string(result)
        end
    )

    capability_test(
        "Drawing",
        "setrenderproperty and getrenderproperty round-trip",
        {
            {"setrenderproperty", setrenderproperty},
            {"set_render_property", set_render_property}
        },
        function(fn)
            if type(drawing_new) ~= "function" then
                return CAPABILITY_SKIP,
                    "Drawing.new is required for verification"
            end

            local getter =
                dependency_function({
                    {"getrenderproperty", getrenderproperty},
                    {"get_render_property", get_render_property}
                })

            if type(getter) ~= "function" then
                return CAPABILITY_SKIP,
                    "getrenderproperty is required for verification"
            end

            local object = drawing_new("Line")
            fn(object, "Thickness", 3)
            local result = getter(object, "Thickness")
            remove_drawing(object)

            return result == 3,
                "returned " .. value_to_string(result)
        end
    )

    capability_test(
        "Drawing",
        "getrenderproperty reads a live Drawing property",
        {
            {"getrenderproperty", getrenderproperty},
            {"get_render_property", get_render_property}
        },
        function(fn)
            if type(drawing_new) ~= "function" then
                return CAPABILITY_SKIP,
                    "Drawing.new is required for verification"
            end

            local object = drawing_new("Line")
            object.Thickness = 4
            local result = fn(object, "Thickness")
            remove_drawing(object)

            return result == 4,
                "returned " .. value_to_string(result)
        end
    )

    capability_test(
        "Drawing",
        "cleardrawcache invalidates live Drawing objects",
        {
            {"cleardrawcache", cleardrawcache},
            {"clear_draw_cache", clear_draw_cache},
            {"Drawing.clear", first_present(Drawing, "clear", "Clear")}
        },
        function(fn)
            if type(drawing_new) ~= "function" then
                return CAPABILITY_SKIP,
                    "Drawing.new is required for verification"
            end

            local checker =
                dependency_function({
                    {"isrenderobj", isrenderobj},
                    {"is_render_obj", is_render_obj}
                })

            if type(checker) ~= "function" then
                return CAPABILITY_SKIP,
                    "isrenderobj is required for verification"
            end

            local object = drawing_new("Line")
            local before = checker(object)
            fn()
            local after = checker(object)
            remove_drawing(object)

            return before == true and after == false,
                "before="
                    .. value_to_string(before)
                    .. ", after="
                    .. value_to_string(after)
        end
    )

    raw_capability_test(
        "Remote Tools",
        "RemoteEvent.FireServer method surface",
        function()
            local instance_new =
                first_present(Instance, "new", "New")
            if type(instance_new) ~= "function" then
                return CAPABILITY_MISSING,
                    "Instance.new is unavailable"
            end

            local remote = instance_new("RemoteEvent")
            local ok, method = pcall(function()
                return remote.FireServer
            end)
            destroy_instance(remote)

            if not ok or type(method) ~= "function" then
                return false,
                    "FireServer lookup returned "
                    .. type(method)
            end

            return CAPABILITY_SKIP,
                "method exists; a server-owned verifier RemoteEvent "
                .. "is required to prove delivery"
        end
    )

    capability_test(
        "Remote Tools",
        "global fireserver compatibility helper",
        {
            {"fireserver", fireserver},
            {"fire_server", fire_server},
            {"fireServer", fireServer},
            {"FireServer", FireServer}
        },
        function()
            return CAPABILITY_SKIP,
                "present; no universal safe call contract or verifier "
                .. "RemoteEvent exists"
        end
    )

    capability_test(
        "Remote Tools",
        "global invokeserver compatibility helper",
        {
            {"invokeserver", invokeserver},
            {"invoke_server", invoke_server},
            {"invokeServer", invokeServer},
            {"InvokeServer", InvokeServer}
        },
        function()
            return CAPABILITY_SKIP,
                "present; no universal safe call contract or verifier "
                .. "RemoteFunction exists"
        end
    )

    raw_capability_test(
        "Remote Tools",
        "remotespy compatibility surface",
        function()
            local function_value, function_path =
                resolve_function_candidates({
                    {"remotespy", remotespy},
                    {"remote_spy", remote_spy},
                    {"remoteSpy", remoteSpy},
                    {"startremotespy", startremotespy}
                })

            if type(function_value) == "function" then
                return CAPABILITY_SKIP,
                    function_path
                    .. " exists; remotespy has no universal "
                    .. "start/stop/capture contract"
            end

            local table_value =
                type(RemoteSpy) == "table"
                    and RemoteSpy
                    or type(remotespy) == "table"
                        and remotespy
                        or type(remote_spy) == "table"
                            and remote_spy
                            or nil

            if table_value == nil then
                return CAPABILITY_MISSING,
                    "checked remotespy, remote_spy, remoteSpy, "
                    .. "RemoteSpy, and startremotespy"
            end

            local control =
                first_present(
                    table_value,
                    "Start",
                    "start",
                    "Enable",
                    "enable",
                    "Connect",
                    "connect"
                )

            if type(control) ~= "function" then
                return false,
                    "RemoteSpy table has no callable control method"
            end

            return CAPABILITY_SKIP,
                "RemoteSpy control surface exists; capture verification "
                .. "requires a known server RemoteEvent"
        end
    )

    pcall(delete_file or function() end, fs_file)
    pcall(delete_file or function() end, fs_append_file)
    pcall(delete_folder or function() end, fs_folder)
end

-- ============================================================
-- 38. BROAD EXTERNAL FUNCTION CATALOG
-- ============================================================
section(
    "38. Broad External Function Surface Catalog",
    "surface",
    "API Surface"
)

-- This section reads ordinary namespace functions directly. Instance
-- methods that an external VM may expose only through Luau NAMECALL are
-- exercised with literal ':' calls on safe or disposable fixtures.
-- Roblox-VM-only APIs, server-authority-only calls, and executor-brand
-- aliases are excluded from the catalog and totals.
do
    local catalog_total = 0
    local catalog_available = 0
    local catalog_missing = 0
    local catalog_nonfunction = 0
    local seen_catalog_names = {}

    local function catalog_probe(path, value)
        if seen_catalog_names[path] then
            return
        end

        seen_catalog_names[path] = true
        catalog_total = catalog_total + 1

        if type(value) == "function" then
            catalog_available = catalog_available + 1
            record_result(
                "API path: " .. path,
                "PASS",
                "function is available",
                "surface",
                true
            )
        elseif value == nil then
            catalog_missing = catalog_missing + 1
            record_result(
                "API path: " .. path,
                "MISSING",
                "function is missing",
                "surface",
                true
            )
        else
            catalog_nonfunction = catalog_nonfunction + 1
            record_result(
                "API path: " .. path,
                "FAIL",
                "expected function, got " .. type(value),
                "surface",
                true
            )
        end
    end

    local function missing_namecall_error(error_value)
        local message = string.lower(tostring(error_value))

        return contains_plain(message, "attempt to call a nil value")
            or contains_plain(message, "attempt to index nil")
            or contains_plain(message, "missing method")
            or contains_plain(message, "unknown method")
            or contains_plain(message, "method not found")
            or contains_plain(message, "not a valid member")
            or contains_plain(message, "no basepart fixture")
            or contains_plain(message, "no userinputservice fixture")
    end

    local function catalog_namecall_probe(
        path,
        callback,
        accept_nonmissing_error
    )
        if seen_catalog_names[path] then
            return
        end

        seen_catalog_names[path] = true
        catalog_total = catalog_total + 1

        if type(callback) ~= "function" then
            catalog_missing = catalog_missing + 1
            record_result(
                "API path: " .. path,
                "MISSING",
                "no namecall probe is available",
                "surface",
                true
            )
            return
        end

        local ok, result = pcall(callback)

        if ok then
            catalog_available = catalog_available + 1
            record_result(
                "API path: " .. path,
                "PASS",
                "method is available through ':' namecall",
                "surface",
                true
            )
        elseif missing_namecall_error(result) then
            catalog_missing = catalog_missing + 1
            record_result(
                "API path: " .. path,
                "MISSING",
                "namecall method is missing: " .. tostring(result),
                "surface",
                true
            )
        elseif accept_nonmissing_error then
            catalog_available = catalog_available + 1
            record_result(
                "API path: " .. path,
                "PASS",
                "method reached argument validation through ':' namecall: "
                    .. tostring(result),
                "surface",
                true
            )
        else
            catalog_nonfunction = catalog_nonfunction + 1
            record_result(
                "API path: " .. path,
                "FAIL",
                "namecall exists but execution failed: "
                    .. tostring(result),
                "surface",
                true
            )
        end
    end

    local global_function_candidates = {
        {"assert", assert},
        {"collectgarbage", collectgarbage},
        {"dofile", dofile},
        {"error", error},
        {"gcinfo", gcinfo},
        {"getfenv", getfenv},
        {"setfenv", setfenv},
        {"getmetatable", getmetatable},
        {"ipairs", ipairs},
        {"load", load},
        {"loadfile", loadfile},
        {"loadstring", loadstring},
        {"module", module},
        {"newproxy", newproxy},
        {"next", next},
        {"pairs", pairs},
        {"pcall", pcall},
        {"print", print},
        {"rawequal", rawequal},
        {"rawget", rawget},
        {"rawlen", rawlen},
        {"rawset", rawset},
        {"require", require},
        {"select", select},
        {"setmetatable", setmetatable},
        {"tonumber", tonumber},
        {"tostring", tostring},
        {"type", type},
        {"typeof", typeof},
        {"unpack", unpack},
        {"xpcall", xpcall},
        {"warn", warn},
        {"tick", tick},
        {"time", time},
        {"elapsedTime", elapsedTime},
        {"wait", wait},
        {"delay", delay},
        {"spawn", spawn},
        {"version", version},
        {"settings", settings},
        {"UserSettings", UserSettings},
        {"PluginManager", PluginManager},
        {"getgenv", getgenv},
        {"getinstances", getinstances},
        {"getnilinstances", getnilinstances},
        {"getscripts", getscripts},
        {"getrunningscripts", getrunningscripts},
        {"getloadedmodules", getloadedmodules},
        {"getscriptbytecode", getscriptbytecode},
        {"getscripthash", getscripthash},
        {"dumpstring", dumpstring},
        {"decompile", decompile},
        {"disassemble", disassemble},
        {"getconnections", getconnections},
        {"getcallbackvalue", getcallbackvalue},
        {"firesignal", firesignal},
        {"replicatesignal", replicatesignal},
        {"fireserver", fireserver},
        {"fire_server", fire_server},
        {"fireServer", fireServer},
        {"FireServer", FireServer},
        {"invokeserver", invokeserver},
        {"invoke_server", invoke_server},
        {"invokeServer", invokeServer},
        {"InvokeServer", InvokeServer},
        {"remotespy", remotespy},
        {"remote_spy", remote_spy},
        {"remoteSpy", remoteSpy},
        {"RemoteSpy", RemoteSpy},
        {"startremotespy", startremotespy},
        {"stopremotespy", stopremotespy},
        {"spyremote", spyremote},
        {"hookremote", hookremote},
        {"unhookremote", unhookremote},
        {"getremotes", getremotes},
        {"getremoteevents", getremoteevents},
        {"getremotefunctions", getremotefunctions},
        {"clonefunction", clonefunction},
        {"newcclosure", newcclosure},
        {"iscclosure", iscclosure},
        {"islclosure", islclosure},
        {"isexecutorclosure", isexecutorclosure},
        {"isourclosure", isourclosure},
        {"getfunctionhash", getfunctionhash},
        {"comparefunction", comparefunction},
        {"getupvalue", getupvalue},
        {"getupvalues", getupvalues},
        {"setupvalue", setupvalue},
        {"getconstant", getconstant},
        {"getconstants", getconstants},
        {"setconstant", setconstant},
        {"getproto", getproto},
        {"getprotos", getprotos},
        {"setproto", setproto},
        {"getstack", getstack},
        {"setstack", setstack},
        {"getrawmetatable", getrawmetatable},
        {"setrawmetatable", setrawmetatable},
        {"setreadonly", setreadonly},
        {"isreadonly", isreadonly},
        {"make_readonly", make_readonly},
        {"make_writeable", make_writeable},
        {"makereadonly", makereadonly},
        {"makewriteable", makewriteable},
        {"cloneref", cloneref},
        {"compareinstances", compareinstances},
        {"gethiddenproperty", gethiddenproperty},
        {"sethiddenproperty", sethiddenproperty},
        {"getproperties", getproperties},
        {"gethiddenproperties", gethiddenproperties},
        {"getspecialinfo", getspecialinfo},
        {"isscriptable", isscriptable},
        {"setscriptable", setscriptable},
        {"ispropertyscriptable", ispropertyscriptable},
        {"isnetworkowner", isnetworkowner},
        {"setsimulationradius", setsimulationradius},
        {"getsimulationradius", getsimulationradius},
        {"readfile", readfile},
        {"writefile", writefile},
        {"appendfile", appendfile},
        {"listfiles", listfiles},
        {"isfile", isfile},
        {"isfolder", isfolder},
        {"makefolder", makefolder},
        {"delfile", delfile},
        {"delfolder", delfolder},
        {"deletefile", deletefile},
        {"deletefolder", deletefolder},
        {"getcustomasset", getcustomasset},
        {"getasset", getasset},
        {"request", request},
        {"http_request", http_request},
        {"httprequest", httprequest},
        {"request_async", request_async},
        {"setclipboard", setclipboard},
        {"getclipboard", getclipboard},
        {"toclipboard", toclipboard},
        {"setrbxclipboard", setrbxclipboard},
        {"queue_on_teleport", queue_on_teleport},
        {"queueonteleport", queueonteleport},
        {"setfpscap", setfpscap},
        {"getfpscap", getfpscap},
        {"setfpsmax", setfpsmax},
        {"getfpsmax", getfpsmax},
        {"identifyexecutor", identifyexecutor},
        {"getexecutorname", getexecutorname},
        {"getexecutorversion", getexecutorversion},
        {"gethwid", gethwid},
        {"get_hwid", get_hwid},
        {"getdeviceid", getdeviceid},
        {"getsystemid", getsystemid},
        {"isrbxactive", isrbxactive},
        {"isgameactive", isgameactive},
        {"iswindowactive", iswindowactive},
        {"getmouseposition", getmouseposition},
        {"getpressedkey", getpressedkey},
        {"getpressedkeys", getpressedkeys},
        {"isleftclicked", isleftclicked},
        {"isrightclicked", isrightclicked},
        {"isleftpressed", isleftpressed},
        {"isrightpressed", isrightpressed},
        {"keypress", keypress},
        {"keyrelease", keyrelease},
        {"mouse1click", mouse1click},
        {"mouse1press", mouse1press},
        {"mouse1release", mouse1release},
        {"mouse2click", mouse2click},
        {"mouse2press", mouse2press},
        {"mouse2release", mouse2release},
        {"mousemoveabs", mousemoveabs},
        {"mousemoverel", mousemoverel},
        {"mousescroll", mousescroll},
        {"fireclickdetector", fireclickdetector},
        {"firetouchinterest", firetouchinterest},
        {"fireproximityprompt", fireproximityprompt},
        {"fireproximitypromptbegin", fireproximitypromptbegin},
        {"fireproximitypromptend", fireproximitypromptend},
        {"rconsolecreate", rconsolecreate},
        {"rconsoledestroy", rconsoledestroy},
        {"rconsoleclear", rconsoleclear},
        {"rconsolename", rconsolename},
        {"rconsoleprint", rconsoleprint},
        {"rconsolewarn", rconsolewarn},
        {"rconsoleerr", rconsoleerr},
        {"rconsoleinfo", rconsoleinfo},
        {"rconsoleinput", rconsoleinput},
        {"consolecreate", consolecreate},
        {"consoledestroy", consoledestroy},
        {"consoleclear", consoleclear},
        {"consolename", consolename},
        {"consoleprint", consoleprint},
        {"consolewarn", consolewarn},
        {"consoleerr", consoleerr},
        {"consoleinfo", consoleinfo},
        {"consoleinput", consoleinput},
        {"messagebox", messagebox},
        {"saveinstance", saveinstance},
        {"saveplace", saveplace},
        {"setfflag", setfflag},
        {"getfflag", getfflag},
        {"setdfflag", setdfflag},
        {"getdfflag", getdfflag},
        {"setfastflag", setfastflag},
        {"getfastflag", getfastflag},
        {"isrenderobj", isrenderobj},
        {"getrenderproperty", getrenderproperty},
        {"setrenderproperty", setrenderproperty},
        {"cleardrawcache", cleardrawcache},
        {"gethui", gethui},
        {"get_hidden_gui", get_hidden_gui},
        {"gethiddengui", gethiddengui},
        {"protect_gui", protect_gui},
        {"unprotect_gui", unprotect_gui},
        {"protectgui", protectgui},
        {"unprotectgui", unprotectgui},
        {"base64_encode", base64_encode},
        {"base64_decode", base64_decode},
        {"base64encode", base64encode},
        {"base64decode", base64decode},
        {"lz4compress", lz4compress},
        {"lz4decompress", lz4decompress},
        {"zstdcompress", zstdcompress},
        {"zstddecompress", zstddecompress},
        {"zlibcompress", zlibcompress},
        {"zlibdecompress", zlibdecompress},
        {"gzipcompress", gzipcompress},
        {"gzipdecompress", gzipdecompress},
        {"compress", compress},
        {"decompress", decompress},
        {"pointer_to_userdata", pointer_to_userdata},
        {"get_overlay_fps", get_overlay_fps},
        {"is_forcefield_check_active", is_forcefield_check_active},
        {"is_local_health_check_active", is_local_health_check_active},
        {"is_team_check_active", is_team_check_active},
        {"ismenuopened", ismenuopened},
        {"send_notification", send_notification},
        {"block_roblox_window", block_roblox_window},
        {"add_model_data", add_model_data},
        {"edit_model_data", edit_model_data},
        {"remove_model_data", remove_model_data},
        {"clear_model_data", clear_model_data},
        {"override_local_data", override_local_data},
        {"clear_local_data", clear_local_data},
        {"get_model_data", get_model_data},
        {"get_local_data", get_local_data}
    }

    for i = 1, #global_function_candidates do
        local entry = global_function_candidates[i]
        catalog_probe(entry[1], entry[2])
    end

    local function namespace_group(label, object, names)
        for name in string.gmatch(names, "%S+") do
            catalog_probe(
                label .. "." .. name,
                first_present(object, name)
            )
        end
    end

    local namespace_groups = {
        {
            "math",
            math,
            [[
            abs acos asin atan atan2 ceil clamp cos cosh deg exp
            floor fmod frexp ldexp log log10 max min modf noise pow
            rad random randomseed round sign sin sinh sqrt tan tanh
            ]]
        },
        {
            "string",
            string,
            [[
            byte char dump find format gmatch gsub len lower match
            pack packsize rep reverse split sub unpack upper
            ]]
        },
        {
            "table",
            table,
            [[
            clear clone concat create find foreach foreachi freeze
            getn insert isfrozen maxn move pack remove sort unpack
            ]]
        },
        {
            "coroutine",
            coroutine,
            [[
            close create isyieldable resume running status wrap yield
            ]]
        },
        {
            "utf8",
            utf8,
            [[
            char codes codepoint graphemes len nfcnormalize
            nfdnormalize offset
            ]]
        },
        {
            "bit32",
            bit32,
            [[
            arshift band bnot bor btest bxor countlz countrz extract
            lrotate lshift replace rrotate rshift
            ]]
        },
        {
            "buffer",
            buffer,
            [[
            copy create fill fromstring len readf32 readf64 readi8
            readi16 readi32 readstring readu8 readu16 readu32 tostring
            writef32 writef64 writei8 writei16 writei32 writestring
            writeu8 writeu16 writeu32
            ]]
        },
        {
            "vector",
            vector,
            [[
            abs angle ceil clamp create cross dot floor magnitude max
            min normalize sign
            ]]
        },
        {
            "os",
            os,
            [[
            clock date difftime execute exit getenv remove rename
            setlocale time tmpname
            ]]
        },
        {
            "debug",
            debug,
            [[
            dumpheap info profilebegin profileend resetmemorycategory
            setmemorycategory traceback getconstant getconstants
            setconstant getproto getprotos getupvalue getupvalues
            setupvalue getstack setstack getinfo getlocal setlocal
            getmetatable setmetatable gethook sethook
            upvalueid upvaluejoin
            ]]
        },
        {
            "task",
            task,
            [[
            cancel defer delay desynchronize spawn synchronize wait
            ]]
        },
        {
            "luau",
            luau,
            [[
            compile load
            ]]
        },
        {
            "Vector2",
            Vector2,
            [[
            new
            ]]
        },
        {
            "Vector2int16",
            Vector2int16,
            [[
            new
            ]]
        },
        {
            "Vector3",
            Vector3,
            [[
            new
            ]]
        },
        {
            "Vector3int16",
            Vector3int16,
            [[
            new
            ]]
        },
        {
            "CFrame",
            CFrame,
            [[
            new Angles fromAxisAngle fromEulerAnglesXYZ
            fromEulerAnglesYXZ fromOrientation fromMatrix lookAt
            ]]
        },
        {
            "Color3",
            Color3,
            [[
            new fromRGB fromHSV fromHex
            ]]
        },
        {
            "UDim",
            UDim,
            [[
            new
            ]]
        },
        {
            "UDim2",
            UDim2,
            [[
            new fromOffset fromScale
            ]]
        },
        {
            "Rect",
            Rect,
            [[
            new
            ]]
        },
        {
            "Region3",
            Region3,
            [[
            new
            ]]
        },
        {
            "Region3int16",
            Region3int16,
            [[
            new
            ]]
        },
        {
            "Ray",
            Ray,
            [[
            new
            ]]
        },
        {
            "BrickColor",
            BrickColor,
            [[
            new palette random White Gray DarkGray Black Red Yellow
            Green Blue
            ]]
        },
        {
            "NumberRange",
            NumberRange,
            [[
            new
            ]]
        },
        {
            "NumberSequence",
            NumberSequence,
            [[
            new
            ]]
        },
        {
            "NumberSequenceKeypoint",
            NumberSequenceKeypoint,
            [[
            new
            ]]
        },
        {
            "ColorSequence",
            ColorSequence,
            [[
            new
            ]]
        },
        {
            "ColorSequenceKeypoint",
            ColorSequenceKeypoint,
            [[
            new
            ]]
        },
        {
            "TweenInfo",
            TweenInfo,
            [[
            new
            ]]
        },
        {
            "PhysicalProperties",
            PhysicalProperties,
            [[
            new
            ]]
        },
        {
            "PathWaypoint",
            PathWaypoint,
            [[
            new
            ]]
        },
        {
            "Random",
            Random,
            [[
            new
            ]]
        },
        {
            "DateTime",
            DateTime,
            [[
            now fromUnixTimestamp fromUnixTimestampMillis
            fromUniversalTime fromLocalTime fromIsoDate
            ]]
        },
        {
            "Font",
            Font,
            [[
            new fromEnum
            ]]
        },
        {
            "Faces",
            Faces,
            [[
            new
            ]]
        },
        {
            "Axes",
            Axes,
            [[
            new
            ]]
        },
        {
            "OverlapParams",
            OverlapParams,
            [[
            new
            ]]
        },
        {
            "RaycastParams",
            RaycastParams,
            [[
            new
            ]]
        },
        {
            "CatalogSearchParams",
            CatalogSearchParams,
            [[
            new
            ]]
        },
        {
            "FloatCurveKey",
            FloatCurveKey,
            [[
            new
            ]]
        },
        {
            "RotationCurveKey",
            RotationCurveKey,
            [[
            new
            ]]
        },
        {
            "SharedTable",
            SharedTable,
            [[
            new clone cloneAndFreeze increment update size clear
            isFrozen freeze
            ]]
        },
        {
            "Secret",
            Secret,
            [[
            fromLocalUser
            ]]
        },
        {
            "Instance",
            Instance,
            [[
            new
            ]]
        },
        {
            "Circle",
            Circle,
            [[
            new
            ]]
        },
        {
            "Image",
            Image,
            [[
            new
            ]]
        },
        {
            "Polyline",
            Polyline,
            [[
            new
            ]]
        },
        {
            "Square",
            Square,
            [[
            new
            ]]
        },
        {
            "Text",
            Text,
            [[
            new
            ]]
        },
        {
            "Triangle",
            Triangle,
            [[
            new
            ]]
        },
        {
            "PointInstance",
            PointInstance,
            [[
            new
            ]]
        },
        {
            "Point3D",
            Point3D,
            [[
            new
            ]]
        },
        {
            "Signal",
            Signal,
            [[
            new Connect connect Once once Wait wait Fire fire
            ]]
        },
        {
            "Drawing",
            Drawing,
            [[
            new clear attach Clear isrenderobj getrenderproperty
            setrenderproperty
            ]]
        },
        {
            "DrawingImmediate",
            DrawingImmediate,
            [[
            Line Circle FilledCircle Triangle FilledTriangle
            Rectangle FilledRectangle Quad FilledQuad Polyline Text
            OutlinedText Image GetTextBounds
            ]]
        },
        {
            "memory",
            memory,
            [[
            changed readbits writebits rtti readstring writestring
            readvector writevector readbuffer writebuffer readi8 readu8
            readi16 readu16
            readi32 readu32 readi64 readu64 readf32 readf64 writei8
            writeu8 writei16 writeu16 writei32 writeu32 writei64
            writeu64 writef32 writef64
            ]]
        },
        {
            "crypt",
            crypt,
            [[
            encrypt decrypt random random_deterministic pwhash
            pwhash_str pwhash_str_verify generatebytes generatekey
            derive custom_encrypt custom_decrypt sha1 sha256 sha384
            sha512 md5 blake2b
            ]]
        },
        {
            "crypto",
            crypto,
            [[
            encrypt decrypt hash random generatebytes generatekey
            ]]
        },
        {
            "base64",
            base64,
            [[
            encode decode
            ]]
        },
        {
            "lz4",
            lz4,
            [[
            compress decompress
            ]]
        },
        {
            "cache",
            cache,
            [[
            invalidate iscached replace compareinstances cloneref
            ]]
        },
        {
            "WebSocket",
            WebSocket,
            [[
            connect Connect
            ]]
        },
        {
            "websocket",
            websocket,
            [[
            connect Connect
            ]]
        },
        {
            "WebsocketClient",
            WebsocketClient,
            [[
            new
            ]]
        },
        {
            "RemoteSpy",
            (
                type(RemoteSpy) == "table"
                    and RemoteSpy
                or type(remotespy) == "table"
                    and remotespy
                or type(remote_spy) == "table"
                    and remote_spy
                or nil
            ),
            [[
            start Start stop Stop enable Enable disable Disable
            hook Hook unhook Unhook getlogs GetLogs clearlogs ClearLogs
            ]]
        },
        {
            "game",
            game,
            [[
            FindService GetObjects HttpGetAsync HttpPostAsync
            IsLoaded GetJobsInfo
            GetEngineFeature SetEngineFeature GetFastFlag
            SetFastFlagForTesting
            ]]
        },
        {
            "workspace",
            workspace,
            [[
            Raycast Blockcast Shapecast Spherecast
            GetPartBoundsInBox GetPartBoundsInRadius GetPartsInPart
            FindPartOnRay FindPartOnRayWithIgnoreList
            FindPartOnRayWithWhitelist FindPartsInRegion3
            FindPartsInRegion3WithIgnoreList
            FindPartsInRegion3WithWhiteList GetRealPhysicsFPS
            GetNumAwakeParts GetServerTimeNow BulkMoveTo
            MakeJoints BreakJoints
            ]]
        },
        {
            "Players",
            players_service,
            [[
            GetPlayers GetPlayerByUserId GetUserIdFromNameAsync
            GetNameFromUserIdAsync GetUserThumbnailAsync GetFriendsAsync
            GetHumanoidDescriptionFromUserId
            GetHumanoidDescriptionFromOutfitId
            CreateHumanoidModelFromDescription
            CreateHumanoidModelFromUserId
            GetCharacterAppearanceAsync GetCharacterAppearanceInfoAsync
            GetUserInfosByUserIdsAsync ReportAbuse
            ]]
        },
        {
            "RunService",
            run_service,
            [[
            BindToRenderStep UnbindFromRenderStep IsClient IsServer
            IsStudio IsRunning IsRunMode IsEdit IsEditMode
            SetRobloxGuiFocused GetRobloxVersion
            GetRobloxClientChannel GetCoreScriptVersion
            ]]
        },
        {
            "UserInputService",
            user_input_service,
            [[
            IsKeyDown GetConnectedGamepads GetGamepadState
            GetNavigationGamepads
            GetSupportedGamepadKeyCodes SetNavigationGamepad
            GetDeviceAcceleration GetDeviceGravity GetDeviceRotation
            GetLastInputType GetStringForKeyCode GetImageForKeyCode
            IsGamepadButtonDown IsNavigationGamepad
            SetMouseIconOverride RequestKeyboard
            ]]
        },
        {
            "Lighting",
            lighting_service,
            [[
            GetMinutesAfterMidnight SetMinutesAfterMidnight
            GetMoonDirection GetSunDirection
            ]]
        }
    }

    for i = 1, #namespace_groups do
        local group = namespace_groups[i]
        namespace_group(group[1], group[2], group[3])
    end

    -- These bridge methods are commonly implemented through Luau's
    -- NAMECALL opcode and can legitimately be absent from ordinary
    -- `object.Method` indexing. Probe the real `object:Method(...)`
    -- form so the surface score reflects what external code can call.
    catalog_namecall_probe(
        "UserInputService:GetMouseLocation",
        function()
            if user_input_service == nil then
                error("no UserInputService fixture available", 0)
            end

            return user_input_service:GetMouseLocation()
        end
    )

    catalog_namecall_probe(
        "UserInputService:IsMouseButtonPressed",
        function()
            if user_input_service == nil then
                error("no UserInputService fixture available", 0)
            end

            local mouse_button = nil
            pcall(function()
                mouse_button = Enum.UserInputType.MouseButton1
            end)

            return user_input_service:IsMouseButtonPressed(
                mouse_button
            )
        end
    )

    catalog_namecall_probe(
        "UserInputService:SetMouseLocation",
        function()
            if user_input_service == nil then
                error("no UserInputService fixture available", 0)
            end

            local current = user_input_service:GetMouseLocation()
            return user_input_service:SetMouseLocation(
                current.X,
                current.Y
            )
        end
    )

    catalog_namecall_probe(
        "game:GetService",
        function()
            if game == nil then
                error("no DataModel fixture available", 0)
            end

            return game:GetService("Workspace")
        end
    )

    catalog_namecall_probe(
        "game:GetPing",
        function()
            if game == nil then
                error("no DataModel fixture available", 0)
            end

            return game:GetPing()
        end
    )

    catalog_namecall_probe(
        "game:GetHwid",
        function()
            if game == nil then
                error("no DataModel fixture available", 0)
            end

            return game:GetHwid()
        end
    )

    catalog_namecall_probe(
        "game:HttpGet",
        function()
            if game == nil then
                error("no DataModel fixture available", 0)
            end

            return game:HttpGet(nil)
        end,
        true
    )

    catalog_namecall_probe(
        "game:HttpPost",
        function()
            if game == nil then
                error("no DataModel fixture available", 0)
            end

            return game:HttpPost(nil, nil)
        end,
        true
    )

    catalog_namecall_probe(
        "Camera:WorldToScreenPoint",
        function()
            if workspace == nil then
                error("no Workspace fixture available", 0)
            end

            local camera = workspace.CurrentCamera
            if camera == nil then
                error("no Camera fixture available", 0)
            end

            return camera:WorldToScreenPoint(
                Vector3.new(0, 0, 0)
            )
        end
    )

    local catalog_instance_new =
        first_present(Instance, "new", "New")

    local function create_catalog_basepart()
        if type(catalog_instance_new) ~= "function" then
            return nil
        end

        local ok, object = pcall(catalog_instance_new, "Part")
        if ok then
            return object
        end

        return nil
    end

    local catalog_disposable_basepart =
        create_catalog_basepart()
    local catalog_peer_basepart =
        create_catalog_basepart()
    local catalog_basepart =
        catalog_disposable_basepart or first_basepart

    local function require_catalog_basepart()
        if catalog_basepart == nil then
            error("no BasePart fixture available", 0)
        end

        return catalog_basepart
    end

    local function require_disposable_basepart()
        if catalog_disposable_basepart == nil then
            error("no BasePart fixture available", 0)
        end

        return catalog_disposable_basepart
    end

    local catalog_tag = "__eUNC_SurfaceProbe"
    local catalog_attribute = "__eUNC_SurfaceProbe"
    local missing_instance_name =
        "__eUNC_Missing_Surface_Child__"

    local basepart_namecall_probes = {
        {
            "AddTag",
            function()
                local object = require_disposable_basepart()
                object:AddTag(catalog_tag)
            end
        },
        {
            "RemoveTag",
            function()
                local object = require_disposable_basepart()
                object:RemoveTag(catalog_tag)
            end
        },
        {
            "HasTag",
            function()
                local object = require_catalog_basepart()
                return object:HasTag(catalog_tag)
            end
        },
        {
            "GetTags",
            function()
                local object = require_catalog_basepart()
                return object:GetTags()
            end
        },
        {
            "ClearTags",
            function()
                local object = require_disposable_basepart()
                object:ClearTags()
            end
        },
        {
            "GetAttribute",
            function()
                local object = require_catalog_basepart()
                return object:GetAttribute(catalog_attribute)
            end
        },
        {
            "GetAttributes",
            function()
                local object = require_catalog_basepart()
                return object:GetAttributes()
            end
        },
        {
            "GetAttributeChangedSignal",
            function()
                local object = require_catalog_basepart()
                return object:GetAttributeChangedSignal(
                    catalog_attribute
                )
            end
        },
        {
            "SetAttribute",
            function()
                local object = require_disposable_basepart()
                object:SetAttribute(catalog_attribute, true)
                object:SetAttribute(catalog_attribute, nil)
            end
        },
        {
            "GetChildren",
            function()
                local object = require_catalog_basepart()
                return object:GetChildren()
            end
        },
        {
            "GetDescendants",
            function()
                local object = require_catalog_basepart()
                return object:GetDescendants()
            end
        },
        {
            "GetFullName",
            function()
                local object = require_catalog_basepart()
                return object:GetFullName()
            end
        },
        {
            "FindFirstDescendant",
            function()
                local object = require_catalog_basepart()
                return object:FindFirstDescendant(
                    missing_instance_name
                )
            end
        },
        {
            "FindFirstAncestor",
            function()
                local object = require_catalog_basepart()
                return object:FindFirstAncestor(
                    missing_instance_name
                )
            end
        },
        {
            "FindFirstAncestorOfClass",
            function()
                local object = require_catalog_basepart()
                return object:FindFirstAncestorOfClass("Workspace")
            end
        },
        {
            "FindFirstAncestorWhichIsA",
            function()
                local object = require_catalog_basepart()
                return object:FindFirstAncestorWhichIsA("Workspace")
            end
        },
        {
            "FindFirstChild",
            function()
                local object = require_catalog_basepart()
                return object:FindFirstChild(missing_instance_name)
            end
        },
        {
            "FindFirstChildOfClass",
            function()
                local object = require_catalog_basepart()
                return object:FindFirstChildOfClass("Folder")
            end
        },
        {
            "FindFirstChildWhichIsA",
            function()
                local object = require_catalog_basepart()
                return object:FindFirstChildWhichIsA("Instance")
            end
        },
        {
            "WaitForChild",
            function()
                local object = require_catalog_basepart()
                return object:WaitForChild(missing_instance_name, 0)
            end
        },
        {
            "IsA",
            function()
                local object = require_catalog_basepart()
                return object:IsA("BasePart")
            end
        },
        {
            "IsAncestorOf",
            function()
                local object = require_catalog_basepart()
                return object:IsAncestorOf(
                    catalog_peer_basepart or object
                )
            end
        },
        {
            "IsDescendantOf",
            function()
                local object = require_catalog_basepart()
                return object:IsDescendantOf(workspace or object)
            end
        },
        {
            "Clone",
            function()
                local object = require_catalog_basepart()
                local clone = object:Clone()

                if clone ~= nil then
                    pcall(function()
                        clone:Destroy()
                    end)
                end

                return clone
            end
        },
        {
            "Destroy",
            function()
                local object = create_catalog_basepart()
                if object == nil then
                    error("no BasePart fixture available", 0)
                end

                object:Destroy()
            end
        },
        {
            "ClearAllChildren",
            function()
                local object = require_disposable_basepart()
                object:ClearAllChildren()
            end
        },
        {
            "GetPropertyChangedSignal",
            function()
                local object = require_catalog_basepart()
                return object:GetPropertyChangedSignal("Name")
            end
        },
        {
            "ApplyAngularImpulse",
            function()
                local object = require_disposable_basepart()
                object:ApplyAngularImpulse(Vector3.new(0, 0, 0))
            end
        },
        {
            "ApplyImpulse",
            function()
                local object = require_disposable_basepart()
                object:ApplyImpulse(Vector3.new(0, 0, 0))
            end
        },
        {
            "ApplyImpulseAtPosition",
            function()
                local object = require_disposable_basepart()
                object:ApplyImpulseAtPosition(
                    Vector3.new(0, 0, 0),
                    object.Position
                )
            end
        },
        {
            "CanCollideWith",
            function()
                local object = require_catalog_basepart()
                return object:CanCollideWith(
                    catalog_peer_basepart or object
                )
            end
        },
        {
            "GetConnectedParts",
            function()
                local object = require_catalog_basepart()
                return object:GetConnectedParts(true)
            end
        },
        {
            "GetJoints",
            function()
                local object = require_catalog_basepart()
                return object:GetJoints()
            end
        },
        {
            "GetMass",
            function()
                local object = require_catalog_basepart()
                return object:GetMass()
            end
        },
        {
            "GetNoCollisionConstraints",
            function()
                local object = require_catalog_basepart()
                return object:GetNoCollisionConstraints()
            end
        },
        {
            "GetRootPart",
            function()
                local object = require_catalog_basepart()
                return object:GetRootPart()
            end
        },
        {
            "GetTouchingParts",
            function()
                local object = require_catalog_basepart()
                return object:GetTouchingParts()
            end
        },
        {
            "IsGrounded",
            function()
                local object = require_catalog_basepart()
                return object:IsGrounded()
            end
        },
        {
            "MakeJoints",
            function()
                local object = require_disposable_basepart()
                object:MakeJoints()
            end
        },
        {
            "BreakJoints",
            function()
                local object = require_disposable_basepart()
                object:BreakJoints()
            end
        },
        {
            "Resize",
            function()
                local object = require_disposable_basepart()
                local old_size = object.Size
                local old_cframe = object.CFrame
                local normal_id = Enum.NormalId.Top
                local ok, result = pcall(function()
                    return object:Resize(normal_id, 1)
                end)

                pcall(function()
                    object.Size = old_size
                    object.CFrame = old_cframe
                end)

                if not ok then
                    error(result, 0)
                end

                return result
            end
        }
    }

    for i = 1, #basepart_namecall_probes do
        local probe = basepart_namecall_probes[i]
        catalog_namecall_probe(
            "BasePart:" .. probe[1],
            probe[2]
        )
    end

    if catalog_peer_basepart ~= nil then
        pcall(function()
            catalog_peer_basepart:Destroy()
        end)
    end

    if catalog_disposable_basepart ~= nil then
        pcall(function()
            catalog_disposable_basepart:Destroy()
        end)
    end

    -- Check the real Roblox remote methods without firing any live
    -- remote. Prefer a live sample, then a disposable unparented
    -- Instance when Instance.new is available.
    local remote_class_specs = {
        {
            "RemoteEvent",
            "FireServer"
        },
        {
            "UnreliableRemoteEvent",
            "FireServer"
        },
        {
            "RemoteFunction",
            "InvokeServer"
        }
    }
    local remote_samples = {}
    local remote_sources = {}

    if game ~= nil then
        local storage_ok, storage = pcall(function()
            return game:GetService("ReplicatedStorage")
        end)

        if storage_ok and storage ~= nil then
            remote_sources[#remote_sources + 1] = storage
        end
    end

    if workspace ~= nil then
        remote_sources[#remote_sources + 1] = workspace
    end

    for source_index = 1, #remote_sources do
        local source = remote_sources[source_index]
        local descendants_ok, descendants = pcall(function()
            return source:GetDescendants()
        end)

        if descendants_ok and type(descendants) == "table" then
            local limit = math.min(#descendants, 2500)

            for descendant_index = 1, limit do
                local object = descendants[descendant_index]
                local class_name = nil

                pcall(function()
                    class_name = object.ClassName
                end)

                if (
                    class_name == "RemoteEvent"
                    or class_name == "UnreliableRemoteEvent"
                    or class_name == "RemoteFunction"
                ) and remote_samples[class_name] == nil
                then
                    remote_samples[class_name] = object
                end
            end
        end
    end

    local instance_new =
        first_present(Instance, "new", "New")

    for i = 1, #remote_class_specs do
        local specification = remote_class_specs[i]
        local class_name = specification[1]
        local object = remote_samples[class_name]
        local disposable = false

        if object == nil and type(instance_new) == "function" then
            local create_ok, created =
                pcall(instance_new, class_name)

            if create_ok and created ~= nil then
                object = created
                disposable = true
            end
        end

        namespace_group(
            class_name,
            object,
            specification[2]
        )

        if disposable and object ~= nil then
            pcall(function()
                object:Destroy()
            end)
        end
    end

    local nested_namespace_groups = {
        {
            "crypt.hash",
            first_present(crypt, "hash"),
            "sha1 sha256 sha384 sha512 md5 blake2b"
        },
        {
            "crypt.base64",
            first_present(crypt, "base64"),
            "encode decode"
        },
        {
            "crypt.secretbox",
            first_present(crypt, "secretbox"),
            "seal open"
        },
        {
            "crypt.aead",
            first_present(crypt, "aead"),
            "encrypt decrypt"
        },
        {
            "crypt.box",
            first_present(crypt, "box"),
            "keypair encrypt decrypt seal open beforenm"
        },
        {
            "crypt.sign",
            first_present(crypt, "sign"),
            "keypair sign open detached verify_detached"
        },
        {
            "crypt.hmac",
            first_present(crypt, "hmac"),
            "sha256 sha512"
        },
        {
            "crypt.hkdf",
            first_present(crypt, "hkdf"),
            "sha256"
        },
        {
            "crypt.json",
            first_present(crypt, "json"),
            "encode decode"
        },
        {
            "crypt.hexadecimal",
            first_present(crypt, "hexadecimal"),
            "encode decode"
        }
    }

    for i = 1, #nested_namespace_groups do
        local group = nested_namespace_groups[i]
        namespace_group(group[1], group[2], group[3])
    end

    info(
        "Broad function catalog result",
        tostring(catalog_available)
            .. "/"
            .. tostring(catalog_total)
            .. " functions available; missing="
            .. tostring(catalog_missing)
            .. "; nonfunctions="
            .. tostring(catalog_nonfunction)
    )
end

-- ============================================================
-- SUMMARY
-- ============================================================
print("")
print("========================================")

if #failure_records > 0 then
    print("  FAILED TEST INDEX")
    print("========================================")

    for i = 1, #failure_records do
        local failure = failure_records[i]
        emit_warn(
            "["
            .. tostring(i)
            .. "] ["
            .. failure.status
            .. "] ["
            .. failure.kind
            .. " / "
            .. failure.category
            .. "] "
            .. failure.label
            .. " | "
            .. failure.detail
        )

        if failure.diagnosis ~= nil then
            emit_warn("    WHY: " .. failure.diagnosis)
        end

        -- Some external VMs enforce a short uninterrupted scheduler
        -- budget. Yield between small output batches so a complete
        -- failure index can be printed without dropping any entries.
        if i % FAILURE_INDEX_YIELD_INTERVAL == 0
            and type(task) == "table"
            and type(task.wait) == "function"
        then
            task.wait(0)
        end
    end

    print("")
    print("========================================")
end

local function score_text(stats)
    local percent = 0
    if stats.counted > 0 then
        percent =
            math.floor(
                (stats.passed / stats.counted) * 1000
            ) / 10
    end

    return tostring(stats.passed)
        .. "/"
        .. tostring(stats.counted)
        .. " ("
        .. tostring(percent)
        .. "%)"
        .. " | failed="
        .. tostring(stats.failed)
        .. " | missing="
        .. tostring(stats.missing)
        .. " | skipped="
        .. tostring(stats.skipped)
end

local compatibility_stats =
    result_kind_stats.compatibility or new_stats()
local extension_stats =
    result_kind_stats.extension or new_stats()
local surface_stats =
    result_kind_stats.surface or new_stats()
local overall_stats = {
    passed = pass_count,
    failed = fail_count,
    missing = missing_count,
    skipped = skip_count,
    counted = pass_count + fail_count + missing_count
}

print("  CATEGORY RESULTS")
print("========================================")

local category_names = {}
for category in pairs(category_stats) do
    category_names[#category_names + 1] = category
end
table.sort(category_names)

for i = 1, #category_names do
    local category = category_names[i]
    print(
        INFO
        .. " "
        .. category
        .. ": "
        .. score_text(category_stats[category])
    )
end

if #failure_records == 0 then
    print(PASS .. " All counted outcomes passed!")
else
    emit_warn(
        FAIL
        .. " "
        .. tostring(#failure_records)
        .. " failed or missing outcomes are indexed above"
    )
end

print(
    INFO
    .. " Severe-extension signatures retained as supplemental tests: "
    .. tostring(SEVERE_EXTENSION_SIGNATURE_COUNT)
)

print("")
print("========================================")
print("  RESULTS")
print("========================================")
print(
    INFO
    .. " Functional compatibility score: "
    .. score_text(compatibility_stats)
)
print(
    INFO
    .. " Supplemental VM-extension score: "
    .. score_text(extension_stats)
)
print(
    INFO
    .. " Raw API surface score: "
    .. score_text(surface_stats)
)
print(
    INFO
    .. " Overall counted outcomes: "
    .. score_text(overall_stats)
)
print("========================================")
