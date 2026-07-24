-- ==========================================================
-- Severe Luau VM - Exhaustive External Capability Test Suite
--
-- Designed around Severe's supplied API documentation and the
-- behavior observed in previous runs.
--
-- Every configurable category is enabled in this build. Tests that
-- require a valid user-supplied memory address still cannot run while
-- that address is nil.
--
-- Optional or undocumented compatibility globals are reported as
-- [INFO]. A failed documented behavior prints a [WHY] diagnosis.
-- ==========================================================

local PASS = "[PASS]"
local FAIL = "[FAIL]"
local INFO = "[INFO]"
local SEP  = "----------------------------------------"

-- ============================================================
-- EXHAUSTIVE TEST CONFIGURATION
-- ============================================================
--
-- The suite contains tests that can change system, game, network,
-- overlay, or process state. All categories below are enabled.
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
    run_destructive_clear_functions = true,
    run_http_get = true,
    run_http_post = true,
    run_hwid_read = true,
    run_websocket = true,
    run_immediate_drawing_calls = true,
    run_drawing_clear = true,
    run_memory_reads = true,
    run_memory_writes = true
}

-- Change these only when enabling the matching tests.
local EXTERNAL_TEST_VALUES = {
    http_get_url = "https://example.com/",
    http_post_url = "https://httpbin.org/post",
    http_post_body = "{\"severe_vm_test\":true}",
    http_post_content_type = "application/json",
    websocket_url = "wss://echo.websocket.events",

    -- A valid address belonging to a disposable test allocation or
    -- another location you are certain is safe to read.
    memory_read_address = nil,

    -- A valid writable scratch address. The test writes the same value
    -- it read and then verifies it, minimizing state changes.
    memory_write_address = nil,

    memory_buffer_size = 16,
    input_test_key = 0x87
}


local pass_count = 0
local fail_count = 0
local failure_records = {}

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

local function check(label, condition, extra)
    if condition then
        pass_count = pass_count + 1
        print(PASS .. " " .. label)
        return true
    end

    fail_count = fail_count + 1

    local detail = extra
    if detail == nil then
        detail = "condition evaluated to false"
    end

    warn(FAIL .. " " .. label .. " | " .. value_to_string(detail))

    local diagnosis = diagnose_failure(label, detail)
    if diagnosis ~= nil then
        warn("[WHY] " .. diagnosis)
    end

    failure_records[#failure_records + 1] = {
        label = label,
        detail = value_to_string(detail),
        diagnosis = diagnosis
    }

    return false
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

local function section(name)
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
-- 1. DOCUMENTED CORE GLOBALS
-- ============================================================
section("1. Documented Core Globals")

check("print is a function", type(print) == "function")
check("warn is a function", type(warn) == "function")
check(
    "load is a function",
    type(load) == "function",
    "actual type=" .. type(load)
        .. "; luau.load type="
        .. (type(luau) == "table" and type(luau.load) or "nil")
)
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

-- These are compatibility probes because they are not required by
-- the supplied Severe API documentation.
info("loadstring global", type(loadstring))
info("getgenv global", type(getgenv))
info("Instance.new", Instance and type(Instance.new) or "nil")
info("ui global", type(ui))
info("fragment_ui global", type(fragment_ui))
info("input namespace", type(input))

if type(getgenv) == "function" then
    local ok, genv = pcall(getgenv)
    check("getgenv() returns a table", ok and type(genv) == "table", genv)
end

-- ============================================================
-- 2. SANDBOX / FILESYSTEM GLOBALS
-- ============================================================
section("2. Sandbox and Filesystem")

-- io/package/require are expected to remain unavailable. os and
-- debug were observed as present, so they are capability-tested rather
-- than incorrectly required to be nil.
check("io is nil", io == nil, "actual type=" .. type(io))
check("package is nil", package == nil, "actual type=" .. type(package))
check("require is nil", require == nil, "actual type=" .. type(require))

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

-- Documented sandboxed filesystem functions.
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
            warn(
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

    local bad_compile_ok, bad_compile_result, bad_compile_extra =
        pcall(
            compile_source,
            "local ="
        )

    local invalid_rejected = bad_compile_ok == false
    local invalid_detail = bad_compile_result

    if bad_compile_ok then
        if bad_compile_result == nil then
            invalid_rejected = true
            invalid_detail = bad_compile_extra
        elseif type(bad_compile_result) == "string"
            and type(luau.load) == "function"
        then
            local bad_load_ok, bad_function_or_error =
                pcall(
                    luau.load,
                    bad_compile_result,
                    {
                        debugName = "InvalidSourceTest",
                        injectGlobals = true,
                        codegenEnabled = false
                    }
                )

            invalid_rejected =
                bad_load_ok == false
                or type(bad_function_or_error) ~= "function"

            invalid_detail =
                "compile returned string; luau.load ok="
                .. value_to_string(bad_load_ok)
                .. " result="
                .. value_to_string(bad_function_or_error)
        else
            invalid_detail =
                "compile unexpectedly returned "
                .. type(bad_compile_result)
                .. ": "
                .. value_to_string(bad_compile_result)
        end
    end

    check(
        "invalid source is rejected by compile/load pipeline",
        invalid_rejected,
        invalid_detail
    )
else
    info("Compilation tests", "skipped because luau.compile is missing")
end

-- ============================================================
-- 4. MISCELLANEOUS DOCUMENTED API
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

local menu_function = is_menu_opened or ismenuopened
check(
    "is_menu_opened/ismenuopened is available",
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
    and type(task.wait) == "function"
then
    local spawn_fired = false
    local spawn_ok, spawn_thread = pcall(task.spawn, function()
        spawn_fired = true
    end)

    check(
        "task.spawn returns a thread",
        spawn_ok and type(spawn_thread) == "thread",
        spawn_thread
    )

    local defer_fired = false
    local defer_ok, defer_thread = pcall(task.defer, function()
        defer_fired = true
    end)

    check(
        "task.defer returns a thread",
        defer_ok and type(defer_thread) == "thread",
        defer_thread
    )

    local delay_fired = false
    local delay_ok, delay_thread = pcall(task.delay, 0, function()
        delay_fired = true
    end)

    check(
        "task.delay returns a thread",
        delay_ok and type(delay_thread) == "thread",
        delay_thread
    )

    local wait_ok, elapsed = pcall(task.wait, 0)
    check(
        "task.wait(0) returns number",
        wait_ok and type(elapsed) == "number",
        elapsed
    )

    check("task.spawn callback fired", spawn_fired == true)
    check("task.defer callback fired after yielding", defer_fired == true)
    check("task.delay callback fired after yielding", delay_fired == true)

    if type(task.cancel) == "function" then
        local cancel_ok, cancel_thread = pcall(task.delay, 60, function()
            warn(FAIL .. " Cancelled delayed task unexpectedly fired")
        end)

        if cancel_ok and type(cancel_thread) == "thread" then
            local did_cancel, cancel_error = pcall(task.cancel, cancel_thread)
            check("task.cancel accepts delayed thread", did_cancel, cancel_error)
        else
            check("create delayed thread for task.cancel test", false, cancel_thread)
        end
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
section("12. Vector2 and Vector3")

check("Vector2.new is a function", Vector2 ~= nil and type(Vector2.new) == "function")
check("Vector3.new is a function", Vector3 ~= nil and type(Vector3.new) == "function")

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

        -- Some Severe builds currently reject this documented property.
        -- Keep it inside pcall so a missing property is reported instead
        -- of terminating the entire suite.
        test("Vector2.Magnitude is correct", function()
            local magnitude = v2.Magnitude
            return type(magnitude) == "number"
                and math.abs(magnitude - 5) < 0.0001,
                magnitude
        end)

        test("Vector2.Unit has magnitude 1", function()
            return math.abs(v2.Unit.Magnitude - 1) < 0.0001,
                v2.Unit.Magnitude
        end)

        test("Vector2:Dot works", function()
            return v2:Dot(Vector2.new(1, 0)) == 3
        end)

        test("Vector2:Cross works", function()
            return v2:Cross(Vector2.new(1, 0)) == -4
        end)

        test("Vector2:Lerp works", function()
            local result = v2:Lerp(Vector2.new(5, 6), 0.5)
            return result.X == 4 and result.Y == 5,
                value_to_string(result)
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

        test("Vector3:Dot works", function()
            return v3:Dot(Vector3.new(1, 0, 0)) == 1
        end)

        test("Vector3:Cross works", function()
            local result = v3:Cross(Vector3.new(0, 1, 0))
            return result.X == -3 and result.Y == 0 and result.Z == 1,
                value_to_string(result)
        end)

        test("Vector3:Lerp works", function()
            local result = v3:Lerp(Vector3.new(3, 4, 5), 0.5)
            return result.X == 2 and result.Y == 3 and result.Z == 4,
                value_to_string(result)
        end)

        test("Vector3 addition works", function()
            local result = v3 + Vector3.new(1, 1, 1)
            return result.X == 2 and result.Y == 3 and result.Z == 4
        end)

        test("Vector3 scalar multiplication works", function()
            local result = v3 * 2
            return result.X == 2 and result.Y == 4 and result.Z == 6
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
    info("WebsocketClient.new", type(WebsocketClient.new))
end

info("Signal", type(Signal))
if Signal ~= nil then
    info("Signal.new", type(Signal.new))
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
        end
    end
end

-- ============================================================
-- 19. VECTOR2 / VECTOR3 COMPLETE OPERATIONS
-- ============================================================
section("19. Vector2 and Vector3 Complete Operations")

if Vector2 ~= nil and type(Vector2.new) == "function" then
    local v = Vector2.new(6, 8)

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

if Vector3 ~= nil and type(Vector3.new) == "function" then
    local v = Vector3.new(2, 3, 6)

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
        local a = Color3.new(1, 0.5, 0)
        local b = Color3.new(1, 0.5, 0)

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

    local cf = CFrame.new(10, 20, 30)

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
            text_object.OutlineColor = Color3.new(0, 0, 0)
            text_object.Position = Vector2.new(50, 50)
            text_object.Font = "Tamzen"

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
        candidates[#candidates + 1] = {
            name = "Vector3.new(0, 10, 0)",
            value = Vector3.new(0, 10, 0)
        }
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

    if workspace ~= nil and workspace.CurrentCamera ~= nil then
        local camera_position_ok, camera_position = pcall(function()
            return workspace.CurrentCamera.Position
        end)

        if camera_position_ok then
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
        local a = Vector2.new(10, 10)
        local b = Vector2.new(30, 10)
        local c = Vector2.new(20, 30)
        local d = Vector2.new(40, 30)
        local white = Color3.new(1, 1, 1)

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

    local get_ping = first_present(game, "GetPing")
    check("game:GetPing exists", type(get_ping) == "function")

    if type(get_ping) == "function" then
        test("game:GetPing returns number", function()
            local ping = get_ping(game)
            return type(ping) == "number", ping
        end)
    end

    local get_hwid = first_present(game, "GetHwid")
    check("game:GetHwid exists", type(get_hwid) == "function")

    if EXTERNAL_TEST_CONFIG.run_hwid_read and type(get_hwid) == "function" then
        test("game:GetHwid returns non-empty string", function()
            local hwid = get_hwid(game)
            return type(hwid) == "string" and #hwid > 0
        end)
    else
        info("game:GetHwid active test", "disabled to avoid printing device identity")
    end

    check(
        "game:HttpGet exists",
        type(first_present(game, "HttpGet")) == "function"
    )
    check(
        "game:HttpPost exists",
        type(first_present(game, "HttpPost")) == "function"
    )

    if EXTERNAL_TEST_CONFIG.run_http_get
        and type(first_present(game, "HttpGet")) == "function"
    then
        test("game:HttpGet returns a string", function()
            local response = game:HttpGet(
                EXTERNAL_TEST_VALUES.http_get_url
            )
            return type(response) == "string" and #response > 0
        end)
    end

    if EXTERNAL_TEST_CONFIG.run_http_post
        and type(first_present(game, "HttpPost")) == "function"
    then
        test("game:HttpPost returns a string", function()
            local response = game:HttpPost(
                EXTERNAL_TEST_VALUES.http_post_url,
                EXTERNAL_TEST_VALUES.http_post_body,
                EXTERNAL_TEST_VALUES.http_post_content_type
            )
            return type(response) == "string"
        end)
    end
end

if workspace ~= nil and workspace.CurrentCamera ~= nil then
    local camera = workspace.CurrentCamera

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

    info("BasePart test target", first_basepart.Name)

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

            first_basepart.CanCollide = old_can_collide
            first_basepart.Transparency = old_transparency
            first_basepart.Size = old_size
            first_basepart.Position = old_position
            first_basepart.CFrame = old_cframe
            first_basepart.Velocity = old_velocity

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
    info("Instance API target", instance_target.Name)

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

        local tag_before = nil
        local before_ok, before_result = pcall(function()
            return instance_target:HasTag(test_tag)
        end)

        if before_ok then
            tag_before = before_result
        end

        local add_ok, add_error = pcall(function()
            instance_target:AddTag(test_tag)
        end)

        check(
            "Instance:AddTag call executes",
            add_ok,
            add_error
        )

        local has_after_add_ok, has_after_add =
            pcall(function()
                return instance_target:HasTag(test_tag)
            end)

        check(
            "Instance:HasTag observes added tag",
            has_after_add_ok and has_after_add == true,
            "before="
                .. value_to_string(tag_before)
                .. " after AddTag="
                .. value_to_string(has_after_add)
        )

        local remove_ok, remove_error = pcall(function()
            instance_target:RemoveTag(test_tag)
        end)

        check(
            "Instance:RemoveTag call executes",
            remove_ok,
            remove_error
        )

        local has_after_remove_ok, has_after_remove =
            pcall(function()
                return instance_target:HasTag(test_tag)
            end)

        check(
            "Instance:HasTag observes removed tag",
            has_after_remove_ok and has_after_remove == false,
            "after RemoveTag="
                .. value_to_string(has_after_remove)
        )

        local original_tags = nil
        local original_tags_ok, original_tags_result =
            pcall(function()
                return instance_target:GetTags()
            end)

        if original_tags_ok and type(original_tags_result) == "table" then
            original_tags = original_tags_result
        end

        if EXTERNAL_TEST_CONFIG.run_destructive_clear_functions then
            local clear_tag = "__SEVERE_VM_CLEAR_TAG_TEST__"

            pcall(function()
                instance_target:AddTag(clear_tag)
            end)

            local clear_ok, clear_error = pcall(function()
                instance_target:ClearTags()
            end)

            check(
                "Instance:ClearTags call executes",
                clear_ok,
                clear_error
            )

            if clear_ok then
                test("Instance:ClearTags removes all tags", function()
                    local tags = instance_target:GetTags()
                    return type(tags) == "table" and #tags == 0,
                        "remaining tag count="
                        .. value_to_string(
                            type(tags) == "table" and #tags or "not-table"
                        )
                end)
            end

            if original_tags ~= nil then
                for i = 1, #original_tags do
                    pcall(function()
                        instance_target:AddTag(original_tags[i])
                    end)
                end
            end
        end

        local old_attribute = nil
        local old_attribute_ok, old_attribute_result =
            pcall(function()
                return instance_target:GetAttribute(test_attribute)
            end)

        if old_attribute_ok then
            old_attribute = old_attribute_result
        end

        local set_attribute_ok, set_attribute_error =
            pcall(function()
                instance_target:SetAttribute(
                    test_attribute,
                    12345
                )
            end)

        check(
            "Instance:SetAttribute call executes",
            set_attribute_ok,
            set_attribute_error
        )

        local get_attribute_ok, set_value =
            pcall(function()
                return instance_target:GetAttribute(test_attribute)
            end)

        check(
            "Instance:GetAttribute observes assigned value",
            get_attribute_ok and set_value == 12345,
            "actual=" .. value_to_string(set_value)
        )

        pcall(function()
            instance_target:SetAttribute(
                test_attribute,
                old_attribute
            )
        end)
    else
        info(
            "Instance mutation tests",
            "disabled; AddTag, RemoveTag, ClearTags, and SetAttribute are not called"
        )
    end
else
    info("Instance API tests", "skipped because no target was found")
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
    {"crypt.random", crypt and crypt.random},
    {"crypt.random_deterministic", crypt and crypt.random_deterministic},
    {"crypt.hash.sha256", crypt and nested_function(crypt, "hash", "sha256")},
    {"crypt.hash.sha512", crypt and nested_function(crypt, "hash", "sha512")},
    {"crypt.hash.blake2b", crypt and nested_function(crypt, "hash", "blake2b")},
    {"crypt.pwhash", crypt and crypt.pwhash},
    {"crypt.pwhash_str", crypt and crypt.pwhash_str},
    {"crypt.pwhash_str_verify", crypt and crypt.pwhash_str_verify},
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
        and type(crypt.random) == "function"
    then
        test("crypt.secretbox round trip works", function()
            local message = "secretbox-message"
            local nonce = crypto_random(24)
            local key = crypto_random(32)
            local cipher = crypt.secretbox.seal(message, nonce, key)
            local plain = crypt.secretbox.open(cipher, nonce, key)
            return plain == message
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
            local a = crypt.hkdf.sha256("key", "salt", "info")
            local b = crypt.hkdf.sha256("key", "salt", "info")
            return type(a) == "string"
                and #a > 0
                and a == b
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
            type(memory["read" .. suffix]) == "function"
        )
        check(
            "memory.write" .. suffix .. " exists",
            type(memory["write" .. suffix]) == "function"
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
            local read_function = memory["read" .. suffix]

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
            local read_function = memory["read" .. suffix]
            local write_function = memory["write" .. suffix]

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
                accepted_signature =
                    "send_notification(content, type="
                    .. notification_type
                    .. ")"
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
            "send_notification accepted form",
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

check(
    "WebsocketClient.new exists",
    WebsocketClient ~= nil
        and type(first_present(WebsocketClient, "new", "New"))
            == "function"
)

if EXTERNAL_TEST_CONFIG.run_websocket
    and WebsocketClient ~= nil
    and type(first_present(WebsocketClient, "new", "New"))
        == "function"
then
    local websocket_new =
        first_present(WebsocketClient, "new", "New")

    local connect_ok, websocket_or_error = pcall(
        websocket_new,
        EXTERNAL_TEST_VALUES.websocket_url
    )

    check(
        "WebsocketClient connects",
        connect_ok and websocket_or_error ~= nil,
        websocket_or_error
    )

    if connect_ok and websocket_or_error ~= nil then
        local websocket = websocket_or_error

        test("WebsocketClient.Url is readable", function()
            return type(websocket.Url) == "string",
                websocket.Url
        end)

        local send = first_present(websocket, "Send", "send")
        local disconnect =
            first_present(websocket, "Disconnect", "disconnect")
        local data_received =
            first_present(websocket, "DataReceived")

        check("WebsocketClient Send exists", type(send) == "function")
        check(
            "WebsocketClient Disconnect exists",
            type(disconnect) == "function"
        )
        check(
            "WebsocketClient DataReceived exists",
            data_received ~= nil
        )

        if data_received ~= nil then
            local connected, connection, connection_detail =
                connect_signal(
                    data_received,
                    function(payload, is_binary)
                        info(
                            "WebSocket echo received",
                            value_to_string(payload)
                                .. " binary="
                                .. value_to_string(is_binary)
                        )
                    end
                )

            info(
                "WebSocket DataReceived connection",
                connected
                    and (
                        "connected through "
                        .. value_to_string(connection_detail)
                    )
                    or value_to_string(connection_detail)
            )
        end

        if type(send) == "function" then
            local ok, err = pcall(
                send,
                websocket,
                "Severe VM websocket test",
                false
            )
            check("WebsocketClient Send executes", ok, err)
        end

        if type(task) == "table" and type(task.wait) == "function" then
            pcall(task.wait, 0.5)
        end

        if type(disconnect) == "function" then
            local ok, err = pcall(disconnect, websocket)
            check("WebsocketClient Disconnect executes", ok, err)
        end
    end
else
    info("WebSocket active test", "disabled")
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

    if local_player ~= nil
        and type(override_local_data) == "function"
    then
        local local_data = {
            LocalPlayer = local_player,
            Displayname = local_player.DisplayName,
            Username = local_player.Name,
            Userid = local_player.UserId,
            Character = character,
            Team = local_player.Team,
            RootPart = root,
            LeftFoot = nil,
            Head = head,
            LowerTorso = nil,
            Tool = nil,
            Humanoid = humanoid,
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
    test("Color3.fromHex rejects invalid hex", function()
        local ok, result = pcall(
            Color3.fromHex,
            "this-is-not-hex"
        )

        return ok == false,
            ok and value_to_string(result) or result
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
    test("PointInstance.new rejects non-BasePart", function()
        local constructor =
            first_present(PointInstance, "new", "New")
        local ok, result = pcall(constructor, workspace)

        return ok == false or result == nil,
            "ok="
                .. value_to_string(ok)
                .. " result="
                .. value_to_string(result)
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

if Vector2 ~= nil and type(Vector2.new) == "function" then
    type_samples[#type_samples + 1] = {
        "Vector2.new",
        Vector2.new(1, 2)
    }
end

if Vector3 ~= nil and type(Vector3.new) == "function" then
    type_samples[#type_samples + 1] = {
        "Vector3.new",
        Vector3.new(1, 2, 3)
    }
end

if Color3 ~= nil and type(Color3.new) == "function" then
    type_samples[#type_samples + 1] = {
        "Color3.new",
        Color3.new(1, 0, 0)
    }
end

if CFrame ~= nil and type(CFrame.new) == "function" then
    type_samples[#type_samples + 1] = {
        "CFrame.new",
        CFrame.new(1, 2, 3)
    }
end

if workspace ~= nil and workspace.CurrentCamera ~= nil then
    pcall(function()
        type_samples[#type_samples + 1] = {
            "Camera.Position",
            workspace.CurrentCamera.Position
        }
    end)
end

if first_basepart ~= nil then
    pcall(function()
        type_samples[#type_samples + 1] = {
            "BasePart.Position",
            first_basepart.Position
        }
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
-- 37. COMMON EXTERNAL COMPATIBILITY PROBES
-- ============================================================
section("37. Common External Compatibility Probes")

-- These names are common across Roblox script environments. They are
-- not required by Severe's supplied documentation, so they are INFO
-- probes and do not count as failures.

local common_external_globals = {
    {"getgenv", getgenv},
    {"getrenv", getrenv},
    {"getreg", getreg},
    {"getgc", getgc},
    {"getinstances", getinstances},
    {"getnilinstances", getnilinstances},
    {"getscripts", getscripts},
    {"getloadedmodules", getloadedmodules},
    {"getconnections", getconnections},
    {"firesignal", firesignal},
    {"fireclickdetector", fireclickdetector},
    {"firetouchinterest", firetouchinterest},
    {"hookfunction", hookfunction},
    {"hookmetamethod", hookmetamethod},
    {"newcclosure", newcclosure},
    {"checkcaller", checkcaller},
    {"islclosure", islclosure},
    {"iscclosure", iscclosure},
    {"clonefunction", clonefunction},
    {"getrawmetatable", getrawmetatable},
    {"setrawmetatable", setrawmetatable},
    {"setreadonly", setreadonly},
    {"isreadonly", isreadonly},
    {"getnamecallmethod", getnamecallmethod},
    {"setnamecallmethod", setnamecallmethod},
    {"identifyexecutor", identifyexecutor},
    {"getexecutorname", getexecutorname},
    {"cloneref", cloneref},
    {"compareinstances", compareinstances},
    {"queue_on_teleport", queue_on_teleport},
    {"request", request},
    {"http_request", http_request},
    {"getclipboard", getclipboard},
    {"setthreadidentity", setthreadidentity},
    {"getthreadidentity", getthreadidentity},
    {"gethiddenproperty", gethiddenproperty},
    {"sethiddenproperty", sethiddenproperty},
    {"getscriptbytecode", getscriptbytecode},
    {"getscriptclosure", getscriptclosure},
    {"decompile", decompile}
}

for i = 1, #common_external_globals do
    local entry = common_external_globals[i]
    info(entry[1], type(entry[2]))
end

if type(syn) == "table" then
    info("syn.request", type(syn.request))
    info(
        "syn.websocket",
        type(syn.websocket)
    )

    if type(syn.websocket) == "table" then
        info(
            "syn.websocket.connect",
            type(syn.websocket.connect)
        )
    end
else
    info("syn namespace", type(syn))
end

if type(websocket) == "table" then
    info("websocket.connect", type(websocket.connect))
else
    info("websocket namespace", type(websocket))
end

if type(WebSocket) == "table" then
    info("WebSocket.connect", type(WebSocket.connect))
else
    info("WebSocket namespace", type(WebSocket))
end

if type(cache) == "table" then
    info("cache.invalidate", type(cache.invalidate))
    info("cache.iscached", type(cache.iscached))
    info("cache.replace", type(cache.replace))
else
    info("cache namespace", type(cache))
end

-- ============================================================
-- SUMMARY
-- ============================================================
print("")
print("========================================")
print("  RESULTS")
print("========================================")
print(PASS .. " " .. tostring(pass_count) .. " tests passed")

if fail_count > 0 then
    warn(FAIL .. " " .. tostring(fail_count) .. " tests FAILED")

    print("")
    print("  FAILED TEST INDEX")
    print("----------------------------------------")

    for i = 1, #failure_records do
        local failure = failure_records[i]
        warn(
            "["
            .. tostring(i)
            .. "] "
            .. failure.label
            .. " | "
            .. failure.detail
        )

        if failure.diagnosis ~= nil then
            warn("    WHY: " .. failure.diagnosis)
        end
    end
else
    print(PASS .. " All counted tests passed!")
end

print(INFO .. " Optional/undocumented probes do not affect totals.")
print("========================================")
