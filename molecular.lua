-- molecular:
-- music box generator
--
-- Create music with simple rules
-- and a (softcut) loop.
--
-- Inspired by Duncan Lockerby's
-- molecular music box video. [0]
--
-- Requires you also have
-- pitfalls [1] installed.
--
-- Use K2 + K3 to select:
-- * A note length (in beats) 4
-- * The start note           E
-- * A different note length  3
-- * A scale by name      Major
--
-- Examples:
--
--       4 E 3    Major
--
--       9 C 14.5 Mavila-5
--
-- Press K2 to play your track.
--
-- Microtonal scale definitions
-- come from pitfalls [1],
-- which you must also install.
--
-- Attach external hardware to
-- norns' audio in jack.
-- Then softcut records loops.
-- As MIDI for only the current
-- loop is sent to MIDI out.
-- As we use MIDI pitch-bend to
-- play microtonal pitches.
--
-- Parameters > EDIT >
-- bars                    4
-- beats_per_bar         4
-- step_divisioh           4
-- output       audio | midi
-- midi out device         4
-- midi out channel        1
--
-- [0] The Molecular Music Box:
-- how simple rules can lead to
-- rich patterns video:
-- https://www.youtube.com/
--          watch?v=3Z8CuAC_-bg
--
-- [1] https://llllllll.co/t/
--          pitfalls/37795
--
-- .................................................................
--
-- molecular 0.1.0
-- copyright 02022 robmckinnon
-- GNU GPL v3.0
-- .................................................................

local tab = require 'tabutil'

-- various functions
pf = include("pitfalls/lib/functions")

-- maps ratio labels to ratio fractions
ratiointervals = include("pitfalls/lib/ratios")

-- maps chord labels to interval labels
chords = include("pitfalls/lib/chords")

-- maps n, LMs, sequence to scale names
named_scales = include("pitfalls/lib/named_scales")
-- mixin the MusicUtil scale names
pf.pop_named_sequences(named_scales.lookup)

-- represents scale with sequence of L,s steps
include("pitfalls/lib/Scale")

-- represents intervals for scale in given mode
include("pitfalls/lib/Intervals")

-- represents intervals for all degrees of scale in given mode
include("pitfalls/lib/ScaleIntervals")

-- represents pitches seeded from a given scale
include("pitfalls/lib/Pitches")
-- midi out to device
midi_out = include("pitfalls/lib/midi_out")

local reverse_name = pf.reverse_name_lookup(named_scales.lookup, named_scales.names)
local scale_name = "Major"
local reversed_name = nil
local scale = Scale:new(2, 1, "LLsLLLs")
local scale_degrees = scale.length
local intervals = ScaleIntervals:new(scale)
local midi_start = 61
local pitches = Pitches:new(scale, intervals, 440, midi_start)

engine.name = 'PolyPerc'
local bars = 4
local step_div = 4
local beats_per_bar = 4
local step_size
local steps_per_bars
local steps_count
local next_on_step
local step = 0
local duration1 = 5
local duration2 = 7.5
local duration = 9
local duration2_affects_sequence = false
local starts_with_another = false
local sequencesteps = {}
local onsteps = {}
local offsteps = {}
local newsteps = {}
local degree = 1
local octave = 2
local loop_id = nil
local options = {}
options.OUTPUT = {"audio", "midi", "audio + midi", "crow out 1+2", "crow ii JF"}
local midi_out_device
local midi_out_channel
local active_notes = {}
local sequence_num = 0

-- softcut vars
local rate = 1.0
local rec = 1.0
local pre = 0.0

local off = 0
local on = 1
local end_of_loop = 61
local time_ref = 0
local initial_loop = true
local s = screen
local western = require('musicutil')

local PI = 3.14159265359
local C = 2*PI
local qC = PI / 2
local cx = 78
local cy = 62

local edit = 1
pf.debug(false)

local redrawing = false

function init_params()
  params:add_number("molecular_bars", "bars", 4, 12, bars)
  params:add_number("molecular_beats_per_bar", "beats_per_bar", 4, 12, beats_per_bar)
  params:add_number("molecular_step_div", "step_division", 1, 16, step_div)

  params:add_number("molecular_midi_start", "midi_start", 60, 71, midi_start)
  params:add_control("molecular_duration1", "duration1", controlspec.new(0.5, 24, 'lin', 0.25, duration1, 'beats'))
  params:add_control("molecular_duration2", "duration2", controlspec.new(0.25, 24, 'lin', 0.25, duration2, 'beats'))

  params:add{type = "option", id = "molecular_scale", name = "scale",
    options = reverse_name.names,
    default = 1,
    action = function(value)
      reset_scale_from_params(value)
      params:write()
      redraw_loop()
    end}
  params:add{type = "option", id = "molecular_output", name = "output",
    options = options.OUTPUT,
    default = 1,
    action = function(value)
      params:write()
      all_notes_off()
      -- if value == 4 then crow.output[2].action = "{to(5,0),to(0,0.25)}"
      -- elseif value == 5 then
        -- crow.ii.pullup(true)
        -- crow.ii.jf.mode(1)
        -- end
    end}

  params:add_number("molecular_midi_out_device", "midi out device", 1, 4, step_div)
  params:add_number("molecular_midi_out_channel", "midi out channel", 1, 16, 1)

  -- Standard MIDI Files use a pitch wheel range of +/-2 semitones = 200 cents
  params:add_control("molecular_pitchbend_semitones", "pitchbend semitones ±", controlspec.new(1, 16, 'lin', 1, 2, '±'))

  -- read default [scriptname]-01.pset from local data folder
  params:read(norns.state.data .. "molecular-01.pset", true)

  bars = params:get("molecular_bars")
  beats_per_bar = params:get("molecular_beats_per_bar")
  step_div = params:get("molecular_step_div")
  midi_start = params:get("molecular_midi_start")
  duration1 = params:get("molecular_duration1")
  duration2 = params:get("molecular_duration2")
  midi_out_channel = params:get("molecular_midi_out_channel")

  reset_scale_from_params(params:get("molecular_scale"))
end

function reset_scale_from_params(value)
  -- print(value)
  value = reverse_name.names[value]
  -- print(value)
  reversed_name = reverse_name.lookup[value]
  reset_scale(reversed_name)
  scale_name = value
end

function init()
  pf.dprint("============")
  pf.dprint("init")

  init_params()

  params:set_action("molecular_bars", function(x) bars = x; calc_steps() end)
  params:set_action("molecular_beats_per_bar", function(x) beats_per_bar = x; calc_steps() end)
  params:set_action("molecular_step_div", function(x) step_div = x; calc_steps() end)

  params:set_action("molecular_midi_start", function(x) midi_start = x; reset_pitches(); redraw(); end)
  params:set_action("molecular_duration1", function(x) duration1 = x; if x < 16.5 then redraw_loop() end; end)
  params:set_action("molecular_duration2", function(x) duration2 = x; if x < 16.5 then redraw_loop() end; end)

  params:set_action("molecular_midi_out_device", function(x) params:write(); connect_midi_out_device() end)
  params:set_action("molecular_midi_out_channel", function(x) params:write(); all_notes_off(); midi_out_channel = x end)

  if midi_output() then connect_midi_out_device() end

  redraw_loop()
  clock.cleanup()
  tab.print(clock.threads)
end

function connect_midi_out_device()
  midi_out_device = midi.connect(params:get("molecular_midi_out_device"))
  midi_out_device.event = function() end
end

function draw_inputs()
  s.level(edit == 1 and 15 or 6)
  s.move(22,12)
  s.text_right(duration1 % 1 == 0 and math.floor(duration1) or duration1)
  s.move(31,12)
  s.level(edit == 2 and 15 or 6)
  s.text_center(western.note_num_to_name(midi_start))
  s.move(40,12)
  s.level(edit == 3 and 15 or 6)
  s.text(duration2)
  s.move(60,12)
  s.level(edit == 4 and 15 or 6)
  s.text(scale_name)
end

function redraw()
  redrawing = true
  s.clear()
  draw_inputs()
  draw_mols()
  s.update()
  redrawing = false
end

function draw_mols()
  -- s.level(1)
  -- s.rect(1,14, 125, 50)
  -- s.stroke()
  local d = (15 / #sequencesteps)
  local x
  local y
  local last_x
  local last_y
  local bright
  local steps_progress -- 0 to 1
  local last_steps_progress = 0
  local last_degree = 0
  local ya = 16
  local yb = 45
  for i,v in pairs(sequencesteps) do
    bright = util.clamp(math.floor(d * (#sequencesteps - i + 3)), 2, 15)
    steps_progress = 0
    last_steps_progress = 0
    if i < (sequence_num+1) then
      for k,j in pairs(v) do
        if (j[1] < (step + 1)) then
          steps_progress = j[1] / steps_count
          x = steps_progress * 125
          y = ya + (2 - intervals:ratio(j[2])) * yb
          if last_degree > 0 then
            s.level(2)
            s.move(last_x, last_y)
            s.line( (x+last_x) / 2, (y + last_y) / 2)
            s.stroke()
            s.level(1)
            s.move((x+last_x) / 2, (y + last_y) / 2)
            s.line(x, y)
            s.stroke()
          end
          last_steps_progress = steps_progress
          last_degree = (scale_degrees - j[2] + 1)
          last_x = x
          last_y = y
        end
      end
      if last_degree > 0 then
      end
    end
  end

  local dd = (2 / #sequencesteps)
  local radius
  for i,v in pairs(sequencesteps) do
    bright = util.clamp(math.floor(d * (i + 3)), 4, 15)
    radius = util.round((dd * (#sequencesteps - i + 3)), 0.1) + 0.5
    steps_progress = 0
    last_steps_progress = 0
    if i < (sequence_num+1) then
      for k,j in pairs(v) do
        if (j[1] < (step + 1)) then
          steps_progress = j[1] / steps_count
          x = steps_progress * 125
          y = ya + (2 - intervals:ratio(j[2])) * yb
          s.level(bright)
          s.circle(x, y, radius)
          s.fill()
          s.stroke()
          last_steps_progress = steps_progress
          last_degree = (scale_degrees - j[2] + 1)
          last_x = x
          last_y = y
        end
        if last_degree > 0 then
        end
      end
    end
  end
end

function draw_arcs()
  local steps_progress -- 0 to 1
  local last_steps_progress = 0
  local radians
  local last_radians
  local last_degree = 0

  print("sequences: "..#sequencesteps)
  s.level(0)
  s.move(cx, cy)
  s.stroke()
  local d = (15 / #sequencesteps)
  local radius = 10

  -- s.blend_mode('xor')
  -- s.level(10)
  -- s.rect(0,14, 120, 100)
  -- s.rect(1,13, 119, 99)
  -- s.level(1)

  -- s.fill()
  local bright
  for i,v in pairs(sequencesteps) do
    bright = util.clamp(math.floor(d * (#sequencesteps - i + 3)), 2, 15)
    s.level(bright)
    -- last_degree = 0
    steps_progress = 0
    last_steps_progress = 0
    last_radians = PI
    if i < 2 then
      for k,j in pairs(v) do
        -- print(j[1].." "..j[2].." "..j[3])
        steps_progress = j[1] / steps_count
        -- print(steps_progress)
        radians = PI + (steps_progress * PI)
        if last_degree > 0 then
          radius = 10 + (last_degree * 5)
          s.level(bright)
          s.arc(cx, cy, radius, last_radians, radians)
          -- s.stroke()
          -- s.level(0)
        end
        last_steps_progress = steps_progress
        last_degree = j[2]
        last_radians = radians
      end
      if last_degree > 0 then
        s.level(bright)
        s.arc(cx, cy, 10 + (last_degree * 5), last_radians, 2*PI)
        s.stroke()
        -- s.level(0)
      end
    end
  end
end

function reset_pitches()
  pitches = Pitches:new(scale, intervals, 440, midi_start)
end

function reset_scale(data)
  -- tab.print(data)
  if data.m == nil then
    scale = Scale:new(data.l, data.s, data.seq)
  else
    scale = Scale:new(data.l, data.s, data.seq, data.m)
  end
  scale_degrees = scale.length
  intervals = ScaleIntervals:new(scale)
  reset_pitches()
end

function await_redraw()
  while redrawing do; end
end

function redraw_loop()
  init_loop()
  step_loop(false)
  await_redraw()
  redraw()
end

function init_loop(existing)
  initial_loop = true
  step = 0
  next_on_step = 1
  sequence_num = 0
  duration = duration1
  calc_steps()
  sequencesteps = existing or {}
  onsteps = {}
  offsteps = {}
  newsteps = {}
  active_notes = {}
  degree = 1
  octave = 2
  increment_sequence()
end

function enc(n,d)
  if n == 1 then
    params:delta("cutoff", d)
  elseif n == 2 then
    edit_position(d)
  elseif n ==3 then
    change_value(d)
  end
end

function edit_position(d)
  edit = util.clamp(edit + d, 1, 4)
  redraw()
end

function only_duration1_affects_sequence()
  duration2_affects_sequence = false
  init_loop()
  step_loop(false)
  if duration2_affects_sequence then
    redraw()
    return false
  else
    return true
  end
end

function change_value(d)
  if edit == 1 then
    if (duration1 > 0.25 or (d > 0 and duration1 == 0.25)) and (duration1 < 16 or (d < 0 and duration1 >= 16)) then
      await_redraw()
      params:delta("molecular_duration1", d)
      if only_duration1_affects_sequence() then
        if duration1 > 0.25 and duration1 < 16.5 then
          -- increment duration1 again
          change_value(d)
        else
          redraw()
        end
      end
    end
  elseif edit == 2 then
    params:delta("molecular_midi_start", d)
  elseif edit == 3 then
    if duration1 > 0.25 and duration1 < 16.5 then
      params:delta("molecular_duration2", d)
    end
  elseif edit == 4 then
    params:delta("molecular_scale", d)
  end
end

function key(n,z)
  if n == 3 and z == 1 then
    s.clear()
  elseif n == 2 and z == 1 then
    toggle_sequence_running()
  end
end

function toggle_sequence_running()
  if loop_id == nil then
    start_sequence()
  else
    stop_sequence()
  end
end

function stop_sequence()
  stop_recording()
  clock.cancel(loop_id)
  loop_id = nil
end

function start_sequence()
  clock.cleanup()
  tab.print(clock.threads)
  init_loop(sequencesteps)
  loop_id = clock.run(step_loop)
  print("loop_id: "..loop_id)
end

function init_recording()
  pf.dprint("init_recording")
  softcut.buffer_clear()
  time_ref = util.time()
  -- audio.level_adc_cut(0.75)

  for i = 1,2 do
    -- ch 1 -> voice 1   ch 2 -> voice 2
    softcut.level_input_cut(i,i,1)
    -- voice 1 -> buffer 1  voice 2 -> buffer 2
    softcut.buffer(i,i)
    -- softcut.pan(i, pan[i])

    softcut.play(i,on)
    softcut.rec(i,on)
    softcut.enable(i,on)
    softcut.rec_offset(i,-0.06)

    -- preserve existing recording amplitude
    softcut.pre_level(i,1)
    -- record at full amplitude
    softcut.rec_level(i, 1)

    -- output level
    softcut.level(i,0.75)
    -- set crossfaded looping mode
    softcut.loop(i,1)
    -- set loop start at 1 second
    softcut.loop_start(i,1)
    -- set loop end at end_of_loop+1 seconds
    softcut.loop_end(i,end_of_loop + 1)
    -- set play position
    softcut.position(i,1)
    -- set playback rate to normal
    softcut.rate(i,1.0)
    -- set fade time position to 0 seconds
    softcut.fade_time(i,0.01)

    -- set slew time to 0.5 seconds?
    softcut.level_slew_time(i,0.5)
    -- set rate slew time to 0.05 seconds?
    softcut.rate_slew_time(i,0.05)
  end
end

function audio_engine_out()
  return params:get("molecular_output") == 1 or params:get("molecular_output") == 3
end

function crow_12()
  return params:get("molecular_output") == 4
end

function crow_ii()
  return params:get("molecular_output") == 5
end

function midi_output()
  return (params:get("molecular_output") == 2 or params:get("molecular_output") == 3)
end

function play_note_on(freq)
  if audio_engine_out() then
    engine.hz(freq)
    print(freq)
  elseif crow_12() then
    -- crow.output[1].volts = (note_num-60)/12
    -- crow.output[2].execute()
  elseif crow_ii() then
    -- crow.ii.jf.play_note((note_num-60)/12,5)
  end

  if midi_output() then
    -- midi_out_device:note_on(note_num, 96, midi_out_channel)

    local note_num = midi_out.hz_to_midi(freq)
    pitchbend_semitones = params:get("molecular_pitchbend_semitones")
    local bend = midi_out.pitch_bend_value(note_num, pitchbend_semitones)
    midi_out_device:pitchbend(math.floor(bend), midi_out_channel)

    note_num = math.floor(note_num)
    local vel = (freq < 150) and 50 or 95
    midi_out_device:note_on(note_num, vel, midi_out_channel)
    -- print(bend)
    table.insert(active_notes, note_num)
    local f = string.format('%.2f', freq)
    pf.dprint(step.." on: freq: "..f.." note_num: "..note_num)

    --local note_off_time =
    -- Note off timeout
    -- if params:get("note_length") < 4 then
      -- notes_off_metro:start((60 / params:get("clock_tempo") / params:get("step_div")) * params:get("note_length"), 1)
    -- end
  end
end

function note_on(deg_oct, clock_on)
  local deg = deg_oct[1]
  local oct = deg_oct[2]
  local freq = pitches:octdegfreq(oct, deg)
  if freq then
    if clock_on then play_note_on(freq) end
    return true
  else
    pf.dprint(step.." on: out of notes: "..deg.." "..oct)
    return false
  end
end

function note_off(deg_oct)
  if midi_output() then
    local deg = deg_oct[1]
    local oct = deg_oct[2]
    local freq = pitches:octdegfreq(oct, deg)
    if freq then
      -- midi_out_device:note_off(note_num, 0, midi_out_channel)
      local note_num = math.floor(midi_out.hz_to_midi(freq))
      midi_out_device:note_off(note_num, 0, midi_out_channel)

      pf.dprint(step.." off: "..deg.." "..oct.." "..note_num)
    else
      pf.dprint(step.." off: out of notes: "..deg.." "..oct)
    end
  end
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
  starts_with_another = onsteps[step] and #onsteps[step] > 0
  if starts_with_another then
    duration2_affects_sequence = true
  end
  return starts_with_another
end

function switch_duration()
  duration = (duration == duration1 and duration2) or duration1
  pf.dprint("duration: "..duration)
end

function init_onstep(step)
  onsteps[step] = {}
end

function add_onstep(step, clock_on)
  if clock_on == false then
    pf.dprint("seq "..sequence_num.." step "..step)
    sequencesteps[sequence_num] = sequencesteps[sequence_num] or {}
    table.insert(sequencesteps[sequence_num], {step, degree, octave})
  end
  onsteps[step][#onsteps[step] + 1] = {degree, octave}
  newsteps[step] = {degree, octave}
end

function add_offstep(step)
  off_step = step + math.floor(duration * step_div)
  if off_step > steps_count then off_step = (off_step % steps_count) end

  if offsteps[off_step] == nil then offsteps[off_step] = {} end
  offsteps[off_step][#offsteps[off_step] + 1] = {degree, octave}

  next_on_step = off_step
  pf.dprint("next_on_step: "..next_on_step)
end

function set_end_of_loop()
  end_of_loop = util.time() - time_ref + 1
  pf.dprint("end_of_loop: "..end_of_loop)
  softcut.loop_end(1,end_of_loop)
  softcut.loop_end(2,end_of_loop)
end

function stop_recording()
  if midi_output() then
    pf.dprint("stop_recording")
    softcut.rec_level(1,off)
    softcut.rec_level(2,off)
    softcut.rec(1,off)
    softcut.rec(2,off)
  end
end

function reset_recording_loop()
  pf.dprint("reset_recording_loop")
  softcut.rec_level(1,off)
  softcut.rec_level(2,off)
  softcut.position(1,1)
  softcut.position(2,1)
  softcut.rec_level(1,on)
  softcut.rec_level(2,on)
end

function increment_sequence()
  sequence_num = sequence_num + 1
  redraw()
  -- print("sequence_num: "..sequence_num)
end

function increment_step(clock_on, record_on)
  if initial_loop and step == 0 then
    if record_on then init_recording() end
  end

  step = step + 1
  if clock_on then redraw() end
  if (step > steps_count) then
    -- stop_recording()
    if initial_loop then
      if record_on then set_end_of_loop() end
      initial_loop = false
    end
    if record_on then reset_recording_loop() end
    step = 1
    increment_sequence()
  end
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

function notes_on(step, clock_on)
  local more_notes = true
  if onsteps[step] then
    if midi_output() and newsteps[step] then
      more_notes = note_on(newsteps[step], clock_on) and more_notes
      newsteps[step] = nil
    else
      for i, deg_oct in pairs(onsteps[step]) do
        more_notes = note_on(deg_oct, clock_on) and more_notes
      end
    end
  end
  return more_notes
end

function step_loop(clock_on)
  clock_on = (clock_on == nil and true) or false
  pf.dprint("step_loop")
  local more_notes = true
  while (more_notes or (step < steps_count)) do
    if clock_on then clock.sync(step_size) end
    increment_step(clock_on, clock_on and midi_output())
    -- if clock_on then print("step: "..step) end
    if clock_on then notes_off(step) end

    if step == next_on_step then
      if starts_with_another_note(step) then
        switch_duration()
      else
        init_onstep(step)
      end
      add_onstep(step, clock_on)
      add_offstep(step)
      increment_scale_degree()
    end

    more_notes = more_notes and notes_on(step, clock_on)
  end
  if clock_on then
    stop_recording()
    step = 1
    local level
    while step < steps_count do
      step = step + 1
      clock.sync(step_size)
      level = util.round((steps_count - step) / steps_count, 0.01)
      softcut.level(1, level)
      softcut.level(2, level)
    end
    clock.cancel(loop_id)
    pf.dprint("step loop complete")
    stop_play()
  end
end

function stop_play()
  softcut.play(1,off)
  softcut.play(2,off)
  softcut.enable(1,off)
  softcut.enable(2,off)
end

function calc_steps()
  step_size = 1/step_div
  steps_per_bar = beats_per_bar * step_div
  steps_count = steps_per_bar * bars
end

function cleanup()
  stop_recording()
  stop_play()
  clock.cancel(loop_id)
  clock.cleanup()
  all_notes_off()
end
