# model.jl
import Pkg
Pkg.add("JuMP")
Pkg.add("HiGHS")

using JuMP
using HiGHS

function build_and_solve(data::GameData)
    model = Model(HiGHS.Optimizer)
    # set_silent(model) # Comment this out if you want to see solver logs

    # --- DECISION VARIABLES ---
    
    # 1. How many times per minute we run a recipe
    recipe_names = data.recipes.Recipe
    @variable(model, x[recipe_names] >= 0)

    # 2. How many items we sink per minute
    @variable(model, sink[data.all_items] >= 0)

    # 3. How much raw resource we extract from the world
    # (Only defined for items listed in global_resources.csv)
    resource_names = collect(keys(data.resources))
    @variable(model, extracted[resource_names] >= 0)

    # --- CONSTRAINTS ---

    # A. Extraction Limits
    # We cannot extract more than the global map limit
    for res in resource_names
        limit = data.resources[res]
        @constraint(model, extracted[res] <= limit)
    end

    # B. Material Balance (Flow Conservation)
    # For every item: (Extraction + Production) == (Consumption + Sink)
    
    println("   -> Creating material balance constraints...")
    for item in data.all_items
        
        # 1. Production (from recipes)
        production = AffExpr(0.0)
        for row in eachrow(data.recipes)
            for i in 1:2 # Check outputs
                if !ismissing(row[Symbol("Out$(i)_Name")]) && row[Symbol("Out$(i)_Name")] == item
                    rate = row[Symbol("Out$(i)_Rate")]
                    add_to_expression!(production, rate * x[row.Recipe])
                end
            end
        end

        # 2. Consumption (in recipes)
        consumption = AffExpr(0.0)
        for row in eachrow(data.recipes)
            for i in 1:4 # Check inputs
                if !ismissing(row[Symbol("In$(i)_Name")]) && row[Symbol("In$(i)_Name")] == item
                    rate = row[Symbol("In$(i)_Rate")]
                    add_to_expression!(consumption, rate * x[row.Recipe])
                end
            end
        end

        # 3. Extraction (only if it is a raw resource)
        extraction_term = AffExpr(0.0)
        if haskey(data.resources, item)
            add_to_expression!(extraction_term, 1.0 * extracted[item])
        end

        # Balance Equation
        # Extracted + Produced = Consumed + Sunk
        @constraint(model, extraction_term + production == consumption + sink[item])
    end

    # # --- OBJECTIVE FUNCTION ---
    # # Maximize total points
    
    # objective_expr = AffExpr(0.0)
    # for item in data.all_items
    #     points = get(data.sink_points, item, 0.0)
    #     if points > 0
    #         add_to_expression!(objective_expr, points * sink[item])
    #     end
    # end

    # @objective(model, Max, objective_expr)

    # --- OBJECTIVE FUNCTION ---
    # Maximize: (Nuclear Power MW * 1000) + (Sink Points)
    # Weighting power by 1000 ensures the model prioritizes burning fuel
    # over sinking the raw rods.

    objective_expr = AffExpr(0.0)

    # 1. Add value for Power Generation
    for (r_name, yield) in data.power_yields
        if r_name in recipe_names
            # x[r_name] is the number of active power plants
            add_to_expression!(objective_expr, 1000.0 * yield * x[r_name])
        end
    end

    # 2. Add value for Sink Points (Standard)
    for item in data.all_items
        points = get(data.sink_points, item, 0.0)
        if points > 0
            add_to_expression!(objective_expr, points * sink[item])
        end
    end
    
    @objective(model, Max, objective_expr)

    # --- SOLVE ---
    println("🚀 Starting optimization...")
    optimize!(model)

    return model, x, sink, extracted
end