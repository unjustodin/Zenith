-- "Show in Zenith": a key in the real game that brings the 3D client's window to the front, on the
-- same running world (the client's Ctrl+F9 comes the other way).
data:extend({
  {
    type = "custom-input",
    name = "f3d-show-3d",
    key_sequence = "CONTROL + F9",
    consuming = "none",
    action = "lua",
  },
})
