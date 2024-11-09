-- Load the ReaImGui library and create a context
local ctx = reaper.ImGui_CreateContext('Notes in ms')

-- Variables to track tempo and note durations
local current_bpm = reaper.Master_GetTempo()
local note_durations = {}
local show_triplet = true
local show_dotted = true

-- Define note divisions based on quarter note as 1/4
local divisions = {
    {name = "1/1", multiplier = 4},      -- Whole note (1/1)
    {name = "1/2", multiplier = 2},      -- Half note (1/2)
    {name = "1/4", multiplier = 1},      -- Quarter note (1/4)
    {name = "1/8", multiplier = 0.5},    -- Eighth note (1/8)
    {name = "1/16", multiplier = 0.25},  -- Sixteenth note (1/16)
    {name = "1/32", multiplier = 0.125}, -- 32nd note (1/32)
    {name = "1/64", multiplier = 0.0625}, -- 64th note (1/64)
    {name = "1/128", multiplier = 0.03125} -- 128th note (1/128)
}

-- Define note types (normal, triplet, dotted)
local types = {
    {name = "Note", multiplier = 1, color = {1.0, 1.0, 1.0}}, -- White for normal
    {name = "Triplet", multiplier = 2/3, color = {0.8, 0.8, 0.0}}, -- Yellow for triplet
    {name = "Dotted", multiplier = 1.5, color = {0.8, 0.0, 0.8}} -- Purple for dotted
}

-- Function to calculate note durations based on current tempo
local function calculateNoteDurations()
    note_durations = {}
    local quarter_note_ms = 60000 / current_bpm -- Duration of a quarter note in ms

    -- Calculate durations for each division and type
    for _, division in ipairs(divisions) do
        for _, note_type in ipairs(types) do
            -- Skip triplet and dotted if they are not to be shown
            if (note_type.name == "Triplet" and not show_triplet) or (note_type.name == "Dotted" and not show_dotted) then
                goto continue
            end

            local duration = quarter_note_ms * division.multiplier * note_type.multiplier
            table.insert(note_durations, {
                name = division.name .. " " .. note_type.name,
                duration = duration,
                color = note_type.color -- Store color for each type
            })

            ::continue::
        end
    end

    -- Sort the table by duration in descending order
    table.sort(note_durations, function(a, b) return a.duration > b.duration end)
end

-- Function to set clipboard text
local function copyToClipboard(value)
    local text = string.format("%.2f", value)  -- Format the value to 2 decimal places
    reaper.CF_SetClipboard(text)
end

-- Initial calculation of note durations
calculateNoteDurations()

-- Create an ImGui frame function
function frame()
    -- Display the note durations
    for _, note in ipairs(note_durations) do
        -- Push color for triplet and dotted types
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(note.color[1], note.color[2], note.color[3], 1.0))
        
        -- Display the note name and duration
        local text = string.format("%s: %.2f ms", note.name, note.duration)

        -- If clicked, copy duration to clipboard
        if reaper.ImGui_Selectable(ctx, text) then
            copyToClipboard(note.duration) -- Copy only the duration rounded to 2 decimals
        end
        
        -- Pop the style color
        reaper.ImGui_PopStyleColor(ctx)
    end

    -- Buttons to toggle showing triplets and dotted notes
    if reaper.ImGui_Button(ctx, show_triplet and "Hide Triplet Notes" or "Show Triplet Notes") then
        show_triplet = not show_triplet
        calculateNoteDurations() -- Recalculate durations with the new setting
    end

    if reaper.ImGui_Button(ctx, show_dotted and "Hide Dotted Notes" or "Show Dotted Notes") then
        show_dotted = not show_dotted
        calculateNoteDurations() -- Recalculate durations with the new setting
    end

    -- Check if 'Esc' key is pressed to close the window
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        return false
    end

    -- Draw a button to close the window
    if reaper.ImGui_Button(ctx, 'Close (Esc)') then
        return false
    end
    
    return true
end

-- Main loop to keep ImGui window open and update if tempo changes
function main()
    -- Get the current project tempo
    local new_bpm = reaper.Master_GetTempo()

    -- Check if the tempo has changed
    if new_bpm ~= current_bpm then
        current_bpm = new_bpm
        calculateNoteDurations() -- Recalculate durations with the new tempo
    end

    -- Set the next window size to 0, 0 for auto-sizing and allow it to be resized
    reaper.ImGui_SetNextWindowSize(ctx, 0, 0, reaper.ImGui_Cond_FirstUseEver())

    -- Display the ImGui window
    local visible, open = reaper.ImGui_Begin(ctx, 'Notes in ms', true, reaper.ImGui_WindowFlags_AlwaysAutoResize())

    if visible then
        if not frame() then
            open = false
        end
        reaper.ImGui_End(ctx)
    end
    
    if open then
        reaper.defer(main) -- Keep running if open
    end
end

-- Start the main loop
main()

