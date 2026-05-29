local addonName, MIS = ...
MacroIconSearch = MIS

local OIconDataProvider = nil
local icons = {}

local searchWorkerFrame = CreateFrame("Frame")

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    local hooks = { "MacroPopupFrame", "GearManagerPopupFrame" }
    
    for _, frameName in ipairs(hooks) do
        local frame = _G[frameName]
        if frame then
            frame:HookScript("OnShow", function(self)
                OIconDataProvider = self.iconDataProvider
                MacroIconSearchFrame:ClearAllPoints()
                MacroIconSearchFrame:SetParent(self)
                MacroIconSearchFrame:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
                MacroIconSearchFrame:Show()
            end)
            
            frame:HookScript("OnHide", function(self)
                MacroIconSearchFrame:Hide()
                MacroIconSearchFrame.SpellSearchBox:SetText("")
                MacroIconSearchFrame.SpellIDBox:SetText("")
                MacroIconSearchFrame.IconIDBox:SetText("")
                MacroIconSearchFrame.ItemIDBox:SetText("")
                
                searchWorkerFrame:SetScript("OnUpdate", nil)
                if MIS.searchCoroutine then MIS.searchCoroutine = nil end
                
                wipe(icons)
                
                -- Run garbage collection twice to completely flush Lua's internal string hashes
                collectgarbage("collect")
                collectgarbage("collect")
                
                -- Force the WoW client to update addon memory usage for trackers like ElvUI
                if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
            end)
        end
    end
end)

local IconDataProvider = CreateAndInitFromMixin(IconDataProviderMixin)
function IconDataProvider:GetIconByIndex(index) return icons[index] end
function IconDataProvider:GetNumIcons() return #icons end

local function SetDirectIcon(iconID)
    if not iconID then return end
    local parent = MacroIconSearchFrame:GetParent()
    if parent and parent.IconSelector then
        parent.IconSelector.selectedCallback(nil, iconID)
        parent.IconSelector:SetSelectedIndex(1)
        
        MacroIconSearchFrame.SpellSearchBox:ClearFocus()
        MacroIconSearchFrame.SpellIDBox:ClearFocus()
        MacroIconSearchFrame.IconIDBox:ClearFocus()
        MacroIconSearchFrame.ItemIDBox:ClearFocus()
    end
end

function MIS:ResetSearch()
    local parent = MacroIconSearchFrame:GetParent()
    if parent then
        parent.iconDataProvider = OIconDataProvider
        parent:Update()
    end
    if self.searchCoroutine then self.searchCoroutine = nil end
end

-- ==========================
-- Spell Handlers
-- ==========================
function MIS:OnSpellSearchEnter(editBox)
    local text = editBox:GetText()
    if text == "" then return self:ResetSearch() end
    self:StartSearch("SPELL", text:lower())
    editBox:ClearFocus()
end

function MIS:OnSpellIDEnter(editBox)
    local id = tonumber(editBox:GetText())
    if id then
        local iconID = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        if iconID then SetDirectIcon(iconID) end
    end
    editBox:SetText("")
    editBox:ClearFocus()
end

-- ==========================
-- Icon / Item Handlers
-- ==========================
function MIS:OnIconIDEnter(editBox)
    local id = tonumber(editBox:GetText())
    if id then SetDirectIcon(id) end
    editBox:SetText("")
    editBox:ClearFocus()
end

function MIS:OnItemIDEnter(editBox)
    local id = tonumber(editBox:GetText())
    if id then
        local iIcon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
        if iIcon then SetDirectIcon(iIcon) end
    end
    editBox:SetText("")
    editBox:ClearFocus()
end

-- ==========================
-- Core Search Logic
-- ==========================
function MIS:StartSearch(mode, query)
    local parent = MacroIconSearchFrame:GetParent()
    if not parent then return end

    if parent.iconDataProvider ~= IconDataProvider then
        parent.iconDataProvider = IconDataProvider
        parent.IconSelector:SetSelectionsDataProvider(
            GenerateClosure(IconDataProvider.GetIconByIndex, parent), 
            GenerateClosure(IconDataProvider.GetNumIcons, parent)
        )
    end

    if self.searchCoroutine and coroutine.status(self.searchCoroutine) ~= "dead" then
        self.searchCoroutine = nil
    end

    print("|cFF00FFFFMacroIconSearch:|r Searching... Please wait.")

    self.searchCoroutine = coroutine.create(function()
        wipe(icons)

        if mode == "SPELL" then
            for id = 1, 200000 do
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                if name and name:lower():find(query, 1, true) then
                    local iconID = C_Spell.GetSpellTexture(id)
                    if iconID then
                        tinsert(icons, iconID)
                    end
                end
                
                -- Yield to keep FPS smooth
                if id % 2500 == 0 then coroutine.yield() end
                
                -- Incrementally dump string memory during the loop to prevent RAM spikes
                if id % 10000 == 0 then collectgarbage("step", 250) end
            end
        end

        parent.IconSelector:UpdateSelections()
        print("|cFF00FFFFMacroIconSearch:|r Search complete! Found " .. #icons .. " icons.")
        
        -- Final cleanup and UI refresh
        collectgarbage("collect")
        if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
    end)

    searchWorkerFrame:SetScript("OnUpdate", function(s)
        if self.searchCoroutine and coroutine.status(self.searchCoroutine) ~= "dead" then
            local startTime = debugprofilestop()
            while debugprofilestop() - startTime < 8 do
                local ok, err = coroutine.resume(self.searchCoroutine)
                if not ok then 
                    geterrorhandler()(err)
                    s:SetScript("OnUpdate", nil)
                    break
                end
                if coroutine.status(self.searchCoroutine) == "dead" then break end
            end
        else
            s:SetScript("OnUpdate", nil)
        end
    end)
end
