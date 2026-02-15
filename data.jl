# data.jl
using DataFrames, CSV

struct GameData
    recipes::DataFrame
    resources::Dict{String, Float64}   # Resource Name => Max Limit
    sink_points::Dict{String, Float64} # Item Name => Points
    building_power::Dict{String, Float64} # Building Name => Power Consumption (MW)
    all_items::Vector{String}          # List of every unique item in the game
end

function load_game_data()
    println("🔄 Loading data...")

    # 1. Load Recipes
    if !isfile("all_recipes.csv")
        error("File 'all_recipes.csv' not found! Run the scraper first.")
    end
    df_recipes = CSV.read("all_recipes.csv", DataFrame)
    # Replace missing values with empty strings/zeros to avoid errors
    df_recipes = coalesce.(df_recipes, "")

    # --- FILTER: EXCLUDE EQUIPMENT WORKSHOP ---
    filter!(row -> row.Building != "Equipment Workshop ×", df_recipes)
    println("   -> Recipes after filtering Workshop: $(nrow(df_recipes))")

    # --- FIX: DEDUPLICATE RECIPE NAMES ---
    # JuMP requires unique indices. If "Turbo Rifle Ammo" appears twice,
    # we rename the second one to "Turbo Rifle Ammo #2".
    seen_names = Dict{String, Int}()
    new_names = String[]

    for name in df_recipes.Recipe
        if haskey(seen_names, name)
            seen_names[name] += 1
            # Create a unique name, e.g., "Turbo Rifle Ammo #2"
            new_name = "$(name) #$(seen_names[name])"
            push!(new_names, new_name)
        else
            seen_names[name] = 1
            push!(new_names, name)
        end
    end

    # Update the DataFrame with unique names
    df_recipes.Recipe = new_names
    println("   -> Recipes loaded and deduplicated: $(nrow(df_recipes)) total.")
    # -------------------------------------

    # 2. Load Global Resource Limits
    if !isfile("global_resources.csv")
        error("File 'global_resources.csv' not found!")
    end
    df_res = CSV.read("global_resources.csv", DataFrame)
    resources = Dict(row.Resource => Float64(row.Max_Rate_Min) for row in eachrow(df_res))

    # 3. Load Sink Points
    if !isfile("sink_points.csv")
        error("File 'sink_points.csv' not found!")
    end
    df_sink = CSV.read("sink_points.csv", DataFrame)
    sink_points = Dict(row.Item => Float64(row.Points) for row in eachrow(df_sink))

    # 4. Load Building Power
    if !isfile("buildings_power.csv")
        println("⚠️ Warning: 'buildings_power.csv' not found. Power calc will be 0.")
        building_power = Dict{String, Float64}()
    else
        df_power = CSV.read("buildings_power.csv", DataFrame)
        building_power = Dict(row.Building => Float64(row.Power_MW) for row in eachrow(df_power))
    end

    # 5. Identify ALL unique items (Resources + Products + Intermediates)
    items_set = Set{String}()

    # Add raw resources
    union!(items_set, keys(resources))
    
    # Add everything found in recipes (Inputs and Outputs)
    for row in eachrow(df_recipes)
        # Check inputs
        for i in 1:4
            col_name = "In$(i)_Name"
            if !ismissing(row[col_name]) && row[col_name] != ""
                push!(items_set, row[col_name])
            end
        end
        # Check outputs
        for i in 1:2
            col_name = "Out$(i)_Name"
            if !ismissing(row[col_name]) && row[col_name] != ""
                push!(items_set, row[col_name])
            end
        end
    end

  return GameData(df_recipes, resources, sink_points, building_power, collect(items_set))
end