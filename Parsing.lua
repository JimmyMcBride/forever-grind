local _, FG = ...
local Parsing = { cache = {}, killFormats = setmetatable({}, { __mode = "k" }) }
FG.Parsing = Parsing

local function Escape(char)
    if char:find("[%^%$%(%)%%%.%[%]%*%+%-%?]") then return "%" .. char end
    return char
end

function Parsing.Compile(format)
    if Parsing.cache[format] then return unpack(Parsing.cache[format]) end
    local pattern, slots, types, offset, nextSlot = "^", {}, {}, 1, 1
    while offset <= #format do
        local rest = format:sub(offset)
        if rest:sub(1, 2) == "%%" then
            pattern, offset = pattern .. "%%", offset + 2
        else
            local token, position, kind = rest:match("^(%%(%d+)%$([sd]))")
            if not token then token, kind = rest:match("^(%%([sd]))"); position = nextSlot end
            if token then
                pattern = pattern .. (kind == "d" and "([%d%.,%s]+)" or "(.-)")
                slots[#slots + 1], types[#types + 1] = tonumber(position), kind
                nextSlot, offset = nextSlot + 1, offset + #token
            else
                pattern, offset = pattern .. Escape(rest:sub(1, 1)), offset + 1
            end
        end
    end
    pattern = pattern .. "$"
    Parsing.cache[format] = { pattern, slots, types }
    return pattern, slots, types
end

function Parsing.Match(format, text, embedded)
    if type(format) ~= "string" or type(text) ~= "string" then return end
    local pattern, slots, types = Parsing.Compile(format)
    if embedded then pattern = pattern:sub(2, -2) end
    local captures = { text:match(pattern) }
    if #captures == 0 then return end
    local values, number = {}, nil
    for i, slot in ipairs(slots) do
        values[slot] = types[i] == "d" and FG.Number(captures[i]) or captures[i]
        if types[i] == "d" and not number then number = values[slot] end
    end
    return values, number
end

function Parsing.KillXP(text, globals)
    local formats = Parsing.killFormats[globals]
    if not formats then
        formats = {}
        for key, format in pairs(globals) do
            if type(key) == "string" and key:match("^COMBATLOG_XPGAIN_") and type(format) == "string" then
                local _, slots, types = Parsing.Compile(format)
                local arguments = {}
                for index, slot in ipairs(slots) do arguments[slot] = types[index] end
                -- Named kills include rested/group variants. Quest/exploration
                -- messages begin with numeric XP rather than a named victim.
                if arguments[1] == "s" and arguments[2] == "d" then formats[#formats + 1] = format end
            end
        end
        Parsing.killFormats[globals] = formats
    end
    for _, format in ipairs(formats) do
        local values = Parsing.Match(format, text)
        local amount = values and values[2]
        if type(amount) == "number" and amount > 0 then return amount, values[1] end
    end
end

function Parsing.Item(text, globals)
    for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF" }) do
        local values = Parsing.Match(globals[key], text)
        if values then return values[1], tonumber(values[2]) or 1 end
    end
end

function Parsing.Money(text, globals)
    local values
    for _, key in ipairs({ "LOOT_MONEY", "LOOT_MONEY_SPLIT" }) do
        values = Parsing.Match(globals[key], text)
        if values then break end
    end
    if not values then return end
    local money, total = tostring(values[1]), 0
    for _, coin in ipairs({ { "GOLD", 10000 }, { "SILVER", 100 }, { "COPPER", 1 } }) do
        local amount = 0
        for _, suffix in ipairs({ "_AMOUNT", "_AMOUNT_SYMBOL" }) do
            local _, number = Parsing.Match(globals[coin[1] .. suffix], money, true)
            if number then amount = number; break end
        end
        if amount == 0 then
            local value = money:match("(%d+)%s*|T[^|]-" .. coin[1]:sub(1, 1) .. coin[1]:sub(2):lower() .. "Icon[^|]-|t")
            amount = tonumber(value) or 0
        end
        total = total + amount * coin[2]
    end
    return total
end

function Parsing.XPDelta(previous, current)
    if not previous then return 0, false end
    if current.level > previous.level then
        return math.max(0, previous.maximum - previous.xp + current.xp), current.level - previous.level > 1
    end
    return math.max(0, current.xp - previous.xp), false
end
