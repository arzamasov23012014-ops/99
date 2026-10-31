-- ============================================================
-- SAKURA v5 (99 Nights) — PINK EDITION
-- Рубка и аура теперь работают так же, как в самой игре:
--   топор лежит в lp.Inventory (не в Backpack), удар = RemoteEvents.ToolDamageObject
-- ============================================================
local env=(getgenv and getgenv()) or _G
if env.Sakura99Unload then pcall(env.Sakura99Unload) env.Sakura99Unload=nil task.wait(0.3) end

local okR,Rayfield=pcall(function() return loadstring(game:HttpGet('https://sirius.menu/rayfield'))() end)
if not okR or not Rayfield then warn("Sakura: не удалось загрузить Rayfield") return end

local Players=game:GetService("Players")
local WS=game:GetService("Workspace")
local RS=game:GetService("RunService")
local RepS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local lp=Players.LocalPlayer
local Running=true
local conns={}
local function Conn(c) conns[#conns+1]=c return c end

local Config={
    AutoChop=false,ChopRange=40,ChopRate=0.35,ChopMulti=2,
    TreeKW="small tree",TreeNot="root, stump, treehouse",
    KillAura=false,AuraRange=20,AuraRate=0.3,AuraMulti=false,MobKW="wolf, bat, cultist",
    IdByCounter=false,
    ItemESP=true,MobESP=true,ESPDist=400,AutoPick=false,PickRange=25,PromptInstant=true,
    Speed=false,SpeedVal=32,Fly=false,FlySpeed=60,Noclip=false,InfJump=false,JumpPower=55,AntiAFK=true,
    FullBright=false,NoFog=false,KeepDay=false,FPSBoost=false,
}
-- категории предметов (поиск по части названия, регистр не важен)
local CATS={
    {id="fuel",ru="Бревна и топливо",icon="🪵",color=Color3.fromRGB(255,170,60),kw={"log","coal","fuel","oil barrel","canister"}},
    {id="child",ru="Дети",icon="🧒",color=Color3.fromRGB(255,105,180),kw={"kid","child"}},
    {id="chest",ru="Сундуки",icon="📦",color=Color3.fromRGB(255,215,0),kw={"chest"}},
    {id="med",ru="Лечение",icon="🩹",color=Color3.fromRGB(80,255,120),kw={"bandage","medkit","med kit"}},
    {id="food",ru="Еда",icon="🍖",color=Color3.fromRGB(255,120,80),kw={"carrot","berry","berries","morsel","steak","meat","apple","pumpkin","corn","chili","stew","cake","pie","ribs"}},
    {id="weapon",ru="Оружие и инструменты",icon="⚔️",color=Color3.fromRGB(120,180,255),kw={"axe","sword","spear","revolver","rifle","shotgun","pistol","morning","flashlight","ray gun","flamethrower","crossbow","machete","sack","compass"}},
    {id="mat",ru="Материалы",icon="🔩",color=Color3.fromRGB(190,190,205),kw={"scrap","bolt","sheet","nail","gear","wire","metal","screw","tire","diamond"}},
    {id="camp",ru="Костёр",icon="🔥",color=Color3.fromRGB(255,90,40),kw={"campfire","camp fire","fire pit"}},
}
local CAT_BY_ID={}
for _,c in ipairs(CATS) do
    CAT_BY_ID[c.id]=c
    Config["ESP_"..c.id]=(c.id~="food" and c.id~="mat")
    Config["Pick_"..c.id]=(c.id=="fuel" or c.id=="med")
end
local nameCache={}
local function CatOfName(n)
    local c=nameCache[n]
    if c==nil then
        c=false
        for _,cat in ipairs(CATS) do
            for _,k in ipairs(cat.kw) do
                if n:find(k,1,true) then c=cat.id break end
            end
            if c then break end
        end
        nameCache[n]=c
    end
    return c or nil
end
local function notify(title,content,dur)
    pcall(function() Rayfield:Notify({Title=title,Content=content,Duration=dur or 4}) end)
end

-- ===================== КЭШ ОБЪЕКТОВ (события, без полного скана каждые N секунд) =====================
local trees,mobs,items={}, {}, {}
local treeKW,mobKW,treeNot={}, {}, {}
local treeCache={}
local function parseKW(s)
    local list={}
    for kw in (s or ""):gmatch("[^,]+") do
        kw=kw:lower():match("^%s*(.-)%s*$")
        if kw~="" then list[#list+1]=kw end
    end
    return list
end
local function setKW()
    treeKW=parseKW(Config.TreeKW)
    mobKW=parseKW(Config.MobKW)
    treeNot=parseKW(Config.TreeNot)
    treeCache={}
end
setKW()
local function isTreeName(n) -- n в нижнем регистре; поиск без шаблонов Lua (plain)
    local c=treeCache[n]
    if c==nil then
        c=false
        local blocked=false
        for _,k in ipairs(treeNot) do
            if n:find(k,1,true) then blocked=true break end
        end
        if not blocked then
            for _,k in ipairs(treeKW) do
                if n:find(k,1,true) then c=true break end
            end
        end
        treeCache[n]=c
    end
    return c
end
local function track(o)
    if o:IsA("Humanoid") then
        local m=o.Parent
        if m and m:IsA("Model") and not Players:GetPlayerFromCharacter(m) then
            local n=m.Name:lower()
            -- потерянных детей и служебные модели ("Character", "FlashlightFill") не бьём
            if not n:find("kid",1,true) and not n:find("child",1,true) and n~="character" and not n:find("flashlightfill",1,true) then
                mobs[m]=true
            end
        end
    elseif o:IsA("Model") then
        if not o:FindFirstChildOfClass("Humanoid") then
            local n=o.Name:lower()
            if isTreeName(n) then trees[o]=true
            else
                local cid=CatOfName(n)
                if cid and not Players:GetPlayerFromCharacter(o) then items[o]=cid end
            end
        end
    elseif o:IsA("BasePart") then
        local p=o.Parent
        if p and p:IsA("Model") and p~=WS then return end -- часть модели: считается сама модель
        local cid=CatOfName(o.Name:lower())
        if cid then items[o]=cid end
    end
end
local scanId=0
local scanned=false
local function scanAll()
    trees,mobs,items={}, {}, {}
    scanned=false
    scanId=scanId+1
    local id=scanId
    task.spawn(function()
        local n=0
        for _,o in ipairs(WS:GetDescendants()) do
            if not Running or scanId~=id then return end
            pcall(track,o)
            n=n+1
            if n%1500==0 then task.wait() end
        end
        scanned=true
    end)
end
scanAll()
Conn(WS.DescendantAdded:Connect(function(o) pcall(track,o) end))
local function count(t) local n=0 for k in pairs(t) do if k.Parent then n=n+1 end end return n end
task.spawn(function()
    while Running do
        task.wait(3)
        for t in pairs(trees) do if not t.Parent or not t:IsDescendantOf(WS) then trees[t]=nil end end
        for it in pairs(items) do if not it.Parent or not it:IsDescendantOf(WS) then items[it]=nil end end
        for m in pairs(mobs) do
            local h=m.Parent and m:FindFirstChildOfClass("Humanoid")
            if not h or h.Health<=0 then mobs[m]=nil end
        end
    end
end)

-- ===================== ИГРОВЫЕ ВЫЗОВЫ =====================
local function pivotPos(inst)
    local ok,p=pcall(function() return inst:GetPivot().Position end)
    return ok and p or nil
end
local remoteDmg,remoteEquip
local function getRemotes()
    if not remoteDmg or not remoteDmg.Parent then
        local re=RepS:FindFirstChild("RemoteEvents")
        remoteDmg=re and re:FindFirstChild("ToolDamageObject")
        remoteEquip=re and re:FindFirstChild("EquipItemHandle")
    end
    return remoteDmg
end
-- топоры: лучший первым. Инвентарь игры — папка Inventory у игрока (на всякий случай смотрим и Character/Backpack)
local AXES={"Chainsaw","Admin Axe","Ice Axe","Strong Axe","Good Axe","Old Axe"}
local function getAxe()
    local containers={lp:FindFirstChild("Inventory"),lp.Character,lp:FindFirstChild("Backpack")}
    for _,name in ipairs(AXES) do
        for _,c in ipairs(containers) do
            local t=c and c:FindFirstChild(name)
            if t then return t end
        end
    end
    -- запасной вариант: любой предмет с "axe" в названии (но не pickaxe)
    for _,c in ipairs(containers) do
        if c then
            for _,t in ipairs(c:GetChildren()) do
                local n=t.Name:lower()
                if n:find("axe",1,true) and not n:find("pick",1,true) then return t end
            end
        end
    end
    return nil
end
-- идентификатор удара: "<номер>_<число>"; у каждого топора свой номер, запасной вариант — счётчик
local TDI={["Old Axe"]="3_7367831688",["Good Axe"]="112_7367831688",["Strong Axe"]="116_7367831688",
    ["Ice Axe"]="116_7367831688",["Admin Axe"]="116_7367831688",["Chainsaw"]="120_7367831688"}
local counter=0
local lastEquip,lastEquipTool=0,nil
local function ensureEquipped(tool)
    if remoteEquip and (tool~=lastEquipTool or tick()-lastEquip>10) then
        lastEquip=tick()
        lastEquipTool=tool
        pcall(function() remoteEquip:FireServer("FireAllClients",tool) end)
    end
end
-- диагностика: что появляется рядом с деревом после удара и что отвечает сервер
local lastRes={}
local watch=nil
local function startWatch(pos,tree)
    watch={pos=pos,t0=tick(),untilT=tick()+6,list={},tree=tree}
end
Conn(WS.DescendantAdded:Connect(function(o)
    local w=watch
    if not w or tick()>w.untilT or #w.list>=80 then return end
    if o:IsA("Model") or o:IsA("BasePart") then
        local ok,p=pcall(function() return o:GetPivot().Position end)
        if ok and (p-w.pos).Magnitude<=60 then
            w.list[#w.list+1]=string.format("%.1fс | %s (%s) | в: %s | %.0fm",tick()-w.t0,o.Name,o.ClassName,o.Parent and o.Parent.Name or "?",(p-w.pos).Magnitude)
        end
    end
end))
local function describe(v)
    if type(v)=="table" then
        local ok,j=pcall(function() return Http:JSONEncode(v) end)
        return ok and j:sub(1,160) or "table"
    end
    return tostring(v)
end
local busy=setmetatable({},{__mode="k"})
local hits=0
local function hit(target,tool,cf)
    local r=getRemotes()
    if not r or not target or not target.Parent then return end
    if busy[target] and tick()-busy[target]<1.5 then return end
    busy[target]=tick()
    counter=counter+1
    local id
    if Config.IdByCounter then id=tostring(counter).."_7367831688"
    else id=TDI[tool.Name] or (tostring(counter).."_7367831688") end
    task.spawn(function()
        local ok,res=pcall(function() return r:InvokeServer(target,tool,id,cf) end)
        if ok then hits=hits+1 end
        lastRes[#lastRes+1]=target.Name.." id="..id.." -> "..(ok and describe(res) or ("ОШИБКА "..tostring(res)))
        if #lastRes>10 then table.remove(lastRes,1) end
        busy[target]=nil
    end)
end
local function treePart(t)
    if t:IsA("BasePart") then return t end
    return t.PrimaryPart or t:FindFirstChildWhichIsA("BasePart",true)
end
local function isHostile(m)
    if #mobKW==0 then return true end
    local n=m.Name:lower()
    for _,k in ipairs(mobKW) do
        if n:find(k,1,true) then return true end
    end
    return false
end

-- ===================== ЦИКЛЫ =====================
local errCount={}
local function guard(name,fn)
    local ok,err=pcall(fn)
    if not ok then
        errCount[name]=(errCount[name] or 0)+1
        if errCount[name]==1 or errCount[name]%20==0 then warn("Sakura["..name.."]: "..tostring(err)) end
    end
end
local lastChop,lastAura,lastNoAxe,lastNoRemote=0,0,0,0
local function checkReady()
    local tool=getAxe()
    if not tool then
        if tick()-lastNoAxe>8 then lastNoAxe=tick() notify("🪓 Топор","Топор не найден (Inventory/Backpack)",4) end
        return nil
    end
    if not getRemotes() then
        if tick()-lastNoRemote>8 then lastNoRemote=tick() notify("⚠️ Remote","ToolDamageObject не найден — открой «Отладка» и пришли список",5) end
        return nil
    end
    ensureEquipped(tool)
    return tool
end
local function chopStep(root)
    if not Config.AutoChop or tick()-lastChop<Config.ChopRate then return end
    lastChop=tick()
    local tool=checkReady()
    if not tool then return end
    local rp=root.Position
    local cand={}
    for t in pairs(trees) do
        if t.Parent then
            local p=pivotPos(t)
            if p then
                local d=(p-rp).Magnitude
                if d<=Config.ChopRange then cand[#cand+1]={t=t,d=d} end
            end
        end
    end
    table.sort(cand,function(a,b) return a.d<b.d end)
    if cand[1] and (not watch or tick()>watch.untilT+20) then
        local p0=treePart(cand[1].t)
        startWatch(p0 and p0.Position or rp,cand[1].t)
    end
    for i=1,math.min(#cand,Config.ChopMulti) do
        local t=cand[i].t
        local part=treePart(t)
        hit(t,tool,part and part.CFrame or CFrame.new())
    end
end
local function auraStep(root)
    if not Config.KillAura or tick()-lastAura<Config.AuraRate then return end
    lastAura=tick()
    local tool=checkReady()
    if not tool then return end
    local list={}
    for m in pairs(mobs) do
        local h=m.Parent and m:FindFirstChildOfClass("Humanoid")
        local r=h and h.Health>0 and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart)
        if r and isHostile(m) then
            local d=(r.Position-root.Position).Magnitude
            if d<=Config.AuraRange then list[#list+1]={m=m,r=r,d=d} end
        end
    end
    table.sort(list,function(a,b) return a.d<b.d end)
    local n=Config.AuraMulti and #list or math.min(#list,1)
    for i=1,n do hit(list[i].m,tool,list[i].r.CFrame) end
end
Conn(RS.Heartbeat:Connect(function()
    local char=lp.Character
    local root=char and char:FindFirstChild("HumanoidRootPart")
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health<=0 then return end
    guard("aura",function() auraStep(root) end)
    guard("chop",function() chopStep(root) end)
end))

-- ===================== ПРЕДМЕТЫ, ESP, ДВИЖЕНИЕ, МИР =====================
local function me()
    local c=lp.Character
    return c,c and c:FindFirstChild("HumanoidRootPart"),c and c:FindFirstChildOfClass("Humanoid")
end
local espGui=Instance.new("ScreenGui")
espGui.Name="Sakura99ESP"
espGui.ResetOnSpawn=false
espGui.IgnoreGuiInset=true
espGui.DisplayOrder=990
espGui.Parent=lp:WaitForChild("PlayerGui")
local function makeTag(adornee,color)
    local g=Instance.new("BillboardGui")
    g.Size=UDim2.new(0,190,0,22)
    g.AlwaysOnTop=true
    g.StudsOffset=Vector3.new(0,2.2,0)
    g.Adornee=adornee
    g.ResetOnSpawn=false
    g.Parent=espGui
    local l=Instance.new("TextLabel")
    l.Name="L"
    l.Size=UDim2.new(1,0,1,0)
    l.BackgroundTransparency=1
    l.TextColor3=color
    l.TextSize=12
    l.Font=Enum.Font.GothamBold
    l.TextStrokeTransparency=0.35
    l.Text=""
    l.Parent=g
    return g
end
local function adorneeOf(inst)
    if inst:IsA("BasePart") then return inst end
    return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart",true)
end
local espTags={}
task.spawn(function()
    while Running do
        task.wait(0.3)
        guard("esp",function()
            local _,root=me()
            local keep={}
            if root then
                local rp=root.Position
                if Config.ItemESP then
                    local cand={}
                    for inst,cid in pairs(items) do
                        if inst.Parent and Config["ESP_"..cid] then
                            local p=pivotPos(inst)
                            if p then
                                local d=(p-rp).Magnitude
                                if d<=Config.ESPDist then cand[#cand+1]={inst=inst,cid=cid,d=d} end
                            end
                        end
                    end
                    table.sort(cand,function(a,b) return a.d<b.d end)
                    for i=1,math.min(#cand,60) do
                        local c=cand[i]
                        local cat=CAT_BY_ID[c.cid]
                        keep[c.inst]=true
                        local g=espTags[c.inst]
                        if not g or not g.Parent then
                            local a=adorneeOf(c.inst)
                            if a then g=makeTag(a,cat.color) espTags[c.inst]=g end
                        end
                        if g then g.L.Text=cat.icon.." "..c.inst.Name.."  "..math.floor(c.d).."m" end
                    end
                end
                if Config.MobESP then
                    for m in pairs(mobs) do
                        local h=m.Parent and m:FindFirstChildOfClass("Humanoid")
                        local r=h and h.Health>0 and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart)
                        if r and (r.Position-rp).Magnitude<=Config.ESPDist then
                            keep[m]=true
                            local g=espTags[m]
                            if not g or not g.Parent then g=makeTag(r,Color3.fromRGB(255,80,80)) espTags[m]=g end
                            g.L.Text="👹 "..m.Name.."  "..math.floor(h.Health).."hp  "..math.floor((r.Position-rp).Magnitude).."m"
                        end
                    end
                end
            end
            for k,g in pairs(espTags) do
                if not keep[k] then pcall(function() g:Destroy() end) espTags[k]=nil end
            end
        end)
    end
end)
-- подбор предметов через ProximityPrompt
local pickT,promptCache,promptOriginal={}, {}, {}
local function promptOf(inst)
    local c=promptCache[inst]
    if c and not c.Parent then
        promptCache[inst]=nil
        promptOriginal[c]=nil
        c=nil
    end
    if c==nil then
        c=inst:FindFirstChildWhichIsA("ProximityPrompt",true) or false
        promptCache[inst]=c
        if c then
            promptOriginal[c]={
                HoldDuration=c.HoldDuration,
                MaxActivationDistance=c.MaxActivationDistance,
                RequiresLineOfSight=c.RequiresLineOfSight,
            }
        end
    end
    if c then
        pcall(function()
            local original=promptOriginal[c]
            if original then
                c.HoldDuration=Config.PromptInstant and 0 or original.HoldDuration
                c.MaxActivationDistance=Config.AutoPick
                    and math.max(original.MaxActivationDistance,Config.PickRange+5)
                    or original.MaxActivationDistance
                c.RequiresLineOfSight=Config.AutoPick and false or original.RequiresLineOfSight
            end
        end)
    end
    return c or nil
end
task.spawn(function()
    while Running do
        task.wait(0.3)
        guard("pick",function()
            if not Config.AutoPick or not fireproximityprompt then return end
            local _,root=me()
            if not root then return end
            local now=tick()
            for inst,cid in pairs(items) do
                if Config["Pick_"..cid] and inst.Parent and (pickT[inst] or 0)<now-1.2 then
                    local p=pivotPos(inst)
                    if p and (p-root.Position).Magnitude<=Config.PickRange then
                        local pp=promptOf(inst)
                        if pp then
                            pickT[inst]=now
                            pcall(fireproximityprompt,pp)
                        end
                    end
                end
            end
        end)
    end
end)
local function nearestItem(cid)
    local _,root=me()
    if not root then return nil end
    local best,bd=nil,math.huge
    for inst,id in pairs(items) do
        if id==cid and inst.Parent then
            local p=pivotPos(inst)
            if p then
                local d=(p-root.Position).Magnitude
                if d<bd then best,bd=inst,d end
            end
        end
    end
    return best,bd
end
local function tpToItem(cid)
    local _,root=me()
    local inst,d=nearestItem(cid)
    local p=inst and pivotPos(inst)
    if root and p then
        root.CFrame=CFrame.new(p+Vector3.new(0,3,0))
        notify(CAT_BY_ID[cid].icon.." Телепорт",inst.Name.." ("..math.floor(d).."m)",3)
    else
        notify("Не найдено",CAT_BY_ID[cid].ru,3)
    end
end
-- эксперимент: тянем предметы категории к себе (перетаскивание через remote игры + локальный перенос)
local function bringItems(cid)
    local _,root=me()
    if not root then return end
    local re=RepS:FindFirstChild("RemoteEvents")
    local drag=re and re:FindFirstChild("RequestStartDraggingItem")
    local stop=re and re:FindFirstChild("StopDraggingItem")
    local n=0
    for inst,id in pairs(items) do
        if id==cid and inst.Parent and inst:IsA("Model") then
            local p=pivotPos(inst)
            if p and (p-root.Position).Magnitude<=150 then
                if drag then pcall(function() drag:FireServer(inst) end) end
                pcall(function() inst:PivotTo(root.CFrame*CFrame.new(0,0,-4)) end)
                if stop then pcall(function() stop:FireServer(inst) end) end
                n=n+1
                if n>=15 then break end
            end
        end
    end
    notify("📥 Притянуть","Обработано предметов: "..n,4)
end
-- движение
local origSpeed=16
-- Храним исходное состояние каждой детали, чтобы Noclip не включал коллизию
-- там, где она изначально была выключена.
local noclipParts=setmetatable({},{__mode="k"})
local ncList,ncChar,ncT=nil,nil,0
task.spawn(function()
    while Running do
        task.wait(0.1)
        guard("move",function()
            local char,root,hum=me()
            if not hum then return end
            if Config.Speed then
                if not Config._spOn then origSpeed=hum.WalkSpeed Config._spOn=true end
                if hum.WalkSpeed~=Config.SpeedVal then hum.WalkSpeed=Config.SpeedVal end
            elseif Config._spOn then
                hum.WalkSpeed=origSpeed
                Config._spOn=false
            end
            if Config.Noclip and char then
                if ncChar~=char or tick()-ncT>1 then
                    ncChar=char ncT=tick() ncList={}
                    for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then ncList[#ncList+1]=p end end
                end
                for _,p in ipairs(ncList) do
                    if p.Parent and noclipParts[p]==nil then
                        noclipParts[p]=p.CanCollide
                    end
                    if p.Parent and p.CanCollide then p.CanCollide=false end
                end
            elseif next(noclipParts) then
                for p,wasCollidable in pairs(noclipParts) do
                    if p.Parent then pcall(function() p.CanCollide=wasCollidable end) end
                    noclipParts[p]=nil
                end
                ncList,ncChar=nil,nil
            end
        end)
    end
end)
-- Fly (LinearVelocity), управление штатным стиком и кнопками ▲▼
local flyAtt,flyLV,flyAO,flyUp,flyDown=nil,nil,nil,false,false
local flyVel=Vector3.zero
local function setFly(on)
    for _,o in ipairs({flyLV,flyAO,flyAtt}) do pcall(function() o:Destroy() end) end
    flyLV,flyAO,flyAtt=nil,nil,nil
    flyVel=Vector3.zero
    if not on then return end
    local _,root=me()
    if not root then return end
    flyAtt=Instance.new("Attachment") flyAtt.Parent=root
    flyLV=Instance.new("LinearVelocity")
    flyLV.Attachment0=flyAtt flyLV.MaxForce=math.huge flyLV.VectorVelocity=Vector3.zero
    flyLV.RelativeTo=Enum.ActuatorRelativeTo.World flyLV.Parent=root
    flyAO=Instance.new("AlignOrientation")
    flyAO.Attachment0=flyAtt flyAO.Mode=Enum.OrientationAlignmentMode.OneAttachment
    flyAO.MaxTorque=math.huge flyAO.Responsiveness=30 flyAO.CFrame=root.CFrame flyAO.Parent=root
end
local flyGui
local function flyButtons(show)
    if show and (not flyGui or not flyGui.Parent) then
        flyGui=Instance.new("ScreenGui")
        flyGui.Name="Sakura99Fly" flyGui.ResetOnSpawn=false flyGui.IgnoreGuiInset=true flyGui.DisplayOrder=997
        flyGui.Parent=lp:WaitForChild("PlayerGui")
        local function mk(text,y,color,setter)
            local b=Instance.new("TextButton")
            b.Size=UDim2.new(0,62,0,62) b.Position=UDim2.new(1,-84,1,y) b.BackgroundColor3=color
            b.BackgroundTransparency=0.3 b.Text=text b.TextSize=28 b.TextColor3=Color3.new(1,1,1)
            b.Font=Enum.Font.GothamBold b.BorderSizePixel=0 b.AutoButtonColor=false b.Parent=flyGui
            local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,31) c.Parent=b
            b.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then setter(true) end end)
            b.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then setter(false) end end)
        end
        mk("▲",-320,Color3.fromRGB(60,160,90),function(v) flyUp=v end)
        mk("▼",-248,Color3.fromRGB(200,70,90),function(v) flyDown=v end)
    end
    if flyGui then flyGui.Enabled=show and true or false end
end
Conn(RS.Heartbeat:Connect(function(dt)
    guard("fly",function()
        local _,root,hum=me()
        if not root or not hum or hum.Health<=0 then return end
        if not Config.Fly then
            if flyLV or flyAtt then setFly(false) end
            flyButtons(false)
            return
        end
        if not flyLV or not flyLV.Parent then setFly(true) end
        if not flyLV then return end
        flyButtons(true)
        local cf=workspace.CurrentCamera.CFrame
        local look=cf.LookVector
        local fl=Vector3.new(look.X,0,look.Z)
        fl=(fl.Magnitude>0.001) and fl.Unit or Vector3.new(0,0,-1)
        local fr=Vector3.new(cf.RightVector.X,0,cf.RightVector.Z)
        fr=(fr.Magnitude>0.001) and fr.Unit or Vector3.new(1,0,0)
        local md=hum.MoveDirection
        local dir=look*md:Dot(fl)+fr*md:Dot(fr)
        local vert=0
        if flyUp or game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.Space) then vert=vert+1 end
        if flyDown or game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.LeftShift) then vert=vert-1 end
        dir=dir+Vector3.new(0,vert,0)
        if dir.Magnitude>1 then dir=dir.Unit end
        local target=dir*Config.FlySpeed
        flyVel=flyVel:Lerp(target,math.clamp(dt*10,0,1))
        if target.Magnitude==0 and flyVel.Magnitude<0.5 then flyVel=Vector3.zero end
        flyLV.VectorVelocity=flyVel
        if flyAO then flyAO.CFrame=CFrame.lookAt(Vector3.zero,fl) end
    end)
end))
-- Infinite Jump: JumpRequest, пробел и своя кнопка 🦘
local UIS=game:GetService("UserInputService")
local lastJ=0
local function airJump()
    if not Config.InfJump then return end
    local _,root,hum=me()
    if not root or not hum or hum.Health<=0 or tick()-lastJ<0.1 then return end
    lastJ=tick()
    local v=root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity=Vector3.new(v.X,Config.JumpPower,v.Z)
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
end
Conn(UIS.JumpRequest:Connect(airJump))
Conn(UIS.InputBegan:Connect(function(i,gp) if not gp and i.KeyCode==Enum.KeyCode.Space then airJump() end end))
local jumpGui
task.spawn(function()
    while Running do
        task.wait(0.4)
        guard("jumpbtn",function()
            local want=Config.InfJump
            if want and (not jumpGui or not jumpGui.Parent) then
                jumpGui=Instance.new("ScreenGui")
                jumpGui.Name="Sakura99Jump" jumpGui.ResetOnSpawn=false jumpGui.IgnoreGuiInset=true jumpGui.DisplayOrder=997
                jumpGui.Parent=lp:WaitForChild("PlayerGui")
                local b=Instance.new("TextButton")
                b.Size=UDim2.new(0,64,0,64) b.Position=UDim2.new(1,-170,1,-130) b.BackgroundColor3=Color3.fromRGB(30,15,46)
                b.BackgroundTransparency=0.25 b.Text="🦘" b.TextSize=28 b.AutoButtonColor=false b.BorderSizePixel=0 b.Parent=jumpGui
                local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,32) c.Parent=b
                b.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then airJump() end end)
            end
            if jumpGui then jumpGui.Enabled=want and true or false end
        end)
    end
end)
Conn(lp.Idled:Connect(function()
    if not Config.AntiAFK then return end
    pcall(function()
        local vu=game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end)
end))
-- мир / видимость
local Lighting=game:GetService("Lighting")
local origL={Brightness=Lighting.Brightness,ClockTime=Lighting.ClockTime,FogEnd=Lighting.FogEnd,FogStart=Lighting.FogStart,Ambient=Lighting.Ambient}
local atmosphereOriginal=setmetatable({},{__mode="k"})
local fpsOriginal=setmetatable({},{__mode="k"})
local worldOn={}
task.spawn(function()
    while Running do
        task.wait(0.5)
        guard("world",function()
            if Config.FullBright then
                Lighting.Brightness=3 Lighting.Ambient=Color3.fromRGB(190,190,190) worldOn.fb=true
            elseif worldOn.fb then Lighting.Brightness=origL.Brightness Lighting.Ambient=origL.Ambient worldOn.fb=false end
            if Config.KeepDay then Lighting.ClockTime=14 worldOn.day=true
            elseif worldOn.day then Lighting.ClockTime=origL.ClockTime worldOn.day=false end
            if Config.NoFog then
                Lighting.FogEnd=1e6 Lighting.FogStart=1e6
                for _,c in ipairs(Lighting:GetChildren()) do
                    if c:IsA("Atmosphere") then
                        if not atmosphereOriginal[c] then
                            atmosphereOriginal[c]={Density=c.Density,Haze=c.Haze}
                        end
                        c.Density=0
                        c.Haze=0
                    end
                end
                worldOn.fog=true
            elseif worldOn.fog then
                Lighting.FogEnd=origL.FogEnd
                Lighting.FogStart=origL.FogStart
                for c,props in pairs(atmosphereOriginal) do
                    if c.Parent then
                        pcall(function() c.Density=props.Density c.Haze=props.Haze end)
                    end
                    atmosphereOriginal[c]=nil
                end
                worldOn.fog=false
            end
        end)
    end
end)
local function applyFPSObject(o)
    if not Config.FPSBoost then return end
    pcall(function()
        if o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Smoke") or o:IsA("Fire") or o:IsA("Sparkles") then
            if fpsOriginal[o]==nil then fpsOriginal[o]={Enabled=o.Enabled} end
            o.Enabled=false
        elseif o:IsA("Decal") or o:IsA("Texture") then
            if fpsOriginal[o]==nil then fpsOriginal[o]={Transparency=o.Transparency} end
            o.Transparency=1
        end
    end)
end
local function setFPSBoost(enabled)
    Config.FPSBoost=enabled
    if enabled then
        for _,o in ipairs(WS:GetDescendants()) do applyFPSObject(o) end
    else
        for o,props in pairs(fpsOriginal) do
            if o.Parent then
                pcall(function()
                    if props.Enabled~=nil then o.Enabled=props.Enabled end
                    if props.Transparency~=nil then o.Transparency=props.Transparency end
                end)
            end
            fpsOriginal[o]=nil
        end
    end
end
Conn(WS.DescendantAdded:Connect(applyFPSObject))
local function restoreAll()
    pcall(function() setFly(false) end)
    pcall(function() flyButtons(false) if flyGui then flyGui:Destroy() end end)
    pcall(function() if jumpGui then jumpGui:Destroy() end end)
    pcall(function() espGui:Destroy() end)
    pcall(function()
        for p,wasCollidable in pairs(noclipParts) do
            if p.Parent then p.CanCollide=wasCollidable end
            noclipParts[p]=nil
        end
        for c,props in pairs(atmosphereOriginal) do
            if c.Parent then c.Density=props.Density c.Haze=props.Haze end
            atmosphereOriginal[c]=nil
        end
        for o,props in pairs(fpsOriginal) do
            if o.Parent then
                if props.Enabled~=nil then o.Enabled=props.Enabled end
                if props.Transparency~=nil then o.Transparency=props.Transparency end
            end
            fpsOriginal[o]=nil
        end
        local _,_,hum=me()
        if hum and Config._spOn then hum.WalkSpeed=origSpeed Config._spOn=false end
        Lighting.Brightness=origL.Brightness Lighting.Ambient=origL.Ambient Lighting.ClockTime=origL.ClockTime
        Lighting.FogEnd=origL.FogEnd Lighting.FogStart=origL.FogStart
        worldOn.fb=false worldOn.day=false worldOn.fog=false
    end)
end

-- ===================== UI =====================
local pink={
    TextColor=Color3.fromRGB(255,215,230),Background=Color3.fromRGB(28,10,20),Topbar=Color3.fromRGB(45,15,30),
    Shadow=Color3.fromRGB(10,3,7),NotificationBackground=Color3.fromRGB(40,14,28),
    NotificationActionsBackground=Color3.fromRGB(255,105,180),TabBackground=Color3.fromRGB(40,12,25),
    TabStroke=Color3.fromRGB(90,30,60),TabBackgroundSelected=Color3.fromRGB(255,105,180),
    TabTextColor=Color3.fromRGB(255,190,215),SelectedTabTextColor=Color3.fromRGB(30,10,20),
    ElementBackground=Color3.fromRGB(50,18,35),ElementBackgroundHover=Color3.fromRGB(65,24,45),
    SecondaryElementBackground=Color3.fromRGB(40,14,28),ElementStroke=Color3.fromRGB(95,35,65),
    SecondaryElementStroke=Color3.fromRGB(75,28,52),SliderBackground=Color3.fromRGB(120,40,85),
    SliderProgress=Color3.fromRGB(255,105,180),SliderStroke=Color3.fromRGB(255,140,200),
    ToggleBackground=Color3.fromRGB(40,14,28),ToggleEnabled=Color3.fromRGB(255,105,180),
    ToggleDisabled=Color3.fromRGB(100,70,85),ToggleEnabledStroke=Color3.fromRGB(255,140,200),
    ToggleDisabledStroke=Color3.fromRGB(125,90,105),ToggleEnabledOuterStroke=Color3.fromRGB(110,40,75),
    ToggleDisabledOuterStroke=Color3.fromRGB(70,30,50),DropdownSelected=Color3.fromRGB(60,22,42),
    DropdownUnselected=Color3.fromRGB(45,16,32),InputBackground=Color3.fromRGB(40,14,28),
    InputStroke=Color3.fromRGB(110,40,75),PlaceholderColor=Color3.fromRGB(180,130,155),
}
local function makeWindow(theme)
    return Rayfield:CreateWindow({
        Name="Sakura 🌸",LoadingTitle="Sakura loading...",LoadingSubtitle="pink edition",Theme=theme,
        ConfigurationSaving={Enabled=true,FolderName="Sakura99",FileName="config4"},
    })
end
local okW,Window=pcall(makeWindow,pink)
if not okW or not Window then okW,Window=pcall(makeWindow,"Default") end
if not okW or not Window then warn("Sakura: не удалось создать окно Rayfield") return end

local Tab=Window:CreateTab("Рубка",4483362458)
Tab:CreateToggle({Name="Авто-рубка",CurrentValue=false,Flag="n4_AutoChop",Callback=function(v)
    Config.AutoChop=v
    if v then checkReady() end
end})
Tab:CreateSlider({Name="Радиус рубки",Range={5,150},Increment=1,Suffix=" studs",CurrentValue=40,Flag="n4_ChopRange",Callback=function(v) Config.ChopRange=v end})
Tab:CreateSlider({Name="Интервал ударов",Range={0.1,1.5},Increment=0.05,Suffix=" с",CurrentValue=0.35,Flag="n4_ChopRate",Callback=function(v) Config.ChopRate=v end})
Tab:CreateSlider({Name="Деревьев за один удар",Range={1,10},Increment=1,Suffix=" шт",CurrentValue=2,Flag="n4_ChopMulti",Callback=function(v) Config.ChopMulti=v end})
local chopLbl=Tab:CreateLabel("Деревьев: …")

local TreeTab=Window:CreateTab("Деревья",4483362458)
TreeTab:CreateInput({Name="Ключевые слова деревьев (через запятую)",PlaceholderText="small tree, treebig",CurrentValue=Config.TreeKW,
    RemoveTextAfterFocusLost=false,Flag="n4_TreeKW",Callback=function(txt)
        Config.TreeKW=txt
        setKW()
        scanAll()
        notify("🌳 Деревья","Ключевые слова обновлены, идёт пересканирование",3)
    end})
TreeTab:CreateInput({Name="Исключить слова",PlaceholderText="root, stump, treehouse",CurrentValue=Config.TreeNot,
    RemoveTextAfterFocusLost=false,Flag="n4_TreeNot",Callback=function(txt)
        Config.TreeNot=txt
        setKW()
        scanAll()
    end})
TreeTab:CreateButton({Name="🔄 Пересканировать мир",Callback=function() setKW() scanAll() notify("🌳 Деревья","Скан запущен",3) end})
TreeTab:CreateButton({Name="📋 Имена найденных деревьев (в буфер)",Callback=function()
    local names,seen={}, {}
    for t in pairs(trees) do
        if t.Parent and not seen[t.Name] then seen[t.Name]=true names[#names+1]=t.Name end
    end
    table.sort(names)
    local txt=#names>0 and table.concat(names,"\n") or ("деревья не найдены, ключевые слова: "..Config.TreeKW)
    if setclipboard then setclipboard(txt) notify("📋 Скопировано",#names.." имён",3) else notify("📋","setclipboard недоступен",3) end
end})

local CombatTab=Window:CreateTab("Бой",4483362458)
CombatTab:CreateToggle({Name="Kill Aura",CurrentValue=false,Flag="n4_KillAura",Callback=function(v) Config.KillAura=v if v then checkReady() end end})
CombatTab:CreateSlider({Name="Радиус ауры",Range={5,100},Increment=1,Suffix=" studs",CurrentValue=20,Flag="n4_AuraRange",Callback=function(v) Config.AuraRange=v end})
CombatTab:CreateSlider({Name="Интервал ударов",Range={0.1,1.5},Increment=0.05,Suffix=" с",CurrentValue=0.3,Flag="n4_AuraRate",Callback=function(v) Config.AuraRate=v end})
CombatTab:CreateToggle({Name="Бить всех в радиусе сразу",CurrentValue=false,Flag="n4_AuraMulti",Callback=function(v) Config.AuraMulti=v end})
CombatTab:CreateInput({Name="Кого бить (слова через запятую, пусто = всех)",PlaceholderText="wolf, bat, cultist, bunny",CurrentValue=Config.MobKW,
    RemoveTextAfterFocusLost=false,Flag="n4_MobKW",Callback=function(txt) Config.MobKW=txt setKW() end})
local mobLbl=CombatTab:CreateLabel("Врагов: …")

-- ===== ПРЕДМЕТЫ =====
local ItemTab=Window:CreateTab("Предметы",4483362458)
ItemTab:CreateSection("ESP")
ItemTab:CreateToggle({Name="ESP предметов",CurrentValue=true,Flag="n5_ItemESP",Callback=function(v) Config.ItemESP=v end})
ItemTab:CreateToggle({Name="ESP врагов",CurrentValue=true,Flag="n5_MobESP",Callback=function(v) Config.MobESP=v end})
ItemTab:CreateSlider({Name="Дальность ESP",Range={50,1500},Increment=10,Suffix=" studs",CurrentValue=400,Flag="n5_ESPDist",Callback=function(v) Config.ESPDist=v end})
for _,c in ipairs(CATS) do
    ItemTab:CreateToggle({Name=c.icon.." "..c.ru,CurrentValue=Config["ESP_"..c.id],Flag="n5_ESP_"..c.id,Callback=function(v) Config["ESP_"..c.id]=v end})
end
ItemTab:CreateSection("Авто-подбор (через подсказки E)")
ItemTab:CreateToggle({Name="Авто-подбор",CurrentValue=false,Flag="n5_AutoPick",Callback=function(v)
    Config.AutoPick=v
    if v and not fireproximityprompt then notify("⚠️","Нет fireproximityprompt в executor",4) end
end})
ItemTab:CreateSlider({Name="Радиус подбора",Range={5,150},Increment=1,Suffix=" studs",CurrentValue=25,Flag="n5_PickRange",Callback=function(v) Config.PickRange=v end})
ItemTab:CreateToggle({Name="Мгновенные подсказки",CurrentValue=true,Flag="n5_PromptInstant",Callback=function(v) Config.PromptInstant=v end})
for _,c in ipairs(CATS) do
    if c.id~="camp" then
        ItemTab:CreateToggle({Name="Подбирать: "..c.icon.." "..c.ru,CurrentValue=Config["Pick_"..c.id],Flag="n5_Pick_"..c.id,Callback=function(v) Config["Pick_"..c.id]=v end})
    end
end
ItemTab:CreateSection("Телепорт к ближайшему")
local selCat="fuel"
local catNames={}
local catByName={}
for _,c in ipairs(CATS) do
    local nm=c.icon.." "..c.ru
    catNames[#catNames+1]=nm
    catByName[nm]=c.id
end
ItemTab:CreateDropdown({Name="Категория",Options=catNames,CurrentOption={catNames[1]},MultipleOptions=false,Flag="n5_SelCat",Callback=function(opt)
    local v=type(opt)=="table" and opt[1] or opt
    if catByName[v] then selCat=catByName[v] end
end})
ItemTab:CreateButton({Name="📍 К ближайшему (выбранная категория)",Callback=function() tpToItem(selCat) end})
ItemTab:CreateButton({Name="🔥 К костру",Callback=function() tpToItem("camp") end})
ItemTab:CreateButton({Name="🧒 К ближайшему ребёнку",Callback=function() tpToItem("child") end})
ItemTab:CreateButton({Name="📦 К ближайшему сундуку",Callback=function() tpToItem("chest") end})
ItemTab:CreateButton({Name="📥 Притянуть предметы категории к себе (эксперимент)",Callback=function() bringItems(selCat) end})
local itemLbl=ItemTab:CreateLabel("Найдено: …")

-- ===== ДВИЖЕНИЕ =====
local MoveTab=Window:CreateTab("Движение",4483362458)
MoveTab:CreateToggle({Name="Своя скорость бега",CurrentValue=false,Flag="n5_Speed",Callback=function(v) Config.Speed=v end})
MoveTab:CreateSlider({Name="Скорость",Range={16,120},Increment=1,Suffix="",CurrentValue=32,Flag="n5_SpeedVal",Callback=function(v) Config.SpeedVal=v end})
MoveTab:CreateToggle({Name="Fly (стик + кнопки ▲▼)",CurrentValue=false,Flag="n5_Fly",Callback=function(v) Config.Fly=v end})
MoveTab:CreateSlider({Name="Скорость полёта",Range={20,200},Increment=1,Suffix="",CurrentValue=60,Flag="n5_FlySpeed",Callback=function(v) Config.FlySpeed=v end})
MoveTab:CreateToggle({Name="Noclip",CurrentValue=false,Flag="n5_Noclip",Callback=function(v) Config.Noclip=v end})
MoveTab:CreateToggle({Name="Infinite Jump (кнопка 🦘 / прыжок / пробел)",CurrentValue=false,Flag="n5_InfJump",Callback=function(v) Config.InfJump=v end})
MoveTab:CreateSlider({Name="Сила прыжка в воздухе",Range={30,150},Increment=1,Suffix="",CurrentValue=55,Flag="n5_JumpPower",Callback=function(v) Config.JumpPower=v end})
MoveTab:CreateToggle({Name="Anti-AFK",CurrentValue=true,Flag="n5_AntiAFK",Callback=function(v) Config.AntiAFK=v end})

-- ===== МИР =====
local WorldTab=Window:CreateTab("Мир",4483362458)
WorldTab:CreateToggle({Name="FullBright (ночь не тёмная)",CurrentValue=false,Flag="n5_FullBright",Callback=function(v) Config.FullBright=v end})
WorldTab:CreateToggle({Name="Без тумана",CurrentValue=false,Flag="n5_NoFog",Callback=function(v) Config.NoFog=v end})
WorldTab:CreateToggle({Name="Всегда день (визуально)",CurrentValue=false,Flag="n5_KeepDay",Callback=function(v) Config.KeepDay=v end})
WorldTab:CreateToggle({Name="FPS Boost (частицы и декали)",CurrentValue=false,Flag="n5_FPSBoost",Callback=function(v) setFPSBoost(v) end})

-- ОТЛАДКА (результат копируется в буфер: на телефоне консоли нет)
local DebugTab=Window:CreateTab("Отладка",4483362458)
local function toClip(txt,label)
    if setclipboard then setclipboard(txt) notify("📋 Скопировано",label,3) else notify("📋","setclipboard недоступен",3) end
end
DebugTab:CreateToggle({Name="ID удара по счётчику (если по таблице не бьёт)",CurrentValue=false,Flag="n4_IdByCounter",Callback=function(v) Config.IdByCounter=v end})
DebugTab:CreateButton({Name="📋 Инвентарь, remote и ID (главный отчёт)",Callback=function()
    local L={"=== ОТЧЁТ SAKURA 99 ==="}
    local inv=lp:FindFirstChild("Inventory")
    L[#L+1]="Inventory: "..(inv and "есть" or "НЕТ")
    if inv then for _,c in ipairs(inv:GetChildren()) do L[#L+1]="  inv: "..c.Name.." ("..c.ClassName..")" end end
    local bp=lp:FindFirstChild("Backpack")
    if bp then for _,c in ipairs(bp:GetChildren()) do L[#L+1]="  backpack: "..c.Name end end
    if lp.Character then for _,c in ipairs(lp.Character:GetChildren()) do if c:IsA("Tool") then L[#L+1]="  в руке: "..c.Name end end end
    local ax=getAxe()
    L[#L+1]="Топор: "..(ax and ax.Name or "не найден")
    local re=RepS:FindFirstChild("RemoteEvents")
    L[#L+1]="RemoteEvents: "..(re and "есть" or "НЕТ")
    L[#L+1]="ToolDamageObject: "..(getRemotes() and getRemotes().ClassName or "НЕТ")
    L[#L+1]="EquipItemHandle: "..(remoteEquip and "есть" or "НЕТ")
    L[#L+1]="Деревьев: "..count(trees).." · врагов: "..count(mobs).." · успешных вызовов: "..hits
    L[#L+1]="-- Remote:"
    local n=0
    for _,v in ipairs(RepS:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            n=n+1
            if n<=120 then L[#L+1]=v.ClassName..": "..v:GetFullName() end
        end
    end
    toClip(table.concat(L,"\n"),"отчёт готов")
end})
DebugTab:CreateButton({Name="📋 Враги (имена и HP)",Callback=function()
    local lines={}
    for m in pairs(mobs) do
        local h=m.Parent and m:FindFirstChildOfClass("Humanoid")
        if h then lines[#lines+1]=m.Name.." | HP "..math.floor(h.Health) end
    end
    table.sort(lines)
    toClip(#lines>0 and table.concat(lines,"\n") or "врагов не найдено",#lines.." врагов")
end})
DebugTab:CreateButton({Name="🧪 Тест: ударить ближайшее дерево 1 раз",Callback=function()
    local char=lp.Character
    local root=char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local tool=checkReady()
    if not tool then return end
    local best,bd=nil,200
    for t in pairs(trees) do
        if t.Parent then
            local p=pivotPos(t)
            if p then
                local d=(p-root.Position).Magnitude
                if d<bd then best,bd=t,d end
            end
        end
    end
    if not best then notify("🧪 Тест","Деревьев в радиусе 200 нет",4) return end
    local part=treePart(best)
    startWatch(part and part.Position or root.Position,best)
    busy[best]=nil
    hit(best,tool,part and part.CFrame or CFrame.new())
    notify("🧪 Тест","Ударил «"..best.Name.."» ("..math.floor(bd).."m). Подожди 6 с и нажми «Что появилось после удара»",6)
end})
DebugTab:CreateButton({Name="📋 Что появилось после удара",Callback=function()
    local L={"=== ЧТО ПРОИСХОДИТ ПОСЛЕ УДАРА ==="}
    L[#L+1]="-- Ответы сервера на ToolDamageObject (последние):"
    for _,r in ipairs(lastRes) do L[#L+1]=r end
    if watch then
        L[#L+1]="-- Новые объекты рядом с деревом (до 60 студов, "..#watch.list.." шт):"
        for _,x in ipairs(watch.list) do L[#L+1]=x end
        L[#L+1]="Дерево после удара: "..((watch.tree and watch.tree.Parent) and "осталось" or "исчезло")
    else
        L[#L+1]="Наблюдение не запускалось (нет ударов)"
    end
    toClip(table.concat(L,"\n"),"отчёт готов")
end})
DebugTab:CreateButton({Name="⏏ Выгрузить скрипт",Callback=function() if env.Sakura99Unload then env.Sakura99Unload() end end})

task.spawn(function()
    while Running do
        task.wait(1)
        local ax=getAxe()
        local txt="🌳 Деревьев: "..count(trees).." · "..(scanned and "скан готов" or "скан идёт…")..
            " · 🪓 "..(ax and ax.Name or "нет топора").." · remote "..(getRemotes() and "✅" or "❌")
        pcall(function() chopLbl:Set(txt) end)
        pcall(function() mobLbl:Set("👹 Врагов: "..count(mobs).." · ударов: "..hits) end)
        pcall(function()
            local cn={}
            for it,cid in pairs(items) do if it.Parent then cn[cid]=(cn[cid] or 0)+1 end end
            local parts={}
            for _,c in ipairs(CATS) do parts[#parts+1]=c.icon..(cn[c.id] or 0) end
            itemLbl:Set("Найдено: "..table.concat(parts,"  "))
        end)
    end
end)

env.Sakura99Unload=function()
    if not Running then return end
    Running=false
    pcall(restoreAll)
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() Rayfield:Destroy() end)
    env.Sakura99Unload=nil
end

pcall(function() Rayfield:LoadConfiguration() end)
notify("Sakura 🌸","Загружено. Топор берётся из Inventory игры",5)
