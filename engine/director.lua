local conditions = require("engine.conditions")
local formulaEngine = require("engine.formula")

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

    -- Shared "flag:"/"hasItem:"/"questStatus:" grammar (see
    -- engine/conditions.lua); anything else falls back to the sandboxed
    -- formula language (mirrors engine/interpreter.lua's IF handler), which
    -- is how compiled CONDITIONAL_BRANCH conditions express randomness,
    -- e.g. "random() < 0.2".
    local matched, result = conditions.evalPrefixed(condStr, self.session)
    if matched then return result end

    local fctx = formulaEngine.makeContext({}, self.session)
    local val, err = formulaEngine.eval(condStr, fctx)
    if err then return false end
    if type(val) == "boolean" then return val end
    return val ~= 0 and val ~= nil
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

return director
