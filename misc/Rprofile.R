# Activate the mountainous-mackerel project when opening RStudio Server
setHook("rstudio.sessionInit", function(newSession) {
  if (newSession && is.null(rstudioapi::getActiveProject()))
    rstudioapi::openProject("mountainous-mackerel")
}, action = "append")
