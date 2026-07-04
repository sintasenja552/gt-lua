botEnabled = false
targetLocked = false
targetX, targetY = nil, nil

local farm_block_id = 3200
local restock_item_id = 3206
local fist_id = 18 

local function logToConsole(msg)
    SendVariant({v1 = "OnConsoleMessage", v2 = "`6[AIM-ASSIST] `w" .. msg})
end

local function getDistance(x1, y1, x2, y2)
    return math.abs(x1 - x2) + math.abs(y1 - y2)
end

local function getInventoryAmount(id)
    local inv = GetInventory()
    if inv then
        for _, item in pairs(inv) do
            if item.id == id then return item.amount end
        end
    end
    return 0
end

addHook("OnDrawImGui", function()
    if not botEnabled or not ImGui then return end
    if ImGui.Begin("Aim Assist", true, ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoResize + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground) then
        ImGui.TextColored(ImVec4(0, 255, 0, 255), "AIM ASSIST: READY")
        if targetLocked and targetX then
            ImGui.TextColored(ImVec4(255, 215, 0, 255), "LOCK AIM: (" .. targetX .. "," .. targetY .. ")")
        else
            ImGui.TextColored(ImVec4(255, 255, 255, 255), "Tahan tombol tinju...")
        end
        ImGui.End()
    end
end)

addHook("OnSendPacket", function(type, packet)
    if type == 2 and packet:find("action|input") then
        local cmd = packet:match("text|(/%a+)")
        if cmd then
            cmd = cmd:lower()
            if cmd == "/start" then
                botEnabled = true
                local itemAmt = getInventoryAmount(restock_item_id)
                if itemAmt > 0 then
                    SendPacket(2, "action|equip\nitemID|" .. restock_item_id .. "\npos|0")
                    Sleep(100)
                    SendPacket(2, "action|use\nitemID|" .. restock_item_id)
                end
                logToConsole("`2Aim Assist Aktif! Tahan tombol tinju kanan.`")
                return true
            elseif cmd == "/stop" then
                botEnabled = false
                targetLocked = false
                targetX, targetY = nil, nil
                logToConsole("`4Aim Assist Nonaktif.`")
                return true
            end
        end
    end

    if botEnabled and type == 3 and packet.int_data == fist_id then
        if targetLocked and targetX and targetY then
            local pl = GetLocal()
            if pl then
                SendPacketRaw({
                    type = 3,
                    int_data = fist_id,
                    pos_x = pl.posX,
                    pos_y = pl.posY,
                    int_x = targetX,
                    int_y = targetY
                })
                return true
            end
        end
    end
end)

runThread(function()
    while true do
        if botEnabled then
            local pl = GetLocal()
            if pl then
                local currentX = pl.posX // 32
                local currentY = pl.posY // 32
                local closestDist = 9999
                local foundX, foundY = nil, nil

                for dx = -2, 2 do
                    for dy = -2, 2 do
                        local tx = currentX + dx
                        local ty = currentY + dy
                        local tile = GetTile(tx, ty)
                        if tile and tile.fg == farm_block_id then
                            local dist = getDistance(currentX, currentY, tx, ty)
                            if dist < closestDist then
                                closestDist = dist
                                foundX = tx
                                foundY = ty
                            end
                        end
                    end
                end

                if foundX and foundY then
                    targetX = foundX
                    targetY = foundY
                    targetLocked = true
                else
                    targetLocked = false
                    targetX, targetY = nil, nil
                end
            end
        end
        Sleep(40)
    end
end)
