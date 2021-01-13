-- molecular: music box generator
-- 0.1.0 @delineator

engine.name = 'PolyPerc'
local bars = 4
local step_div = 4
local beats_per_bar = 4
local step_size
local steps_per_bars
local steps_count
local step = 0
local duration1 = 9
local duration2 = 14.5
local duration = 9
local onsteps = {}
local offsteps = {}
local degree = 1
local scale_degrees = 7
local octave = 2

function note_on(deg, oct)
end
  
function note_off(deg_oct)
  local deg = deg_oct[1]
  local oct = deg_oct[2]
end
  
function step()
  local off_step
  while true do
    clock.sync(step_size)
    step = step + 1
    
    if (step % duration) == 1 then
      if onsteps[step] and #onsteps[step] > 0 then
        duration = (duration == duration1 and duration2) or duration1
      else
        onsteps[step] = {}
      end
      if offsteps[step] then
        for i, deg_oct in pairs(offsteps[step]) do
          note_off(deg_oct)
        end
      end
      
      note_on(degree, octave)
      onsteps[step][#onsteps[step] + 1] = {degree, octave}
      off_step = step + (duration * step_div)
      if offsteps[off_step] == nil then offsteps[off_step] = {} end
      offsteps[off_step][#offsteps[off_step] + 1] = {degree, octave} 
      
      degree = degree + 1
      if degree > scale_degrees then
        degree = degree % scale_degrees
      end
    end
  end
end

function calc_steps()
  step_size = 1/step_div
  steps_per_bar = beats_per_bar * step_div
  steps_count = steps_per_bar * bars
end

function init()
  params:add_number("bars", "bars", 4, 12, bars)
  params:add_number("beats_per_bar", "beats_per_bar", 4, 12, beats_per_bar)
  params:add_number("step_div", "step_division", 1, 16, step_div)

  params:set_action("bars", function(x) bars = x; calc_steps() end)
  params:set_action("beats_per_bar", function(x) beats_per_bar = x; calc_steps() end)
  params:set_action("step_div", function(x) step_div = x; calc_steps() end)

  params:add_control("duration1", "duration1", controlspec.new(0.25, 24, 'lin', 0.25, duration1, 'beats'))
  params:add_control("duration2", "duration2", controlspec.new(0.25, 24, 'lin', 0.25, duration2, 'beats'))
  params:set_action("duration1", function(x) duration1 = x end)
  params:set_action("duration2", function(x) duration2 = x end)
  calc_steps()
end
  