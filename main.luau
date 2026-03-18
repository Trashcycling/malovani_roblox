
-- script JE závislý na robloxu, dávám ho sem na implicitní žádost ze zadání. Ne vše šlo splnit, za což se omlouvám.
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All,false)

local canvas = script.Parent
local header = script.Parent.Parent.Header
local footer = script.Parent.Parent.Footer

local modeButton = header.ModeBtn
local labelX = header["X"]
local labelY = header["Y"]
local brushSizeInput = header.Radius
local shapeSelector = header.SwitchOperator
local colorValue = header.ColorVal

local jointTemplate = canvas.jointTemplate
local eraserButton = footer.Eraser
local bucketButton = footer.Bucket

canvas.Active = true
canvas.Draggable = false
task.wait()

local CANVAS_WIDTH_PIXELS = math.floor(canvas.AbsoluteSize.X)
local CANVAS_HEIGHT_PIXELS = math.floor(canvas.AbsoluteSize.Y)

local DOTTED_LINE_DASH_LENGTH = 10
local DOTTED_LINE_GAP_LENGTH = 6
local ANGLE_SNAP_INCREMENT = 45
local DOUBLE_CLICK_THRESHOLD = 0.35

local MAX_UNDO_HISTORY = 20
local FILL_BATCH_SIZE = 2500

local BASE_ZINDEX = 2
local MAX_ZINDEX = 500
local currentZIndex = BASE_ZINDEX

local COLOR_PREVIEW = Color3.fromRGB(255,0,0)
local COLOR_BLACK = Color3.new(0,0,0)

local COLOR_BUTTON_ACTIVE_BG = Color3.fromRGB(75,255,25)
local COLOR_BUTTON_ACTIVE_BORDER = Color3.fromRGB(0,170,0)
local COLOR_BUTTON_INACTIVE_BG = Color3.fromRGB(251,255,28)
local COLOR_BUTTON_INACTIVE_BORDER = Color3.fromRGB(255,128,1)


local AVAILABLE_MODES ={"line","polygon","shapes"}

local currentMode ="line"
local activeTool ="draw"
local brushSize = 1

local lineStartPoint = nil
local isDraggingLine = false

local shapeStartPoint = nil

local isShiftHeld = false
local isCtrlHeld = false
local isSpaceHeld = false

local activePolygon = nil
local selectedJoint = nil

local isEraserDragging = false
local eraserMode ="erase"
local hasEraserUndoBeenPushed = false

local lastMouseX = nil
local lastMouseY = nil

local isFilling = false

local undoHistory ={}


local pixelData ={}

local framePool ={}
local renderFrames ={}
local dirtyRows ={}


local previewFramePool ={}
local activePreviewFrames ={}

local isWithinBounds
local clearPreviewFrames
local updatePolygonPreview
local pushUndoState
local closePolygon
local autoClosePolygon
local registerJointEvents

local plotTarget = nil

local function getCurrentColor()
	return colorValue.Value
end

local function getFillColor()
	return colorValue.Value
end


local function isInsideCanvasPixel(pixelX,pixelY)
	return pixelX >= 0
		and pixelX < CANVAS_WIDTH_PIXELS
		and pixelY >= 0
		and pixelY < CANVAS_HEIGHT_PIXELS
end


local function screenToPixel(screenX,screenY)
	return math.floor(screenX),math.floor(screenY)
end

local function encodePixel(pixelX,pixelY)
	return(pixelY * CANVAS_WIDTH_PIXELS)+ pixelX
end

local function decodePixel(encodedValue)
	local pixelX = encodedValue % CANVAS_WIDTH_PIXELS
	local pixelY = math.floor(encodedValue / CANVAS_WIDTH_PIXELS)
	return pixelX,pixelY
end

local function colorsAreEqual(colorA,colorB)
	if colorA == nil and colorB == nil then
		return true
	end

	if colorA == nil or colorB == nil then
		return false
	end

	local tolerance = 0.004

	return math.abs(colorA.R - colorB.R)< tolerance
		and math.abs(colorA.G - colorB.G)< tolerance
		and math.abs(colorA.B - colorB.B)< tolerance
end

local function calculateBrushRadius()
	return math.floor(brushSize / 2)
end

local function calculateBrushDiameter()
	local radius = calculateBrushRadius()
	return(radius * 2)+ 1
end


local function getPixelData(pixelX,pixelY)
	local row = pixelData[pixelY]
	return row and row[pixelX]or nil
end

local function getPixelColor(pixelX,pixelY)
	return getPixelData(pixelX,pixelY)
end

local function setPixelData(pixelX,pixelY,color)
	if not isInsideCanvasPixel(pixelX,pixelY)then
		return
	end

	if color == nil then
		if pixelData[pixelY]then
			pixelData[pixelY][pixelX]= nil
		end
	else
		if not pixelData[pixelY]then
			pixelData[pixelY]={}
		end
		pixelData[pixelY][pixelX]= color
	end
end

local function createDataSnapshot()
	local snapshot ={}

	for pixelY,row in pairs(pixelData)do
		snapshot[pixelY]={}
		for pixelX,color in pairs(row)do
			snapshot[pixelY][pixelX]= color
		end
	end

	return snapshot
end

local function restoreDataSnapshot(snapshot)
	pixelData ={}

	for pixelY,row in pairs(snapshot)do
		pixelData[pixelY]={}
		for pixelX,color in pairs(row)do
			pixelData[pixelY][pixelX]= color
		end
	end
end

local function markRowDirty(pixelY)
	dirtyRows[pixelY]= true
end

local function setPixel(pixelX,pixelY,color)
	if not isInsideCanvasPixel(pixelX,pixelY)then
		return
	end

	setPixelData(pixelX,pixelY,color)
	markRowDirty(pixelY)
end

local function plotPixel(pixelX,pixelY,color)
	if not isInsideCanvasPixel(pixelX,pixelY)then
		return
	end

	if plotTarget then
		if not plotTarget[pixelY]then
			plotTarget[pixelY]={}
		end
		plotTarget[pixelY][pixelX]= color
	else
		setPixelData(pixelX,pixelY,color)
		markRowDirty(pixelY)
	end
end

local function getFrame()
	if#framePool > 0 then
		return table.remove(framePool)
	end

	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.Parent = canvas
	return frame
end

local function returnFrame(frame)
	frame.Visible = false
	table.insert(framePool,frame)
end


local function rebuildRow(pixelY)
	if renderFrames[pixelY]then
		for _,frame in ipairs(renderFrames[pixelY])do
			returnFrame(frame)
		end
	end
	renderFrames[pixelY]={}

	local row = pixelData[pixelY]
	if not row then
		return
	end

	local xCoordinates ={}
	for pixelX in pairs(row)do
		table.insert(xCoordinates,pixelX)
	end
	table.sort(xCoordinates)

	if#xCoordinates == 0 then
		return
	end

	local currentSpanStartX = xCoordinates[1]
	local currentSpanColor = row[currentSpanStartX]
	local previousXInSpan = currentSpanStartX

	local function commitCurrentSpan()
		local spanWidth =(previousXInSpan - currentSpanStartX)+ 1

		local frame = getFrame()
		frame.Position = UDim2.new(0,currentSpanStartX,0,pixelY)
		frame.Size = UDim2.new(0,spanWidth,0,1)
		frame.BackgroundColor3 = currentSpanColor
		frame.ZIndex = currentZIndex
		frame.Visible = true

		table.insert(renderFrames[pixelY],frame)
	end

	for i = 2,#xCoordinates do
		local pixelX = xCoordinates[i]
		local color = row[pixelX]

		local isImmediatelyNextPixel =(pixelX == previousXInSpan + 1)
		local isSameColor = colorsAreEqual(color,currentSpanColor)

		if isImmediatelyNextPixel and isSameColor then
			previousXInSpan = pixelX
		else
			commitCurrentSpan()

			currentSpanStartX = pixelX
			currentSpanColor = color
			previousXInSpan = pixelX
		end
	end

	commitCurrentSpan()
end

local function flushRender()
	for pixelY in pairs(dirtyRows)do
		rebuildRow(pixelY)
	end
	dirtyRows ={}
end

local function rebuildAllRows()
	for pixelY in pairs(renderFrames)do
		dirtyRows[pixelY]= true
	end

	for pixelY in pairs(pixelData)do
		dirtyRows[pixelY]= true
	end

	flushRender()
end

local function flattenCanvas()
	currentZIndex = BASE_ZINDEX
	rebuildAllRows()
end

local function incrementZIndex()
	currentZIndex = currentZIndex + 1
	if currentZIndex > MAX_ZINDEX then
		flattenCanvas()
	end
end

local function clearAllPixels()
	for pixelY in pairs(renderFrames)do
		if renderFrames[pixelY]then
			for _,frame in ipairs(renderFrames[pixelY])do
				returnFrame(frame)
			end
		end
	end

	renderFrames ={}
	pixelData ={}
	dirtyRows ={}
	currentZIndex = BASE_ZINDEX
end

local function getPreviewFrame()
	if#previewFramePool > 0 then
		local frame = table.remove(previewFramePool)
		frame.Visible = true
		return frame
	end

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0,0)
	frame.BackgroundColor3 = COLOR_PREVIEW
	frame.BorderSizePixel = 0
	frame.Rotation = 0
	frame.ZIndex = 100
	frame.Parent = canvas
	return frame
end

local function returnPreviewFrame(frame)
	frame.Visible = false
	table.insert(previewFramePool,frame)
end

clearPreviewFrames = function()
	for i =#activePreviewFrames,1,-1 do
		returnPreviewFrame(table.remove(activePreviewFrames,i))
	end
end



local function renderPreviewBuffer(buffer)
	clearPreviewFrames()

	for y,row in pairs(buffer)do
		local xs ={}
		for x in pairs(row)do
			table.insert(xs,x)
		end
		table.sort(xs)

		if#xs == 0 then
			continue
		end

		local spanStart = xs[1]
		local spanEnd = spanStart

		for i = 2,#xs do
			local x = xs[i]

			if x == spanEnd + 1 then
				spanEnd = x
			else
				local frame = getPreviewFrame()
				frame.Position = UDim2.new(0,spanStart,0,y)
				frame.Size = UDim2.new(0,spanEnd - spanStart + 1,0,1)
				table.insert(activePreviewFrames,frame)

				spanStart = x
				spanEnd = x
			end
		end

		local frame = getPreviewFrame()
		frame.Position = UDim2.new(0,spanStart,0,y)
		frame.Size = UDim2.new(0,spanEnd - spanStart + 1,0,1)
		table.insert(activePreviewFrames,frame)
	end
end


local function beginPreviewCapture()
	plotTarget ={}
end

local function endPreviewCapture()
	local buffer = plotTarget
	plotTarget = nil
	return buffer
end


local eraserCursor = Instance.new("Frame")
eraserCursor.AnchorPoint = Vector2.new(0.5,0.5)
eraserCursor.BackgroundColor3 = Color3.fromRGB(255,255,255)
eraserCursor.BackgroundTransparency = 0.6
eraserCursor.BorderSizePixel = 1
eraserCursor.BorderColor3 = Color3.fromRGB(0,0,0)
eraserCursor.ZIndex = 150
eraserCursor.Visible = false
Instance.new("UICorner",eraserCursor).CornerRadius = UDim.new(1,0)
eraserCursor.Parent = canvas

local function updateEraserCursorSize()
	local cursorDiameter = calculateBrushDiameter()
	eraserCursor.Size = UDim2.new(0,cursorDiameter,0,cursorDiameter)
end

local function getCanvasPosition(inputObject)
	local canvasAbsolutePosition = canvas.AbsolutePosition
	local localX = inputObject.Position.X - canvasAbsolutePosition.X
	local localY = inputObject.Position.Y - canvasAbsolutePosition.Y
	return localX,localY
end

isWithinBounds = function(screenX,screenY)
	return screenX >= 0
		and screenX < CANVAS_WIDTH_PIXELS
		and screenY >= 0
		and screenY < CANVAS_HEIGHT_PIXELS
end

local function updateCanvasPositionLabels()
	local pozice = canvas.Position
	labelX.Text ="X: "..math.floor(pozice.X.Offset)
	labelY.Text ="Y: "..math.floor(pozice.Y.Offset)
end


local function snapAngleToIncrement(startX,startY,endX,endY)
	local differenceInX = endX - startX
	local differenceInY = endY - startY

	local originalAngleInDegrees = math.deg(math.atan2(differenceInY,differenceInX))
	local snappedAngleInDegrees =
		math.round(originalAngleInDegrees / ANGLE_SNAP_INCREMENT)* ANGLE_SNAP_INCREMENT

	local delkaUsecky = math.sqrt((differenceInX * differenceInX)+(differenceInY * differenceInY))
	local snappedAngleInRadians = math.rad(snappedAngleInDegrees)

	local snappedEndX = startX +(delkaUsecky * math.cos(snappedAngleInRadians))
	local snappedEndY = startY +(delkaUsecky * math.sin(snappedAngleInRadians))

	return snappedEndX,snappedEndY
end

local function constrainToSquare(startX,startY,endX,endY)
	if not isShiftHeld then
		return endX,endY
	end

	local differenceInX = endX - startX
	local differenceInY = endY - startY

	local sideLength = math.min(math.abs(differenceInX),math.abs(differenceInY))

	local signX =(differenceInX >= 0)and 1 or -1
	local signY =(differenceInY >= 0)and 1 or -1

	return startX +(sideLength * signX),startY +(sideLength * signY)
end

local function stampBrush(cx,cy,radius,color)
	for oy =-radius,radius do
		for ox =-radius,radius do
			plotPixel(cx + ox,cy + oy,color)
		end
	end
end



local function drawRasterLine(startX,startY,endX,endY,color,isDotted)
	local sx,sy = screenToPixel(startX,startY)
	local ex,ey = screenToPixel(endX,endY)

	local dx = ex - sx
	local dy = ey - sy
	local steps = math.max(math.abs(dx),math.abs(dy))

	local radius = calculateBrushRadius()


	if steps == 0 then
		stampBrush(sx,sy,radius,color)
		return
	end


	if not isDotted and radius > 0 then
		if dy == 0 then

			local left = math.max(0,math.min(sx,ex)- radius)
			local right = math.min(CANVAS_WIDTH_PIXELS - 1,math.max(sx,ex)+ radius)
			local top = math.max(0,sy - radius)
			local bottom = math.min(CANVAS_HEIGHT_PIXELS - 1,sy + radius)

			for y = top,bottom do
				for x = left,right do
					plotPixel(x,y,color)
				end
			end
			return

		elseif dx == 0 then

			local left = math.max(0,sx - radius)
			local right = math.min(CANVAS_WIDTH_PIXELS - 1,sx + radius)
			local top = math.max(0,math.min(sy,ey)- radius)
			local bottom = math.min(CANVAS_HEIGHT_PIXELS - 1,math.max(sy,ey)+ radius)

			for y = top,bottom do
				for x = left,right do
					plotPixel(x,y,color)
				end
			end
			return
		end
	end

	if radius == 0 then

		local xStep = dx / steps
		local yStep = dy / steps
		local fullPatternLength = DOTTED_LINE_DASH_LENGTH + DOTTED_LINE_GAP_LENGTH

		for i = 0,steps do
			local shouldDraw =(not isDotted)or((i % fullPatternLength)< DOTTED_LINE_DASH_LENGTH)

			if shouldDraw then
				plotPixel(math.floor(sx + i * xStep),math.floor(sy + i * yStep),color)
			end
		end
	else
		local len = math.sqrt(dx * dx + dy * dy)
		local dirX = dx / len
		local dirY = dy / len


		local perpX =-dirY * radius
		local perpY = dirX * radius


		local cornersX ={sx + perpX,ex + perpX,ex - perpX,sx - perpX}
		local cornersY ={sy + perpY,ey + perpY,ey - perpY,sy - perpY}


		local bandMinY = math.huge
		local bandMaxY =-math.huge
		for i = 1,4 do
			if cornersY[i]< bandMinY then bandMinY = cornersY[i]end
			if cornersY[i]> bandMaxY then bandMaxY = cornersY[i]end
		end

		local rowTop = math.max(0,math.floor(bandMinY))
		local rowBottom = math.min(CANVAS_HEIGHT_PIXELS - 1,math.floor(bandMaxY))

		local fullPatternLength = DOTTED_LINE_DASH_LENGTH + DOTTED_LINE_GAP_LENGTH


		for y = rowTop,rowBottom do
			local scanY = y + 0.5
			local leftEdge = math.huge
			local rightEdge =-math.huge


			for i = 1,4 do
				local j =(i % 4)+ 1
				local ay = cornersY[i]
				local by = cornersY[j]


				if(ay <= scanY and by > scanY)or(by <= scanY and ay > scanY)then

					local t =(scanY - ay)/(by - ay)
					local hitX = cornersX[i]+ t *(cornersX[j]- cornersX[i])

					if hitX < leftEdge then leftEdge = hitX end
					if hitX > rightEdge then rightEdge = hitX end
				end
			end

			if leftEdge <= rightEdge then
				local fillLeft = math.max(0,math.floor(leftEdge))
				local fillRight = math.min(CANVAS_WIDTH_PIXELS - 1,math.floor(rightEdge))

				if not isDotted then

					for x = fillLeft,fillRight do
						plotPixel(x,y,color)
					end
				else


					for x = fillLeft,fillRight do

						local dist =(x - sx)* dirX +(y - sy)* dirY
						if dist < 0 then dist = 0 end

						if(dist % fullPatternLength)< DOTTED_LINE_DASH_LENGTH then
							plotPixel(x,y,color)
						end
					end
				end
			end
		end
	end
end




local function drawRasterRectangle(x1,y1,x2,y2,color,isDotted)
	drawRasterLine(x1,y1,x2,y1,color,isDotted)
	drawRasterLine(x2,y1,x2,y2,color,isDotted)
	drawRasterLine(x2,y2,x1,y2,color,isDotted)
	drawRasterLine(x1,y2,x1,y1,color,isDotted)
end

local function drawRasterPolygon(joints,isClosed,color,isDotted)
	for i = 1,#joints - 1 do
		drawRasterLine(joints[i].x,joints[i].y,joints[i + 1].x,joints[i + 1].y,color,isDotted)
	end

	if isClosed and#joints >= 3 then
		drawRasterLine(joints[#joints].x,joints[#joints].y,joints[1].x,joints[1].y,color,isDotted)
	end
end






local function drawRasterOval(x1,y1,x2,y2,color,isDotted)
	local centerX =(x1 + x2)/ 2
	local centerY =(y1 + y2)/ 2

	local radiusX = math.abs(x2 - x1)/ 2
	local radiusY = math.abs(y2 - y1)/ 2

	if radiusX < 1 or radiusY < 1 then
		return
	end


	local estimatedCircumference = math.pi *(radiusX + radiusY)
	local segmentCount = math.max(64,math.floor(estimatedCircumference))

	local previousX = nil
	local previousY = nil


	local perimeterWalked = 0
	local fullPattern = DOTTED_LINE_DASH_LENGTH + DOTTED_LINE_GAP_LENGTH

	for i = 0,segmentCount do
		local angle =(i / segmentCount)* 2 * math.pi

		local currentX = centerX +(radiusX * math.cos(angle))
		local currentY = centerY +(radiusY * math.sin(angle))

		if previousX ~= nil then
			if not isDotted then

				drawRasterLine(previousX,previousY,currentX,currentY,color,false)
			else



				local segDx = currentX - previousX
				local segDy = currentY - previousY
				local segLen = math.sqrt(segDx * segDx + segDy * segDy)

				local walked = 0
				while walked < segLen do
					local patternPos =(perimeterWalked + walked)% fullPattern

					if patternPos < DOTTED_LINE_DASH_LENGTH then

						local dashRemaining = DOTTED_LINE_DASH_LENGTH - patternPos
						local drawLen = math.min(dashRemaining,segLen - walked)
						local t0 = walked / segLen
						local t1 =(walked + drawLen)/ segLen

						drawRasterLine(
							previousX + segDx * t0,previousY + segDy * t0,
							previousX + segDx * t1,previousY + segDy * t1,
							color,false
						)

						walked = walked + drawLen
					else

						local gapRemaining = fullPattern - patternPos
						walked = walked + math.min(gapRemaining,segLen - walked)
					end
				end

				perimeterWalked = perimeterWalked + segLen
			end
		end

		previousX = currentX
		previousY = currentY
	end
end








local function updateLinePreview(mouseX,mouseY)
	if not lineStartPoint then
		clearPreviewFrames()
		return
	end

	local finalX = mouseX
	local finalY = mouseY

	if isShiftHeld then
		finalX,finalY = snapAngleToIncrement(lineStartPoint.x,lineStartPoint.y,mouseX,mouseY)
	end

	beginPreviewCapture()
	drawRasterLine(lineStartPoint.x,lineStartPoint.y,finalX,finalY,COLOR_PREVIEW,isCtrlHeld)
	renderPreviewBuffer(endPreviewCapture())
end

updatePolygonPreview = function(mouseX,mouseY)
	if not activePolygon then
		clearPreviewFrames()
		return
	end

	local joints = activePolygon.joints

	beginPreviewCapture()

	for i = 1,#joints - 1 do
		drawRasterLine(joints[i].x,joints[i].y,joints[i + 1].x,joints[i + 1].y,COLOR_PREVIEW,isCtrlHeld)
	end

	if mouseX and#joints > 0 then
		drawRasterLine(joints[#joints].x,joints[#joints].y,mouseX,mouseY,COLOR_PREVIEW,isCtrlHeld)
	end

	renderPreviewBuffer(endPreviewCapture())


	for _,joint in ipairs(joints)do
		if joint.frame then
			joint.frame.ZIndex = 105
		end
		if joint.button then
			joint.button.ZIndex = 106
		end
	end
end

local function updateShapePreview(mouseX,mouseY)
	if not shapeStartPoint then
		clearPreviewFrames()
		return
	end

	local finalX,finalY = constrainToSquare(shapeStartPoint.x,shapeStartPoint.y,mouseX,mouseY)

	beginPreviewCapture()

	if shapeSelector.Value =="Rectangle"then
		drawRasterRectangle(shapeStartPoint.x,shapeStartPoint.y,finalX,finalY,COLOR_PREVIEW,isCtrlHeld)
	else
		drawRasterOval(shapeStartPoint.x,shapeStartPoint.y,finalX,finalY,COLOR_PREVIEW,isCtrlHeld)
	end

	renderPreviewBuffer(endPreviewCapture())
end






pushUndoState = function(entry)
	table.insert(undoHistory,entry)

	if#undoHistory > MAX_UNDO_HISTORY then
		table.remove(undoHistory,1)
	end
end

local function performUndo()
	if#undoHistory == 0 then
		return
	end

	local undoEntry = table.remove(undoHistory)

	if undoEntry.type =="snap"then
		restoreDataSnapshot(undoEntry.data)
		currentZIndex = undoEntry.zIndex or BASE_ZINDEX
		rebuildAllRows()

	elseif undoEntry.type =="jointAdd"then
		if activePolygon and undoEntry.polygon == activePolygon and#activePolygon.joints > 0 then
			local lastJoint = table.remove(activePolygon.joints)

			if lastJoint and lastJoint.frame then
				lastJoint.frame:Destroy()
			end

			updatePolygonPreview(lastMouseX,lastMouseY)
		end
	end
end

local function floodFill(screenX,screenY)
	if isFilling then
		return
	end

	if not isWithinBounds(screenX,screenY)then
		return
	end

	local startPixelX,startPixelY = screenToPixel(screenX,screenY)

	if not isInsideCanvasPixel(startPixelX,startPixelY)then
		return
	end

	local targetColor = getPixelData(startPixelX,startPixelY)
	local fillColor = getFillColor()

	if colorsAreEqual(targetColor,fillColor)then
		return
	end

	local preSnapshot = createDataSnapshot()
	local preZIndex = currentZIndex

	local pixelsToFill ={}
	local fillCount = 0

	local visited ={}
	local queued ={}

	local isBounded = true

	local stack ={}
	local stackTop = 0

	local function shouldFill(pixelX,pixelY)
		if not isInsideCanvasPixel(pixelX,pixelY)then
			return false
		end

		local encoded = encodePixel(pixelX,pixelY)

		if visited[encoded]then
			return false
		end

		return colorsAreEqual(getPixelData(pixelX,pixelY),targetColor)
	end

	local startEncoded = encodePixel(startPixelX,startPixelY)
	stackTop = 1
	stack[1]= startEncoded
	queued[startEncoded]= true
	isFilling = true

	local fillConnection
	fillConnection = RunService.Heartbeat:Connect(function()
		local processedThisHeartbeat = 0

		while stackTop > 0 and processedThisHeartbeat < FILL_BATCH_SIZE do
			processedThisHeartbeat = processedThisHeartbeat + 1

			local encoded = stack[stackTop]
			stack[stackTop]= nil
			stackTop = stackTop - 1

			local currentPixelX,currentPixelY = decodePixel(encoded)

			if not shouldFill(currentPixelX,currentPixelY)then
				continue
			end

			local levaHranice = currentPixelX
			while levaHranice > 0 and shouldFill(levaHranice - 1,currentPixelY)do
				levaHranice = levaHranice - 1
			end

			local pravaHranice = currentPixelX
			while pravaHranice < CANVAS_WIDTH_PIXELS - 1 and shouldFill(pravaHranice + 1,currentPixelY)do
				pravaHranice = pravaHranice + 1
			end

			if levaHranice == 0
				or pravaHranice == CANVAS_WIDTH_PIXELS - 1
				or currentPixelY == 0
				or currentPixelY == CANVAS_HEIGHT_PIXELS - 1
			then
				isBounded = false
				break
			end

			for pixelX = levaHranice,pravaHranice do
				local spanEncoded = encodePixel(pixelX,currentPixelY)
				visited[spanEncoded]= true

				fillCount = fillCount + 1
				pixelsToFill[fillCount]= spanEncoded
			end

			for pixelX = levaHranice,pravaHranice do
				if currentPixelY > 0 and shouldFill(pixelX,currentPixelY - 1)then
					local aboveEncoded = encodePixel(pixelX,currentPixelY - 1)

					if not queued[aboveEncoded]then
						queued[aboveEncoded]= true
						stackTop = stackTop + 1
						stack[stackTop]= aboveEncoded
					end
				end

				if currentPixelY < CANVAS_HEIGHT_PIXELS - 1 and shouldFill(pixelX,currentPixelY + 1)then
					local belowEncoded = encodePixel(pixelX,currentPixelY + 1)

					if not queued[belowEncoded]then
						queued[belowEncoded]= true
						stackTop = stackTop + 1
						stack[stackTop]= belowEncoded
					end
				end
			end
		end

		if stackTop == 0 or not isBounded then
			fillConnection:Disconnect()
			isFilling = false

			if not isBounded then
				return
			end

			incrementZIndex()

			for i = 1,fillCount do
				local pixelX,pixelY = decodePixel(pixelsToFill[i])
				setPixelData(pixelX,pixelY,fillColor)
				markRowDirty(pixelY)
			end

			flushRender()

			pushUndoState({
				type ="snap",
				data = preSnapshot,
				zIndex = preZIndex
			})
		end
	end)
end

local function eraseAtPosition(screenX,screenY)
	local centerPixelX,centerPixelY = screenToPixel(screenX,screenY)

	local pixelRadius = calculateBrushRadius()
	local radiusSquared = pixelRadius * pixelRadius

	for offsetY =-pixelRadius,pixelRadius do
		for offsetX =-pixelRadius,pixelRadius do
			local distanceSquared =(offsetX * offsetX)+(offsetY * offsetY)

			if distanceSquared <= radiusSquared then
				setPixel(centerPixelX + offsetX,centerPixelY + offsetY,nil)
			end
		end
	end

	if pixelRadius == 0 then
		setPixel(centerPixelX,centerPixelY,nil)
	end
end

local function blackenAtPosition(screenX,screenY)
	local centerPixelX,centerPixelY = screenToPixel(screenX,screenY)

	local pixelRadius = calculateBrushRadius()
	local radiusSquared = pixelRadius * pixelRadius

	for offsetY =-pixelRadius,pixelRadius do
		for offsetX =-pixelRadius,pixelRadius do
			local distanceSquared =(offsetX * offsetX)+(offsetY * offsetY)

			if distanceSquared <= radiusSquared then
				local targetPixelX = centerPixelX + offsetX
				local targetPixelY = centerPixelY + offsetY

				if getPixelColor(targetPixelX,targetPixelY)~= nil then
					setPixel(targetPixelX,targetPixelY,COLOR_BLACK)
				end
			end
		end
	end

	if pixelRadius == 0 and getPixelColor(centerPixelX,centerPixelY)~= nil then
		setPixel(centerPixelX,centerPixelY,COLOR_BLACK)
	end
end

closePolygon = function(polygon)
	if not polygon or polygon.closed then
		return
	end

	for i =#undoHistory,1,-1 do
		if undoHistory[i].type =="jointAdd"and undoHistory[i].polygon == polygon then
			table.remove(undoHistory,i)
		end
	end

	if#polygon.joints < 3 then
		for _,joint in ipairs(polygon.joints)do
			if joint.frame then
				joint.frame:Destroy()
			end
		end

		clearPreviewFrames()
		activePolygon = nil
		selectedJoint = nil
		return
	end

	polygon.closed = true

	local preSnapshot = createDataSnapshot()
	local preZIndex = currentZIndex

	clearPreviewFrames()
	incrementZIndex()
	drawRasterPolygon(polygon.joints,true,getCurrentColor(),isCtrlHeld)
	flushRender()

	for _,joint in ipairs(polygon.joints)do
		if joint.frame then
			joint.frame:Destroy()
		end
	end

	activePolygon = nil
	selectedJoint = nil

	pushUndoState({
		type ="snap",
		data = preSnapshot,
		zIndex = preZIndex
	})
end

autoClosePolygon = function()
	if activePolygon then
		closePolygon(activePolygon)
	end
end

registerJointEvents = function(polygon,joint)
	local button = joint.button
	if not button then
		return
	end

	local lastClickTime = 0
	local isDraggingJoint = false

	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		local now = tick()

		if now - lastClickTime < DOUBLE_CLICK_THRESHOLD then
			isDraggingJoint = false

			if polygon == activePolygon and not polygon.closed then
				closePolygon(polygon)
			end
		else
			isDraggingJoint = true
			selectedJoint ={
				joint = joint,
				polygon = polygon
			}
		end

		lastClickTime = now
	end)

	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isDraggingJoint = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not isDraggingJoint or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local newX = input.Position.X - canvas.AbsolutePosition.X
		local newY = input.Position.Y - canvas.AbsolutePosition.Y

		joint.x = newX
		joint.y = newY

		local halfSizeX = joint.frame.Size.X.Offset / 2
		local halfSizeY = joint.frame.Size.Y.Offset / 2
		joint.frame.Position = UDim2.new(0,newX - halfSizeX,0,newY - halfSizeY)

		updatePolygonPreview(lastMouseX,lastMouseY)
	end)
end

local function createJoint(polygon,screenX,screenY)
	local jointFrame = jointTemplate:Clone()
	jointFrame.Position = UDim2.new(
		0,
		screenX -(jointFrame.Size.X.Offset / 2),
		0,
		screenY -(jointFrame.Size.Y.Offset / 2)
	)
	jointFrame.ZIndex = 105
	jointFrame.Visible = true
	jointFrame.Parent = canvas

	local jointButton = jointFrame:FindFirstChildWhichIsA("TextButton")
	if jointButton then
		jointButton.ZIndex = 106
	end

	local joint ={
		x = screenX,
		y = screenY,
		frame = jointFrame,
		button = jointButton
	}

	table.insert(polygon.joints,joint)
	registerJointEvents(polygon,joint)

	pushUndoState({
		type ="jointAdd",
		polygon = polygon
	})

	return joint
end

local function deleteSelectedJoint()
	if not selectedJoint or selectedJoint.polygon ~= activePolygon then
		selectedJoint = nil
		return
	end

	local joint = selectedJoint.joint
	local polygon = selectedJoint.polygon

	local jointIndex = nil

	for i,existingJoint in ipairs(polygon.joints)do
		if existingJoint == joint then
			jointIndex = i
			break
		end
	end

	if not jointIndex then
		return
	end

	for i =#undoHistory,1,-1 do
		if undoHistory[i].type =="jointAdd"and undoHistory[i].polygon == polygon then
			table.remove(undoHistory,i)
			break
		end
	end

	table.remove(polygon.joints,jointIndex)

	if joint.frame then
		joint.frame:Destroy()
	end

	selectedJoint = nil
	updatePolygonPreview(lastMouseX,lastMouseY)
end


local function setActiveTool(newTool)
	if activeTool =="eraser"then
		eraserCursor.Visible = false
		isEraserDragging = false
		hasEraserUndoBeenPushed = false
	end

	if activeTool =="draw"and newTool ~="draw"then
		clearPreviewFrames()
		lineStartPoint = nil
		isDraggingLine = false
		shapeStartPoint = nil

		if currentMode =="polygon"then
			autoClosePolygon()
		end
	end

	activeTool = newTool

	modeButton.BackgroundColor3 =(newTool =="draw")and COLOR_BUTTON_ACTIVE_BG or COLOR_BUTTON_INACTIVE_BG
	modeButton.BorderColor3 =(newTool =="draw")and COLOR_BUTTON_ACTIVE_BORDER or COLOR_BUTTON_INACTIVE_BORDER

	eraserButton.BackgroundColor3 =(newTool =="eraser")and COLOR_BUTTON_ACTIVE_BG or COLOR_BUTTON_INACTIVE_BG
	eraserButton.BorderColor3 =(newTool =="eraser")and COLOR_BUTTON_ACTIVE_BORDER or COLOR_BUTTON_INACTIVE_BORDER

	bucketButton.BackgroundColor3 =(newTool =="bucket")and COLOR_BUTTON_ACTIVE_BG or COLOR_BUTTON_INACTIVE_BG
	bucketButton.BorderColor3 =(newTool =="bucket")and COLOR_BUTTON_ACTIVE_BORDER or COLOR_BUTTON_INACTIVE_BORDER
end

local function getModeDisplayText(modeName)
	if modeName =="line"then
		return"Mode: Line"
	elseif modeName =="polygon"then
		return"Mode: Polygon"
	else
		return"Mode: Shapes"
	end
end

local function setDrawingMode(newMode)
	if currentMode =="polygon"and newMode ~="polygon"then
		autoClosePolygon()
	end

	if currentMode =="shapes"then
		clearPreviewFrames()
		shapeStartPoint = nil
	end

	currentMode = newMode
	modeButton.Text = getModeDisplayText(newMode)

	clearPreviewFrames()
	lineStartPoint = nil
	isDraggingLine = false
	selectedJoint = nil
end

modeButton.Activated:Connect(function()
	local currentIndex = table.find(AVAILABLE_MODES,currentMode)or 1
	local nextIndex =(currentIndex %#AVAILABLE_MODES)+ 1

	setDrawingMode(AVAILABLE_MODES[nextIndex])
	setActiveTool("draw")
end)

eraserButton.MouseButton1Click:Connect(function()
	if activeTool =="eraser"then
		setActiveTool("draw")
	else
		setActiveTool("eraser")
	end
end)

bucketButton.MouseButton1Click:Connect(function()
	if activeTool =="bucket"then
		setActiveTool("draw")
	else
		setActiveTool("bucket")
	end
end)

setActiveTool("draw")
modeButton.Text = getModeDisplayText(currentMode)
brushSizeInput.Text = tostring(brushSize)
updateEraserCursorSize()
updateCanvasPositionLabels()

brushSizeInput.FocusLost:Connect(function()
	local text = brushSizeInput.Text

	if text:match("^%d+$")then
		local value = tonumber(text)

		if value and value >= 1 and value <= 1024 then
			brushSize = value
			updateEraserCursorSize()
			return
		end
	end

	brushSizeInput.Text = tostring(brushSize)
end)

canvas:GetPropertyChangedSignal("Position"):Connect(function()
	updateCanvasPositionLabels()
end)


UserInputService.InputBegan:Connect(function(input,gameProcessed)
	if gameProcessed then
		return
	end

	local key = input.KeyCode

	if key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
		isShiftHeld = true

		if activeTool =="draw"and lastMouseX then
			if currentMode =="line"and isDraggingLine then
				updateLinePreview(lastMouseX,lastMouseY)
			elseif currentMode =="shapes"and shapeStartPoint then
				updateShapePreview(lastMouseX,lastMouseY)
			end
		end

	elseif key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.RightControl then
		isCtrlHeld = true

		if activeTool =="draw"and lastMouseX then
			if currentMode =="line"and isDraggingLine then
				updateLinePreview(lastMouseX,lastMouseY)
			elseif currentMode =="polygon"and activePolygon then
				updatePolygonPreview(lastMouseX,lastMouseY)
			elseif currentMode =="shapes"and shapeStartPoint then
				updateShapePreview(lastMouseX,lastMouseY)
			end
		end

	elseif key == Enum.KeyCode.Space then
		isSpaceHeld = true
		canvas.Draggable = true

	elseif key == Enum.KeyCode.L then
		performUndo()

	elseif key == Enum.KeyCode.Delete or key == Enum.KeyCode.Backspace then
		deleteSelectedJoint()

	elseif key == Enum.KeyCode.C then
		clearAllPixels()
		clearPreviewFrames()
		undoHistory ={}

		lineStartPoint = nil
		isDraggingLine = false
		shapeStartPoint = nil

		if activePolygon then
			for _,joint in ipairs(activePolygon.joints)do
				if joint.frame then
					joint.frame:Destroy()
				end
			end
			activePolygon = nil
		end

		selectedJoint = nil
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local key = input.KeyCode

	if key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
		isShiftHeld = false

		if activeTool =="draw"and lastMouseX then
			if currentMode =="line"and isDraggingLine then
				updateLinePreview(lastMouseX,lastMouseY)
			elseif currentMode =="shapes"and shapeStartPoint then
				updateShapePreview(lastMouseX,lastMouseY)
			end
		end

	elseif key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.RightControl then
		isCtrlHeld = false

		if activeTool =="draw"and lastMouseX then
			if currentMode =="line"and isDraggingLine then
				updateLinePreview(lastMouseX,lastMouseY)
			elseif currentMode =="polygon"and activePolygon then
				updatePolygonPreview(lastMouseX,lastMouseY)
			elseif currentMode =="shapes"and shapeStartPoint then
				updateShapePreview(lastMouseX,lastMouseY)
			end
		end

	elseif key == Enum.KeyCode.Space then
		isSpaceHeld = false
		canvas.Draggable = false
	end

	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseButton2 then
		isEraserDragging = false
		hasEraserUndoBeenPushed = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end

	local mouseX = input.Position.X - canvas.AbsolutePosition.X
	local mouseY = input.Position.Y - canvas.AbsolutePosition.Y

	lastMouseX = mouseX
	lastMouseY = mouseY

	if activeTool =="eraser"then
		if isWithinBounds(mouseX,mouseY)then
			eraserCursor.Position = UDim2.new(0,mouseX,0,mouseY)
			eraserCursor.Visible = true

			if isEraserDragging then
				if eraserMode =="erase"then
					eraseAtPosition(mouseX,mouseY)
				else
					blackenAtPosition(mouseX,mouseY)
				end

				flushRender()
			end
		else
			eraserCursor.Visible = false
		end

	elseif activeTool =="draw"then
		if currentMode =="line"and isDraggingLine then
			updateLinePreview(mouseX,mouseY)
		elseif currentMode =="polygon"and activePolygon then
			updatePolygonPreview(mouseX,mouseY)
		elseif currentMode =="shapes"and shapeStartPoint then
			updateShapePreview(mouseX,mouseY)
		end
	end
end)

canvas.InputBegan:Connect(function(input)
	local inputType = input.UserInputType

	if inputType == Enum.UserInputType.MouseButton1 then
		local mouseX,mouseY = getCanvasPosition(input)

		if activeTool =="eraser"and not isSpaceHeld then
			isEraserDragging = true
			eraserMode ="erase"

			if not hasEraserUndoBeenPushed then
				pushUndoState({
					type ="snap",
					data = createDataSnapshot(),
					zIndex = currentZIndex
				})
				incrementZIndex()
				hasEraserUndoBeenPushed = true
			end

			eraseAtPosition(mouseX,mouseY)
			flushRender()

		elseif activeTool =="bucket"and not isSpaceHeld then
			floodFill(mouseX,mouseY)

		elseif activeTool =="draw"and not isSpaceHeld then
			if not isWithinBounds(mouseX,mouseY)then
				return
			end

			selectedJoint = nil

			if currentMode =="line"then
				lineStartPoint ={x = mouseX,y = mouseY}
				isDraggingLine = true

			elseif currentMode =="polygon"then
				if not activePolygon then
					activePolygon ={
						joints ={},
						closed = false
					}
				end

				if not activePolygon.closed then
					createJoint(activePolygon,mouseX,mouseY)
					updatePolygonPreview(mouseX,mouseY)
				end

			elseif currentMode =="shapes"then
				shapeStartPoint ={x = mouseX,y = mouseY}
			end
		end

	elseif inputType == Enum.UserInputType.MouseButton2 then
		if activeTool =="eraser"and not isSpaceHeld then
			local mouseX,mouseY = getCanvasPosition(input)

			isEraserDragging = true
			eraserMode ="blacken"

			if not hasEraserUndoBeenPushed then
				pushUndoState({
					type ="snap",
					data = createDataSnapshot(),
					zIndex = currentZIndex
				})
				incrementZIndex()
				hasEraserUndoBeenPushed = true
			end

			blackenAtPosition(mouseX,mouseY)
			flushRender()
		end
	end
end)

canvas.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if activeTool ~="draw"then
		return
	end

	if currentMode =="line"and lineStartPoint then
		local mouseX,mouseY = getCanvasPosition(input)

		if not isWithinBounds(mouseX,mouseY)then
			clearPreviewFrames()
			lineStartPoint = nil
			isDraggingLine = false
			return
		end

		local finalX = mouseX
		local finalY = mouseY

		if isShiftHeld then
			finalX,finalY = snapAngleToIncrement(lineStartPoint.x,lineStartPoint.y,mouseX,mouseY)
		end

		clearPreviewFrames()

		local preSnapshot = createDataSnapshot()
		local preZIndex = currentZIndex

		incrementZIndex()
		drawRasterLine(lineStartPoint.x,lineStartPoint.y,finalX,finalY,getCurrentColor(),isCtrlHeld)
		flushRender()

		pushUndoState({
			type ="snap",
			data = preSnapshot,
			zIndex = preZIndex
		})

		lineStartPoint = nil
		isDraggingLine = false

	elseif currentMode =="shapes"and shapeStartPoint then
		local mouseX,mouseY = getCanvasPosition(input)

		if not isWithinBounds(mouseX,mouseY)then
			clearPreviewFrames()
			shapeStartPoint = nil
			return
		end

		local finalX,finalY = constrainToSquare(shapeStartPoint.x,shapeStartPoint.y,mouseX,mouseY)

		clearPreviewFrames()

		local preSnapshot = createDataSnapshot()
		local preZIndex = currentZIndex

		incrementZIndex()

		if shapeSelector.Value =="Rectangle"then
			drawRasterRectangle(shapeStartPoint.x,shapeStartPoint.y,finalX,finalY,getCurrentColor(),isCtrlHeld)
		else
			drawRasterOval(shapeStartPoint.x,shapeStartPoint.y,finalX,finalY,getCurrentColor(),isCtrlHeld)
		end

		flushRender()

		pushUndoState({
			type ="snap",
			data = preSnapshot,
			zIndex = preZIndex
		})

		shapeStartPoint = nil
	end
end)
