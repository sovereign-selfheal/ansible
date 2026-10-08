-- triage-agent-operator: TriageAgent is Healthy when status.phase is Running.
hs = {}
if obj.status ~= nil and obj.status.phase ~= nil then
  if obj.status.phase == "Running" then
    hs.status = "Healthy"
    if obj.status.routeUrl ~= nil and obj.status.routeUrl ~= "" then
      hs.message = obj.status.routeUrl
    else
      hs.message = "TriageAgent is running"
    end
    return hs
  end
  if obj.status.phase == "Degraded" then
    hs.status = "Degraded"
    hs.message = "TriageAgent deployment is degraded"
    return hs
  end
end

if obj.status ~= nil and obj.status.conditions ~= nil then
  for i, condition in ipairs(obj.status.conditions) do
    if condition.type == "Available" and condition.status == "True" then
      hs.status = "Healthy"
      hs.message = condition.message
      return hs
    end
    if condition.type == "Available" and condition.status == "False" then
      hs.status = "Degraded"
      hs.message = condition.message
      return hs
    end
  end
end

hs.status = "Progressing"
hs.message = "Waiting for TriageAgent"
return hs
