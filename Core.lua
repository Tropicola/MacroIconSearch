local addonName, MIS = ...
MacroIconSearch = MIS

local OIconDataProvider = nil
local icons = {}

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
                wipe(icons)
                if MIS.searchCoroutine then MIS.searchCoroutine = nil end
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
        local sInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        if sInfo and sInfo.iconID then SetDirectIcon(sInfo.iconID) end
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
                local sInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                if sInfo and sInfo.name and sInfo.iconID and sInfo.name:lower():find(query, 1, true) then
                    tinsert(icons, sInfo.iconID)
                end
                if id % 2500 == 0 then coroutine.yield() end
            end
        end

        parent.IconSelector:UpdateSelections()
        print("|cFF00FFFFMacroIconSearch:|r Search complete! Found " .. #icons .. " icons.")
    end)

    local coFrame = CreateFrame("Frame")
    coFrame:SetScript("OnUpdate", function(s)
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
