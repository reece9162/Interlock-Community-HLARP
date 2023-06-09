
AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "Vending Machine"
ENT.Category = "IX:HLA RP"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.PhysgunDisable = true
ENT.bNoPersist = true

ENT.MaxRenderDistance = math.pow(256, 2)
ENT.MaxStock = 4
ENT.Items = {
    {"REGULAR", "drink_breen_water", 5},
    {"SPARKLING", "drink_sparkling_water", 30},
    {"SPECIAL", "drink_premium_water", 50}
}

function ENT:GetStock(id)
    return self:GetNetVar("stock", {})[id] or self.MaxStock
end

function ENT:GetAllStock()
    return self:GetNetVar("stock", {})
end

if ( SERVER ) then
    function ENT:Initialize()
        self:SetModel("models/props_interiors/vendingmachinesoda01a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)

        local physics = self:GetPhysicsObject()
        physics:EnableMotion(false)
        physics:Sleep()

        self.nextUseTime = 0
        self:SetNetVar("stock", {})
    end

    function ENT:SpawnFunction(ply, trace)
        local vendor = ents.Create("ix_vendingmachine")

        vendor:SetPos(trace.HitPos + Vector(0, 0, 48))
        vendor:SetAngles(Angle(0, (vendor:GetPos() - ply:GetPos()):Angle().y - 180, 0))
        vendor:Spawn()
        vendor:Activate()

        Schema:SaveVendingMachines()
        return vendor
    end

    function ENT:GetClosestButton(ply)
        local data = {}
            data.start = ply:GetShootPos()
            data.endpos = data.start + ply:GetAimVector() * 96
            data.filter = ply
        local trace = util.TraceLine(data)
        local tracePosition = trace.HitPos

        if (tracePosition) then
            for k, v in ipairs(self.Items) do
                local position = self:GetPos() + self:GetForward() * 17.5 + self:GetRight() * -24.4 + (self:GetUp() * 5.3 - Vector(0, 0, (k - 1) * 2.1))

                if (position:DistToSqr(tracePosition) <= 1) then
                    return k
                end
            end
        end
    end

    function ENT:SetStock(id, amount)
        if (type(id) == "table") then
            self:SetNetVar("stock", id)
            return
        end

        local stock = self:GetNetVar("stock", {})
        stock[id] = math.Clamp(amount, 0, self.MaxStock)

        self:SetNetVar("stock", stock)
    end

    function ENT:ResetStock(id)
        local stock = self:GetNetVar("stock", {})

        -- reset stock of all items if no id is specified
        if (id) then
            stock[id] = self.MaxStock
        else
            for k, v in ipairs(self.Items) do
                stock[k] = self.MaxStock
            end
        end

        self:SetNetVar("stock", stock)
    end

    function ENT:RemoveStock(id)
        self:SetStock(id, self:GetStock(id) - 1)
    end

    function ENT:Use(ply)
        local buttonID = self:GetClosestButton(ply)

        if (buttonID) then
            ply:EmitSound("buttons/lightswitch2.wav", 40, 150)
        else
            return
        end

        if (self.nextUseTime > CurTime()) then
            return
        end

        local char = ply:GetCharacter()
        
        local itemInfo = self.Items[buttonID]
        local price = itemInfo[3]

        if (!char:HasMoney(price)) then
            self:EmitSound("buttons/button2.wav", 50)
            self.nextUseTime = CurTime() + 1

            ply:NotifyLocalized("vendingNeedMoney", ix.currency.Get(price))
            return false
        end

        if (self:GetStock(buttonID) > 0) then
            ix.item.Spawn(itemInfo[2], self:GetPos() + self:GetForward() * 19 + self:GetRight() * 4 + self:GetUp() * -26, function(item, entity)
                self:EmitSound("buttons/button4.wav", 60)

                char:TakeMoney(price)
                ply:NotifyLocalized("vendingPurchased", ix.currency.Get(price))

                self:RemoveStock(buttonID)
                self.nextUseTime = CurTime() + 1
            end)
        else
            self:EmitSound("buttons/button2.wav", 50)
            self.nextUseTime = CurTime() + 1
        end
    end

    function ENT:OnRemove()
        if (!ix.shuttingDown) then
            Schema:SaveVendingMachines()
        end
    end
else
    surface.CreateFont("ixVendingMachine", {
        font = "Default",
        size = 13,
        weight = 800,
        antialias = false
    })

    local color_red = Color(100, 20, 20, 255)
    local color_blue = Color(0, 50, 100, 255)
    local color_black = Color(60, 60, 60, 255)

    function ENT:Draw()
        self:DrawModel()

        local position = self:GetPos()

        if (LocalPlayer():GetPos():DistToSqr(position) > self.MaxRenderDistance) then
            return
        end

        local angles = self:GetAngles()
        local forward, right, up = self:GetForward(), self:GetRight(), self:GetUp()

        angles:RotateAroundAxis(angles:Up(), 90)
        angles:RotateAroundAxis(angles:Forward(), 90)

        cam.Start3D2D(position + forward * 17.33 + right * -19.2 + up * 6.1, angles, 0.06)
            render.PushFilterMin(TEXFILTER.NONE)
            render.PushFilterMag(TEXFILTER.NONE)

            local width = 70
            local smallWidth = 20
            local height = 29
            local halfWidth = width / 2
            local halfHeight = height / 2

            for i = 1, 8 do
                local itemInfo = self.Items[i]
                local x = 0
                local y = (i - 1) * 34

                surface.SetDrawColor(color_black)
                surface.DrawOutlinedRect(x, y, width, height)

                surface.SetDrawColor(color_black)
                surface.DrawRect(x + 1, y + 1, width - 2, height - 2)

                surface.SetDrawColor(color_red)

                if (itemInfo) then
                    draw.SimpleText(itemInfo[1], "ixVendingMachine", x + halfWidth, y + halfHeight, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

                    if (self:GetStock(i) > 0) then
                        surface.SetDrawColor(color_blue)
                    end
                end

                surface.DrawRect(x + width + 6, y, smallWidth, height)
            end

            render.PopFilterMin()
            render.PopFilterMag()
        cam.End3D2D()
    end
    
    ENT.PopulateEntityInfo = true

    function ENT:OnPopulateEntityInfo(container)
        local name = container:AddRow("name")
        name:SetImportant()
        name:SetText("Vending Machine")
        name:SizeToContents()
    end
end
