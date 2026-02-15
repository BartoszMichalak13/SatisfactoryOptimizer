# import Pkg
# # Pkg.add(["HTTP", "Gumbo", "Cascadia", "DataFrames", "CSV"])

# include("scrapers.jl")

# df_recipes = scrape_recipes()
# scrape_awesome_sink()

# println("\n--- DONE ---")

# main.jl
include("data.jl")
include("model.jl")

# 1. Load Data
data = load_game_data()

# 2. Run Solver
model, x_vars, sink_vars, extracted_vars = build_and_solve(data)

# 3. Analyze Results
if termination_status(model) == MOI.OPTIMAL
    obj_val = objective_value(model)
    println("\n==========================================")
    println("🏆 OPTIMAL SOLUTION FOUND!")
    println("Maximum AWESOME Points/min: ", round(obj_val, digits=0))
    println("==========================================\n")

    # --- A. SINK REPORT ---
    println("--- 🗑️  WHAT ARE WE SINKING? (Top 10) ---")
    sink_results = []
    for item in data.all_items
        val = value(sink_vars[item])
        if val > 0.1
            points = get(data.sink_points, item, 0.0)
            total_points = val * points
            push!(sink_results, (Name=item, Amount=val, TotalPoints=total_points))
        end
    end
    sort!(sink_results, by = row -> row.TotalPoints, rev=true)

    for row in first(sink_results, 10)
        println("  Item: $(rpad(row.Name, 25)) Amount: $(lpad(round(row.Amount, digits=2), 8))/min   Points: $(round(Int, row.TotalPoints))")
    end

    # --- B. RESOURCE REPORT (Requested Feature) ---
    println("\n--- ⛏️  RESOURCE USAGE & LEFTOVERS ---")
    println(rpad("Resource", 20) * lpad("Limit", 12) * lpad("Used", 12) * lpad("REMAINING", 12) * lpad("% Used", 10))
    println("-"^66)

    # Helper to sort resources by usage percentage
    res_stats = []
    for (res_name, limit) in data.resources
        used = value(extracted_vars[res_name])
        remaining = limit - used
        percent = (limit > 0) ? (used / limit * 100) : 0.0
        push!(res_stats, (Name=res_name, Limit=limit, Used=used, Left=remaining, Pct=percent))
    end
    # Sort by % Used (Descending)
    sort!(res_stats, by = row -> row.Pct, rev=true)

    for r in res_stats
        # Only print if the limit is greater than 0
        if r.Limit > 0
            println(
                rpad(r.Name, 20),
                lpad(round(Int, r.Limit), 12),
                lpad(round(Int, r.Used), 12),
                lpad(round(Int, r.Left), 12), # <--- THIS IS WHAT YOU WANTED
                lpad(round(r.Pct, digits=1), 9), "%"
            )
        end
    end

    # --- C. RECIPE REPORT ---
    println("\n--- 🏭 KEY RECIPES (Top 10) ---")
    recipe_results = []
    for r in data.recipes.Recipe
        val = value(x_vars[r])
        if val > 0.1
            push!(recipe_results, (Name=r, Count=val))
        end
    end
    sort!(recipe_results, by = row -> row.Count, rev=true)

    for row in first(recipe_results, 10)
        println("  Recipe: $(rpad(row.Name, 40)) Machines: $(round(row.Count, digits=2))")
    end

    # --- POWER CONSUMPTION REPORT ---
    println("\n--- ⚡ POWER CONSUMPTION ---")
    total_power = 0.0

    # Calculate power based on running machines
    for r in data.recipes.Recipe
        count = value(x_vars[r])
        if count > 0.001
            # Find the row in DataFrame to get the Building name
            # (Note: In a large DB this is slow, but for <200 recipes it's instant)
            row_idx = findfirst(==(r), data.recipes.Recipe)
            if row_idx !== nothing
                b_name = data.recipes.Building[row_idx]
                mw = get(data.building_power, b_name, 0.0)
                global total_power += count * mw
            end
        end
    end

    gw_power = total_power / 1000.0
    println("Total Power Required: $(round(total_power, digits=2)) MW")
    println("                      $(round(gw_power, digits=3)) GW")

else
    println("❌ No optimal solution found. Status: ", termination_status(model))
end