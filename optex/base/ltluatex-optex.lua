luatexbase = luatexbase or {}

-- for a \XXdef'd csname return corresponding register number
function luatexbase.registernumber(name)
    return token.create(name).index
end

-- an attribute allocator in Lua that cooperates with normal OpTeX allocator
luatexbase.attributes = {}
local attribute_max = luatexbase.registernumber("_maiattribute")
function luatexbase.new_attribute(name)
    local cnt = tex.count["_attributealloc"] + 1
    if cnt > attribute_max then
        tex.error("No room for new attribute")
    else
        tex.setcount("global", "_attributealloc", cnt)
        luatexbase.attributes[name] = cnt
        return cnt
    end
end

luatexbase.info = "log"
function luatexbase.module_info(module, message)
    if luatexbase.info then
        texio.write_nl(luatexbase.info, module.." info: "..message)
    end
end

luatexbase.warning = "term and log"
function luatexbase.module_warning(module, message)
    if luatexbase.warning then
        texio.write_nl(luatexbase.warning, module.." info: "..message)
    end
end

function luatexbase.module_error(module, message)
    error("\n"..module.." error: "..message.."\n")
end

function luatexbase.provides_module(info)
end

local function err(message)
    luatexbase.module_error("luatexbase", message)
end

local callback_functions = {}
local user_callbacks = {}
local callback_description = {}
local callback_types = {
    find_read_file     = "exclusive",
    find_write_file    = "exclusive",
    find_font_file     = "data",
    find_output_file   = "data",
    find_format_file   = "data",
    find_vf_file       = "data",
    find_map_file      = "data",
    find_enc_file      = "data",
    find_pk_file       = "data",
    find_data_file     = "data",
    find_opentype_file = "data",
    find_truetype_file = "data",
    find_type1_file    = "data",
    find_image_file    = "data",
    open_read_file     = "exclusive",
    read_font_file     = "exclusive",
    read_vf_file       = "exclusive",
    read_map_file      = "exclusive",
    read_enc_file      = "exclusive",
    read_pk_file       = "exclusive",
    read_data_file     = "exclusive",
    read_truetype_file = "exclusive",
    read_type1_file    = "exclusive",
    read_opentype_file = "exclusive",
    find_cidmap_file   = "data",
    read_cidmap_file   = "exclusive",
    process_input_buffer  = "data",
    process_output_buffer = "data",
    process_jobname       = "data",
    contribute_filter      = "simple",
    buildpage_filter       = "simple",
    build_page_insert      = "exclusive",
    pre_linebreak_filter   = "list",
    linebreak_filter       = "exclusive",
    append_to_vlist_filter = "exclusive",
    post_linebreak_filter  = "reverselist",
    hpack_filter           = "list",
    vpack_filter           = "list",
    hpack_quality          = "list",
    vpack_quality          = "list",
    pre_output_filter      = "list",
    process_rule           = "exclusive",
    hyphenate              = "simple",
    ligaturing             = "simple",
    kerning                = "simple",
    insert_local_par       = "simple",
    pre_mlist_to_hlist_filter = "list",
    mlist_to_hlist         = "exclusive",
    post_mlist_to_hlist_filter = "reverselist",
    new_graf               = "exclusive",
    pre_dump             = "simple",
    start_run            = "simple",
    stop_run             = "simple",
    start_page_number    = "simple",
    stop_page_number     = "simple",
    show_error_hook      = "simple",
    show_warning_message = "simple",
    show_error_message   = "simple",
    show_lua_error_hook  = "simple",
    start_file           = "simple",
    stop_file            = "simple",
    call_edit            = "simple",
    finish_synctex       = "simple",
    wrapup_run           = "simple",
    finish_pdffile            = "data",
    finish_pdfpage            = "data",
    page_objnum_provider      = "data",
    page_order_index          = "data",
    process_pdf_image_content = "data",
    define_font                     = "exclusive",
    glyph_info                      = "exclusive",
    glyph_not_found                 = "exclusive",
    glyph_stream_provider           = "exclusive",
    make_extensible                 = "exclusive",
    font_descriptor_objnum_provider = "exclusive",
}


function luatexbase.callback_descriptions(name)
    return callback_description[name] or {}
end

local valid_callback_types = {
    exclusive = true ,
    simple = true,
    data = true,
    list = true,
    reverselist = true,
}

function luatexbase.create_callback(name, cbtype, default)
    if ctype == "exclusive" and not default then
        err("unable to create exclusive callback '"..name.."', default function is required")
    elseif not valid_callback_types[cbtype] then
        err("cannot create callback '"..name.."' with invalid callback type '"..cbtype.."'")
    end
    callback_types[name] = cbtype
    callback_functions[name] = {}
    user_callbacks[name] = true
end

function luatexbase.add_to_callback(name, fn, description)
    if user_callbacks[name] then
        -- user defined callback
    elseif callback_types[name] then
        -- standard luatex callback, register a proxy function as
        -- a real callback
        callback.register(name, function(...)
            return luatexbase.call_callback(name, ...)
        end)
    end

    -- add function to callback list for this callback
    callback_functions[name] = callback_functions[name] or {}
    table.insert(callback_functions[name], fn)

    -- add description to description list
    callback_description[name] = callback_description[name] or {}
    table.insert(callback_description[name], description)
end

function luatexbase.call_callback(name, ...)
    local cbtype = callback_types[name]
    local functions = callback_functions[name] or {}

    if cbtype == "exclusive" then
        -- only one function
        return functions[1] and functions[1](...)
    elseif cbtype == "simple" then
        -- call all functions one after another, no passing of data
        for _, fn in ipairs(functions) do
            fn(...)
        end
        return
    elseif cbtype == "data" then
        -- pass data (first argument) from one function to other,
        -- while keeping other arguments
        local args = {...}
        local data, args = args[1], table.unpack(args, 2)
        for _, fn in ipairs(functions) do
            data = fn(data, ...)
        end
        return data
    end

    -- list and reverselist are like data, but "true" keeps data (head node)
    -- unchanged and "false" ends the chain immediately

    if #functions == 0 then
        -- there is no callback function, just return the head as we
        -- received it
        return (...)
    end
    local start, stop
    if cbtype == "list" then
        start, stop = 1, #functions
    elseif cbtype == "reverselist" then
        start, stop = #functions, 1
    end

    local args = {...}
    local head, args = args[1], table.unpack(args, 2)
    local new_head
    local changed = false
    for i = start, stop do
        new_head = functions[i](head, ...)
        if new_head == false then
            return false
        elseif new_head ~= true then
            head = new_head
            changed = true
        end
    end
    return not change or head
end

callback.register("mlist_to_hlist", function(head, ...)
    -- pre_mlist_to_hlist_filter
    local new_head = luatexbase.call_callback("pre_mlist_to_hlist_filter", head, ...)
    if new_head == false then
        node.flush_list(head)
        return nil
    elseif new_head ~= true then
        head = new_head
    end

    -- mlist_to_hlist (exclusive callback)
    local functions = callback_functions["mlist_to_hlist"]
    if functions then
        -- the callback has been defined
        head = functions[1](head, ...)
    else
        -- standard luatex behavior
        head = node.mlist_to_hlist(head, ...)
    end

    -- post_mlist_to_hlist_filter
    new_head = luatexbase.call_callback("post_mlist_to_hlist_filter", head, ...)
    if new_head == false then
        node.flush_list(head)
        return nil
    elseif new_head ~= true then
        head = new_head
    end
    return head
end)
