-- hover.py presses this after running a hover step's actions, so the next step waits for it
-- (the mod can't read files, and grabbing the screen takes a varying time).
data:extend{{type = "custom-input", name = "f3d-ui-next", key_sequence = "CONTROL + SHIFT + F9", consuming = "game-only"}}
