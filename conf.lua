function love.conf(t)
    t.identity = "portal-coop"
    t.version = "11.4"
    t.window.title = "Portal Pals"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 320
    t.window.minheight = 180
    t.window.vsync = 1
    t.window.highdpi = true
    t.window.usedpiscale = false
    t.modules.physics = false
    t.modules.video = false
end
