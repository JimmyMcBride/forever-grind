local _, FG = ...
local Value = {}
FG.Value = Value

function Value.Settings(settings)
    return { auctionator = settings.auctionator, ahCut = settings.ahCut, maxPriceAge = settings.maxPriceAge }
end

function Value.Item(entry, settings, quote)
    local vendor = entry.vendor
    if vendor == nil then return { route = "pending", reason = "Waiting for item information", pending = entry.quantity } end
    local result = { vendor = vendor * entry.quantity, route = "vendor", ah = 0, upside = 0 }
    if not settings.auctionator then result.reason = "Auctionator estimates disabled"
    elseif entry.bindingPending then result.reason = "Receipt binding unknown; vendor fallback"
    elseif not entry.auctionable then result.reason = "Bound or not auctionable"
    elseif not quote or not quote.price or quote.price <= 0 then result.reason = "No cached AH quote; vendor fallback"
    elseif quote.age == nil then result.reason = "Unknown quote age; vendor fallback"
    elseif quote.age > settings.maxPriceAge then result.reason = "Stale quote; vendor fallback"
    else
        local proceeds = math.floor(quote.price * entry.quantity * (1 - settings.ahCut / 100))
        if proceeds > result.vendor then
            result.route, result.ah = "AH", proceeds
            result.upside = proceeds - result.vendor
            result.reason = "Cached AH proceeds exceed vendor value after cut"
        else result.reason = "Vendor value meets or exceeds AH proceeds" end
    end
    return result
end

function Value.Total(record, settings, quoteProvider)
    local total = { baseline = 0, vendor = 0, ah = 0, projected = 0, pending = 0, quantity = 0, rows = {},
        sources = { loot = 0, gathering = 0, quest = 0 } }
    settings = record.pricing or settings
    for _, entry in pairs(record.items) do
        local quote
        if record.closed then quote = entry.quote else quote = quoteProvider(entry) end
        local value = Value.Item(entry, settings, quote)
        total.quantity = total.quantity + entry.quantity
        total.pending = total.pending + (value.pending or 0)
        total.baseline = total.baseline + (value.vendor or 0)
        total.vendor = total.vendor + (value.route ~= "AH" and value.vendor or 0)
        total.ah = total.ah + (value.ah or 0)
        local earned = value.route == "AH" and value.ah or (value.vendor or 0)
        total.sources[entry.source] = (total.sources[entry.source] or 0) + earned
        total.rows[#total.rows + 1] = { entry = entry, value = value, quote = quote }
    end
    total.projected = record.coin.loot + record.coin.quest + total.vendor + total.ah
    total.xp = record.xp.combat + record.xp.quest + record.xp.other
    total.xpHour = record.active > 0 and total.xp * 3600 / record.active or 0
    total.goldHour = record.active > 0 and total.projected * 3600 / record.active or 0
    total.vendorHour = record.active > 0 and (record.coin.loot + record.coin.quest + total.baseline) * 3600 / record.active or 0
    table.sort(total.rows, function(a, b)
        if (a.value.upside or 0) ~= (b.value.upside or 0) then return (a.value.upside or 0) > (b.value.upside or 0) end
        return a.entry.link < b.entry.link
    end)
    return total
end

function Value.Freeze(record, settings, quoteProvider)
    record.pricing = Value.Settings(settings)
    for _, entry in pairs(record.items) do entry.quote = FG.Copy(quoteProvider(entry)) end
end
