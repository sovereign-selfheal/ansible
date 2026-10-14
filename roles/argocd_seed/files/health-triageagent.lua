-- triage-agent-operator: TriageAgent is Healthy when status.phase is Running.
-- The operator always writes status.phase (Pending, Running or Degraded, see the CRD) together
-- with an Available condition that is False for every phase except Running. So the phase
-- decides, and the conditions are read only when there is no phase.
-- The operator refreshes the status on every change of the CR and with a 60 s timer, so the
-- phase can be up to one minute behind the Deployment. Since v0.4.0 a normal rollout (for
-- example a long image pull) is Pending, not Degraded.
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
  -- Pending (no Deployment yet, or its rollout is in progress) or a phase this check does not know.
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
