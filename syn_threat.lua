local ADDON_NAME = ...
local SynThreatOptionsCategory

local frame = CreateFrame("Frame", "SynThreatFrame", UIParent)
frame:SetSize(280, 70)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")

frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.text:SetAllPoints()
frame.text:SetJustifyH("CENTER")
frame.text:SetJustifyV("TOP")

local bgTexture = frame:CreateTexture(nil, "BACKGROUND")
bgTexture:SetAllPoints(frame)
bgTexture:Hide()

local DEFAULTS = {
  hidden = false,
  lock = false,
  showSecond = true,
  showPercent = true,
  scale = 1,
  onlyInCombat = false,
  customTextColor = false,
  textColor = { r = 1, g = 1, b = 1 },
  customBg = false,
  bgTransparent = false,
  bgColor = { r = 0, g = 0, b = 0, a = 0.5 },
}

local function InitDB()
  SynThreatDB = SynThreatDB or {}
  for k, v in pairs(DEFAULTS) do
    if SynThreatDB[k] == nil then
      if type(v) == "table" then
        local copy = {}
        for tk, tv in pairs(v) do
          copy[tk] = tv
        end
        SynThreatDB[k] = copy
      else
        SynThreatDB[k] = v
      end
    elseif type(v) == "table" then
      for tk, tv in pairs(v) do
        if SynThreatDB[k][tk] == nil then
          SynThreatDB[k][tk] = tv
        end
      end
    end
  end
end

local function ApplyPosition()
  if SynThreatDB and SynThreatDB.point then
    frame:ClearAllPoints()
    frame:SetPoint(SynThreatDB.point, UIParent, SynThreatDB.relativePoint, SynThreatDB.x, SynThreatDB.y)
  else
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
  end
end

local function SavePosition()
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  SynThreatDB = SynThreatDB or {}
  SynThreatDB.point = point
  SynThreatDB.relativePoint = relativePoint
  SynThreatDB.x = x
  SynThreatDB.y = y
end

frame:SetScript("OnDragStart", function(self)
  if InCombatLockdown() then
    return
  end
  if SynThreatDB and SynThreatDB.lock then
    return
  end
  if IsShiftKeyDown() then
    self:StartMoving()
  end
end)

frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  SavePosition()
end)

local function BuildUnitList()
  local units = {}
  if IsInRaid() then
    local n = GetNumGroupMembers()
    for i = 1, n do
      units[#units + 1] = "raid" .. i
    end
  elseif IsInGroup() then
    units[#units + 1] = "player"
    for i = 1, 4 do
      units[#units + 1] = "party" .. i
    end
  else
    units[#units + 1] = "player"
  end
  return units
end

local function HasValidTarget()
  if not UnitExists("target") or UnitIsDead("target") then
    return false
  end
  if not UnitCanAttack("player", "target") then
    return false
  end
  return true
end

local function GetThreatLeaders()
  if not HasValidTarget() then
    return nil
  end

  local units = BuildUnitList()
  local entries = {}
  local tankEntry

  for _, unit in ipairs(units) do
    if UnitExists(unit) then
      local isTanking, status, threatPercent, rawThreatPercent, threatValue = UnitDetailedThreatSituation(unit, "target")
      if threatValue and threatValue > 0 then
        local compare = rawThreatPercent or threatPercent or 0
        local entry = {
          unit = unit,
          raw = rawThreatPercent,
          pct = threatPercent,
          status = status,
          compare = compare,
          isTanking = isTanking,
        }
        entries[#entries + 1] = entry
        if isTanking and (not tankEntry or compare > tankEntry.compare) then
          tankEntry = entry
        end
      end
    end
  end

  if #entries == 0 then
    return nil
  end

  table.sort(entries, function(a, b)
    return a.compare > b.compare
  end)

  local primary = tankEntry or entries[1]
  local secondary
  for _, entry in ipairs(entries) do
    if entry.unit ~= primary.unit then
      secondary = entry
      break
    end
  end

  return primary, secondary
end

local function SetTextColorForUnit(unit)
  if SynThreatDB and SynThreatDB.customTextColor and SynThreatDB.textColor then
    local c = SynThreatDB.textColor
    frame.text:SetTextColor(c.r or 1, c.g or 1, c.b or 1)
    return
  end
  if UnitIsPlayer(unit) then
    local _, class = UnitClass(unit)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then
      frame.text:SetTextColor(color.r, color.g, color.b)
      return
    end
  end
  frame.text:SetTextColor(1, 1, 1)
end

local function SetNeutralTextColor(r, g, b)
  if SynThreatDB and SynThreatDB.customTextColor and SynThreatDB.textColor then
    local c = SynThreatDB.textColor
    frame.text:SetTextColor(c.r or 1, c.g or 1, c.b or 1)
  else
    frame.text:SetTextColor(r, g, b)
  end
end

local function ApplyBackground()
  if SynThreatDB and SynThreatDB.customBg then
    local c = SynThreatDB.bgColor or {}
    local alpha = c.a or 0.5
    if SynThreatDB.bgTransparent then
      alpha = 0
    end
    bgTexture:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, alpha)
    bgTexture:Show()
  else
    bgTexture:Hide()
  end
end

local function FormatThreatLine(label, entry)
  if not entry then
    return label .. ": N/A"
  end

  local name = UnitName(entry.unit) or "Unknown"
  if entry.unit == "player" then
    name = "You"
  end

  local pctText = ""
  if SynThreatDB and SynThreatDB.showPercent then
    if entry.raw then
      pctText = string.format(" (%.0f%%)", entry.raw)
    elseif entry.pct then
      pctText = string.format(" (%.0f%%)", entry.pct)
    end
  end

  return label .. ": " .. name .. pctText
end

local function UpdateDisplay()
  if SynThreatDB and SynThreatDB.onlyInCombat then
    if InCombatLockdown() then
      if not SynThreatDB.hidden then
        frame:Show()
      end
    else
      frame:Hide()
      return
    end
  end

  if not HasValidTarget() then
    frame.text:SetText("No hostile target")
    SetNeutralTextColor(0.7, 0.7, 0.7)
    return
  end

  local targetName = UnitName("target") or "Target"
  local primary, secondary = GetThreatLeaders()

  local primaryLabel = "Aggro"
  if primary and not primary.isTanking then
    primaryLabel = "Threat lead"
  end

  local primaryLine = FormatThreatLine(primaryLabel, primary)
  local display = targetName .. "\n" .. primaryLine
  if SynThreatDB and SynThreatDB.showSecond then
    local secondaryLine = FormatThreatLine("Next", secondary)
    display = display .. "\n" .. secondaryLine
  end

  frame.text:SetText(display)

  if primary then
    SetTextColorForUnit(primary.unit)
  else
    SetNeutralTextColor(1, 1, 1)
  end
end

local function OnEvent(self, event, ...)
  if event == "PLAYER_LOGIN" then
    InitDB()
    ApplyPosition()
    frame:SetScale(SynThreatDB.scale or 1)
    ApplyBackground()
    if SynThreatDB.hidden then
      self:Hide()
    else
      self:Show()
    end
  end
  if event == "PLAYER_REGEN_ENABLED" and SynThreatDB and SynThreatDB.onlyInCombat then
    self:Hide()
  end
  if event == "PLAYER_REGEN_DISABLED" and SynThreatDB and SynThreatDB.onlyInCombat then
    if not SynThreatDB.hidden then
      self:Show()
    end
  end
  UpdateDisplay()
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
frame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:SetScript("OnEvent", OnEvent)

SLASH_SYNTHREAT1 = "/synt"
local function OpenOptionsPanel()
  if Settings and Settings.OpenToCategory and SynThreatOptionsCategory then
    Settings.OpenToCategory(SynThreatOptionsCategory.ID)
    return
  end
  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory("Syn Threat")
    InterfaceOptionsFrame_OpenToCategory("Syn Threat")
  elseif InterfaceOptionsFrame and InterfaceOptionsFrame.OpenToCategory then
    InterfaceOptionsFrame:OpenToCategory("Syn Threat")
  end
end

SlashCmdList["SYNTHREAT"] = function(msg)
  msg = (msg or ""):lower()
  SynThreatDB = SynThreatDB or {}

  if msg == "hide" then
    frame:Hide()
    SynThreatDB.hidden = true
  elseif msg == "show" then
    frame:Show()
    SynThreatDB.hidden = false
    UpdateDisplay()
  elseif msg == "reset" then
    SynThreatDB.hidden = false
    ApplyPosition()
    UpdateDisplay()
  elseif msg == "options" or msg == "config" then
    OpenOptionsPanel()
  else
    print("syn_threat commands: /synt show, /synt hide, /synt reset, /synt options")
  end
end

local function CreateOptionsPanel()
  local panel = CreateFrame("Frame", "SynThreatOptionsPanel")
  panel.name = "Syn Threat"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Syn Threat")

  local subText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subText:SetJustifyH("LEFT")
  subText:SetText("Display who has aggro and who is next in threat on your target.")

  local function CreateCheckbox(name, label, tooltip, anchor, yOffset)
    local cb = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
    local text = _G[cb:GetName() .. "Text"]
    if text then
      text:SetText(label)
    end
    cb.tooltipText = label
    cb.tooltipRequirement = tooltip
    return cb
  end

  local UpdateSwatches

  local enableCb = CreateFrame("CheckButton", "SynThreatOptionsEnable", panel, "InterfaceOptionsCheckButtonTemplate")
  enableCb:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", -2, -12)
  _G[enableCb:GetName() .. "Text"]:SetText("Enable display")
  enableCb:SetScript("OnClick", function(self)
    SynThreatDB.hidden = not self:GetChecked()
    if SynThreatDB.hidden then
      frame:Hide()
    else
      frame:Show()
      UpdateDisplay()
    end
  end)

  local lockCb = CreateCheckbox("SynThreatOptionsLock", "Lock frame", "Disable Shift-drag move", enableCb, -8)
  lockCb:SetScript("OnClick", function(self)
    SynThreatDB.lock = self:GetChecked()
  end)

  local secondCb = CreateCheckbox("SynThreatOptionsSecond", "Show second threat", "Show the next highest threat holder",
    lockCb, -8)
  secondCb:SetScript("OnClick", function(self)
    SynThreatDB.showSecond = self:GetChecked()
    UpdateDisplay()
  end)

  local percentCb = CreateCheckbox("SynThreatOptionsPercent", "Show percentages", "Show threat percentage values",
    secondCb, -8)
  percentCb:SetScript("OnClick", function(self)
    SynThreatDB.showPercent = self:GetChecked()
    UpdateDisplay()
  end)

  local combatCb = CreateCheckbox("SynThreatOptionsCombatOnly", "Only show in combat", "Hide the display out of combat",
    percentCb, -8)
  combatCb:SetScript("OnClick", function(self)
    SynThreatDB.onlyInCombat = self:GetChecked()
    if SynThreatDB.onlyInCombat and not InCombatLockdown() then
      frame:Hide()
    elseif not SynThreatDB.hidden then
      frame:Show()
    end
    UpdateDisplay()
  end)

  local customTextCb = CreateCheckbox("SynThreatOptionsCustomText", "Use custom text color",
    "Override class colors with a custom color", combatCb, -8)
  customTextCb:SetScript("OnClick", function(self)
    SynThreatDB.customTextColor = self:GetChecked()
    UpdateDisplay()
    UpdateSwatches()
  end)

  local textColorBtn = CreateFrame("Button", "SynThreatOptionsTextColor", panel, "UIPanelButtonTemplate")
  textColorBtn:SetSize(120, 22)
  textColorBtn:SetPoint("TOPLEFT", customTextCb, "BOTTOMLEFT", 0, -6)
  textColorBtn:SetText("Text color")
  local textSwatch = textColorBtn:CreateTexture(nil, "ARTWORK")
  textSwatch:SetSize(14, 14)
  textSwatch:SetPoint("LEFT", textColorBtn, "RIGHT", 6, 0)

  local customBgCb = CreateCheckbox("SynThreatOptionsCustomBg", "Use custom background",
    "Show a colored background behind the text", textColorBtn, -10)
  customBgCb:SetScript("OnClick", function(self)
    SynThreatDB.customBg = self:GetChecked()
    ApplyBackground()
    UpdateSwatches()
  end)

  local transparentBgCb = CreateCheckbox("SynThreatOptionsTransparentBg", "Transparent background",
    "Force background alpha to 0", customBgCb, -8)
  transparentBgCb:SetScript("OnClick", function(self)
    SynThreatDB.bgTransparent = self:GetChecked()
    ApplyBackground()
    UpdateSwatches()
  end)

  local bgColorBtn = CreateFrame("Button", "SynThreatOptionsBgColor", panel, "UIPanelButtonTemplate")
  bgColorBtn:SetSize(120, 22)
  bgColorBtn:SetPoint("TOPLEFT", transparentBgCb, "BOTTOMLEFT", 0, -6)
  bgColorBtn:SetText("Background")
  local bgSwatch = bgColorBtn:CreateTexture(nil, "ARTWORK")
  bgSwatch:SetSize(14, 14)
  bgSwatch:SetPoint("LEFT", bgColorBtn, "RIGHT", 6, 0)

  local scaleSlider = CreateFrame("Slider", "SynThreatOptionsScale", panel, "OptionsSliderTemplate")
  scaleSlider:SetPoint("TOPLEFT", bgColorBtn, "BOTTOMLEFT", 0, -18)
  scaleSlider:SetMinMaxValues(0.8, 1.5)
  scaleSlider:SetValueStep(0.05)
  scaleSlider:SetObeyStepOnDrag(true)
  _G[scaleSlider:GetName() .. "Low"]:SetText("80%")
  _G[scaleSlider:GetName() .. "High"]:SetText("150%")
  _G[scaleSlider:GetName() .. "Text"]:SetText("Scale")
  scaleSlider:SetScript("OnValueChanged", function(self, value)
    SynThreatDB.scale = value
    frame:SetScale(value)
  end)

  UpdateSwatches = function()
    if SynThreatDB.textColor then
      textSwatch:SetColorTexture(SynThreatDB.textColor.r or 1, SynThreatDB.textColor.g or 1, SynThreatDB.textColor.b or 1,
        1)
    end
    if SynThreatDB.bgColor then
      local alpha = SynThreatDB.bgColor.a or 0.5
      if SynThreatDB.bgTransparent then
        alpha = 0
      end
      bgSwatch:SetColorTexture(SynThreatDB.bgColor.r or 0, SynThreatDB.bgColor.g or 0, SynThreatDB.bgColor.b or 0, alpha)
    end
    textColorBtn:SetEnabled(SynThreatDB.customTextColor)
    bgColorBtn:SetEnabled(SynThreatDB.customBg)
  end

  local function OpenColorPicker(color, hasOpacity, onChange)
    local r = color.r or 1
    local g = color.g or 1
    local b = color.b or 1
    local a = color.a or 1

    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
      local function ApplyColor()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = a
        if hasOpacity then
          if ColorPickerFrame.GetColorAlpha then
            na = 1 - (ColorPickerFrame:GetColorAlpha() or 0)
          else
            na = 1 - (ColorPickerFrame.opacity or 0)
          end
        end
        onChange(nr, ng, nb, na)
      end

      local info = {
        r = r,
        g = g,
        b = b,
        hasOpacity = hasOpacity,
        opacity = hasOpacity and (1 - a) or 0,
        swatchFunc = ApplyColor,
        opacityFunc = ApplyColor,
        cancelFunc = function(prev)
          if type(prev) == "table" then
            onChange(prev.r or r, prev.g or g, prev.b or b, prev.a or a)
          else
            onChange(r, g, b, a)
          end
        end,
      }

      ColorPickerFrame:SetupColorPickerAndShow(info)
      return
    end

    if not ColorPickerFrame and LoadAddOn then
      LoadAddOn("Blizzard_ColorPickerFrame")
    end
    if not ColorPickerFrame then
      return
    end

    local function ApplyColor()
      local nr, ng, nb = ColorPickerFrame:GetColorRGB()
      local na = hasOpacity and (1 - (ColorPickerFrame.opacity or 0)) or 1
      onChange(nr, ng, nb, na)
    end

    ColorPickerFrame.hasOpacity = hasOpacity
    ColorPickerFrame.opacity = hasOpacity and (1 - a) or 0
    ColorPickerFrame.previousValues = { r = r, g = g, b = b, a = a }
    ColorPickerFrame.func = ApplyColor
    ColorPickerFrame.opacityFunc = ApplyColor
    ColorPickerFrame.cancelFunc = function(prev)
      if type(prev) == "table" then
        onChange(prev.r or r, prev.g or g, prev.b or b, prev.a or a)
      else
        onChange(r, g, b, a)
      end
    end

    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Show()
  end

  textColorBtn:SetScript("OnClick", function()
    if not SynThreatDB.textColor then
      SynThreatDB.textColor = { r = 1, g = 1, b = 1 }
    end
    OpenColorPicker(SynThreatDB.textColor, false, function(r, g, b)
      SynThreatDB.textColor.r = r
      SynThreatDB.textColor.g = g
      SynThreatDB.textColor.b = b
      UpdateDisplay()
      UpdateSwatches()
    end)
  end)

  bgColorBtn:SetScript("OnClick", function()
    if not SynThreatDB.bgColor then
      SynThreatDB.bgColor = { r = 0, g = 0, b = 0, a = 0.5 }
    end
    OpenColorPicker(SynThreatDB.bgColor, true, function(r, g, b, a)
      SynThreatDB.bgColor.r = r
      SynThreatDB.bgColor.g = g
      SynThreatDB.bgColor.b = b
      SynThreatDB.bgColor.a = a
      ApplyBackground()
      UpdateSwatches()
    end)
  end)

  panel:SetScript("OnShow", function()
    InitDB()
    enableCb:SetChecked(not SynThreatDB.hidden)
    lockCb:SetChecked(SynThreatDB.lock)
    secondCb:SetChecked(SynThreatDB.showSecond)
    percentCb:SetChecked(SynThreatDB.showPercent)
    combatCb:SetChecked(SynThreatDB.onlyInCombat)
    customTextCb:SetChecked(SynThreatDB.customTextColor)
    customBgCb:SetChecked(SynThreatDB.customBg)
    transparentBgCb:SetChecked(SynThreatDB.bgTransparent)
    scaleSlider:SetValue(SynThreatDB.scale or 1)
    UpdateSwatches()
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    SynThreatOptionsCategory = category
  else
    if not InterfaceOptions_AddCategory and LoadAddOn then
      LoadAddOn("Blizzard_InterfaceOptions")
    end
    if InterfaceOptions_AddCategory then
      InterfaceOptions_AddCategory(panel)
    end
  end
end

CreateOptionsPanel()
