if IS_RUNNING_SCRIPT then return end
IS_RUNNING_SCRIPT = true

-- ==========================================
-- 1. CONFIGURATION & CONSTANTS
-- ==========================================
local farm_block_id = 3200
local restock_item_id = 3206
local fist_id = 18

-- ==========================================
-- 2. STATE MACHINE VARIABLES
-- ==========================================
local botEnabled = false
local equipmentReady = false
local radiusActive = false
local targetLocked = false
local pathFinished = false
local readyToPunch = false

local currentState = "IDLE" 
local targetX, targetY = nil, nil
local standX, standY = nil, nil

local blacklistedTargets = {}
local hitCount = 0

-- ==========================================
-- 3. HELPER FUNCTIONS
-- ==========================================
local function logToConsole(msg)
    SendVariant({v1 = "OnConsoleMessage", v2 = "`6[TARGET-ASSIST] `w" .. msg})
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

local function findAdjacentEmptyTile(tx, ty)
    local offsets = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
    for i = 1, 4 do
        local os = offsets[i]
        local ex, ey = tx + os[1], ty + os[2]
        local tile = GetTile(ex, ey)
        if tile and tile.fg == 0 then
            return ex, ey
        end
    end
    return nil, nil
end

-- ==========================================
-- 4. VISUAL GUIDE ENGINE (IMGUI OVERLAY)
-- ==========================================
addHook("OnDrawImGui", function()
    if not botEnabled or not ImGui then return end
    
    if ImGui.Begin("Target Assist", true, ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoResize + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground) then
        ImGui.TextColored(ImVec4(0, 255, 0, 255), "STATUS: " .. currentState)
        if targetLocked and targetX then
            ImGui.TextColored(ImVec4(255, 215, 0, 255), "LOCK: " .. targetX .. "," .. targetY)
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
                blacklistedTargets = {}
                logToConsole("`2Sistem Diaktifkan (Sinkronisasi Gerak Aktif).`")
                return true
            elseif cmd == "/stop" then
                botEnabled = false
                equipmentReady = false
                radiusActive = false
                targetLocked = false
                pathFinished = false
                readyToPunch = false
                targetX, targetY = nil, nil
                blacklistedTargets = {}
                currentState = "IDLE"
                logToConsole("`4Sistem Dinonaktifkan.`")
                return true
            end
        end
    end
end)

-- ==========================================
-- 6. CORE STATE MACHINE LOOP
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
                        currentState = "SCAN"
                    else
                        logToConsole("`4[ERROR] Item 3206 Habis.`")
                        botEnabled = false
                        currentState = "IDLE"
                    end

                -- ----------------------------------
                -- [STATE: SCAN]
                -- ----------------------------------
                elseif currentState == "SCAN" then
                    radiusActive = true
                    local closestDist = 9999
                    local foundX, foundY = nil, nil

                    for dx = -2, 2 do
                        for dy = -2, 2 do
                            local tx = currentX + dx
                            local ty = currentY + dy
                            local tile = GetTile(tx, ty)
                            
                            local tKey = tx * 1000 + ty 
                            
                            if tile and tile.fg == farm_block_id and not blacklistedTargets[tKey] then
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
                        currentState = "PATH"
                    else
                        radiusActive = false
                        blacklistedTargets = {} 
                        Sleep(300) 
                    end

                -- ----------------------------------
                -- [STATE: PATH] (BAGIAN YANG DIPERBAIKI)
                -- ----------------------------------
                elseif currentState == "PATH" then
                    standX, standY = findAdjacentEmptyTile(targetX, targetY)
                    
                    if standX and standY then
                        if currentX == standX and currentY == standY then
                            pathFinished = true
                            hitCount = 0
                            currentState = "READY"
                        else
                            -- 1. Hitung berapa kotak jarak yang harus ditempuh karakter
                            local distanceToWalk = getDistance(currentX, currentY, standX, standY)
                            
                            -- 2. Panggil fungsi jalan
                            pcall(FindPath, standX, standY)
                            
                            -- 3. SINKRONISASI: Tahan script selama waktu perjalanan (1 kotak = ~160ms) + Ping
                            local walkDelay = (distanceToWalk * 160) + getPingDelay()
                            Sleep(walkDelay) 
                            
                            -- 4. Cek ulang posisi setelah masa tunggu perjalanan selesai
                            local checkPl = GetLocal()
                            if checkPl then
                                local cx = checkPl.posX // 32
                                  local cy = checkPl.posY // 32
                                if cx == standX and cy == standY then
                                    pathFinished = true
                                    hitCount = 0
                                    currentState = "READY"
                                end
                            end
                            
                            -- Jika setelah ditunggu ternyata belum sampai juga (karena nyangkut)
                            if currentState == "PATH" then
                                local tKey = targetX * 1000 + targetY
                                blacklistedTargets[tKey] = true
                                targetLocked = false
                                currentState = "SCAN"
                                Sleep(150)
                            end
                        end
                    else
                        local tKey = targetX * 1000 + targetY
                        blacklistedTargets[tKey] = true
                        targetLocked = false
                        currentState = "SCAN"
                        Sleep(150)
                    end

                -- ----------------------------------
                -- [STATE: READY]
                -- ----------------------------------
                elseif currentState == "READY" then
                    readyToPunch = true
                    
                    local currentTile = GetTile(targetX, targetY)
                    if currentTile and currentTile.fg == farm_block_id and hitCount < 8 then
                        
                        -- Mengambil koordinat real-time terbaru setelah dipastikan sampai
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
                        local delayPukul = getPingDelay() + 180 
                        Sleep(delayPukul)
                        
                    else
                        if hitCount >= 8 then
                            local tKey = targetX * 1000 + targetY
                            blacklistedTargets[tKey] = true
                        end
                        
                        targetLocked = false
                        pathFinished = false
                        readyToPunch = false
                        targetX, targetY = nil, nil
                        standX, standY = nil, nil
                        
                        Sleep(150) 
                        currentState = "SCAN"
                    end
                end

            end
        end
        Sleep(100) 
    end
end)
