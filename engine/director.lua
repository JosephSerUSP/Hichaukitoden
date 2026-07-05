local director = {}

local GraphWalker = {}
GraphWalker.__index = GraphWalker

function GraphWalker.new(session, graphData)
    local self = setmetatable({}, GraphWalker)
    self.session = session
    self.graph = graphData
    self.currentNodeId = graphData.initialNode or "start"
    self.currentNode = graphData.nodes[self.currentNodeId]
    self.history = {}
    return self
end

function GraphWalker:evaluateCondition(condStr)
    if not condStr or condStr == "" then return true end
    
    if condStr:match("^flag:(.+)") then
        local flag = condStr:match("^flag:(.+)")
        return self.session.flags[flag] == true
    elseif condStr:match("^hasItem:(.+)") then
        local itemId = condStr:match("^hasItem:(.+)")
        return self.session:hasItem(itemId, 1)
    end
    
    return false
end

function GraphWalker:getCurrentNode()
    return self.currentNode, self.currentNodeId
end

function GraphWalker:advance()
    if not self.currentNode then return nil end
    
    local nextNodeId = self.currentNode.next
    if self.currentNode.type == "ROUTER" then
        if self:evaluateCondition(self.currentNode.condition) then
            nextNodeId = self.currentNode.trueNode
        else
            nextNodeId = self.currentNode.falseNode
        end
    end
    
    if nextNodeId then
        self:goToNode(nextNodeId)
    else
        self.currentNode = nil
        self.currentNodeId = nil
    end
    
    return self.currentNode
end

function GraphWalker:goToNode(nodeId)
    table.insert(self.history, self.currentNodeId)
    self.currentNodeId = nodeId
    self.currentNode = self.graph.nodes[nodeId]
    
    -- Auto-evaluate routers
    if self.currentNode and self.currentNode.type == "ROUTER" then
        self:advance()
    end
end

function GraphWalker:selectChoice(optionIndex)
    if not self.currentNode or self.currentNode.type ~= "CHOICE" then return end
    
    local opt = self.currentNode.options[optionIndex]
    if not opt then return end
    
    if opt.setFlag then
        self.session.flags[opt.setFlag] = true
    end
    
    if opt.action == "close" then
        self.currentNode = nil
        self.currentNodeId = nil
    elseif opt.target then
        self:goToNode(opt.target)
    end
end

director.GraphWalker = GraphWalker

-- Helper to load graph by name using loader
function director.startConversation(session, graphName)
    local path = "data/graphs/" .. graphName .. ".json"
    local contents = love.filesystem.read(path)
    if not contents then
        print("Warning: Conversation graph not found: " .. path)
        return nil
    end
    local json = require("data.json")
    local graphData = json.decode(contents)
    return GraphWalker.new(session, graphData)
end

return director
