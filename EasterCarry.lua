local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SwapToolsGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "MainFrame"
frame.Size = UDim2.new(0, 100, 0, 40)
frame.Position = UDim2.new(0, 0, 1, 0)
frame.AnchorPoint = Vector2.new(0, 1)
frame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
frame.BackgroundTransparency = 1
frame.Parent = screenGui

local btnRecover = Instance.new("TextButton")
btnRecover.Name = "RecoverBtn"
btnRecover.Size = UDim2.new(1, 0, 0.5, 0)
btnRecover.Position = UDim2.new(0.5, 0, 0, 0)
btnRecover.AnchorPoint = Vector2.new(0.5, 0)
btnRecover.Text = "Recover"
btnRecover.Visible = false
btnRecover.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
btnRecover.TextColor3 = Color3.fromRGB(255, 255, 255)
btnRecover.Parent = frame

local btnExecute = Instance.new("TextButton")
btnExecute.Name = "ExecuteBtn"
btnExecute.Size = UDim2.new(1, 0, 0.5, 0)
btnExecute.Position = UDim2.new(0.5, 0, 1, 0)
btnExecute.AnchorPoint = Vector2.new(0.5, 1)
btnExecute.Text = "Execute"
btnExecute.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
btnExecute.TextColor3 = Color3.fromRGB(255, 255, 255)
btnExecute.Parent = frame

local historyParent = {}

local swapList = {
	{
		path1 = "ReplicatedStorage.Items.BaseItems.CarryAnimations.Cradle",
		path2 = "ReplicatedStorage.Items.ItemPacks.EventsDailyShop.Easter.CarryAnimations.EasterCarry",
	},
}

local function getObject(pathString)
	local parts = string.split(pathString, ".")
	local current = game
	for _, part in ipairs(parts) do
		current = current:FindFirstChild(part)
		if not current then
			warn("Object ga ketemu: " .. part .. " (cek path: " .. pathString .. ")")
			return nil
		end
	end
	return current
end

btnExecute.MouseButton1Click:Connect(function()
	for _, swap in ipairs(swapList) do
		local folder1 = getObject(swap.path1)
		local folder2 = getObject(swap.path2)

		if folder1 and folder2 then
			local children1 = folder1:GetChildren()
			local children2 = folder2:GetChildren()

			for _, child in ipairs(children1) do
				if not historyParent[child] then
					historyParent[child] = folder1
				end
				child.Parent = folder2
			end

			for _, child in ipairs(children2) do
				if not historyParent[child] then
					historyParent[child] = folder2
				end
				child.Parent = folder1
			end
		end
	end

	btnExecute.Visible = false 
	btnRecover.Visible = true
end)

btnRecover.MouseButton1Click:Connect(function()
	for child, originalParent in pairs(historyParent) do
		if child and originalParent then
			child.Parent = originalParent
		end
	end

	historyParent = {}

	btnRecover.Visible = false
	btnExecute.Visible = true
end)
