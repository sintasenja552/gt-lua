if IS_RUNNING_SCRIPT then return end
IS_RUNNING_SCRIPT = true

-- ==========================================
-- 1. CONFIGURATION & CONSTANTS
-- ==========================================
local farm_block_id = 3200
local restock_item_id = 3206
local fist_id = 18  -- SUDAH BENAR: 18 adalah ID Fist/Pukul resmi Growtopia

-- ==========================================
-- 2. STATE MACHINE VARIABLES
-- ==========================================
local botEnabled = false
local equipmentReady = false
local targetLocked = false

local currentState = "IDLE" 
local targetX, targetY = nil, nil
local hitCount = 0

-- ==========================================
-- 3. HELPER FUNCTIONS
-- ==========================================
local function logToConsole(msg)
    SendVariant({v1 = "OnConsoleMessage", v2 = "`6[AIM-ASSIST] `w" .. msg})
end

local function getPingDelay()
    local ping = 150 
    if GetPing then
        ping = GetPing()
    elseif GetLocal and GetLocal().ping then
        ping = GetLocal().ping
    end
    return math.max(70, math.min(ping, 400))
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

-- ==========================================
-- 4. VISUAL GUIDE ENGINE (IMGUI OVERLAY)
-- ==========================================
addHook("OnDrawImGui", function()
    if not botEnabled or not ImGui then return end
    
    if ImGui.Begin("Aim Assist Overlay", true, ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoResize + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground) then
        ImGui.TextColored(ImVec4(0, 255, 0, 255), "AIM ASSIST: ACTIVE")
        if targetLocked and targetX then
            ImGui.TextColored(ImVec4(255, 215, 0, 255), "LOCKED TARGET: (" .. targetX .. "," .. targetY .. ")")
        else
            ImGui.TextColored(ImVec4(255, 255, 255, 255), "Mencari balok terdekat...")
        end
        ImGui.End()
    end
end)

-- ==========================================
-- 5. INTERCEPTOR COMMANDS (/start & /stop)
-- ==========================================
addHook("OnSendPacket", function(type, packet)
    if type == 2 and packet:find("action|input") then
        local cmd = packet:match("text|(/%a+)")
        if cmd then
            cmd = cmd:lower()
            if cmd == "/start" then
                botEnabled = true
                currentState = "INIT"
                logToConsole("`2Aim Assist Dinyalakan. Gerakkan karaktermu secara manual!`")
                return true
            elseif cmd == "/stop" then
                botEnabled = false
                equipmentReady = false
                targetLocked = false
                targetX, targetY = nil, nil
                currentState = "IDLE"
                logToConsole("`4Aim Assist Dimatikan.`")
                return true
            end
        end
    end
end)

-- ==========================================
-- 6. CORE AIM ASSIST LOOP
-- ==========================================
runThread(function()
    while true do
        if botEnabled then
            local pl = GetLocal()
            if pl then
                local visualX = pl.posX
                local visualY = pl.posY
                
                local currentX = visualX // 32
                local currentY = visualY // 32

                -- ----------------------------------
                -- [STATE: INIT]
                -- ----------------------------------
                if currentState == "INIT" then
                    local itemAmt = getInventoryAmount(restock_item_id)
                    if itemAmt > 0 then
                        SendPacket(2, "action|equip\nitemID|" .. restock_item_id .. "\npos|0")
                        Sleep(150)
                        SendPacket(2, "action|use\nitemID|" .. restock_item_id)
                        Sleep(150)
                        
                        equipmentReady = true
                        currentState = "AIM_SCAN"
                    else
                        logToConsole("`4[ERROR] Item 3206 tidak siap.`")
                        botEnabled = false
                        currentState = "IDLE"
                    end

                -- ----------------------------------
                -- [STATE: AIM_SCAN] (Mencari & Mengunci Target)
                -- ----------------------------------
                elseif currentState == "AIM_SCAN" then
                    local closestDist = 9999
                    local foundX, foundY = nil, nil

                    -- Scan radius jangkauan pukulan tangan (2 kotak ke segala arah)
                    for dx = -2, 2 do
                        for dy = -2, 2 do
                            local tx = currentX + dx
                            local ty = currentY + dy
                            local tile = GetTile(tx, ty)
                            
                            if tile and tile.fg == farm_block_id then
                                local dist = getDistance(currentX, currentY, tx, ty)
                                -- Mengunci balok yang jaraknya paling dekat dengan posisi berdiri player saat ini
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
                        hitCount = 0
                        currentState = "AUTO_HIT"
                    else
                        targetLocked = false
                        targetX, targetY = nil, nil
                        Sleep(100) -- Jika tidak ada balok di sekitar, tunggu player berjalan mendekati balok
                    end

                -- ----------------------------------
                -- [STATE: AUTO_HIT] (Mengeksekusi Pukulan Akurat)
                -- ----------------------------------
                elseif currentState == "AUTO_HIT" then
                    local currentTile = GetTile(targetX, targetY)
                    
                    -- Cek real-time apakah balok masih ada dan jaraknya masih dalam jangkauan pukul (maksimal 2 kotak)
                    if currentTile and currentTile.fg == farm_block_id and getDistance(currentX, currentY, targetX, targetY) <= 3 and hitCount < 10 then
                        
                        -- Mengirim paket pukulan langsung tertuju ke target koordinat balok
                        local livePl = GetLocal()
                        SendPacketRaw({
                            type = 3, 
                            int_data = fist_id, 
                            pos_x = livePl.posX, 
                            pos_y = livePl.posY,
                            int_x = targetX,
                            int_y = targetY
                        })
                        
                        hitCount = hitCount + 1
                        local delayPukul = getPingDelay() + 160 
                        Sleep(delayPukul)
                        
                    else
                        -- Jika balok sudah hancur ATAU player berjalan menjauh dari jangkauan balok tersebut
                        targetLocked = false
                        targetX, targetY = nil, nil
                        
                        Sleep(50) 
                        currentState = "AIM_SCAN" -- Scan ulang mencari balok terdekat berikutnya
                    end
                end

            end
        end
        Sleep(50) -- Loop utama berjalan sangat cepat dan ringan demi responsivitas aim yang instan
    end
end)
