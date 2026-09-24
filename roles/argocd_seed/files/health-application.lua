-- Health of an Argo CD Application = the health it reports. Argo CD does not assess
-- child Applications by default, so sync waves in an app of apps would not wait.
-- A new Application reports Healthy before its first sync (it has no resources yet):
-- until its first sync operation has finished, it counts as Progressing.
hs = {}
if obj.status == nil or obj.status.operationState == nil then
  hs.status = "Progressing"
  hs.message = "Waiting for the first sync"
  return hs
end
if obj.status.operationState.phase == "Running" then
  hs.status = "Progressing"
  hs.message = "Sync in progress"
  return hs
end
hs.status = "Progressing"
hs.message = ""
if obj.status.health ~= nil then
  hs.status = obj.status.health.status
  if obj.status.health.message ~= nil then
    hs.message = obj.status.health.message
  end
end
return hs
