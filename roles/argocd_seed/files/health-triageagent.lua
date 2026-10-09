-- triage-agent-operator: TriageAgent is Healthy when status.phase is Running.
-- The operator always writes status.phase (Pending, Running or Degraded, see the CRD) together
-- with an Available condition that is False for every phase except Running. So the phase
-- decides, and the conditions are read only when there is no phase.
-- Note: the operator computes the status only on create/update/resume today; the refresh
-- (timer or watch on the child Deployment) is being fixed in the triage-agent-operator repo.
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
  -- Pending (the Deployment is not observed yet) or a phase this check does not know.
  hs.status = "Progressing"
  hs.message = "TriageAgent is " .. obj.status.phase
  return hs
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
