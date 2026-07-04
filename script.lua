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

-- ==========================================
-- 3. HELPER FUNCTIONS
-- ==========================================
local function logToConsole(msg)
    SendVariant({v1 = "OnConsoleMessage", v2 = "`6[TARGET-ASSIST] `w" .. msg})
end

local function getPingDelay()
    local ping = 100 
    if GetPing then
        ping = GetPing()
    elseif GetLocal and GetLocal().ping then
        ping = GetLocal().ping
    end
    return math.max(50, math.min(ping, 400))
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
    for _, os in ipairs(offsets) do
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
addHook("onDrawImGui", function()
    if not botEnabled then return end
    
    if ImGui and ImGui.Begin("Target Assist Overlay", true, ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoResize + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground) then
        local currentPing = GetPing and GetPing() or 0
        ImGui.TextColored(ImVec4(0, 255, 0, 255), "SYSTEM STATUS: " .. currentState .. " | PING: " .. currentPing .. "ms")
        
        if targetLocked and targetX and targetY then
            ImGui.TextColored(ImVec4(255, 215, 0, 255), "LOCKED TARGET: (" .. targetX .. ", " .. targetY .. ")")
            
            local drawList = ImGui.GetForegroundDrawList()
            if drawList then
                ImGui.TextColored(ImVec4(255, 0, 0, 255), ">> TARGET LOCK INDICATOR ACTIVE <<")
            end
        end
        ImGui.End()
    end
end)

-- ==========================================
-- 5. INTERCEPTOR COMMANDS (/start & /stop)
-- ==========================================
addHook("onSendPacket", function(type, packet)
    if type == 2 and packet:find("action|input") then
        local cmd = packet:match("text|(/%a+)")
        if cmd then
            cmd = cmd:lower()
            if cmd == "/start" then
                botEnabled = true
                currentState = "INIT"
                logToConsole("`2Sistem Diaktifkan. Memulai Fase INIT.`")
                return true
            elseif cmd == "/stop" then
                botEnabled = false
                equipmentReady = false
                radiusActive = false
                targetLocked = false
                pathFinished = false
                readyToPunch = false
                targetX, targetY = nil, nil
                currentState = "IDLE"
                logToConsole("`4Sistem Dinonaktifkan Bersih.`")
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
                -- Simpan posisi visual asli (dalam satuan pixel)
                local visualX = pl.posX
                local visualY = pl.posY
                
                -- Konversi ke koordinat ubin/tile game
                local currentX = visualX // 32
                local currentY = visualY // 32

                -- ----------------------------------
                -- [STATE: INIT]
                -- ----------------------------------
                if currentState == "INIT" then
                    local itemAmt = getInventoryAmount(restock_item_id)
                    if itemAmt > 0 then
                        SendPacket(2, "action|equip\nitemID|" .. restock_item_id .. "\npos|0")
                        Sleep(100)
                        SendPacket(2, "action|use\nitemID|" .. restock_item_id)
                        Sleep(100)
                        
                        equipmentReady = true
                        currentState = "SCAN"
                        logToConsole("Equipment siap. Masuk ke fase SCAN.")
                    else
                        logToConsole("`4[ERROR] Item 3206 tidak ditemukan di tas! Sistem dihentikan.`")
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
                        currentState = "PATH"
                        logToConsole("Target ditemukan di: (" .. targetX .. "," .. targetY .. "). Menghitung Jalur.")
                    else
                        radiusActive = false
                        Sleep(250)
                    end

                -- ----------------------------------
                -- [STATE: PATH]
                -- ----------------------------------
                elseif currentState == "PATH" then
                    standX, standY = findAdjacentEmptyTile(targetX, targetY)
                    
                    if standX and standY then
                        if currentX == standX and currentY == standY then
                            pathFinished = true
                            currentState = "READY"
                        else
                            local clientPing = getPingDelay()
                            
                            pcall(FindPath, standX, standY)
                            Sleep(clientPing + 50) 
                            
                            local moveTimeout = 0
                            while moveTimeout < 20 do
                                local checkPl = GetLocal()
                                if checkPl then
                                    local cx = checkPl.posX // 32
                                    local cy = checkPl.posY // 32
                                    if cx == standX and cy == standY then
                                        pathFinished = true
                                        currentState = "READY"
                                        break
                                    end
                                end
                                
                                Sleep(math.max(50, clientPing // 2))
                                moveTimeout = moveTimeout + 1
                            end
                            
                            if currentState == "PATH" then
                                targetLocked = false
                                currentState = "SCAN"
                                Sleep(200)
                            end
                        end
                    else
                        targetLocked = false
                        currentState = "SCAN"
                        Sleep(200)
                    end

                -- ----------------------------------
                -- [STATE: READY] - FIXED PUNCH PACKET
                -- ----------------------------------
                elseif currentState == "READY" then
                    readyToPunch = true
                    
                    local currentTile = GetTile(targetX, targetY)
                    if currentTile and currentTile.fg == farm_block_id then
                        
                        -- PERBAIKAN F ATAL: pos_x/y diisi posisi berdiri player, int_x/y diisi posisi balok target
                        SendPacketRaw({
                            type = 3, 
                            int_data = fist_id, 
                            pos_x = visualX, 
                            pos_y = visualY,
                            int_x = targetX,
                            int_y = targetY
                        })
                        
                        local delayPukul = getPingDelay() + 40 
                        Sleep(delayPukul)
                        
                    else
                        logToConsole("Target hancur! Mencari target berikutnya.")
                        targetLocked = false
                        pathFinished = false
                        readyToPunch = false
                        targetX, targetY = nil, nil
                        standX, standY = nil, nil
                        
                        currentState = "SCAN"
                    end
                end

            end
        end
        Sleep(50) 
    end
end)
