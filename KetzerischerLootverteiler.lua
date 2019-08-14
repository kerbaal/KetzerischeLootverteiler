local ADDON, Addon = ...

local Util = Addon.Util

KetzerischerLootverteilerData = {}

local function getActiveTab()
  local tab = PanelTemplates_GetSelectedTab(KetzerischerLootverteilerFrame)
  return KetzerischerLootverteilerFrame.tabView[tab]
end

function HereticTabView_Update(self)
  self.itemView:HereticUpdate()
end

local function update(reason)
  Util.dbgprint("Updating UI (" .. reason ..")..")
  HereticTabView_Update(getActiveTab())
end

function KetzerischerLootverteilerShow()
  KetzerischerLootverteilerFrame:Show()
  update("show")
end

function KetzerischerLootverteilerToggle()
  if (KetzerischerLootverteilerFrame:IsVisible()) then
    KetzerischerLootverteilerFrame:Hide()
  else
    KetzerischerLootverteilerShow()
  end
end

-- This function assumes that there is at most one saved ID for each
-- instance name and difficulty.
function FindSavedInstanceID(instanceName, instanceDifficultyID)
  local numInstances = GetNumSavedInstances()
  for i = 1, numInstances do
    local savedInstanceName, id, reset, savedInstanceDifficultyID = GetSavedInstanceInfo(i)
    if savedInstanceName == instanceName and savedInstanceDifficultyID == instanceDifficultyID then
      return id
    end
  end
  return nil
end

function Addon:GetCurrentInstance()
  local instanceName, instanceType, instanceDifficultyID, difficultyName, maxPlayers, playerDifficulty, isDynamicInstance, mapID, instanceGroupSize = GetInstanceInfo()
  if (instanceType == "raid" or instanceType == "party") then
    local instanceID = FindSavedInstanceID(instanceName, instanceDifficultyID)
    return instanceName, instanceID, difficultyName, instanceDifficultyID
  end
  return nil
end

function Addon:DifficultyIDToString(difficultyID)
  return GetDifficultyInfo(difficultyID)
end

function Addon:GetHistoryForInstanceID(instanceName, instanceDifficultyID, instanceID)
  local match_i, match_history, noid_i, noid_history
  for i,history in ipairs(Addon.histories) do
    if instanceID and history.instanceID == instanceID and
       history.difficultyID == instanceDifficultyID and
       history.instanceName == instanceName then
      match_i, match_history = i, history
    end
    if history.instanceID == nil and
       history.difficultyID == instanceDifficultyID and
       history.instanceName == instanceName then
      noid_i, noid_history = i, history
    end
  end
  if match_i and match_history then
    return match_i, match_history
  end
  if noid_i and noid_history then
    noid_history.instanceID = instanceID
    return noid_i, noid_history
  end
  return nil
end

function Addon:GetHistoryForCurrentInstance()
  local instanceName, instanceID, difficultyName, instanceDifficultyID = Addon:GetCurrentInstance()
  instanceID = 0
  if instanceName then
    local i, history = Addon:GetHistoryForInstanceID(instanceName, instanceDifficultyID, instanceID)
    if history then return i, history end
    local newHistory = HereticList:New(instanceName, instanceDifficultyID, instanceID)
    table.insert(Addon.histories, 2, newHistory)
    return 2, newHistory
  end
  return 1, Addon.histories[1]
end

function Addon:Initialize()
  Addon.MSG_PREFIX = "KTZR_LT_VERT";
  Addon.MSG_CLAIM_MASTER = "ClaimMaster";
  Addon.MSG_CHECK_MASTER = "CheckMaster";
  Addon.MSG_DELETE_LOOT = "DeleteLoot";
  Addon.MSG_DELETE_LOOT_PATTERN = "^%s+([^ ]+)%s+(.*)$";
  Addon.MSG_RENOUNCE_MASTER = "RenounceMaster";
  Addon.MSG_ANNOUNCE_LOOT = "LootAnnounce";
  Addon.MSG_ANNOUNCE_LOOT_PATTERN = "^%s+([^ ]+)%s+(.*)$";
  Addon.MSG_ANNOUNCE_WINNER = "Winner";
  Addon.MSG_ANNOUNCE_WINNER_PATTERN = "^%s+([^ ]+)%s+([^ ]+)%s+([^ ]+)%s+([^ ]+)%s+([^ ]+)$";
  Addon.TITLE_TEXT = "Ketzerischer Lootverteiler";
  Addon.itemList = HereticList:New("master");
  Addon.histories = { HereticList:New("default") };
  Addon.activeHistoryIndex = 1;
  Addon.master = nil;
  Addon.lootCount = {};
  Addon.rolls = {};
  C_ChatInfo.RegisterAddonMessagePrefix(Addon.MSG_PREFIX);
end

function Addon:GetActiveHistory()
  return Addon.histories[Addon.activeHistoryIndex]
end

function Addon:RecomputeLootCount()
  wipe(Addon.lootCount)
  for i,entry in pairs(Addon:GetActiveHistory().entries) do
    if (entry.winner) then
      local cat = entry.winner:GetCategory()
      local record = Addon.lootCount[entry.winner.name] or {}
      Addon.lootCount[entry.winner.name] = record
      record.name = entry.winner.name
      local count = record.count or {}
      record.count = count
      count[cat] = (count[cat] or 0) + 1
    end
    if (entry.donator) then
      local record = Addon.lootCount[entry.donator] or {}
      Addon.lootCount[entry.donator] = record
      record.name = entry.donator
      local donations = record.donations or 0
      record.donations = donations + 1
    end
  end
end

function Addon:AnnouceLootCount()
  Addon:RecomputeLootCount()
  local n = 0
  for k,v in pairs(Addon.lootCount) do
    n=n+1
    local line = Util.ShortenFullName(v.name)
    if (v.donations) then
      line = line .. " donated " .. v.donations .. ""
    end
    if (v.count) then
      if (v.donations) then line = line .. " and" end
      line = line ..  " received " .. Util.formatLootCountMono(v.count, true, true)
    end
    line = line .. "."
    SendChatMessage(line, "RAID")
  end
end

function Addon:CountLootFor(name, cat)
  local entry = Addon.lootCount[name] or {}
  local count = entry.count or {}
  if cat == nil then return count end
  return count[cat] or 0
end

function Addon:CountDonationsFor(name)
  local entry = Addon.lootCount[name] or {}
  local donations = entry.donations or 0
  return donations
end

function Addon:OnWinnerUpdate(entry, prevWinner)
  Addon:RecomputeLootCount()
  update("on winner update")
  if (Addon:IsMaster()) then
    local msg = Addon.MSG_ANNOUNCE_WINNER .. " " .. entry.donator .. " " ..
      entry.itemLink .. " "

    if entry.winner then
      msg = msg .. entry.winner.name .. " " .. entry.winner.roll ..
        " " .. entry.winner.max
    else
      msg = msg .. "- - -"
    end

    Util.dbgprint ("Announcing winner: " .. msg)
    C_ChatInfo.SendAddonMessage(Addon.MSG_PREFIX, msg, "RAID")
  end
  HereticRollCollectorFrame_Update(HereticRollCollectorFrame)
end

function Addon:SetWinner(itemString, donator, sender, winnerName, rollValue, rollMax)
  local index = Addon:GetActiveHistory():GetEntryId(itemString, donator, sender)
  if not index then
    return
  end
  local entry = Addon:GetActiveHistory():GetEntry(index)
  local prevWinner = entry.winner
  rollValue, rollMax = tonumber(rollValue), tonumber(rollMax)
  if (winnerName == "-" or not rollValue or not rollMax) then
    entry.winner = nil
  else
    entry.winner = HereticRoll:New(winnerName, rollValue, rollMax)
  end
  Addon:OnWinnerUpdate(entry, prevWinner)
end

function Addon:CanModify(owner)
  return Addon:IsMaster()
    or (not Addon:HasMaster())
    or (owner ~= nil and owner ~= Addon.master)
end

local function showIfNotCombat()
  if not UnitAffectingCombat("player") then
    KetzerischerLootverteilerShow()
  end
end

function Addon:AddItem(itemString, from, sender)
  if (Addon:HasMaster() and sender ~= Addon.master) then return end
  itemString = itemString:match("item[%-?%d:]+")
  if (itemString == nil) then return end
  if (from == nil or from:gsub("%s+", "") == "") then return end
  from = from:gsub("%s+", "")
  itemString = itemString:gsub("%s+", "")

  -- Do not filter if the item comes from the lootmaster.
  if (sender ~= Addon.master or Addon:IsMaster()) then
    local quality = select(3,GetItemInfo(itemString))
    if (Addon.minRarity and quality < Addon.minRarity[1]) then
      return
    end
  end

  local item = HereticItem:New(itemString, from, sender)
  Addon.itemList:AddEntry(item)
  local historyIndex, history = Addon:GetHistoryForCurrentInstance()
  history:AddEntry(item)
  --PlaySound("igBackPackCoinSelect")
  PlaySound(SOUNDKIT.TELL_MESSAGE);
  --PlaySound("igMainMenuOptionCheckBoxOn")

  if Addon:IsMaster() then
    local msg = Addon.MSG_ANNOUNCE_LOOT .. " " .. from .. " " .. itemString
    Util.dbgprint("Announcing loot")
    C_ChatInfo.SendAddonMessage(Addon.MSG_PREFIX, msg, "RAID")
  end

  update("AddItem")
  showIfNotCombat()
end

function Addon:DeleteItem(index)
  local entry = Addon.itemList:GetEntry(index)
  entry.isCurrent = false

  if Addon:IsMaster() then
    local msg = Addon.MSG_DELETE_LOOT .. " " .. entry.donator .. " " .. entry.itemLink
    Util.dbgprint("Announcing loot deletion")
    C_ChatInfo.SendAddonMessage(Addon.MSG_PREFIX, msg, "RAID")
  end

  Addon.itemList:DeleteEntryAt(index)
  PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF);
  update("DeleteItem")
end

local function updateTitle()
  if (Addon.master) then
    local name, _ = Util.DecomposeName(Addon.master)
    KetzerischerLootverteilerTitleText:SetText(Addon.TITLE_TEXT .. ": "
      .. Util.GetPlayerLink(Addon.master, name))
  else
    KetzerischerLootverteilerTitleText:SetText(Addon.TITLE_TEXT)
  end
end

function Addon:IsMaster()
  return Util.GetFullUnitName("player") == Addon.master
end

function Addon:HasMaster()
  return Addon.master ~= nil and not Addon:IsMaster()
end

function Addon:SetMaster(name)
  Addon.master = name
  updateTitle()
end

local function IsPlayerInPartyOrRaid()
  return GetNumGroupMembers(LE_PARTY_CATEGORY_HOME) > 0
end

function Addon:IsAuthorizedToClaimMaster(unitId)
  -- Reject master claims from instance groups.
  if not unitId then return false end
  if (Util.GetFullUnitName(unitId) == Util.GetFullUnitName("player")
      and not IsPlayerInPartyOrRaid()) then
    return true
  end
  return UnitIsGroupAssistant(unitId) or UnitIsGroupLeader(unitId)
end

function Addon:ClaimMaster()
  if Addon:IsAuthorizedToClaimMaster("player") then
    print ("You proclaim yourself Ketzerischer Lootverteiler.")
    C_ChatInfo.SendAddonMessage(Addon.MSG_PREFIX, Addon.MSG_CLAIM_MASTER, "RAID")
    C_ChatInfo.SendAddonMessage(Addon.MSG_PREFIX, Addon.MSG_CLAIM_MASTER, "WHISPER", Util.GetFullUnitName("player"))
  else
    print ("Only leader or assistant may become Ketzerischer Lootverteiler.")
  end
end

function Addon:GetItemLinkFromId(id)
  local itemIndex = Addon.itemListView:IdToIndex(id);
  return Addon.itemList:GetItemLinkByID(itemIndex)
end

function Addon:ProcessClaimMaster(name)
  if (name == nil) then return end
  if (Addon.master == name) then return end
  Util.dbgprint(name .. " claims lootmastership")

  local unitId = HereticRaidInfo:GetUnitId(name)
  if (Addon:IsAuthorizedToClaimMaster(unitId)) then
    Addon:SetMaster(name)
    print ("You accepted " .. name .. " as your Ketzerischer Lootverteiler.")
  end
end

function Addon:RenounceMaster()
  if (Addon.master ~= Util.GetFullUnitName("player")) then return end
  print ("You renounce your title of Ketzerischer Lootverteiler.")
  C_ChatInfo.SendAddonMessage(Addon.MSG_PREFIX, Addon.MSG_RENOUNCE_MASTER, "RAID")
end

function Addon:ProcessRenounceMaster(name)
  if (Addon.master == name) then
    Addon:SetMaster(nil)
  end
end

function KetzerischerLootverteilerFrame_Update(self, elapsed)
  getActiveTab():Update()
end

local function eventHandlerLoot(self, event, message, sender)
  local LOOT_SELF_REGEX = gsub(LOOT_ITEM_SELF, "%%s", "(.+)")
  local LOOT_REGEX = gsub(LOOT_ITEM, "%%s", "(.+)")
  local _, _, sPlayer, itemlink = string.find(message, LOOT_REGEX)
  if not sPlayer then
    _, _, itemlink = string.find(message, LOOT_SELF_REGEX)
    sPlayer = Util.GetFullUnitName("player")
  else
    sPlayer = Util.CompleteUnitName(sPlayer)
  end
  if itemlink then
    local _, _, itemId = string.find(itemlink, "item:(%d+):")
    Util.dbgprint(sPlayer .. " got " .. itemlink)
  end
end

function Addon:AddAllItems(itemStrings, from, sender)
  for itemString in string.gmatch(itemStrings, "item[%-?%d:]+") do
    Addon:AddItem(itemString, from, sender)
  end
end

function Addon:IsTrackedDifficulity(difficultyID)
  return 14 <= difficultyID and difficultyID <= 16
end

local function eventHandlerEncounterEnd(self, event, encounterID, encounterName, difficultyID, raidSize, endStatus)
  if (endStatus == 1 and Addon:IsTrackedDifficulity(difficultyID) and
      (not Addon.minRarity or Addon.minRarity[1] < 1000)) then
    KetzerischerLootverteilerShow()
  end
  if (Addon:IsMaster() and Addon:IsAuthorizedToClaimMaster("player") ) then
    Addon:ClaimMaster()
  end
end

local function eventHandlerLogout(self, event)
  KetzerischerLootverteilerData.histories = Addon.histories
  KetzerischerLootverteilerData.activeHistoryIndex = Addon.activeHistoryIndex
  KetzerischerLootverteilerData.isVisible = KetzerischerLootverteilerFrame:IsVisible()
  KetzerischerLootverteilerData.master = Addon.master
  KetzerischerLootverteilerData.minRarity = Addon.minRarity
  KetzerischerLootverteilerData.activeTab = PanelTemplates_GetSelectedTab(KetzerischerLootverteilerFrame)
  HereticRaidInfo:Serialize(KetzerischerLootverteilerData)
end

local function eventHandlerAddonLoaded(self, event, addonName)
   if (addonName == ADDON) then
    HereticRaidInfo:Deserialize(KetzerischerLootverteilerData)
    HereticRaidInfo:Update()
    if KetzerischerLootverteilerData.activeHistoryIndex then
      Addon.activeHistoryIndex = KetzerischerLootverteilerData.activeHistoryIndex
    end
    if KetzerischerLootverteilerData.histories then
      wipe(Addon.histories)
      for i,history in pairs(KetzerischerLootverteilerData.histories) do
        if HereticList.Validate(history) then
          table.insert(Addon.histories, history)
          for i,entry in pairs(history.entries) do
            if entry.isCurrent then
              Addon.itemList:AddEntry(entry)
            end
          end
        end
      end
      if #Addon.histories == 0 then
        Addon.histories = { HereticList:New("default") }
        Addon.activeHistoryIndex = 1
      end
    end
    Addon:RecomputeLootCount()
    if KetzerischerLootverteilerData.minRarity then
      Addon.minRarity = KetzerischerLootverteilerData.minRarity
    end
    if (KetzerischerLootverteilerData.isVisible == nil or
        KetzerischerLootverteilerData.isVisible == true) then
      KetzerischerLootverteilerShow()
    end
    if (KetzerischerLootverteilerData.master and IsPlayerInPartyOrRaid()) then
      C_ChatInfo.SendAddonMessage(Addon.MSG_PREFIX, Addon.MSG_CHECK_MASTER, "WHISPER",
        KetzerischerLootverteilerData.master)
    end
    if KetzerischerLootverteilerData.activeTab then
      HereticTab_SetActiveTab(Util.toRange(KetzerischerLootverteilerFrame.tabView, KetzerischerLootverteilerData.activeTab))
    end
    update("addon loaded")
  end
end

local function eventHandlerAddonMessage(self, event, prefix, message, channel, sender)
  if (prefix ~= Addon.MSG_PREFIX) then return end
  local type, msg = message:match("^%s*([^ ]+)(.*)$")
  if (type == nil) then return end
  Util.dbgprint ("Received: " .. type)
  if (type == Addon.MSG_CLAIM_MASTER) then
    Addon:ProcessClaimMaster(sender)
  elseif (type == Addon.MSG_RENOUNCE_MASTER) then
    Addon:ProcessRenounceMaster(sender)
  elseif (type == Addon.MSG_ANNOUNCE_LOOT) then
    if not msg then return end
    local from, itemString = msg:match(Addon.MSG_ANNOUNCE_LOOT_PATTERN)
    Util.dbgprint ("Announcement: " .. from .. " " .. itemString)
    if (sender == Addon.master and not Addon:IsMaster()) then
      Addon:AddItem(itemString, from, sender)
    end
  elseif (type == Addon.MSG_DELETE_LOOT) then
    if not msg then return end
    local donator, itemString = msg:match(Addon.MSG_DELETE_LOOT_PATTERN)
    Util.dbgprint ("Deletion: " .. donator .. " " .. itemString)
    if (sender == Addon.master and not Addon:IsMaster()) then
      local index = Addon.itemList:GetEntryId(itemString, donator, sender)
      if (index) then Addon:DeleteItem(index) end
    end
  elseif (type == Addon.MSG_ANNOUNCE_WINNER) then
    if not msg then return end
    local from, itemString, winnerName, roll, rollMax = msg:match(Addon.MSG_ANNOUNCE_WINNER_PATTERN)
    Util.dbgprint ("Winner: " .. from .. " " .. itemString .. " "
      .. winnerName .. " " .. roll .. " " .. rollMax)
    if (sender == Addon.master and not Addon:IsMaster()) then
      Addon:SetWinner(itemString, from, sender, winnerName, roll, rollMax)
    end
  elseif (type == Addon.MSG_CHECK_MASTER) then
    C_ChatInfo.SendAddonMessage(Addon.MSG_PREFIX, Addon.MSG_CLAIM_MASTER, "WHISPER", sender)
  end
end

local function eventHandlerRaidRosterUpdate(self, event, arg)
  HereticRaidInfo:Update()
  if Addon:IsMaster() then
    if Addon:IsAuthorizedToClaimMaster("player") then
      for i,v in pairs(HereticRaidInfo:GetNewPlayers()) do
        C_ChatInfo.SendAddonMessage(Addon.MSG_PREFIX, Addon.MSG_CLAIM_MASTER, "WHISPER", v)
      end
    else
      Addon:RenounceMaster()
    end
  end
end

local function eventHandlerWhisper(self, event, msg, from)
  Addon:AddAllItems(msg, from, from)
end

local function eventHandlerBNChat(self, event, msg, sender, u1, u2, u3, u4, u5, u6, u7, u8, cnt, u9, bnetIDAccount)
  local bnetIDGameAccount = select(6,BNGetFriendInfoByID(bnetIDAccount))
  local _, name, client, realm = BNGetGameAccountInfo(bnetIDGameAccount)
  Util.dbgprint("BN: " .. sender .. " " .. bnetIDAccount .. " " .. name .. "-" .. realm)

  Addon:AddAllItems(msg, name .. "-" .. realm, sender)
end

local function eventHandler(self, event, ...)
  if event == "CHAT_MSG_WHISPER" then
    eventHandlerWhisper(self, event, ...)
  elseif event == "CHAT_MSG_BN_WHISPER" then
    eventHandlerBNChat(self, event, ...)
  elseif (event == "ENCOUNTER_END") then
    eventHandlerEncounterEnd(self, event, ...)
  elseif (event == "CHAT_MSG_LOOT") then
    eventHandlerLoot(self, event, ...)
  elseif (event == "PLAYER_LOGOUT") then
    eventHandlerLogout(self, event, ...)
  elseif (event == "ADDON_LOADED") then
    eventHandlerAddonLoaded(self, event, ...)
  elseif (event == "CHAT_MSG_ADDON") then
    eventHandlerAddonMessage(self, event, ...)
  elseif (event == "GROUP_ROSTER_UPDATE") then
    eventHandlerRaidRosterUpdate(self, event, ...)
  elseif (event == "GET_ITEM_INFO_RECEIVED") then
    update("ItemInfoReceived")
  elseif (event == "RAID_INSTANCE_WELCOME") then
    Util.dbgprint("RaidInstanceWelcome: " .. (select(1, ...) .. " " .. select(2, ...)))
  elseif (event == "UPDATE_INSTANCE_INFO") then
    Util.dbgprint("UpdateInstanceInfo")
  end
end


-- Keybindings
BINDING_HEADER_KETZERISCHER_LOOTVERTEILER = "Ketzerischer Lootverteiler"
BINDING_NAME_KETZERISCHER_LOOTVERTEILER_TOGGLE = "Toggle window"

-- Slashcommands
SLASH_KetzerischerLootverteiler1, SLASH_KetzerischerLootverteiler2 = '/klv', '/kpm';
function SlashCmdList.KetzerischerLootverteiler(msg, editbox)
  if (msg == "" or msg:match("^%s*toggle%s*$")) then
    KetzerischerLootverteilerToggle()
  elseif (msg:match("^%s*show%s*$")) then
    KetzerischerLootverteilerShow()
  elseif (msg:match("^%s*hide%s*$")) then
    KetzerischerLootverteilerFrame:Hide()
  elseif (msg:match("^%s*master.*$")) then
    local action, argument = msg:match("^%s*master%s+([^ ]*) ?([^ ]*)$")
    if (action == nil or action == "set") then
      Addon:ClaimMaster();
    elseif (action == "unset") then
      Addon:RenounceMaster();
    end
  elseif (msg:match("^%s*clear%s*$")) then
    Addon.itemList:DeleteAllEntries()
    update("clear")
  elseif (msg:match("^%s*list%s*$")) then
    Addon:AnnouceLootCount()
  elseif (msg:match("^%s*clearall%s*$")) then
    Addon.itemList:DeleteAllEntries()
    wipe(Addon.histories)
    Addon.histories[1] = HereticList:New("default")
    Addon.activeHistoryIndex = 1
    HereticTab_SetActiveTab(1)
    update("clearall")
  elseif (msg:match("^%s*debug%s*$")) then
    KetzerischerLootverteilerData.debug = not KetzerischerLootverteilerData.debug
    if KetzerischerLootverteilerData.debug then
      print ("Debug is now on.")
    else
      print ("Debug is now off.")
    end
  elseif (msg:match("^%s*raid%s*$")) then
    HereticRaidInfo:DebugPrint()
  else
    print ("Unknown option.")
  end
end

StaticPopupDialogs["HERETIC_LOOT_MASTER_CONFIRM_DELETE_FROM_HISTORY"] = {
  text = "Are you sure you want to delete this item permanently from history?",
  button1 = "Yes",
  button2 = "No",
  OnAccept = function(self)
    self.data.list:DeleteEntryAt(self.data.index)
    update("delete from history")
  end,
  OnCancel = function()
    -- Do nothing and keep item.
  end,
  timeout = 10,
  whileDead = true,
  hideOnEscape = true,
  hasItemFrame = 1,
}

function MasterLootItem_OnClick(self, button, down, entry)
  if (button == "RightButton" and IsModifiedClick("SHIFT")) then
    if not Addon:CanModify(self.entry.sender) then return end
    if self.index then Addon:DeleteItem(self.index) end
    return true
  end
  if (button == "RightButton" and not IsModifiedClick()) then
    HereticRollCollectorFrame:Toggle()
    return true
  end
  if (button == "LeftButton" and IsModifiedClick("ALT")) then
    local itemLink = select(2,GetItemInfo(entry.itemLink))
    local text = itemLink .. " (" .. Util.ShortenFullName(entry.donator) .. ")"
    SendChatMessage(text, "RAID")
    HereticRollCollectorFrame_BeginRollCollection(HereticRollCollectorFrame, entry)
    return true
  end
  return false
end

function HistoryLootItem_OnClick(self, button, down)
  if (button == "RightButton" and IsModifiedClick()) then
    if not Addon:CanModify(self.entry.sender) then return end
    if self.entry.isCurrent then
      print ("Refusing to delete item from history that is still on Master page.")
    elseif self.entry.winner then
      print ("Refusing to delete item from history that has a winner assigned.")
    else
      StaticPopup_Show("HERETIC_LOOT_MASTER_CONFIRM_DELETE_FROM_HISTORY", "", "",
        {useLinkForItemInfo = true, link = self.entry.itemLink, list = Addon:GetActiveHistory(), index = self.index})
    end
    return true
  end
  -- Disable whispering for history items.
  if (button == "RightButton") then return true end
  return false
end

function KetzerischerLootverteilerFrame_GetItemAtCursor(self)
  local frame = HereticHistoryScrollFrame_GetItemAtCursor(getActiveTab().itemView)
  if frame then return frame end
  frame = HereticRollCollectorFrame
  if (frame and frame:IsMouseOver() and frame:IsVisible()) then
    return frame
  end
  return nil
end

function KetzerischerLootverteilerFrame_OnLoad(self)
  Addon:Initialize()
  HereticRaidInfo:Initialize()
  KetzerischerLootverteilerFrame:SetScript("OnEvent", eventHandler);
  KetzerischerLootverteilerFrame:RegisterEvent("CHAT_MSG_WHISPER");
  KetzerischerLootverteilerFrame:RegisterEvent("CHAT_MSG_BN_WHISPER");
  KetzerischerLootverteilerFrame:RegisterEvent("CHAT_MSG_LOOT");
  KetzerischerLootverteilerFrame:RegisterEvent("ENCOUNTER_END");
  KetzerischerLootverteilerFrame:RegisterEvent("ADDON_LOADED");
  KetzerischerLootverteilerFrame:RegisterEvent("PLAYER_LOGOUT");
  KetzerischerLootverteilerFrame:RegisterEvent("CHAT_MSG_ADDON");
  KetzerischerLootverteilerFrame:RegisterEvent("RAID_ROSTER_UPDATE");
  KetzerischerLootverteilerFrame:RegisterEvent("GROUP_ROSTER_UPDATE");
  KetzerischerLootverteilerFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED");

  self:RegisterForDrag("LeftButton");

  KetzerischerLootverteilerFrame.tabView[1].itemView.HereticUpdate = HereticHistoryScrollFrame_Update
  KetzerischerLootverteilerFrame.tabView[1].itemView.itemList = Addon.itemList
  KetzerischerLootverteilerFrame.tabView[1].itemView.HereticOnItemClicked =  MasterLootItem_OnClick
  KetzerischerLootverteilerFrame.tabView[2].itemView.HereticUpdate =
    function (self)
      self.itemList = Addon:GetActiveHistory()
      HereticHistoryScrollFrame_Update(self)
    end
  KetzerischerLootverteilerFrame.tabView[2].itemView.itemList = Addon.histories[1]
  KetzerischerLootverteilerFrame.tabView[2].itemView.HereticOnItemClicked = HistoryLootItem_OnClick
  KetzerischerLootverteilerFrame.tabView[3].itemView.HereticUpdate =
    function (self)
      HereticPlayerInfoScrollFrame_Update(self)
    end

  KetzerischerLootverteilerFrame.GetItemAtCursor = KetzerischerLootverteilerFrame_GetItemAtCursor
  PanelTemplates_SetNumTabs(KetzerischerLootverteilerFrame, #KetzerischerLootverteilerFrame.tabView);
  HereticTab_SetActiveTab(1)
end

function KetzerischerLootverteilerFrame_OnDragStart()
  KetzerischerLootverteilerFrame:StartMoving();
end

function KetzerischerLootverteilerFrame_OnDragStop()
  KetzerischerLootverteilerFrame:StopMovingOrSizing();
end

local function KetzerischerLootverteilerRarityDropDown_OnClick(self)
   UIDropDownMenu_SetSelectedID(KetzerischerLootverteilerRarityDropDown, self:GetID())
   Addon.minRarity = { self.value, self:GetID() }
end

function KetzerischerLootverteilerRarityDropDown_Initialize(self, level)
  for i = 0, 5 do
    local r, g, b, hex = GetItemQualityColor(i)
    local info = UIDropDownMenu_CreateInfo()
    info.text = "|c" .. hex .. _G["ITEM_QUALITY" .. i .. "_DESC"] .. "|r"
    info.value = i
    info.func = KetzerischerLootverteilerRarityDropDown_OnClick
    UIDropDownMenu_AddButton(info, level)
  end
  local info = UIDropDownMenu_CreateInfo()
  info.text = "|cFFFF0000" .. DISABLE .. "|r"
  info.value = 1000
  info.func = KetzerischerLootverteilerRarityDropDown_OnClick
  UIDropDownMenu_AddButton(info, level)
  UIDropDownMenu_JustifyText(self, "LEFT")
  UIDropDownMenu_SetWidth(self, 100);
end


function HereticTab_SetActiveTab(id)
  PanelTemplates_SetTab(KetzerischerLootverteilerFrame, id);
  for i,tab in pairs(KetzerischerLootverteilerFrame.tabView) do
    if i == id then
      tab:Show();
    else
      tab:Hide();
    end
  end
  update("set active tab")
end

function HereticTab_OnClick(self)
  HereticTab_SetActiveTab(self:GetID())
end


function Addon:SetHistoryDropDown(id)
  Addon.activeHistoryIndex = id
  Addon:RecomputeLootCount()
  update("change history")
end


local function KetzerischerLootverteilerHistoryDropDown_OnClick(self)
  UIDropDownMenu_SetSelectedID(KetzerischerLootverteilerHistoryDropDown, self:GetID())
  Addon:SetHistoryDropDown(self:GetID())
end


function KetzerischerLootverteilerHistoryDropDown_Initialize(self, level)
  UIDropDownMenu_SetWidth(self, 200);
  UIDropDownMenu_JustifyText(self, "LEFT")
  if not Addon.histories or not Addon.activeHistoryIndex or #Addon.histories < 1 then return end

  for i, h in ipairs(Addon.histories or {}) do
    local info = UIDropDownMenu_CreateInfo()
    info.text = h.instanceName .. " " .. ((h.difficultyID and "("..Addon:DifficultyIDToString(h.difficultyID) .. ")") or "") .. " " .. (h.instanceID or "")
    info.value = i
    info.func = KetzerischerLootverteilerHistoryDropDown_OnClick
    UIDropDownMenu_AddButton(info, level)
  end
end

function KetzerischerLootverteilerRarityDropDown_OnShow(self)
  UIDropDownMenu_Initialize(self, KetzerischerLootverteilerRarityDropDown_Initialize);
  if not Addon.minRarity then return end
  UIDropDownMenu_SetSelectedID(self, Addon.minRarity[2])
end

function KetzerischerLootverteilerHistoryDropDown_OnShow(self)
  UIDropDownMenu_Initialize(self, KetzerischerLootverteilerHistoryDropDown_Initialize);
  UIDropDownMenu_SetSelectedID(self, Addon.activeHistoryIndex)
end

function KetzerischerLootverteilerRollButton_OnClick(self)
   HereticRollCollectorFrame:Toggle()
end

function HereticPlayerInfo_OnClick(self)
  Util.dbgprint("clicked")
end

function HereticPlayerInfo_OnEnter(self)

end

function HereticPlayerInfoScrollFrame_OnLoad(self)
  HybridScrollFrame_OnLoad(self);
  self.update = HereticPlayerInfoScrollFrame_Update;
  self.scrollBar.doNotHide = true
  self.dynamic =
    function (offset)
      return math.floor(offset / 20), offset % 20
    end
  HybridScrollFrame_CreateButtons(self, "HereticPlayerInfoTemplate");
end

function HereticLootTally_OnEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
  local categories = ""
  local first = true
  for category,max in pairs(HereticRoll.GetCategories()) do
    local coloredCategory = HereticRoll.GetColoredCategoryName(category);
    categories = coloredCategory .. (first and " " or ", ") .. categories
    first = false
  end
  local text = "Shows items |cff00ccffdonated|r and received in categories "
  GameTooltip:SetText(text .. categories);
end

function HereticLootTally_SetFromPlayer(self, name)
  local donations = Addon:CountDonationsFor(name)
  if donations > 0 then
    self.donated:SetFormattedText("|cff00ccff%d|r /", donations);
  else
    self.donated:SetText("");
  end
  local count = Addon:CountLootFor(name)
  self.received:SetText(Util.formatLootCount(count))
end

function HereticPlayerInfoScrollFrame_Update(self)
  local scrollFrame = KetzerischerLootverteilerFrameTabView3Container
  local offset = HybridScrollFrame_GetOffset(scrollFrame);
  local buttons = scrollFrame.buttons;
  local numButtons = #buttons;
  local buttonHeight = buttons[1]:GetHeight();

  local playernames={}
  local n=0

  for k,v in pairs(Addon.lootCount) do
    n=n+1
    playernames[n]=k
  end

  for i=1, numButtons do
    local frame = buttons[i];
    local index = i + offset;
    if (index <= n) then
      frame:SetID(index);
      frame.name:SetText(HereticRaidInfo:GetColoredPlayerName(playernames[index]));
      HereticLootTally_SetFromPlayer(frame.lootTally, playernames[index])
      frame:Show()
    else
      frame:Hide()
    end
  end
  HybridScrollFrame_Update(scrollFrame, n * buttonHeight, scrollFrame:GetHeight());
end

function HereticHistoryScrollFrame_OnLoad(self)
  HybridScrollFrame_OnLoad(self);
  self.update = HereticHistoryScrollFrame_Update;
  self.scrollBar.doNotHide = true
  --self.dynamic =
  --  function (offset)
  --    return math.floor(offset / 20), offset % 20
  --  end
  HybridScrollFrame_CreateButtons(self, "HereticLootFrame");
end

function HereticHistoryScrollFrame_Update(self)
  if not self or not self.itemList then return end
  local scrollFrame = self
  local offset = HybridScrollFrame_GetOffset(scrollFrame);
  local buttons = scrollFrame.buttons;
  local numButtons = #buttons;
  local buttonHeight = buttons[1]:GetHeight();
  local itemList = self.itemList
  local n = itemList:Size();
  Util.dbgprint("update history list")
  for i=1, numButtons do
    local frame = buttons[i];
    local index = i + offset;
    HereticLootFrame_SetLoot(frame, index, itemList:GetEntry(index))
    HereticLootFrame_Update(frame)
    frame.HereticOnClick = scrollFrame.HereticOnItemClicked
  end
  HybridScrollFrame_Update(scrollFrame, n * buttonHeight, scrollFrame:GetHeight());
end

function HereticHistoryScrollFrame_GetItemAtCursor(self)
  if not self or not self.itemList then return nil end
  local buttons = self.buttons;
  local numButtons = #buttons;
  for i=1, numButtons do
    local frame = buttons[i];
    if (frame and frame:IsMouseOver() and frame:IsVisible()) then
      return frame
    end
  end
  return nil
end
