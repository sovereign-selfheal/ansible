-- TempoMonolithic (Tempo operator): Healthy when Ready, Degraded when the operator reports
-- a failure. Argo CD has no built-in check for it, so without this the sync wave of the
-- observability component would not wait for Tempo.
hs = {}
if obj.status ~= nil and obj.status.conditions ~= nil then
  for i, condition in ipairs(obj.status.conditions) do
    if (condition.type == "Failed" or condition.type == "ConfigurationError") and condition.status == "True" then
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
hs.status = "Progressing"
hs.message = "Waiting for Tempo to be ready"
return hs
