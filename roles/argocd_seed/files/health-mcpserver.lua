-- RHOAI MCP lifecycle: MCPServer is Healthy when it reports Ready.
-- Keep this generic enough to tolerate status shape changes between versions.
hs = {}
if obj.status ~= nil and obj.status.conditions ~= nil then
  for i, condition in ipairs(obj.status.conditions) do
    if (condition.type == "Failed" or condition.type == "Error" or condition.type == "Degraded")
      and condition.status == "True" then
      hs.status = "Degraded"
      hs.message = condition.message
      return hs
    end
  end
  for i, condition in ipairs(obj.status.conditions) do
    if condition.type == "Ready" and condition.status == "True" then
      hs.status = "Healthy"
      hs.message = condition.message
      return hs
    end
  end
end

if obj.status ~= nil and obj.status.phase ~= nil then
  if obj.status.phase == "Ready" or obj.status.phase == "Running" or obj.status.phase == "Succeeded" then
    hs.status = "Healthy"
    hs.message = "MCPServer is ready"
    return hs
  end
  if obj.status.phase == "Failed" or obj.status.phase == "Error" then
    hs.status = "Degraded"
    hs.message = "MCPServer failed"
    return hs
  end
end

hs.status = "Progressing"
hs.message = "Waiting for MCPServer to be ready"
return hs
