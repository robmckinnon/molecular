-- molecular: music box generator
-- 0.1.0 @delineator

local tab = require 'tabutil'

-- various functions
pf = include("pitfalls/lib/functions")

-- maps ratio labels to ratio fractions
ratiointervals = include("pitfalls/lib/ratios")

-- maps chord labels to interval labels
chords = include("pitfalls/lib/chords")

-- maps n, LMs, sequence to scale names
named_scales = include("pitfalls/lib/named_scales")

-- represents scale with sequence of L,s steps
include("pitfalls/lib/Scale")

-- represents intervals for scale in given mode
include("pitfalls/lib/Intervals")

-- represents intervals for all degrees of scale in given mode
include("pitfalls/lib/ScaleIntervals")

-- represents pitches seeded from a given scale
include("pitfalls/lib/Pitches")

scale = Scale:new(2, 1, "LLsLs")
intervals = ScaleIntervals:new(scale)
pitches = Pitches:new(scale, intervals, 440, 60-12-12)
local western=require 'musicutil'

engine.name = 'PolyPerc'
local bars = 4
local step_div = 1
local beats_per_bar = 4
local step_size
local steps_per_bars
local steps_count
local next_on_step
local step = 0
local duration1 = 7
local duration2 = 15.5
local duration = 9
local onsteps = {}
local offsteps = {}
local degree = 1
local scale_degrees = scale.length
local octave = 5
local loop_id
local options = {}
options.OUTPUT = {"audio", "midi", "audio + midi", "crow out 1+2", "crow ii JF"}
local midi_out_device
local midi_out_channel
local active_notes = {}

function init()
  print("init")
  midi_out_device = midi.connect(1)
  midi_out_device.event = function() end

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

  params:add{type = "option", id = "output", name = "output",
    options = options.OUTPUT,
    default = 2,
    action = function(value)
      all_notes_off()
      -- if value == 4 then crow.output[2].action = "{to(5,0),to(0,0.25)}"
      -- elseif value == 5 then
        -- crow.ii.pullup(true)
        -- crow.ii.jf.mode(1)
        -- end
    end}

  params:add_number("midi_out_device", "midi out device", 1, 4, step_div)
  params:add_number("midi_out_channel", "midi out channel", 1, 16, 1)

  params:set_action("midi_out_device", function(x) midi_out_device = midi.connect(x) end)
  params:set_action("midi_out_channel", function(x) all_notes_off(); midi_out_channel = x end)

  next_on_step = 1
  duration = duration1
  calc_steps()

  loop_id = clock.run(step_loop)
end

function key(n,z)
  if n == 3 and z == 1 then
  elseif n == 2 and z == 1 then
    clock.cancel(loop_id)
  end
end

function audio_engine_out()
  return params:get("output") == 1 or params:get("output") == 3
end

function crow_12()
  return params:get("output") == 4
end

function crow_ii()
  return params:get("output") == 5
end

function midi_output()
  return (params:get("output") == 2 or params:get("output") == 3)
end

function play_note_on(freq, note_num)
  if audio_engine_out() then
    engine.hz(freq)
  elseif crow_12() then
    -- crow.output[1].volts = (note_num-60)/12
    -- crow.output[2].execute()
  elseif crow_ii() then
    -- crow.ii.jf.play_note((note_num-60)/12,5)
  end

  if midi_output() then
    midi_out_device:note_on(note_num, 96, midi_out_channel)
    table.insert(active_notes, note_num)

    --local note_off_time =
    -- Note off timeout
    -- if params:get("note_length") < 4 then
      -- notes_off_metro:start((60 / params:get("clock_tempo") / params:get("step_div")) * params:get("note_length"), 1)
    -- end
  end
end

function note_on(deg_oct)
  local deg = deg_oct[1]
  local oct = deg_oct[2]
  local freq = pitches:octdegfreq(oct, deg)
  local note_num = western.freq_to_note_num(freq)
  play_note_on(freq, note_num)
  print(step.." on: "..deg.." "..oct.." note_num: "..note_num)
end

function note_off(deg_oct)
  local deg = deg_oct[1]
  local oct = deg_oct[2]
  local freq = pitches:octdegfreq(oct, deg)
  local note_num = western.freq_to_note_num(freq)
  midi_out_device:note_off(note_num, 0, midi_out_channel)
  print(step.." off: "..deg.." "..oct.." "..western.freq_to_note_num(freq))
end

function all_notes_off()
  if midi_output() then
    for _, a in pairs(active_notes) do
      midi_out_device:note_off(a, nil, midi_out_channel)
    end
  end
  active_notes = {}
end

function starts_with_another_note(step)
  return onsteps[step] and #onsteps[step] > 0
end

function switch_duration()
  duration = (duration == duration1 and duration2) or duration1
  print("duration: "..duration)
end

function init_onstep(step)
  onsteps[step] = {}
end

function add_onstep(step)
  onsteps[step][#onsteps[step] + 1] = {degree, octave}
end

function add_offstep(step)
  off_step = step + (duration * step_div)
  if off_step > steps_count then off_step = (off_step % steps_count) end

  if offsteps[off_step] == nil then offsteps[off_step] = {} end
  offsteps[off_step][#offsteps[off_step] + 1] = {degree, octave}

  next_on_step = off_step
  print("next_on_step: "..next_on_step)
end

function increment_step()
  step = step + 1
  if (step > steps_count) then step = 1 end
end

function increment_scale_degree()
  degree = degree + 1
  if degree > scale_degrees then
    degree = degree % scale_degrees
    octave = octave + 1
  end
end

function notes_off(step)
  if offsteps[step] then
    for i, deg_oct in pairs(offsteps[step]) do
      note_off(deg_oct)
    end
  end
end

function notes_on(step)
  if onsteps[step] then
    for i, deg_oct in pairs(onsteps[step]) do
      note_on(deg_oct)
    end
  end
end

function step_loop()
  while true do
    clock.sync(step_size)
    increment_step()
    print("step: "..step)
    notes_off(step)

    if step == next_on_step then
      if starts_with_another_note(step) then
        switch_duration()
      else
        init_onstep(step)
      end
      add_onstep(step)
      add_offstep(step)
      increment_scale_degree()
    end

    notes_on(step)
  end
end

function calc_steps()
  step_size = 1/step_div
  steps_per_bar = beats_per_bar * step_div
  steps_count = steps_per_bar * bars
end

function cleanup()
  all_notes_off()
end
