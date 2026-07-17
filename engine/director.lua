local conditions = require("engine.conditions")

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
    -- A CONDITIONAL_BRANCH command can compile to a ROUTER as the very first
    -- node of a graph; settle it immediately so callers never see a raw ROUTER.
    self:settleRouter()
    return self
end

function GraphWalker:evaluateCondition(condStr)
    if not condStr or condStr == "" then return true end

    -- Shared "flag:"/"hasItem:" grammar (see engine/conditions.lua); a
    -- ROUTER's fallback for any non-prefixed string is false.
    local matched, result = conditions.evalPrefixed(condStr, self.session)
    if matched then return result end

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
    self:settleRouter()
end

-- ROUTER nodes (compiled from CONDITIONAL_BRANCH) are silent/automatic: they
-- pick a branch and continue rather than waiting for player input, so nothing
-- outside this file should ever see currentNode.type == "ROUTER".
function GraphWalker:settleRouter()
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
    local walker = GraphWalker.new(session, graphData)
    walker.eventName = graphData.name
    return walker
end

return director
